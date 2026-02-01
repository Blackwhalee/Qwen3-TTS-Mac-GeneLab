#!/usr/bin/env python3
# coding=utf-8
# Copyright 2026 Qwen3-TTS-Mac-GeneLab Contributors.
# SPDX-License-Identifier: Apache-2.0
"""
Qwen3-TTS-Mac-GeneLab クイックスタート

Apple Silicon Mac 上で Qwen3-TTS を使用するサンプルスクリプト。
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

# ログ設定
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


def check_environment() -> bool:
    """環境をチェックする。"""
    print("=" * 50)
    print("環境チェック")
    print("=" * 50)

    # Apple Silicon チェック
    from mac.device_utils import get_mac_info, is_apple_silicon, is_mps_available

    info = get_mac_info()

    print(f"プラットフォーム: {info.get('platform', 'Unknown')}")
    print(f"チップ: {info.get('chip', 'Unknown')}")
    print(f"メモリ: {info.get('total_memory_gb', 'Unknown')} GB")
    print(f"Python: {info.get('python_version', 'Unknown')}")
    print(f"PyTorch: {info.get('torch_version', 'Unknown')}")
    print(f"Apple Silicon: {'Yes' if is_apple_silicon() else 'No'}")
    print(f"MPS 利用可能: {'Yes' if is_mps_available() else 'No'}")

    # MLX チェック
    try:
        import mlx.core as mx
        print(f"MLX: 利用可能")
    except ImportError:
        print(f"MLX: 利用不可")

    # mlx-audio チェック
    try:
        import mlx_audio
        print(f"mlx-audio: 利用可能")
    except ImportError:
        print(f"mlx-audio: 利用不可")

    print("=" * 50)
    return is_apple_silicon()


def demo_custom_voice(
    text: str = "こんにちは、今日はいい天気ですね。散歩に出かけましょう。",
    speaker: str = "Vivian",
    language: str = "Japanese",
    output_path: str = "output_custom.wav",
) -> None:
    """CustomVoice デモ。"""
    print("\n[CustomVoice デモ]")
    print(f"テキスト: {text}")
    print(f"スピーカー: {speaker}")
    print(f"言語: {language}")

    from mac import DualEngine, TaskType

    engine = DualEngine()

    result = engine.generate(
        text=text,
        task_type=TaskType.CUSTOM_VOICE,
        language=language,
        speaker=speaker,
    )

    # 保存
    import soundfile as sf
    sf.write(output_path, result.audio, result.sample_rate)

    print(f"生成完了!")
    print(f"  音声長: {result.duration_seconds:.2f} 秒")
    print(f"  生成時間: {result.generation_time_seconds:.2f} 秒")
    print(f"  エンジン: {result.engine_used.value}")
    print(f"  出力: {output_path}")


def demo_voice_design(
    text: str = "本日は晴天なり。マイクテスト、マイクテスト。",
    description: str = "A calm and professional male announcer voice.",
    language: str = "Japanese",
    output_path: str = "output_design.wav",
) -> None:
    """VoiceDesign デモ。"""
    print("\n[VoiceDesign デモ]")
    print(f"テキスト: {text}")
    print(f"ボイス記述: {description}")
    print(f"言語: {language}")

    from mac import DualEngine, TaskType

    engine = DualEngine()

    result = engine.generate(
        text=text,
        task_type=TaskType.VOICE_DESIGN,
        language=language,
        voice_description=description,
    )

    # 保存
    import soundfile as sf
    sf.write(output_path, result.audio, result.sample_rate)

    print(f"生成完了!")
    print(f"  音声長: {result.duration_seconds:.2f} 秒")
    print(f"  生成時間: {result.generation_time_seconds:.2f} 秒")
    print(f"  エンジン: {result.engine_used.value}")
    print(f"  出力: {output_path}")


def demo_device_utils() -> None:
    """device_utils デモ。"""
    print("\n[device_utils デモ]")

    from mac.device_utils import (
        get_attn_implementation,
        get_optimal_device,
        get_optimal_dtype,
        TaskType,
    )

    device = get_optimal_device()
    print(f"最適デバイス: {device}")

    print("タスク別 dtype:")
    for task in TaskType:
        dtype = get_optimal_dtype(task, device)
        print(f"  {task.value}: {dtype}")

    attn = get_attn_implementation()
    print(f"Attention 実装: {attn}")


def demo_memory_manager() -> None:
    """memory_manager デモ。"""
    print("\n[memory_manager デモ]")

    from mac.memory_manager import get_memory_manager

    mm = get_memory_manager()
    print(mm.get_memory_summary())

    # モデルメモリ推定
    print("\nモデルメモリ推定:")
    test_models = [
        "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
        "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-4bit",
        "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice",
    ]
    for model in test_models:
        estimate = mm.estimate_model_memory(model)
        print(f"  {model}: ~{estimate:.1f} GB")


def main() -> None:
    """メイン関数。"""
    parser = argparse.ArgumentParser(
        description="Qwen3-TTS-Mac-GeneLab クイックスタート",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用例:
  python mac_quickstart.py --check           # 環境チェックのみ
  python mac_quickstart.py --demo custom     # CustomVoice デモ
  python mac_quickstart.py --demo design     # VoiceDesign デモ
  python mac_quickstart.py --demo all        # 全デモ
  python mac_quickstart.py --text "テスト"   # カスタムテキスト
        """,
    )

    parser.add_argument(
        "--check",
        action="store_true",
        help="環境チェックのみ実行",
    )
    parser.add_argument(
        "--demo",
        choices=["custom", "design", "memory", "device", "all"],
        default="custom",
        help="実行するデモ",
    )
    parser.add_argument(
        "--text",
        type=str,
        default="こんにちは、今日はいい天気ですね。",
        help="読み上げテキスト",
    )
    parser.add_argument(
        "--speaker",
        type=str,
        default="Vivian",
        help="スピーカー名 (CustomVoice)",
    )
    parser.add_argument(
        "--language",
        type=str,
        default="Japanese",
        help="言語",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="output.wav",
        help="出力ファイルパス",
    )

    args = parser.parse_args()

    # 環境チェック
    if not check_environment():
        print("警告: Apple Silicon Mac ではありません。一部の機能が利用できない場合があります。")

    if args.check:
        return

    # デモ実行
    if args.demo in ("device", "all"):
        demo_device_utils()

    if args.demo in ("memory", "all"):
        demo_memory_manager()

    if args.demo in ("custom", "all"):
        demo_custom_voice(
            text=args.text,
            speaker=args.speaker,
            language=args.language,
            output_path=args.output if args.demo == "custom" else "output_custom.wav",
        )

    if args.demo in ("design", "all"):
        demo_voice_design(
            text=args.text,
            language=args.language,
            output_path="output_design.wav" if args.demo == "all" else args.output,
        )

    print("\n完了!")


if __name__ == "__main__":
    main()
