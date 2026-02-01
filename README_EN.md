<p align="center">
  <img src="https://img.shields.io/badge/Apple%20Silicon-Optimized-black?style=for-the-badge&logo=apple" alt="Apple Silicon Optimized">
  <img src="https://img.shields.io/badge/MLX-Native-orange?style=for-the-badge" alt="MLX Native">
  <img src="https://img.shields.io/badge/PyTorch-MPS-red?style=for-the-badge&logo=pytorch" alt="PyTorch MPS">
  <img src="https://img.shields.io/badge/License-Apache%202.0-blue?style=for-the-badge" alt="License">
</p>

<h1 align="center">Qwen3-TTS-Mac-GeneLab</h1>

<p align="center">
  <strong>World's First</strong>: Fully optimized Qwen3-TTS fork for Apple Silicon Mac<br>
  Native Mac TTS experience with MLX + PyTorch MPS dual-engine architecture
</p>

<p align="center">
  English | <a href="README.md">日本語</a>
</p>

---

## Why Qwen3-TTS-Mac-GeneLab?

| Feature | Official Qwen3-TTS | **This Project** |
|---------|-------------------|------------------|
| Apple Silicon Optimization | Limited | **Full Support** |
| MLX Native Inference | Not supported | **Supported** (8bit/4bit quantization) |
| PyTorch MPS | Manual setup required | **Auto-switching** |
| GUI | None | **Web UI with i18n** |
| Voice Clone | CLI only | **Web UI + Whisper auto-transcription** |
| Memory Management | None | **Unified Memory optimization** |
| Setup | Complex | **One-command** |

### Key Innovations

1. **Dual-Engine Architecture**
   - MLX: Apple Silicon native, fast & memory-efficient with 8bit/4bit quantization
   - PyTorch MPS: Auto-switches for float32-required tasks like Voice Clone

2. **Task-Aware Auto-Optimization**
   - CustomVoice → MLX preferred (fast)
   - VoiceDesign → MLX preferred (fast)
   - VoiceClone → PyTorch MPS (float32 precision required)

3. **Fully Internationalized Web UI**
   - Gradio-based intuitive interface
   - Japanese/English switchable

---

## System Requirements

| Item | Minimum | Recommended |
|------|---------|-------------|
| Chip | Apple Silicon (M1) | M2 Pro / M3+ |
| RAM | 16GB | 32GB+ |
| OS | macOS 14 Sonoma | macOS 15 Sequoia |
| Python | 3.10 | 3.11 |
| Free Storage | 10GB | 20GB+ |

> **Note**: 8GB M1/M2 models can work with 4bit quantized models, but with reduced quality and speed.

---

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/hiroki-abe-58/Qwen3-TTS-Mac-GeneLab.git
cd Qwen3-TTS-Mac-GeneLab
```

### 2. Setup (First Time Only, ~5-10 minutes)

```bash
chmod +x setup_mac.sh
./setup_mac.sh
```

The setup script automatically:
- Installs Homebrew dependencies (sox, ffmpeg, portaudio)
- Creates Miniforge conda environment (Python 3.11)
- Installs MLX, PyTorch MPS, Gradio, etc.
- Configures environment variables
- Runs verification tests

### 3. Launch Web UI

```bash
./run.sh
```

### 4. Open in Browser

Navigate to http://localhost:7860

---

## Web UI Features

### Custom Voice

Generate speech from 9 preset speakers with optional emotion control.

| Speaker | Characteristics | Languages |
|---------|----------------|-----------|
| Chelsie | Bright young female | English/Chinese |
| Ethan | Calm young male | English/Chinese |
| Aiden | Mature male | English/Chinese |
| Bella | Warm female | English/Chinese |
| Vivian | Energetic female | English/Chinese |
| Lucas | Bright young male | English/Chinese |
| Eleanor | Elegant female | English/Chinese |
| Alexander | Powerful male | English/Chinese |
| Serena | Soothing female | English/Chinese |

**Japanese text input is also supported**, though pronunciation may not be native-quality.

### Voice Design

Generate voice by describing characteristics in text.

```
Example: "A calm middle-aged male voice with a warm, reassuring tone."
Example: "An energetic young female voice with high pitch."
```

### Voice Clone

Clone a voice from just **3 seconds** of reference audio.

- **Whisper Auto-Transcription**: Automatically recognizes reference audio text
- **ICL Mode**: High-quality cloning with reference text
- **X-Vector Mode**: Extract voice characteristics only (no text needed)

> **Note**: Voice Clone requires the **Base model** (~3.8GB). It will be auto-downloaded on first use.

### Settings

- Engine selection (AUTO / MLX / PyTorch MPS)
- Memory monitor
- Model management

---

## MLX vs PyTorch MPS

| Item | MLX (Default) | PyTorch MPS |
|------|---------------|-------------|
| Inference Speed | **Fast** | Medium |
| Memory Efficiency | **Excellent** (quantization) | Normal |
| Voice Clone | Supported | **Stable with float32** |
| Quantization | **4bit/8bit** | Not supported |
| Precision | May be slightly lower | **High** |

**Auto-Switching Logic:**
- CustomVoice/VoiceDesign → MLX preferred
- VoiceClone → PyTorch MPS forced (float32 required)

---

## CLI Usage

```python
from mac import DualEngine, TaskType

# Initialize engine
engine = DualEngine()

# Generate with CustomVoice
result = engine.generate(
    text="Hello, this is a test of Qwen3 TTS.",
    task_type=TaskType.CUSTOM_VOICE,
    language="English",
    speaker="Vivian",
)

# Save audio
import soundfile as sf
sf.write("output.wav", result.audio, result.sample_rate)
print(f"Generation time: {result.generation_time:.2f}s")
print(f"Engine used: {result.engine_used}")
```

### Voice Clone Example

```python
import librosa
from mac import DualEngine, TaskType

engine = DualEngine()

# Load reference audio
ref_audio, ref_sr = librosa.load("reference.wav", sr=None)

# Generate with Voice Clone
result = engine.generate(
    text="This is my cloned voice speaking new text.",
    task_type=TaskType.VOICE_CLONE,
    language="English",
    reference_audio=ref_audio,
    reference_text="The original text from reference audio",
    reference_sr=ref_sr,
)

sf.write("cloned_output.wav", result.audio, result.sample_rate)
```

---

## Directory Structure

```
Qwen3-TTS-Mac-GeneLab/
├── setup_mac.sh          # Setup script
├── run.sh                # Launch script
├── pyproject.toml        # Project configuration
├── requirements-mac.txt  # Mac dependencies
│
├── mac/                  # Mac-specific code
│   ├── __init__.py
│   ├── engine.py         # Dual-engine management
│   ├── device_utils.py   # Device detection & dtype selection
│   ├── memory_manager.py # Unified Memory management
│   ├── whisper_transcriber.py  # Whisper transcription
│   └── benchmark.py      # Performance measurement
│
├── ui/                   # Gradio Web UI
│   ├── app.py            # Main application
│   ├── components/       # Tab components
│   │   ├── custom_voice_tab.py
│   │   ├── voice_design_tab.py
│   │   ├── voice_clone_tab.py
│   │   └── settings_tab.py
│   └── i18n/             # Internationalization
│       ├── ja.json
│       └── en.json
│
├── qwen_tts/             # Original TTS core (upstream)
│   ├── core/
│   │   ├── models/       # Model definitions
│   │   └── tokenizer_*/  # Tokenizers
│   └── inference/        # Inference wrappers
│
└── examples/             # Sample code
    └── mac_quickstart.py
```

---

## Troubleshooting

### Installation Issues

| Error | Cause | Solution |
|-------|-------|----------|
| `zsh: command not found: conda` | Miniforge not installed | Re-run setup script |
| `brew: command not found` | Homebrew not installed | Install [Homebrew](https://brew.sh) |
| `No space left on device` | Insufficient disk space | Free up at least 10GB |

### Runtime Issues

| Error | Cause | Solution |
|-------|-------|----------|
| `Virtual environment not found` | conda not activated | `source "$(conda info --base)/etc/profile.d/conda.sh" && conda activate qwen3-tts-mac-genelab` |
| `RuntimeError: MPS backend` | Unsupported MPS operation | Set `PYTORCH_ENABLE_MPS_FALLBACK=1` (already set by setup) |
| `Out of memory` | Insufficient RAM | Close other apps or use quantized models |
| `probability tensor contains inf` | Using float16 for Voice Clone | Ensure PyTorch MPS is auto-selected |

### Voice Clone Issues

| Error | Cause | Solution |
|-------|-------|----------|
| `'default'` error | Wrong model type | Base model required; will auto-download |
| Reference audio recognition failed | Audio too short/noisy | Use 3+ seconds of clear audio |
| Low quality generated audio | Inaccurate reference text | Verify/correct Whisper transcription |

---

## Memory Usage Estimates

| Model | dtype | VRAM Usage | Recommended RAM |
|-------|-------|------------|-----------------|
| 1.7B CustomVoice | bf16 | ~3.4 GB | 16GB |
| 1.7B CustomVoice | 8bit | ~1.7 GB | 16GB |
| 1.7B CustomVoice | 4bit | ~0.9 GB | 8GB |
| 1.7B Base (Voice Clone) | float32 | ~6.8 GB | 32GB |
| 0.6B | bf16 | ~1.2 GB | 8GB |

> **Tips**: When switching between models, the previous model is automatically unloaded.

---

## Environment Variables

The setup script auto-configures these in `.env`:

```bash
# MPS fallback (run unsupported ops on CPU)
export PYTORCH_ENABLE_MPS_FALLBACK=1

# MPS memory limit (70%)
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.7

# Disable tokenizer parallelism (avoid warnings)
export TOKENIZERS_PARALLELISM=false
```

---

## Syncing with Upstream

To incorporate updates from the original Qwen3-TTS repository:

```bash
# Add upstream (first time only)
git remote add upstream https://github.com/QwenLM/Qwen3-TTS.git

# Fetch and merge updates
git fetch upstream
git merge upstream/main --allow-unrelated-histories
```

---

## Acknowledgments

- [QwenLM/Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) — Original repository by Alibaba Qwen team
- [Blaizzy/mlx-audio](https://github.com/Blaizzy/mlx-audio) — Apple MLX audio library
- [mlx-community](https://huggingface.co/mlx-community) — Quantized MLX models
- [OpenAI Whisper](https://github.com/openai/whisper) — Speech recognition model

---

## License

[Apache License 2.0](LICENSE) (same as original repository)

---

## Contributing

Issues and Pull Requests are welcome!

1. Fork this repository
2. Create a new branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Create a Pull Request

---

<p align="center">
  Made with ❤️ for the Apple Silicon community
</p>
