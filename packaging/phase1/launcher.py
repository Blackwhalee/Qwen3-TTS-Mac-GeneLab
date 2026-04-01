#!/usr/bin/env python3
"""
YujieTTS.app launcher — bootstraps model check, then starts Gradio UI.
"""
from __future__ import annotations

import logging
import os
import sys
import webbrowser
from pathlib import Path
from threading import Timer

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("YujieTTS")

os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
os.environ.setdefault("PYTORCH_MPS_HIGH_WATERMARK_RATIO", "0.0")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

PROJECT_ROOT = Path(__file__).resolve().parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

_PARENT = Path(__file__).resolve().parent
if str(_PARENT) not in sys.path:
    sys.path.insert(0, str(_PARENT))

from model_manager import ensure_required_models, check_all_models


def main() -> None:
    logger.info("YujieTTS starting — checking models …")
    statuses = check_all_models()
    for s in statuses:
        tag = "OK" if s.available else "MISSING"
        logger.info("  [%s] %s (%s) %s", tag, s.name, s.size_hint, s.repo_id)

    if not ensure_required_models():
        logger.error(
            "Could not download required models. "
            "Check your network and try again."
        )
        sys.exit(1)

    from ui.app import create_app, CUSTOM_CSS, _UPLOAD_FIX_JS
    import gradio as gr

    port = int(os.environ.get("YUJIE_PORT", "7860"))

    app = create_app(default_lang="zh")

    def _open_browser() -> None:
        webbrowser.open(f"http://localhost:{port}")

    Timer(2.0, _open_browser).start()

    logger.info("Starting YujieTTS on http://localhost:%d", port)
    app.launch(
        server_name="127.0.0.1",
        server_port=port,
        share=False,
        show_error=True,
        css=CUSTOM_CSS,
        js=_UPLOAD_FIX_JS,
        theme=gr.themes.Soft(
            primary_hue="blue",
            secondary_hue="slate",
            neutral_hue="slate",
        ),
        inbrowser=False,
    )


if __name__ == "__main__":
    main()
