"""
Model auto-detection, download, and management for YujieTTS.
"""
from __future__ import annotations

import logging
import os
import shutil
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger("YujieTTS.model")

MODELS = {
    "voice_design": {
        "repo_id": "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit",
        "description": "VoiceDesign (MLX 8-bit) — create voices from text description",
        "size_hint": "~2.9 GB",
        "required": True,
    },
    "custom_voice": {
        "repo_id": "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
        "description": "CustomVoice (MLX 8-bit) — 9 preset speakers with emotion control",
        "size_hint": "~2.9 GB",
        "required": False,
    },
    "base": {
        "repo_id": "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit",
        "description": "Base (MLX 8-bit) — voice cloning",
        "size_hint": "~2.9 GB",
        "required": False,
    },
}


@dataclass
class ModelStatus:
    name: str
    repo_id: str
    available: bool
    path: Path | None
    size_hint: str
    required: bool


def hf_cache_root() -> Path:
    return Path(os.environ.get("HF_HOME", Path.home() / ".cache" / "huggingface"))


def _snapshot_dir(repo_id: str) -> Path:
    slug = f"models--{repo_id.replace('/', '--')}"
    return hf_cache_root() / "hub" / slug / "snapshots"


def is_model_cached(repo_id: str) -> bool:
    sd = _snapshot_dir(repo_id)
    return sd.exists() and any(sd.iterdir())


def get_model_path(repo_id: str) -> Path | None:
    sd = _snapshot_dir(repo_id)
    if not sd.exists():
        return None
    snapshots = sorted(sd.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
    return snapshots[0] if snapshots else None


def check_all_models() -> list[ModelStatus]:
    results = []
    for name, info in MODELS.items():
        repo_id = info["repo_id"]
        cached = is_model_cached(repo_id)
        results.append(
            ModelStatus(
                name=name,
                repo_id=repo_id,
                available=cached,
                path=get_model_path(repo_id) if cached else None,
                size_hint=info["size_hint"],
                required=info["required"],
            )
        )
    return results


def download_model(
    repo_id: str,
    progress_callback: callable | None = None,
) -> Path:
    """Download a model from HuggingFace Hub. Returns snapshot path."""
    from huggingface_hub import snapshot_download

    logger.info("Downloading %s …", repo_id)
    path = snapshot_download(repo_id)
    logger.info("Download complete: %s", path)
    return Path(path)


def ensure_required_models() -> bool:
    """Check and download all required models. Returns True if all ready."""
    statuses = check_all_models()
    missing = [s for s in statuses if s.required and not s.available]
    if not missing:
        logger.info("All required models available.")
        return True

    for s in missing:
        logger.info(
            "Required model '%s' (%s) not found. Downloading %s …",
            s.name,
            s.size_hint,
            s.repo_id,
        )
        try:
            download_model(s.repo_id)
        except Exception as e:
            logger.error("Failed to download %s: %s", s.repo_id, e)
            return False
    return True


def delete_model(repo_id: str) -> bool:
    """Remove a cached model."""
    slug = f"models--{repo_id.replace('/', '--')}"
    model_dir = hf_cache_root() / "hub" / slug
    if model_dir.exists():
        shutil.rmtree(model_dir)
        logger.info("Deleted model cache: %s", model_dir)
        return True
    return False


def get_total_cache_size_gb() -> float:
    hub = hf_cache_root() / "hub"
    if not hub.exists():
        return 0.0
    total = sum(f.stat().st_size for f in hub.rglob("*") if f.is_file())
    return total / (1024**3)
