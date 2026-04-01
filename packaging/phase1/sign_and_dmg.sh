#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

APP="$PROJECT_ROOT/dist/YujieTTS.app"
DMG="$PROJECT_ROOT/dist/YujieTTS.dmg"
IDENTITY="${CODESIGN_IDENTITY:-}"  # e.g. "Developer ID Application: Your Name (TEAMID)"

if [ ! -d "$APP" ]; then
    echo "ERROR: $APP not found. Run build.sh first."
    exit 1
fi

echo "========================================"
echo "  YujieTTS — Sign & DMG"
echo "========================================"

# -------------------------------------------------------
# 1. Recursive codesign
# -------------------------------------------------------
if [ -n "$IDENTITY" ]; then
    echo "[1/3] Signing with identity: $IDENTITY"

    find "$APP" -type f \( -name "*.dylib" -o -name "*.so" -o -name "*.framework" \) -print0 | \
        xargs -0 -I{} codesign --force --options runtime --timestamp -s "$IDENTITY" "{}" 2>/dev/null || true

    codesign --force --deep --options runtime --timestamp \
        --entitlements /dev/stdin -s "$IDENTITY" "$APP" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

    echo "  Verifying …"
    codesign --verify --deep --strict "$APP"
    echo "  Signature OK."
else
    echo "[1/3] SKIP signing (no CODESIGN_IDENTITY set)"
    echo "  To sign: export CODESIGN_IDENTITY='Developer ID Application: ...'"
fi

# -------------------------------------------------------
# 2. Create DMG
# -------------------------------------------------------
echo "[2/3] Creating DMG …"
rm -f "$DMG"

if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "YujieTTS" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 80 \
        --icon "YujieTTS.app" 175 190 \
        --app-drop-link 425 190 \
        --no-internet-enable \
        "$DMG" "$APP"
else
    hdiutil create -volname "YujieTTS" \
        -srcfolder "$APP" \
        -ov -format UDZO \
        "$DMG"
fi

echo "  DMG: $DMG  ($(du -sh "$DMG" | cut -f1))"

# -------------------------------------------------------
# 3. Notarize (optional)
# -------------------------------------------------------
APPLE_ID="${NOTARIZE_APPLE_ID:-}"
TEAM_ID="${NOTARIZE_TEAM_ID:-}"
APP_PASSWORD="${NOTARIZE_APP_PASSWORD:-}"

if [ -n "$APPLE_ID" ] && [ -n "$TEAM_ID" ] && [ -n "$APP_PASSWORD" ]; then
    echo "[3/3] Submitting for notarization …"
    xcrun notarytool submit "$DMG" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait

    xcrun stapler staple "$DMG"
    echo "  Notarization complete & stapled."
else
    echo "[3/3] SKIP notarization (set NOTARIZE_APPLE_ID, NOTARIZE_TEAM_ID, NOTARIZE_APP_PASSWORD)"
fi

echo ""
echo "DONE. Distributable: $DMG"
