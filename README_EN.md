# Qwen3-TTS-Mac-GeneLab

An Apple Silicon Mac optimized fork of Qwen3-TTS.
Provides the best TTS experience on Mac with a dual-engine architecture combining MLX native inference and PyTorch MPS.

## Features

- **Dual Engine**: Automatic switching between MLX (Apple optimized) and PyTorch MPS
- **Japanese GUI**: Fully Japanese-supported Gradio Web UI
- **Whisper Integration**: Auto-transcription of reference audio for Voice Clone
- **Memory Optimization**: Unified Memory management, 4bit/8bit quantization support
- **One-Command Setup**: Complete environment setup with setup_mac.sh

## System Requirements

| Item | Requirement |
|------|-------------|
| Chip | Apple Silicon (M1/M2/M3/M4) |
| RAM | 16GB+ (32GB+ recommended for 1.7B model) |
| OS | macOS 14 Sonoma or later |
| Python | 3.10-3.12 |

## Quick Start

```bash
# Clone the repository
git clone https://github.com/hiroki-abe-58/Qwen3-TTS-Mac-GeneLab.git
cd Qwen3-TTS-Mac-GeneLab

# Setup (first time only)
chmod +x setup_mac.sh && ./setup_mac.sh

# Launch Web UI
./run.sh
```

Open http://localhost:7860 in your browser.

## Web UI Features

### 1. Custom Voice
Generate speech from 9 preset speakers with optional emotion control.

| Speaker | Description |
|---------|-------------|
| Chelsie | Bright young female voice |
| Ethan | Calm young male voice |
| Aiden | Mature male voice |
| Bella | Warm female voice |
| Vivian | Energetic female voice |
| Lucas | Bright young male voice |
| Eleanor | Elegant female voice |
| Alexander | Powerful male voice |
| Serena | Soothing female voice |

### 2. Voice Design
Generate voice by describing characteristics in text.

```
Example: "A calm middle-aged male voice with a warm, reassuring tone."
```

### 3. Voice Clone
Clone a voice from just 3 seconds of reference audio.
Includes Whisper auto-transcription feature.

### 4. Settings
Engine selection, memory monitor, model management.

## MLX vs PyTorch MPS

| Item | MLX (Default) | PyTorch MPS |
|------|---------------|-------------|
| Inference Speed | Fast | Medium |
| Memory Efficiency | Excellent (quantization) | Normal |
| Voice Clone | Supported | float32 required but stable |
| Quantization | 4bit/8bit | Not supported |

## CLI Usage

```python
from mac import DualEngine, TaskType

# Initialize engine
engine = DualEngine()

# Generate with CustomVoice
result = engine.generate(
    text="Hello, this is a test.",
    task_type=TaskType.CUSTOM_VOICE,
    language="English",
    speaker="Vivian",
)

# Save audio
import soundfile as sf
sf.write("output.wav", result.audio, result.sample_rate)
```

## Technical Notes

### Known MPS Constraints

1. **Voice Clone requires float32**: float16 causes `RuntimeError: probability tensor contains either inf, nan or element < 0`
2. **FlashAttention 2 not supported on Mac**: Always uses SDPA
3. **BFloat16**: May be unstable on M1/M2 → float16 recommended

### Environment Variables

Automatically set by setup script, but for manual setup:

```bash
export PYTORCH_ENABLE_MPS_FALLBACK=1
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.7
export TOKENIZERS_PARALLELISM=false
```

### Troubleshooting

| Issue | Solution |
|-------|----------|
| SoX error | `brew install sox` |
| Out of memory | Close other apps or use 8bit/4bit quantized models |
| Slow generation | Use MLX engine (select AUTO in settings) |
| Voice Clone error | Ensure PyTorch MPS engine is auto-selected |

## Memory Usage Estimates

| Model | dtype | Size |
|-------|-------|------|
| 1.7B | bf16 | ~3.4 GB |
| 1.7B | 8bit | ~1.7 GB |
| 1.7B | 4bit | ~0.9 GB |
| 0.6B | bf16 | ~1.2 GB |

## Acknowledgments

- [QwenLM/Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) — Original repository
- [Blaizzy/mlx-audio](https://github.com/Blaizzy/mlx-audio) — MLX audio library
- [mlx-community](https://huggingface.co/mlx-community) — Quantized models

## License

Apache License 2.0 (same as original repository)
