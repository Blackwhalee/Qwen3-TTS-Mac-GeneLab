# YujieTTS Build System
# Usage:
#   make phase1         — Build Gradio-based .app (py2app)
#   make phase1-dmg     — Sign + create DMG for Phase 1
#   make sidecar        — Build PyInstaller Python sidecar
#   make phase2         — Build SwiftUI native app (requires Xcode)
#   make phase2-dmg     — Create DMG for Phase 2
#   make clean          — Remove all build artifacts

PROJECT_ROOT := $(shell cd .. && pwd)
DIST := $(PROJECT_ROOT)/dist
CONDA_PY := /opt/homebrew/Caskroom/miniforge/base/envs/qwen3-tts-mac-genelab/bin/python3

.PHONY: phase1 phase1-dmg sidecar phase2 phase2-dmg clean

# ===== Phase 1: py2app =====
phase1:
	@echo "=== Phase 1: Building Gradio .app ==="
	cd $(PROJECT_ROOT) && bash packaging/phase1/build.sh

phase1-dmg: phase1
	@echo "=== Phase 1: Sign + DMG ==="
	cd $(PROJECT_ROOT) && bash packaging/phase1/sign_and_dmg.sh

# ===== Phase 2: Native SwiftUI =====
sidecar:
	@echo "=== Building Python sidecar ==="
	cd $(PROJECT_ROOT) && bash packaging/phase2/scripts/build_sidecar.sh

phase2: sidecar
	@echo "=== Phase 2: Building SwiftUI app ==="
	@# Copy sidecar into Xcode resources
	mkdir -p phase2/YujieTTS/YujieTTS/Resources/python-engine
	cp -R $(DIST)/sidecar/yujie-engine/* phase2/YujieTTS/YujieTTS/Resources/python-engine/
	@# Build with xcodebuild
	cd phase2/YujieTTS && xcodebuild \
		-scheme YujieTTS \
		-configuration Release \
		-derivedDataPath $(DIST)/xcode-build \
		ARCHS=arm64 \
		ONLY_ACTIVE_ARCH=NO \
		CODE_SIGN_IDENTITY="-" \
		build
	@echo "=== Phase 2 build complete ==="
	@echo "App: $$(find $(DIST)/xcode-build -name 'YujieTTS.app' -type d | head -1)"

phase2-dmg: phase2
	@echo "=== Phase 2: Creating DMG ==="
	@APP=$$(find $(DIST)/xcode-build -name 'YujieTTS.app' -type d | head -1); \
	DMG=$(DIST)/YujieTTS-native.dmg; \
	rm -f "$$DMG"; \
	if command -v create-dmg >/dev/null 2>&1; then \
		create-dmg \
			--volname "YujieTTS" \
			--window-pos 200 120 \
			--window-size 600 400 \
			--icon-size 80 \
			--icon "YujieTTS.app" 175 190 \
			--app-drop-link 425 190 \
			--no-internet-enable \
			"$$DMG" "$$APP"; \
	else \
		hdiutil create -volname "YujieTTS" -srcfolder "$$APP" -ov -format UDZO "$$DMG"; \
	fi; \
	echo "DMG: $$DMG"

# ===== Dev: run engine server standalone =====
dev-server:
	$(CONDA_PY) $(PROJECT_ROOT)/packaging/phase2/scripts/engine_server.py --port 7861

# ===== Clean =====
clean:
	rm -rf $(PROJECT_ROOT)/build $(PROJECT_ROOT)/dist $(PROJECT_ROOT)/.eggs
	rm -rf phase2/YujieTTS/YujieTTS/Resources/python-engine
