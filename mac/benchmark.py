# coding=utf-8
# Copyright 2026 Qwen3-TTS-Mac-GeneLab Contributors.
# SPDX-License-Identifier: Apache-2.0
"""
パフォーマンスベンチマーク

- 生成速度（tokens/sec）計測
- メモリ使用量トラッキング
- 結果を UI に表示
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Callable

import numpy as np

from .memory_manager import MemoryInfo, get_memory_manager

logger = logging.getLogger(__name__)


@dataclass
class BenchmarkResult:
    """ベンチマーク結果"""
    # 基本情報
    timestamp: datetime
    engine: str
    task_type: str
    model_name: str | None

    # 入力情報
    input_text: str
    input_length_chars: int

    # 出力情報
    audio_duration_seconds: float
    audio_sample_rate: int

    # パフォーマンス指標
    total_time_seconds: float
    load_time_seconds: float | None
    generation_time_seconds: float
    real_time_factor: float  # audio_duration / generation_time

    # メモリ情報
    memory_before: MemoryInfo | None
    memory_after: MemoryInfo | None
    memory_peak_mb: float | None

    # 追加メタデータ
    metadata: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        """派生フィールドを計算する。"""
        if self.audio_duration_seconds > 0 and self.generation_time_seconds > 0:
            self.real_time_factor = self.audio_duration_seconds / self.generation_time_seconds

    def to_dict(self) -> dict[str, Any]:
        """辞書形式に変換する。"""
        return {
            "timestamp": self.timestamp.isoformat(),
            "engine": self.engine,
            "task_type": self.task_type,
            "model_name": self.model_name,
            "input_length_chars": self.input_length_chars,
            "audio_duration_seconds": self.audio_duration_seconds,
            "total_time_seconds": self.total_time_seconds,
            "generation_time_seconds": self.generation_time_seconds,
            "real_time_factor": self.real_time_factor,
            "memory_used_gb": self.memory_after.used_gb if self.memory_after else None,
        }

    def format_summary(self) -> str:
        """サマリー文字列を生成する。"""
        lines = [
            "=== ベンチマーク結果 ===",
            f"エンジン: {self.engine}",
            f"タスク: {self.task_type}",
            f"入力: {self.input_length_chars} 文字",
            f"出力: {self.audio_duration_seconds:.2f} 秒の音声",
            f"生成時間: {self.generation_time_seconds:.2f} 秒",
            f"リアルタイム比率: {self.real_time_factor:.2f}x",
        ]

        if self.memory_after:
            lines.append(f"メモリ使用: {self.memory_after.used_gb:.1f} GB")

        return "\n".join(lines)


class Benchmark:
    """パフォーマンスベンチマーククラス"""

    def __init__(self) -> None:
        """初期化。"""
        self._memory_manager = get_memory_manager()
        self._results: list[BenchmarkResult] = []
        self._is_tracking = False
        self._start_time: float | None = None
        self._start_memory: MemoryInfo | None = None

    def start_tracking(self) -> None:
        """トラッキングを開始する。"""
        self._is_tracking = True
        self._start_time = time.time()
        self._start_memory = self._memory_manager.get_memory_info()
        logger.debug("ベンチマークトラッキング開始")

    def stop_tracking(
        self,
        engine: str,
        task_type: str,
        input_text: str,
        audio: np.ndarray,
        sample_rate: int,
        model_name: str | None = None,
        load_time: float | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> BenchmarkResult:
        """トラッキングを停止し、結果を記録する。

        Args:
            engine: 使用したエンジン名
            task_type: タスクの種類
            input_text: 入力テキスト
            audio: 生成された音声データ
            sample_rate: サンプルレート
            model_name: モデル名
            load_time: モデルロード時間
            metadata: 追加メタデータ

        Returns:
            BenchmarkResult: ベンチマーク結果
        """
        if not self._is_tracking or self._start_time is None:
            raise RuntimeError("トラッキングが開始されていません。")

        end_time = time.time()
        end_memory = self._memory_manager.get_memory_info()

        total_time = end_time - self._start_time
        generation_time = total_time - (load_time or 0)
        audio_duration = len(audio) / sample_rate

        result = BenchmarkResult(
            timestamp=datetime.now(),
            engine=engine,
            task_type=task_type,
            model_name=model_name,
            input_text=input_text[:100],  # 最初の100文字のみ保存
            input_length_chars=len(input_text),
            audio_duration_seconds=audio_duration,
            audio_sample_rate=sample_rate,
            total_time_seconds=total_time,
            load_time_seconds=load_time,
            generation_time_seconds=generation_time,
            real_time_factor=audio_duration / generation_time if generation_time > 0 else 0,
            memory_before=self._start_memory,
            memory_after=end_memory,
            memory_peak_mb=None,  # PyTorch MPS では取得困難
            metadata=metadata or {},
        )

        self._results.append(result)
        self._is_tracking = False
        self._start_time = None
        self._start_memory = None

        logger.info(f"ベンチマーク完了: {result.real_time_factor:.2f}x リアルタイム")

        return result

    def measure(
        self,
        func: Callable[[], tuple[np.ndarray, int]],
        engine: str,
        task_type: str,
        input_text: str,
        model_name: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> tuple[np.ndarray, int, BenchmarkResult]:
        """関数の実行時間を計測する。

        Args:
            func: 実行する関数（戻り値: (audio, sample_rate)）
            engine: エンジン名
            task_type: タスク種類
            input_text: 入力テキスト
            model_name: モデル名
            metadata: 追加メタデータ

        Returns:
            tuple: (音声データ, サンプルレート, ベンチマーク結果)
        """
        self.start_tracking()

        try:
            audio, sample_rate = func()
        except Exception as e:
            self._is_tracking = False
            raise

        result = self.stop_tracking(
            engine=engine,
            task_type=task_type,
            input_text=input_text,
            audio=audio,
            sample_rate=sample_rate,
            model_name=model_name,
            metadata=metadata,
        )

        return audio, sample_rate, result

    def get_results(self) -> list[BenchmarkResult]:
        """全てのベンチマーク結果を取得する。"""
        return self._results.copy()

    def get_latest_result(self) -> BenchmarkResult | None:
        """最新のベンチマーク結果を取得する。"""
        return self._results[-1] if self._results else None

    def get_average_stats(self) -> dict[str, float]:
        """平均統計を取得する。"""
        if not self._results:
            return {}

        total_times = [r.total_time_seconds for r in self._results]
        gen_times = [r.generation_time_seconds for r in self._results]
        rtf = [r.real_time_factor for r in self._results]

        return {
            "avg_total_time": sum(total_times) / len(total_times),
            "avg_generation_time": sum(gen_times) / len(gen_times),
            "avg_real_time_factor": sum(rtf) / len(rtf),
            "total_runs": len(self._results),
        }

    def clear_results(self) -> None:
        """結果をクリアする。"""
        self._results.clear()
        logger.info("ベンチマーク結果をクリアしました。")

    def format_comparison_table(self) -> str:
        """エンジン比較テーブルを文字列で生成する。"""
        if not self._results:
            return "ベンチマーク結果がありません。"

        # エンジンごとに結果をグループ化
        by_engine: dict[str, list[BenchmarkResult]] = {}
        for r in self._results:
            if r.engine not in by_engine:
                by_engine[r.engine] = []
            by_engine[r.engine].append(r)

        lines = [
            "| エンジン | 実行回数 | 平均生成時間 | 平均RTF |",
            "|----------|----------|--------------|---------|",
        ]

        for engine, results in by_engine.items():
            count = len(results)
            avg_gen = sum(r.generation_time_seconds for r in results) / count
            avg_rtf = sum(r.real_time_factor for r in results) / count
            lines.append(f"| {engine} | {count} | {avg_gen:.2f}秒 | {avg_rtf:.2f}x |")

        return "\n".join(lines)


# グローバルインスタンス
_benchmark: Benchmark | None = None


def get_benchmark() -> Benchmark:
    """Benchmark のシングルトンインスタンスを取得する。"""
    global _benchmark
    if _benchmark is None:
        _benchmark = Benchmark()
    return _benchmark


def format_performance_status(
    generation_time: float,
    audio_duration: float,
    memory_used_gb: float | None = None,
) -> str:
    """パフォーマンスステータス文字列を生成する。

    Args:
        generation_time: 生成時間（秒）
        audio_duration: 音声長（秒）
        memory_used_gb: メモリ使用量（GB）

    Returns:
        str: ステータス文字列
    """
    rtf = audio_duration / generation_time if generation_time > 0 else 0

    parts = [
        f"生成時間: {generation_time:.2f}秒",
        f"音声長: {audio_duration:.2f}秒",
        f"RTF: {rtf:.2f}x",
    ]

    if memory_used_gb is not None:
        parts.append(f"メモリ: {memory_used_gb:.1f}GB")

    return " | ".join(parts)


# エクスポート
__all__ = [
    "Benchmark",
    "BenchmarkResult",
    "get_benchmark",
    "format_performance_status",
]
