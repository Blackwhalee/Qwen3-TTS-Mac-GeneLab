# coding=utf-8
# Copyright 2026 Qwen3-TTS-Mac-GeneLab Contributors.
# SPDX-License-Identifier: Apache-2.0
"""
Whisper 自動書き起こし

Voice Clone 用の参照音声書き起こし機能を提供する。
- MLX Whisper を優先使用（Apple Silicon ネイティブ）
- フォールバック: openai-whisper (PyTorch MPS/CPU)
- 言語自動検出 + 手動指定オプション
"""

from __future__ import annotations

import logging
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Literal

import numpy as np

logger = logging.getLogger(__name__)


# サポートする言語
SUPPORTED_LANGUAGES = {
    "auto": "自動検出",
    "ja": "日本語",
    "en": "英語",
    "zh": "中国語",
    "ko": "韓国語",
    "fr": "フランス語",
    "de": "ドイツ語",
    "es": "スペイン語",
    "it": "イタリア語",
    "pt": "ポルトガル語",
    "ru": "ロシア語",
}

# UI で使用する言語コードへのマッピング
LANGUAGE_CODE_MAP = {
    "Japanese": "ja",
    "English": "en",
    "Chinese": "zh",
    "Korean": "ko",
    "French": "fr",
    "German": "de",
    "Spanish": "es",
    "Italian": "it",
    "Portuguese": "pt",
    "Russian": "ru",
}


@dataclass
class TranscriptionResult:
    """書き起こし結果"""
    text: str
    language: str
    duration_seconds: float
    processing_time_seconds: float
    engine: Literal["mlx", "openai-whisper", "unknown"]
    confidence: float | None = None


class WhisperTranscriber:
    """Whisper 書き起こしクラス

    MLX Whisper を優先使用し、利用不可の場合は openai-whisper にフォールバック。
    """

    def __init__(
        self,
        model_name: str = "mlx-community/whisper-large-v3-turbo-asr-fp16",
        prefer_mlx: bool = True,
    ) -> None:
        """初期化。

        Args:
            model_name: 使用する Whisper モデル名
            prefer_mlx: MLX を優先するかどうか
        """
        self._model_name = model_name
        self._prefer_mlx = prefer_mlx
        self._mlx_model: Any = None
        self._openai_model: Any = None
        self._mlx_available = False
        self._openai_available = False

        # 利用可能なエンジンをチェック
        self._check_available_engines()

    def _check_available_engines(self) -> None:
        """利用可能なエンジンをチェックする。"""
        # MLX Whisper チェック
        try:
            from mlx_audio.stt import load_model as mlx_load_model  # noqa: F401
            self._mlx_available = True
            logger.info("MLX Whisper (mlx-audio) が利用可能です。")
        except ImportError:
            logger.info("MLX Whisper が利用できません。")

        # openai-whisper チェック
        try:
            import whisper  # noqa: F401
            self._openai_available = True
            logger.info("openai-whisper が利用可能です。")
        except ImportError:
            logger.info("openai-whisper が利用できません。")

        if not self._mlx_available and not self._openai_available:
            logger.warning("Whisper エンジンが利用できません。書き起こし機能は使用できません。")

    def _load_mlx_model(self) -> None:
        """MLX Whisper モデルをロードする。"""
        if self._mlx_model is not None:
            return

        logger.info(f"MLX Whisper モデルをロード中: {self._model_name}")
        start_time = time.time()

        try:
            from mlx_audio.stt import load_model as mlx_load_model
            self._mlx_model = mlx_load_model(self._model_name)

            elapsed = time.time() - start_time
            logger.info(f"MLX Whisper モデルのロード完了: {elapsed:.2f}秒")
        except Exception as e:
            logger.error(f"MLX Whisper モデルのロードに失敗: {e}")
            self._mlx_available = False
            raise

    def _load_openai_model(self) -> None:
        """openai-whisper モデルをロードする。"""
        if self._openai_model is not None:
            return

        logger.info("openai-whisper モデルをロード中...")
        start_time = time.time()

        try:
            import whisper
            # large-v3-turbo または large-v3 を使用
            model_size = "large-v3"
            self._openai_model = whisper.load_model(model_size)

            elapsed = time.time() - start_time
            logger.info(f"openai-whisper モデルのロード完了: {elapsed:.2f}秒")
        except Exception as e:
            logger.error(f"openai-whisper モデルのロードに失敗: {e}")
            self._openai_available = False
            raise

    def _transcribe_mlx(
        self,
        audio_path: str,
        language: str | None = None,
    ) -> TranscriptionResult:
        """MLX Whisper で書き起こす。"""
        self._load_mlx_model()

        logger.info(f"MLX Whisper で書き起こし中: {audio_path}")
        start_time = time.time()

        try:
            # MLX Whisper の generate メソッドを使用
            decode_options = {}
            if language and language != "auto":
                decode_options["language"] = language

            result = self._mlx_model.generate(
                audio_path,
                verbose=False,
                **decode_options,
            )

            # 結果のパース
            if isinstance(result, dict):
                text = result.get("text", "")
                detected_lang = result.get("language", language or "unknown")
            elif hasattr(result, "text"):
                text = result.text
                detected_lang = getattr(result, "language", language or "unknown")
            elif isinstance(result, str):
                text = result
                detected_lang = language or "unknown"
            else:
                # ジェネレータの場合、全てのセグメントを結合
                segments = list(result)
                text = " ".join(seg.get("text", "") if isinstance(seg, dict) else str(seg) for seg in segments)
                detected_lang = language or "unknown"

            processing_time = time.time() - start_time

            # 音声長を取得
            try:
                import librosa
                audio, sr = librosa.load(audio_path, sr=None)
                duration = len(audio) / sr
            except Exception:
                duration = 0.0

            return TranscriptionResult(
                text=text.strip(),
                language=detected_lang,
                duration_seconds=duration,
                processing_time_seconds=processing_time,
                engine="mlx",
            )

        except Exception as e:
            logger.error(f"MLX Whisper 書き起こしエラー: {e}")
            raise

    def _transcribe_openai(
        self,
        audio_path: str,
        language: str | None = None,
    ) -> TranscriptionResult:
        """openai-whisper で書き起こす。"""
        self._load_openai_model()

        logger.info(f"openai-whisper で書き起こし中: {audio_path}")
        start_time = time.time()

        try:
            result = self._openai_model.transcribe(
                audio_path,
                language=language if language and language != "auto" else None,
            )

            text = result.get("text", "")
            detected_lang = result.get("language", language or "unknown")

            processing_time = time.time() - start_time

            # 音声長を取得
            try:
                import librosa
                audio, sr = librosa.load(audio_path, sr=None)
                duration = len(audio) / sr
            except Exception:
                duration = 0.0

            return TranscriptionResult(
                text=text.strip(),
                language=detected_lang,
                duration_seconds=duration,
                processing_time_seconds=processing_time,
                engine="openai-whisper",
            )

        except Exception as e:
            logger.error(f"openai-whisper 書き起こしエラー: {e}")
            raise

    def transcribe(
        self,
        audio_path: str | Path,
        language: str | None = None,
        progress_callback: Callable[[float], None] | None = None,
    ) -> str:
        """音声を書き起こす。

        Args:
            audio_path: 音声ファイルパス
            language: 言語コード（"ja", "en", etc.）または UI 言語名（"Japanese", etc.）
            progress_callback: 進捗コールバック（0.0-1.0）

        Returns:
            str: 書き起こされたテキスト
        """
        audio_path = str(audio_path)

        # UI 言語名を言語コードに変換
        if language and language in LANGUAGE_CODE_MAP:
            language = LANGUAGE_CODE_MAP[language]

        # 進捗コールバック（開始）
        if progress_callback:
            progress_callback(0.1)

        result: TranscriptionResult

        # MLX を優先
        if self._prefer_mlx and self._mlx_available:
            try:
                if progress_callback:
                    progress_callback(0.3)
                result = self._transcribe_mlx(audio_path, language)
                if progress_callback:
                    progress_callback(1.0)
                logger.info(
                    f"書き起こし完了 (MLX): "
                    f"{result.duration_seconds:.2f}秒の音声 -> {result.processing_time_seconds:.2f}秒で処理"
                )
                return result.text
            except Exception as e:
                logger.warning(f"MLX Whisper 失敗、フォールバック: {e}")

        # openai-whisper にフォールバック
        if self._openai_available:
            try:
                if progress_callback:
                    progress_callback(0.3)
                result = self._transcribe_openai(audio_path, language)
                if progress_callback:
                    progress_callback(1.0)
                logger.info(
                    f"書き起こし完了 (openai-whisper): "
                    f"{result.duration_seconds:.2f}秒の音声 -> {result.processing_time_seconds:.2f}秒で処理"
                )
                return result.text
            except Exception as e:
                logger.error(f"openai-whisper も失敗: {e}")
                raise

        raise RuntimeError("利用可能な Whisper エンジンがありません。mlx-audio または openai-whisper をインストールしてください。")

    def transcribe_detailed(
        self,
        audio_path: str | Path,
        language: str | None = None,
    ) -> TranscriptionResult:
        """音声を書き起こし、詳細な結果を返す。

        Args:
            audio_path: 音声ファイルパス
            language: 言語コード

        Returns:
            TranscriptionResult: 詳細な書き起こし結果
        """
        audio_path = str(audio_path)

        # UI 言語名を言語コードに変換
        if language and language in LANGUAGE_CODE_MAP:
            language = LANGUAGE_CODE_MAP[language]

        # MLX を優先
        if self._prefer_mlx and self._mlx_available:
            try:
                return self._transcribe_mlx(audio_path, language)
            except Exception as e:
                logger.warning(f"MLX Whisper 失敗、フォールバック: {e}")

        # openai-whisper にフォールバック
        if self._openai_available:
            return self._transcribe_openai(audio_path, language)

        raise RuntimeError("利用可能な Whisper エンジンがありません。")

    def unload(self) -> None:
        """モデルをアンロードしてメモリを解放する。"""
        if self._mlx_model is not None:
            logger.info("MLX Whisper モデルをアンロード中...")
            self._mlx_model = None
            try:
                import mlx.core as mx
                mx.metal.clear_cache()
            except Exception:
                pass

        if self._openai_model is not None:
            logger.info("openai-whisper モデルをアンロード中...")
            del self._openai_model
            self._openai_model = None
            try:
                import torch
                if hasattr(torch.mps, "empty_cache"):
                    torch.mps.empty_cache()
            except Exception:
                pass

        import gc
        gc.collect()
        logger.info("Whisper モデルのアンロード完了")

    @property
    def is_available(self) -> bool:
        """Whisper が利用可能かどうか。"""
        return self._mlx_available or self._openai_available

    @property
    def available_engines(self) -> list[str]:
        """利用可能なエンジンのリスト。"""
        engines = []
        if self._mlx_available:
            engines.append("mlx")
        if self._openai_available:
            engines.append("openai-whisper")
        return engines


# 便利なグローバルインスタンス
_transcriber: WhisperTranscriber | None = None


def get_transcriber() -> WhisperTranscriber:
    """WhisperTranscriber のシングルトンインスタンスを取得する。"""
    global _transcriber
    if _transcriber is None:
        _transcriber = WhisperTranscriber()
    return _transcriber


# エクスポート
__all__ = [
    "WhisperTranscriber",
    "TranscriptionResult",
    "SUPPORTED_LANGUAGES",
    "LANGUAGE_CODE_MAP",
    "get_transcriber",
]
