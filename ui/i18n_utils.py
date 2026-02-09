# coding=utf-8
# Copyright 2026 Qwen3-TTS-Mac-GeneLab Contributors.
# SPDX-License-Identifier: Apache-2.0
"""
多言語 (i18n) ユーティリティ

グローバルな翻訳辞書を管理し、全コンポーネントから t() で翻訳文字列を取得する。
対応言語: ja, en, zh, ko, ru, es, it, de, fr, pt
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

I18N_DIR = Path(__file__).parent / "i18n"

# グローバル翻訳辞書
_i18n: dict[str, Any] = {}
_current_lang: str = "ja"

# UI 言語選択肢（常にネイティブ表記で表示）
UI_LANGUAGES: list[tuple[str, str]] = [
    ("日本語", "ja"),
    ("English", "en"),
    ("中文", "zh"),
    ("한국어", "ko"),
    ("Русский", "ru"),
    ("Español", "es"),
    ("Italiano", "it"),
    ("Deutsch", "de"),
    ("Français", "fr"),
    ("Português", "pt"),
]

SUPPORTED_LANG_CODES = [code for _, code in UI_LANGUAGES]


def load_i18n(lang: str = "ja") -> dict[str, Any]:
    """i18n ファイルをロードしグローバル辞書を更新する。

    Args:
        lang: 言語コード (ja, en, zh, ko, ru, es, it, de, fr, pt)

    Returns:
        翻訳辞書
    """
    global _i18n, _current_lang

    if lang not in SUPPORTED_LANG_CODES:
        logger.warning(f"未対応言語: {lang}, en にフォールバック")
        lang = "en"

    i18n_file = I18N_DIR / f"{lang}.json"
    if not i18n_file.exists():
        logger.warning(f"i18n ファイルが見つかりません: {i18n_file}, en にフォールバック")
        i18n_file = I18N_DIR / "en.json"

    with open(i18n_file, "r", encoding="utf-8") as f:
        _i18n = json.load(f)

    _current_lang = lang
    return _i18n


def t(key: str, default: str | None = None) -> str:
    """翻訳キーから文字列を取得する。

    Args:
        key: ドット区切りのキー (例: "tabs.custom_voice")
        default: デフォルト値

    Returns:
        翻訳された文字列
    """
    keys = key.split(".")
    value: Any = _i18n
    for k in keys:
        if isinstance(value, dict) and k in value:
            value = value[k]
        else:
            return default if default is not None else key
    return str(value) if not isinstance(value, dict) else (default or key)


def t_list(key: str) -> list[str]:
    """翻訳キーからリストを取得する。

    Args:
        key: ドット区切りのキー

    Returns:
        翻訳された文字列のリスト
    """
    keys = key.split(".")
    value: Any = _i18n
    for k in keys:
        if isinstance(value, dict) and k in value:
            value = value[k]
        else:
            return []
    return value if isinstance(value, list) else []


def get_current_lang() -> str:
    """現在の UI 言語コードを返す。"""
    return _current_lang
