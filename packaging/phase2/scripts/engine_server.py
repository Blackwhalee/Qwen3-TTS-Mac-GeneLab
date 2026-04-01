#!/usr/bin/env python3
"""
YujieTTS Engine Server — FastAPI HTTP backend for the SwiftUI native app.

Provides:
  POST /generate          — full synthesis, returns WAV
  POST /generate/stream   — SSE streaming audio chunks
  GET  /voices            — list available voice configs
  POST /voice/config      — update voice config on the fly
  GET  /status            — engine + model status
  GET  /models            — model download status
  POST /models/download   — trigger model download
  GET  /health            — liveness probe
"""
from __future__ import annotations

import argparse
import base64
import io
import json
import logging
import os
import signal
import sys
import tempfile
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import AsyncGenerator

import numpy as np
import soundfile as sf
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response, StreamingResponse
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Paths — works both in-tree and when launched via EnvironmentManager
# (EnvironmentManager sets PYTHONPATH to the extracted project-src dir)
# ---------------------------------------------------------------------------
_PYTHONPATH_DIRS = os.environ.get("PYTHONPATH", "").split(os.pathsep)
for _p in _PYTHONPATH_DIRS:
    if _p and _p not in sys.path:
        sys.path.insert(0, _p)

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

VOICE_CONFIG_DIR = Path.home() / ".openclaw" / "yujie-voice"
DEFAULT_CONFIG = VOICE_CONFIG_DIR / "config.json"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("engine_server")

os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
os.environ.setdefault("PYTORCH_MPS_HIGH_WATERMARK_RATIO", "0.0")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------
class GenerateRequest(BaseModel):
    text: str
    voice_description: str = ""
    emotion_instruction: str = ""
    emotion: str = ""
    language: str = "Chinese"
    speed: float = 0.85
    speaker: str = "serena"
    task_type: str = "VOICE_DESIGN"
    format: str = Field(default="wav", description="wav or base64")
    reference_audio_wav_base64: str = Field(
        default="",
        description="VOICE_CLONE: entire WAV file as base64 (mono preferred, ~3–15s).",
    )
    reference_text: str = Field(
        default="",
        description="VOICE_CLONE: transcript of the reference audio.",
    )
    # --- 以下仅在使用 PyTorch MPS 回退时传入 generate_voice_design / generate_custom_voice ---
    temperature: float | None = None
    top_p: float | None = None
    top_k: int | None = None
    repetition_penalty: float | None = None
    do_sample: bool | None = None
    max_new_tokens: int | None = None


class StreamGenerateRequest(BaseModel):
    text: str
    voice_description: str = ""
    emotion_instruction: str = ""
    emotion: str = ""
    language: str = "Chinese"
    speed: float = 0.85
    speaker: str = "serena"
    task_type: str = "VOICE_DESIGN"
    reference_audio_wav_base64: str = ""
    reference_text: str = ""
    mode: str = Field(default="auto", description="auto, mlx, paragraph, whole")
    paragraph_max_chars: int = 520
    min_chars: int = 12
    temperature: float | None = None
    top_p: float | None = None
    top_k: int | None = None
    repetition_penalty: float | None = None
    do_sample: bool | None = None
    max_new_tokens: int | None = None


class VoiceConfigUpdate(BaseModel):
    voice_description: str | None = None
    speed: float | None = None
    language: str | None = None
    speaker: str | None = None


class ModelDownloadRequest(BaseModel):
    repo_id: str


# ---------------------------------------------------------------------------
# Global engine state
# ---------------------------------------------------------------------------
_engine = None
_engine_loaded = False


def _get_engine():
    global _engine, _engine_loaded
    if _engine is None:
        from mac.engine import DualEngine
        _engine = DualEngine()
        _engine_loaded = True
    return _engine


def _load_voice_config() -> dict:
    if DEFAULT_CONFIG.exists():
        with open(DEFAULT_CONFIG, encoding="utf-8") as f:
            return json.load(f)
    return {
        "voice_description": "26岁成熟御姐女声，声音低沉沙哑且性感，带有明显的气音和喘息感。",
        "parameters": {"language": "Chinese", "speed": 0.85, "base_voice": "serena"},
    }


def _save_voice_config(config: dict) -> None:
    DEFAULT_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    with open(DEFAULT_CONFIG, "w", encoding="utf-8") as f:
        json.dump(config, f, ensure_ascii=False, indent=2)


def _effective_voice_design_instruct(voice_description: str, emotion_instruction: str) -> str:
    """VoiceDesign：主描述 + 表演补充，与流式脚本 voice_prompt 行为一致。"""
    base = (voice_description or "").rstrip()
    extra = (emotion_instruction or "").strip()
    if not extra:
        return base
    tail = (
        "\n\n表演与情感（同一角色、连贯表达、避免念稿感）:\n" + extra
    )
    return base + tail if base else extra


def _sampling_kwargs(req: GenerateRequest) -> dict:
    out = {}
    if req.temperature is not None:
        out["temperature"] = req.temperature
    if req.top_p is not None:
        out["top_p"] = req.top_p
    if req.top_k is not None:
        out["top_k"] = req.top_k
    if req.repetition_penalty is not None:
        out["repetition_penalty"] = req.repetition_penalty
    if req.do_sample is not None:
        out["do_sample"] = req.do_sample
    if req.max_new_tokens is not None:
        out["max_new_tokens"] = req.max_new_tokens
    return out


def _sampling_kwargs_stream(req: StreamGenerateRequest) -> dict:
    out = {}
    if req.temperature is not None:
        out["temperature"] = req.temperature
    if req.top_p is not None:
        out["top_p"] = req.top_p
    if req.top_k is not None:
        out["top_k"] = req.top_k
    if req.repetition_penalty is not None:
        out["repetition_penalty"] = req.repetition_penalty
    if req.do_sample is not None:
        out["do_sample"] = req.do_sample
    if req.max_new_tokens is not None:
        out["max_new_tokens"] = req.max_new_tokens
    return out


def _resolve_vd_emotion(tt, voice_description: str, emotion_instruction: str, emotion: str):
    """返回 (voice_description, emotion)，供 DualEngine.generate 使用。"""
    from mac.engine import TaskType

    emotion_val = (emotion or "").strip() or None
    if tt == TaskType.VOICE_DESIGN:
        vd = _effective_voice_design_instruct(voice_description, emotion_instruction)
        return (vd if vd else None), None
    v = (voice_description or "").strip() or None
    return v, emotion_val


def _audio_to_wav_bytes(audio: np.ndarray, sample_rate: int) -> bytes:
    buf = io.BytesIO()
    sf.write(buf, audio, sample_rate, format="WAV")
    buf.seek(0)
    return buf.read()


def _decode_reference_wav_b64(b64: str) -> tuple[np.ndarray, int]:
    """从 base64 WAV 解码为 mono float32 与采样率。"""
    raw = base64.b64decode(b64.strip())
    buf = io.BytesIO(raw)
    data, sr = sf.read(buf, dtype="float32", always_2d=False)
    if data.ndim > 1:
        data = np.mean(data.astype(np.float32), axis=1)
    return np.ascontiguousarray(data, dtype=np.float32), int(sr)


def _clone_inputs_from_request(req: GenerateRequest | StreamGenerateRequest):
    """VOICE_CLONE 时返回 (ref_audio, ref_text, ref_sr)；否则 (None, None, 24000)。"""
    from mac.engine import TaskType

    tt = TaskType[req.task_type]
    if tt != TaskType.VOICE_CLONE:
        return None, None, 24000
    b64 = (getattr(req, "reference_audio_wav_base64", None) or "").strip()
    if not b64:
        raise HTTPException(status_code=400, detail="声音克隆需要上传参考音频 (reference_audio_wav_base64)。")
    ref_txt = (getattr(req, "reference_text", None) or "").strip()
    if not ref_txt:
        raise HTTPException(status_code=400, detail="声音克隆需要填写参考音频对应的文字 (reference_text)。")
    try:
        audio, sr = _decode_reference_wav_b64(b64)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"参考音频解码失败（请传 WAV base64）: {e}") from e
    if audio.size == 0:
        raise HTTPException(status_code=400, detail="参考音频为空。")
    return audio, ref_txt, sr


# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator:
    logger.info("Engine server starting …")
    yield
    logger.info("Engine server shutting down …")
    if _engine is not None:
        _engine.unload()


app = FastAPI(title="YujieTTS Engine", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.get("/health")
async def health():
    return {"status": "ok", "engine_loaded": _engine_loaded}


@app.get("/status")
async def status():
    info = {"engine_loaded": _engine_loaded, "models": {}}
    if _engine is not None:
        try:
            statuses = _engine.get_status()
            for k, v in statuses.items():
                info["models"][k] = {
                    "type": v.engine_type.value,
                    "loaded": v.is_loaded,
                    "model": v.model_name,
                    "device": v.device,
                }
        except Exception:
            pass
    return info


@app.get("/voices")
async def list_voices():
    configs = []
    if VOICE_CONFIG_DIR.exists():
        for p in VOICE_CONFIG_DIR.glob("*.json"):
            try:
                with open(p, encoding="utf-8") as f:
                    data = json.load(f)
                configs.append({
                    "name": p.stem,
                    "path": str(p),
                    "voice_description": data.get("voice_description", ""),
                    "parameters": data.get("parameters", {}),
                })
            except Exception:
                pass
    return {"voices": configs}


@app.post("/voice/config")
async def update_voice_config(req: VoiceConfigUpdate):
    config = _load_voice_config()
    if req.voice_description is not None:
        config["voice_description"] = req.voice_description
    params = config.setdefault("parameters", {})
    if req.speed is not None:
        params["speed"] = req.speed
    if req.language is not None:
        params["language"] = req.language
    if req.speaker is not None:
        params["base_voice"] = req.speaker
    _save_voice_config(config)
    return {"status": "ok", "config": config}


@app.post("/generate")
async def generate(req: GenerateRequest):
    from mac.engine import TaskType

    engine = _get_engine()
    tt = TaskType[req.task_type]
    vd, emo = _resolve_vd_emotion(tt, req.voice_description, req.emotion_instruction, req.emotion)
    samp = _sampling_kwargs(req)
    ref_a, ref_t, ref_sr = _clone_inputs_from_request(req)

    try:
        t0 = time.time()
        result = engine.generate(
            text=req.text,
            task_type=tt,
            language=req.language,
            speaker=req.speaker,
            voice_description=vd,
            emotion=emo,
            speed=req.speed,
            reference_audio=ref_a,
            reference_text=ref_t,
            reference_sr=ref_sr,
            **samp,
        )
        gen_time = time.time() - t0
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    wav_bytes = _audio_to_wav_bytes(result.audio, result.sample_rate)

    if req.format == "base64":
        return {
            "audio_base64": base64.b64encode(wav_bytes).decode(),
            "sample_rate": result.sample_rate,
            "duration": result.duration_seconds,
            "generation_time": gen_time,
            "engine": result.engine_used.value,
        }

    return Response(
        content=wav_bytes,
        media_type="audio/wav",
        headers={
            "X-Duration": str(result.duration_seconds),
            "X-Generation-Time": str(gen_time),
            "X-Engine": result.engine_used.value,
        },
    )


@app.post("/generate/with-progress")
async def generate_with_progress(req: GenerateRequest):
    """SSE endpoint that sends progress events then the final audio."""
    import asyncio
    import threading

    ref_a, ref_t, ref_sr = _clone_inputs_from_request(req)

    SEC_PER_CHAR = 0.088
    estimated_total = max(5.0, len(req.text) * SEC_PER_CHAR)

    gen_result_holder: dict = {}
    gen_error_holder: dict = {}
    gen_done = threading.Event()

    def _run_generate():
        try:
            from mac.engine import TaskType
            engine = _get_engine()
            tt = TaskType[req.task_type]
            vd, emo = _resolve_vd_emotion(tt, req.voice_description, req.emotion_instruction, req.emotion)
            samp = _sampling_kwargs(req)
            t0 = time.time()
            result = engine.generate(
                text=req.text,
                task_type=tt,
                language=req.language,
                speaker=req.speaker,
                voice_description=vd,
                emotion=emo,
                speed=req.speed,
                reference_audio=ref_a,
                reference_text=ref_t,
                reference_sr=ref_sr,
                **samp,
            )
            gen_time = time.time() - t0
            wav_bytes = _audio_to_wav_bytes(result.audio, result.sample_rate)
            gen_result_holder["data"] = {
                "audio_base64": base64.b64encode(wav_bytes).decode(),
                "sample_rate": result.sample_rate,
                "duration": result.duration_seconds,
                "generation_time": gen_time,
                "engine": result.engine_used.value,
            }
        except Exception as e:
            gen_error_holder["error"] = str(e)
        finally:
            gen_done.set()

    async def event_stream() -> AsyncGenerator[str, None]:
        thread = threading.Thread(target=_run_generate, daemon=True)
        thread.start()
        t0 = time.time()

        while not gen_done.is_set():
            await asyncio.sleep(0.5)
            elapsed = time.time() - t0
            pct = min(elapsed / estimated_total, 0.95)
            eta = max(0, estimated_total - elapsed)
            evt = {
                "type": "progress",
                "percent": round(pct * 100, 1),
                "elapsed": round(elapsed, 1),
                "eta_seconds": round(eta, 1),
            }
            yield f"data: {json.dumps(evt)}\n\n"

        if "error" in gen_error_holder:
            yield f"data: {json.dumps({'type': 'error', 'message': gen_error_holder['error']})}\n\n"
        elif "data" in gen_result_holder:
            result_data = gen_result_holder["data"]
            result_data["type"] = "complete"
            result_data["percent"] = 100
            yield f"data: {json.dumps(result_data)}\n\n"

        yield "data: [DONE]\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")


@app.post("/generate/stream")
async def generate_stream(req: StreamGenerateRequest):
    """SSE streaming: each event carries a base64-encoded WAV chunk."""
    from mac.engine import DualEngine, TaskType

    async def event_stream() -> AsyncGenerator[str, None]:
        try:
            try:
                ref_a, ref_t, ref_sr = _clone_inputs_from_request(req)
            except HTTPException as he:
                yield f"data: {json.dumps({'as_json_error': True, 'detail': he.detail})}\n\n"
                return
            engine = _get_engine()
            tt = TaskType[req.task_type]
            vd, emo = _resolve_vd_emotion(tt, req.voice_description, req.emotion_instruction, req.emotion)
            samp = _sampling_kwargs_stream(req)

            if req.mode == "whole" or (req.mode == "auto" and len(req.text) <= 1400):
                t0 = time.time()
                result = engine.generate(
                    text=req.text,
                    task_type=tt,
                    language=req.language,
                    speaker=req.speaker,
                    voice_description=vd,
                    emotion=emo,
                    speed=req.speed,
                    reference_audio=ref_a,
                    reference_text=ref_t,
                    reference_sr=ref_sr,
                    **samp,
                )
                wav_b = _audio_to_wav_bytes(result.audio, result.sample_rate)
                chunk_data = {
                    "chunk_index": 0,
                    "audio_base64": base64.b64encode(wav_b).decode(),
                    "sample_rate": result.sample_rate,
                    "duration": result.duration_seconds,
                    "is_final": True,
                }
                yield f"data: {json.dumps(chunk_data)}\n\n"
            else:
                segments = _split_text(req.text, req.min_chars, req.paragraph_max_chars)
                for i, seg in enumerate(segments):
                    t0 = time.time()
                    result = engine.generate(
                        text=seg,
                        task_type=tt,
                        language=req.language,
                        speaker=req.speaker,
                        voice_description=vd,
                        emotion=emo,
                        speed=req.speed,
                        reference_audio=ref_a,
                        reference_text=ref_t,
                        reference_sr=ref_sr,
                        **samp,
                    )
                    wav_b = _audio_to_wav_bytes(result.audio, result.sample_rate)
                    chunk_data = {
                        "chunk_index": i,
                        "audio_base64": base64.b64encode(wav_b).decode(),
                        "sample_rate": result.sample_rate,
                        "duration": result.duration_seconds,
                        "segment_text": seg[:50],
                        "is_final": (i == len(segments) - 1),
                    }
                    yield f"data: {json.dumps(chunk_data)}\n\n"

            yield "data: [DONE]\n\n"
        except Exception as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")


def _split_text(text: str, min_chars: int, max_chars: int) -> list[str]:
    sentences: list[str] = []
    buf = ""
    for ch in text:
        buf += ch
        if ch in "。！？…\n" and len(buf.strip()) >= min_chars:
            sentences.append(buf.strip())
            buf = ""
    if buf.strip():
        sentences.append(buf.strip())
    if not sentences:
        return [text.strip()]

    merged: list[str] = []
    cur = ""
    for s in sentences:
        if not cur:
            cur = s
        elif len(cur) + len(s) <= max_chars:
            cur += s
        else:
            merged.append(cur)
            cur = s
    if cur:
        merged.append(cur)
    return merged if merged else [text.strip()]


def _import_model_manager():
    """Import model_manager from wherever it lives (PYTHONPATH or sibling dir)."""
    try:
        from model_manager import check_all_models, get_total_cache_size_gb, download_model
        return check_all_models, get_total_cache_size_gb, download_model
    except ImportError:
        p1 = Path(__file__).resolve().parent.parent / "phase1"
        if str(p1) not in sys.path:
            sys.path.insert(0, str(p1))
        from model_manager import check_all_models, get_total_cache_size_gb, download_model
        return check_all_models, get_total_cache_size_gb, download_model


@app.get("/models")
async def list_models():
    check_all_models, get_total_cache_size_gb, _ = _import_model_manager()
    statuses = check_all_models()
    return {
        "models": [
            {
                "name": s.name,
                "repo_id": s.repo_id,
                "available": s.available,
                "size_hint": s.size_hint,
                "required": s.required,
            }
            for s in statuses
        ],
        "total_cache_gb": round(get_total_cache_size_gb(), 2),
    }


@app.post("/models/download")
async def download_model_route(req: ModelDownloadRequest):
    _, _, download_model = _import_model_manager()
    try:
        path = download_model(req.repo_id)
        return {"status": "ok", "path": str(path)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
def main() -> None:
    parser = argparse.ArgumentParser(description="YujieTTS Engine Server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0, help="0 = auto pick")
    args = parser.parse_args()

    port = args.port
    if port == 0:
        import socket
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]

    port_file = Path(os.environ.get("YUJIE_TTS_PORT_FILE", str(Path("/tmp") / "yujie_tts_port")))
    port_file.parent.mkdir(parents=True, exist_ok=True)
    port_file.write_text(str(port))
    logger.info("Port file: %s → %d", port_file, port)

    def _shutdown(signum, frame):
        logger.info("Received signal %d, shutting down …", signum)
        port_file.unlink(missing_ok=True)
        sys.exit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    logger.info("Starting engine server on %s:%d", args.host, port)
    uvicorn.run(app, host=args.host, port=port, log_level="info")


if __name__ == "__main__":
    main()
