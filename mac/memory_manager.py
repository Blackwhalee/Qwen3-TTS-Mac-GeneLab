# coding=utf-8
# Copyright 2026 Qwen3-TTS-Mac-GeneLab Contributors.
# SPDX-License-Identifier: Apache-2.0
"""
Apple Silicon Unified Memory マネージャー

- 現在のメモリ使用量をモニタリング
- モデルロード前にメモリ余裕を確認
- 複数モデルの同時ロード回避（1モデルずつロード/アンロード）
- PYTORCH_MPS_HIGH_WATERMARK_RATIO の動的調整
"""

from __future__ import annotations

import gc
import logging
import os
from dataclasses import dataclass
from enum import Enum
from typing import Any

import psutil

logger = logging.getLogger(__name__)


class ModelSize(str, Enum):
    """モデルサイズの種類"""
    SMALL_0_6B = "0.6B"
    LARGE_1_7B = "1.7B"


class ModelDtype(str, Enum):
    """モデルの dtype"""
    BF16 = "bf16"
    FP16 = "fp16"
    FP32 = "fp32"
    INT8 = "8bit"
    INT4 = "4bit"


@dataclass
class MemoryInfo:
    """メモリ情報"""
    total_gb: float
    used_gb: float
    available_gb: float
    percent_used: float
    mps_allocated_gb: float | None = None
    mps_cached_gb: float | None = None


@dataclass
class ModelMemoryEstimate:
    """モデルのメモリ使用量推定"""
    model_size: ModelSize
    dtype: ModelDtype
    estimated_gb: float
    description: str


# モデルサイズ推定テーブル
MODEL_MEMORY_ESTIMATES: list[ModelMemoryEstimate] = [
    # 1.7B モデル
    ModelMemoryEstimate(ModelSize.LARGE_1_7B, ModelDtype.BF16, 3.4, "1.7B bf16 フル精度"),
    ModelMemoryEstimate(ModelSize.LARGE_1_7B, ModelDtype.FP16, 3.4, "1.7B fp16 フル精度"),
    ModelMemoryEstimate(ModelSize.LARGE_1_7B, ModelDtype.FP32, 6.8, "1.7B fp32 フル精度"),
    ModelMemoryEstimate(ModelSize.LARGE_1_7B, ModelDtype.INT8, 1.7, "1.7B 8bit 量子化"),
    ModelMemoryEstimate(ModelSize.LARGE_1_7B, ModelDtype.INT4, 0.9, "1.7B 4bit 量子化"),
    # 0.6B モデル
    ModelMemoryEstimate(ModelSize.SMALL_0_6B, ModelDtype.BF16, 1.2, "0.6B bf16 フル精度"),
    ModelMemoryEstimate(ModelSize.SMALL_0_6B, ModelDtype.FP16, 1.2, "0.6B fp16 フル精度"),
    ModelMemoryEstimate(ModelSize.SMALL_0_6B, ModelDtype.FP32, 2.4, "0.6B fp32 フル精度"),
    ModelMemoryEstimate(ModelSize.SMALL_0_6B, ModelDtype.INT8, 0.6, "0.6B 8bit 量子化"),
    ModelMemoryEstimate(ModelSize.SMALL_0_6B, ModelDtype.INT4, 0.3, "0.6B 4bit 量子化"),
]


class MemoryManager:
    """Apple Silicon Unified Memory マネージャー（シングルトン）"""

    _instance: MemoryManager | None = None

    def __new__(cls, *args: Any, **kwargs: Any) -> MemoryManager:
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self, watermark_ratio: float = 0.7) -> None:
        if self._initialized:
            return

        self._watermark_ratio = watermark_ratio
        self._initialized = True

        # 環境変数を設定
        self._apply_watermark_ratio()

        logger.info(f"MemoryManager 初期化: watermark_ratio={watermark_ratio}")

    def _apply_watermark_ratio(self) -> None:
        """MPS メモリ上限を環境変数で設定する。"""
        os.environ["PYTORCH_MPS_HIGH_WATERMARK_RATIO"] = str(self._watermark_ratio)
        logger.debug(f"PYTORCH_MPS_HIGH_WATERMARK_RATIO={self._watermark_ratio}")

    def get_memory_info(self) -> MemoryInfo:
        """現在のメモリ使用量を取得する。

        Returns:
            MemoryInfo: メモリ情報
        """
        mem = psutil.virtual_memory()

        info = MemoryInfo(
            total_gb=mem.total / (1024 ** 3),
            used_gb=mem.used / (1024 ** 3),
            available_gb=mem.available / (1024 ** 3),
            percent_used=mem.percent,
        )

        # MPS メモリ情報を取得（利用可能な場合）
        try:
            import torch
            if torch.backends.mps.is_available():
                # PyTorch 2.1+ では mps.current_allocated_memory() が利用可能
                if hasattr(torch.mps, "current_allocated_memory"):
                    info.mps_allocated_gb = torch.mps.current_allocated_memory() / (1024 ** 3)
                # キャッシュメモリ（ドライバレベル）
                if hasattr(torch.mps, "driver_allocated_memory"):
                    info.mps_cached_gb = torch.mps.driver_allocated_memory() / (1024 ** 3)
        except Exception as e:
            logger.debug(f"MPS メモリ情報取得エラー: {e}")

        return info

    def estimate_model_memory(
        self,
        model_name: str,
    ) -> float:
        """モデル名からメモリ使用量を推定する。

        Args:
            model_name: モデル名（例: "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit"）

        Returns:
            float: 推定メモリ使用量 (GB)
        """
        model_name_lower = model_name.lower()

        # サイズ判定
        if "0.6b" in model_name_lower:
            size = ModelSize.SMALL_0_6B
        else:
            size = ModelSize.LARGE_1_7B

        # dtype 判定
        if "4bit" in model_name_lower:
            dtype = ModelDtype.INT4
        elif "8bit" in model_name_lower:
            dtype = ModelDtype.INT8
        elif "fp32" in model_name_lower or "float32" in model_name_lower:
            dtype = ModelDtype.FP32
        elif "bf16" in model_name_lower or "bfloat16" in model_name_lower:
            dtype = ModelDtype.BF16
        else:
            dtype = ModelDtype.FP16  # デフォルト

        # 推定テーブルから取得
        for estimate in MODEL_MEMORY_ESTIMATES:
            if estimate.model_size == size and estimate.dtype == dtype:
                logger.info(f"モデル '{model_name}' の推定メモリ: {estimate.estimated_gb} GB ({estimate.description})")
                return estimate.estimated_gb

        # デフォルト値
        default_estimate = 3.4
        logger.warning(f"モデル '{model_name}' のメモリ推定に失敗。デフォルト値 {default_estimate} GB を使用。")
        return default_estimate

    def check_available_memory(
        self,
        required_gb: float,
        safety_margin_gb: float = 2.0,
    ) -> tuple[bool, str]:
        """モデルロード前にメモリ余裕を確認する。

        Args:
            required_gb: 必要なメモリ量 (GB)
            safety_margin_gb: 安全マージン (GB)

        Returns:
            tuple[bool, str]: (ロード可能か, メッセージ)
        """
        mem_info = self.get_memory_info()
        total_required = required_gb + safety_margin_gb

        if mem_info.available_gb >= total_required:
            msg = (
                f"メモリ確認OK: 必要 {required_gb:.1f} GB, "
                f"利用可能 {mem_info.available_gb:.1f} GB"
            )
            logger.info(msg)
            return True, msg
        else:
            msg = (
                f"メモリ不足の可能性: 必要 {required_gb:.1f} GB + マージン {safety_margin_gb:.1f} GB = {total_required:.1f} GB, "
                f"利用可能 {mem_info.available_gb:.1f} GB。"
                f"他のアプリを閉じるか、量子化モデルの使用を検討してください。"
            )
            logger.warning(msg)
            return False, msg

    def can_load_model(self, model_name: str, safety_margin_gb: float = 2.0) -> tuple[bool, str]:
        """モデルをロード可能かチェックする。

        Args:
            model_name: モデル名
            safety_margin_gb: 安全マージン (GB)

        Returns:
            tuple[bool, str]: (ロード可能か, メッセージ)
        """
        required_gb = self.estimate_model_memory(model_name)
        return self.check_available_memory(required_gb, safety_margin_gb)

    def clear_cache(self) -> None:
        """GPU キャッシュとガベージコレクションを実行する。"""
        logger.info("メモリキャッシュをクリア中...")

        # Python ガベージコレクション
        gc.collect()

        # MPS キャッシュクリア
        try:
            import torch
            if torch.backends.mps.is_available() and hasattr(torch.mps, "empty_cache"):
                torch.mps.empty_cache()
                logger.debug("MPS キャッシュをクリアしました。")
        except Exception as e:
            logger.debug(f"MPS キャッシュクリアエラー: {e}")

        # MLX キャッシュクリア
        try:
            import mlx.core as mx
            mx.metal.clear_cache()
            logger.debug("MLX Metal キャッシュをクリアしました。")
        except Exception as e:
            logger.debug(f"MLX キャッシュクリアエラー: {e}")

        logger.info("メモリキャッシュのクリア完了")

    def set_watermark_ratio(self, ratio: float) -> None:
        """MPS メモリ上限比率を設定する。

        Args:
            ratio: 上限比率 (0.0-1.0)
        """
        if not 0.0 <= ratio <= 1.0:
            raise ValueError(f"ratio は 0.0-1.0 の範囲で指定してください: {ratio}")

        self._watermark_ratio = ratio
        self._apply_watermark_ratio()
        logger.info(f"MPS メモリ上限比率を {ratio} に変更しました。")

    def get_memory_summary(self) -> str:
        """メモリ使用量のサマリーを文字列で返す。"""
        mem_info = self.get_memory_info()

        lines = [
            "=== メモリ使用状況 ===",
            f"総メモリ: {mem_info.total_gb:.1f} GB",
            f"使用中: {mem_info.used_gb:.1f} GB ({mem_info.percent_used:.1f}%)",
            f"利用可能: {mem_info.available_gb:.1f} GB",
        ]

        if mem_info.mps_allocated_gb is not None:
            lines.append(f"MPS 割り当て: {mem_info.mps_allocated_gb:.2f} GB")

        if mem_info.mps_cached_gb is not None:
            lines.append(f"MPS キャッシュ: {mem_info.mps_cached_gb:.2f} GB")

        lines.append(f"MPS 上限比率: {self._watermark_ratio}")

        return "\n".join(lines)

    @staticmethod
    def get_model_estimates_table() -> str:
        """モデルメモリ推定テーブルを文字列で返す。"""
        lines = [
            "=== モデルメモリ使用量の目安 ===",
            "",
            "| モデル | dtype | サイズ |",
            "|--------|-------|--------|",
        ]

        for est in MODEL_MEMORY_ESTIMATES:
            lines.append(f"| {est.model_size.value} | {est.dtype.value} | ~{est.estimated_gb:.1f} GB |")

        return "\n".join(lines)


# 便利なグローバルインスタンス取得関数
def get_memory_manager() -> MemoryManager:
    """MemoryManager のシングルトンインスタンスを取得する。"""
    return MemoryManager()


# エクスポート
__all__ = [
    "MemoryManager",
    "MemoryInfo",
    "ModelSize",
    "ModelDtype",
    "ModelMemoryEstimate",
    "MODEL_MEMORY_ESTIMATES",
    "get_memory_manager",
]
