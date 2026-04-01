"""
py2app setup for YujieTTS.app

Usage (from project root):
    cd /path/to/Qwen3-TTS-Mac-GeneLab
    python packaging/phase1/setup_py2app.py py2app

The resulting .app lands in dist/YujieTTS.app
"""
from __future__ import annotations

import os
import sys
from pathlib import Path
from setuptools import setup

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
os.chdir(PROJECT_ROOT)
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

APP = ["packaging/phase1/launcher.py"]

PLIST = {
    "CFBundleName": "YujieTTS",
    "CFBundleDisplayName": "YujieTTS - 御姐语音",
    "CFBundleIdentifier": "com.yujie.tts",
    "CFBundleVersion": "0.1.0",
    "CFBundleShortVersionString": "0.1.0",
    "LSMinimumSystemVersion": "14.0",
    "NSHighResolutionCapable": True,
    "CFBundleDocumentTypes": [],
    "NSMicrophoneUsageDescription": "Voice clone requires microphone access.",
}

OPTIONS = {
    "argv_emulation": False,
    "plist": PLIST,
    "iconfile": None,
    "packages": [
        "gradio",
        "gradio_client",
        "huggingface_hub",
        "transformers",
        "accelerate",
        "safetensors",
        "tokenizers",
        "mlx",
        "mlx_lm",
        "mlx_audio",
        "numpy",
        "scipy",
        "soundfile",
        "librosa",
        "audioread",
        "psutil",
        "einops",
        "tqdm",
        "fastapi",
        "uvicorn",
        "starlette",
        "httpx",
        "httpcore",
        "anyio",
        "pydantic",
        "pydantic_core",
        "jinja2",
        "markupsafe",
        "yaml",
        "aiofiles",
        "multidict",
        "yarl",
        "ui",
        "mac",
        "qwen_tts",
    ],
    "includes": [
        "ui.app",
        "ui.components.custom_voice_tab",
        "ui.components.voice_design_tab",
        "ui.components.voice_clone_tab",
        "ui.components.settings_tab",
        "ui.i18n_utils",
        "mac.engine",
        "mac.device_utils",
        "mac.memory_manager",
        "mac.whisper_transcriber",
        "mac.benchmark",
        "cffi",
        "_cffi_backend",
    ],
    "excludes": [
        "torch",
        "torchvision",
        "torchaudio",
        "onnxruntime",
        "matplotlib",
        "PIL",
        "tkinter",
        "test",
        "unittest",
        "xmlrpc",
        "pydoc",
        "doctest",
    ],
    "resources": [
        "ui/i18n",
    ],
    "frameworks": [],
    "semi_standalone": False,
    "site_packages": True,
}

setup(
    name="YujieTTS",
    app=APP,
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
