# coding=utf-8
# Copyright 2026 Qwen3-TTS-Mac-GeneLab Contributors.
# SPDX-License-Identifier: Apache-2.0
"""
mac: Apple Silicon Mac 最適化モジュール

このモジュールは、Qwen3-TTS を Apple Silicon Mac 上で最適に動作させるための
ユーティリティとエンジン管理機能を提供します。

主要コンポーネント:
- device_utils: デバイス検出と dtype 自動選択
- engine: デュアルエンジンマネージャー（MLX / PyTorch MPS）
- memory_manager: Unified Memory 管理
- whisper_transcriber: Whisper 自動書き起こし
- benchmark: パフォーマンス計測
"""

from __future__ import annotations

from .device_utils import (
    get_optimal_device,
    get_optimal_dtype,
    get_attn_implementation,
    get_environment_vars,
    is_apple_silicon,
    is_mps_available,
)
from .engine import DualEngine, EngineType, TaskType
from .memory_manager import MemoryManager, get_memory_manager
from .whisper_transcriber import WhisperTranscriber, get_transcriber
from .benchmark import Benchmark, get_benchmark

__all__ = [
    # device_utils
    "get_optimal_device",
    "get_optimal_dtype",
    "get_attn_implementation",
    "get_environment_vars",
    "is_apple_silicon",
    "is_mps_available",
    # engine
    "DualEngine",
    "EngineType",
    "TaskType",
    # memory_manager
    "MemoryManager",
    "get_memory_manager",
    # whisper_transcriber
    "WhisperTranscriber",
    "get_transcriber",
    # benchmark
    "Benchmark",
    "get_benchmark",
]

__version__ = "0.1.0"
