# coding=utf-8
# Copyright 2026 Qwen3-TTS-Mac-GeneLab Contributors.
# SPDX-License-Identifier: Apache-2.0
"""
設定タブ

エンジン選択、量子化レベル、メモリモニタなどの設定を管理する。
"""

from __future__ import annotations

import logging
from typing import Any

import gradio as gr

logger = logging.getLogger(__name__)


def get_system_info() -> str:
    """システム情報を取得する。"""
    try:
        from mac.device_utils import get_mac_info

        info = get_mac_info()
        lines = [
            "### システム情報",
            "",
            f"- **チップ**: {info.get('chip', '不明')}",
            f"- **メモリ**: {info.get('total_memory_gb', '不明')} GB",
            f"- **macOS**: {info.get('platform_version', '不明')}",
            f"- **Python**: {info.get('python_version', '不明')}",
            f"- **PyTorch**: {info.get('torch_version', '不明')}",
            f"- **MPS**: {'利用可能' if info.get('mps_available') else '利用不可'}",
        ]
        return "\n".join(lines)
    except Exception as e:
        logger.error(f"システム情報取得エラー: {e}")
        return f"システム情報の取得に失敗しました: {e}"


def get_memory_usage() -> dict[str, Any]:
    """メモリ使用量を取得する。"""
    try:
        import psutil

        mem = psutil.virtual_memory()
        return {
            "total_gb": mem.total / (1024 ** 3),
            "used_gb": mem.used / (1024 ** 3),
            "available_gb": mem.available / (1024 ** 3),
            "percent": mem.percent,
        }
    except Exception as e:
        logger.error(f"メモリ情報取得エラー: {e}")
        return {
            "total_gb": 0,
            "used_gb": 0,
            "available_gb": 0,
            "percent": 0,
        }


def format_memory_display() -> str:
    """メモリ使用量の表示文字列を生成する。"""
    mem = get_memory_usage()
    return (
        f"使用中: {mem['used_gb']:.1f} GB / {mem['total_gb']:.1f} GB "
        f"({mem['percent']:.1f}%) | "
        f"空き: {mem['available_gb']:.1f} GB"
    )


def get_engine_status() -> str:
    """エンジンの状態を取得する。"""
    try:
        from mac.engine import DualEngine

        engine = DualEngine()
        status = engine.get_status()

        lines = ["### エンジン状態", ""]

        for name, eng_status in status.items():
            loaded = "ロード済み" if eng_status.is_loaded else "未ロード"
            model = eng_status.model_name or "-"
            lines.append(f"**{name.upper()}**")
            lines.append(f"- 状態: {loaded}")
            lines.append(f"- モデル: {model}")
            lines.append(f"- デバイス: {eng_status.device}")
            lines.append(f"- dtype: {eng_status.dtype}")
            lines.append("")

        return "\n".join(lines)
    except Exception as e:
        logger.error(f"エンジン状態取得エラー: {e}")
        return f"エンジン状態の取得に失敗しました: {e}"


def change_engine(engine_type: str) -> str:
    """優先エンジンを変更する。"""
    try:
        from mac.engine import DualEngine, EngineType

        engine = DualEngine()
        engine.set_preferred_engine(engine_type)
        return f"優先エンジンを {engine_type} に変更しました。"
    except Exception as e:
        logger.error(f"エンジン変更エラー: {e}")
        return f"エラー: {e}"


def unload_models() -> str:
    """全モデルをアンロードする。"""
    try:
        from mac.engine import DualEngine

        engine = DualEngine()
        engine.unload()
        return "全モデルをアンロードしました。メモリを解放しました。"
    except Exception as e:
        logger.error(f"モデルアンロードエラー: {e}")
        return f"エラー: {e}"


def create_settings_tab() -> None:
    """設定タブを作成する。"""
    with gr.Row():
        with gr.Column(scale=1):
            gr.Markdown("## エンジン設定")

            # エンジン選択
            engine_selector = gr.Radio(
                choices=[
                    ("AUTO（推奨）", "auto"),
                    ("MLX（Apple Silicon 最適化）", "mlx"),
                    ("PyTorch MPS", "pytorch_mps"),
                ],
                value="auto",
                label="優先エンジン",
                info="AUTO: タスクに応じて自動選択。MLX: 高速・省メモリ。MPS: Voice Clone 用。",
            )

            engine_status_btn = gr.Button("エンジン状態を更新", variant="secondary")
            engine_change_btn = gr.Button("エンジンを変更", variant="primary")

            engine_status_display = gr.Markdown(get_engine_status())

            # エンジン変更結果
            engine_change_result = gr.Textbox(
                label="結果",
                interactive=False,
                visible=True,
            )

        with gr.Column(scale=1):
            gr.Markdown("## メモリ管理")

            # メモリモニター
            memory_display = gr.Textbox(
                label="メモリ使用量",
                value=format_memory_display(),
                interactive=False,
            )

            memory_refresh_btn = gr.Button("更新", variant="secondary")

            # モデルアンロード
            gr.Markdown("### モデル管理")
            unload_btn = gr.Button(
                "全モデルをアンロード",
                variant="stop",
            )
            unload_result = gr.Textbox(
                label="結果",
                interactive=False,
            )

            # メモリ使用量の目安
            gr.Markdown(
                """
                #### メモリ使用量の目安
                
                | モデル | dtype | サイズ |
                |--------|-------|--------|
                | 1.7B | bf16 | ~3.4 GB |
                | 1.7B | 8bit | ~1.7 GB |
                | 1.7B | 4bit | ~0.9 GB |
                | 0.6B | bf16 | ~1.2 GB |
                
                > MLX の量子化モデルを使用すると、大幅にメモリを節約できます。
                """
            )

    with gr.Row():
        with gr.Column():
            gr.Markdown("## システム情報")
            system_info = gr.Markdown(get_system_info())
            refresh_system_btn = gr.Button("システム情報を更新", variant="secondary")

    with gr.Row():
        with gr.Column():
            gr.Markdown(
                """
                ## 技術情報
                
                ### MPS の既知の制約
                
                - **Voice Clone**: `float32` 必須（float16 だとエラー）
                - **FlashAttention 2**: Mac 非対応（SDPA を使用）
                - **BFloat16**: M1/M2 では不安定な場合あり
                
                ### 環境変数
                
                ```
                PYTORCH_ENABLE_MPS_FALLBACK=1
                PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.7
                TOKENIZERS_PARALLELISM=false
                ```
                
                ### トラブルシューティング
                
                1. **SoX エラー**: `brew install sox`
                2. **メモリ不足**: 他のアプリを閉じるか、量子化モデルを使用
                3. **生成が遅い**: MLX エンジンを使用（AUTO で自動選択）
                """
            )

    # イベントハンドラ
    engine_status_btn.click(
        fn=get_engine_status,
        outputs=[engine_status_display],
    )

    engine_change_btn.click(
        fn=change_engine,
        inputs=[engine_selector],
        outputs=[engine_change_result],
    )

    memory_refresh_btn.click(
        fn=format_memory_display,
        outputs=[memory_display],
    )

    unload_btn.click(
        fn=unload_models,
        outputs=[unload_result],
    )

    refresh_system_btn.click(
        fn=get_system_info,
        outputs=[system_info],
    )
