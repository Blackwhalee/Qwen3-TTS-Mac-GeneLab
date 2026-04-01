# YujieTTS Packaging

Two-phase strategy for packaging Qwen3-TTS into a macOS application.

## Quick Start

```bash
cd packaging

# Phase 1: Gradio-based .app (fastest to build)
make phase1

# Phase 2: Native SwiftUI app (requires Xcode + sidecar build)
make phase2
```

## Phase 1 — Gradio App (py2app)

Wraps the existing Gradio Web UI into a standalone `.app` bundle.

- **Build**: `make phase1`
- **Sign + DMG**: `make phase1-dmg`
- **Output**: `dist/YujieTTS.app`
- **Size**: ~500MB-1GB (model downloaded on first launch)
- **Requirements**: conda env `qwen3-tts-mac-genelab`, py2app

### Environment Variables for Signing

```bash
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARIZE_APPLE_ID="you@example.com"
export NOTARIZE_TEAM_ID="ABCDEF1234"
export NOTARIZE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

## Phase 2 — Native SwiftUI App

Full macOS-native app with SwiftUI frontend and Python engine sidecar.

### Architecture

```
YujieTTS.app
├── SwiftUI Frontend (native macOS UI)
└── Contents/Resources/python-engine/
    └── yujie-engine (PyInstaller sidecar)
        └── FastAPI server → DualEngine (MLX)
```

### Build Steps

1. **Build Python sidecar**: `make sidecar`
2. **Open Xcode project**: `open phase2/YujieTTS/YujieTTS.xcodeproj` (create via Xcode)
3. **Build app**: `make phase2`
4. **Create DMG**: `make phase2-dmg`

### Development Mode

Run the engine server standalone for SwiftUI development:

```bash
make dev-server
# Engine runs on http://127.0.0.1:7861
# Then run the SwiftUI app from Xcode — it auto-detects the running server
```

## File Structure

```
packaging/
├── Makefile                    # Top-level build commands
├── README.md                   # This file
├── phase1/
│   ├── build.sh                # py2app build script
│   ├── launcher.py             # App entry point
│   ├── model_manager.py        # Model download & detection
│   ├── setup_py2app.py         # py2app configuration
│   └── sign_and_dmg.sh         # Signing & DMG creation
└── phase2/
    ├── scripts/
    │   ├── engine_server.py    # FastAPI sidecar (Python)
    │   └── build_sidecar.sh    # PyInstaller build script
    └── YujieTTS/
        └── YujieTTS/
            ├── App.swift
            ├── Info.plist
            ├── YujieTTS.entitlements
            ├── Views/
            │   ├── MainView.swift
            │   ├── TextInputView.swift
            │   ├── VoiceConfigPanel.swift
            │   ├── PlaybackBar.swift
            │   ├── HistoryView.swift
            │   └── SettingsView.swift
            ├── Services/
            │   ├── EngineService.swift
            │   ├── ProcessManager.swift
            │   └── AudioService.swift
            ├── Models/
            │   ├── VoiceConfig.swift
            │   └── GenerationResult.swift
            └── Resources/
                └── default-voices/
```
