# coding=utf-8
# Copyright 2026 Qwen3-TTS-Mac-GeneLab Contributors.
# SPDX-License-Identifier: Apache-2.0
"""
ui.components: Gradio コンポーネントモジュール
"""

from __future__ import annotations

from .custom_voice_tab import create_custom_voice_tab
from .settings_tab import create_settings_tab
from .voice_clone_tab import create_voice_clone_tab
from .voice_design_tab import create_voice_design_tab

__all__ = [
    "create_custom_voice_tab",
    "create_voice_design_tab",
    "create_voice_clone_tab",
    "create_settings_tab",
]
