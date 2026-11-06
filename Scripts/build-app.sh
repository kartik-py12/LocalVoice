#!/bin/bash
set -euo pipefail
umask 077

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP="$BUILD_DIR/LocalVoice.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/LocalVoice.app"
SIGNING_IDENTITY="LocalVoice Local Signer"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

mkdir -p "$BUILD_DIR" "$APP/Contents/MacOS" "$APP/Contents/Resources" "$INSTALL_DIR"
rm -rf "$BUILD_DIR/AppIcon.iconset"
mkdir -p "$BUILD_DIR/AppIcon.iconset"

/usr/bin/swift "$PROJECT_DIR/Scripts/make-icon.swift" "$BUILD_DIR/AppIcon.iconset/icon_512x512@2x.png"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    read -r size name <<< "$spec"
    sips -z "$size" "$size" "$BUILD_DIR/AppIcon.iconset/icon_512x512@2x.png" --out "$BUILD_DIR/AppIcon.iconset/icon_$name.png" >/dev/null
done
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

swiftc -parse-as-library -swift-version 5 -O -target arm64-apple-macosx13.0 \
    -framework AppKit -framework SwiftUI -framework AVFoundation -framework CoreGraphics -framework Security \
    "$PROJECT_DIR"/Sources/*.swift -o "$APP/Contents/MacOS/LocalVoice"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>LocalVoice</string>
    <key>CFBundleIdentifier</key><string>com.localvoice.app</string>
    <key>CFBundleName</key><string>LocalVoice</string>
    <key>CFBundleDisplayName</key><string>LocalVoice</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon.icns</string>
    <key>LSUIElement</key><false/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>LocalVoice records your speech when you start it and saves the audio on this Mac.</string>
</dict>
</plist>
PLIST

if ! security find-identity -p codesigning "$LOGIN_KEYCHAIN" | grep -Fq "\"$SIGNING_IDENTITY\""; then
    echo "Missing stable LocalVoice signing identity. Run ./Scripts/setup-signing.sh once, then rebuild." >&2
    exit 1
fi
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"
running_pid="$(pgrep -x LocalVoice | head -n 1 || true)"
if [[ -n "$running_pid" ]]; then
    if lsof -p "$running_pid" 2>/dev/null | grep -E '\.m4a([[:space:]]|$)' >/dev/null; then
        echo "LocalVoice has an audio file open. Stop recording or wait for transcription before updating; the installed app was not changed." >&2
        exit 1
    fi
    kill -TERM "$running_pid"
    for _ in {1..40}; do
        kill -0 "$running_pid" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 "$running_pid" 2>/dev/null; then
        echo "LocalVoice did not quit. Quit it manually, then rerun this build." >&2
        exit 1
    fi
fi
ditto "$APP" "$INSTALLED_APP"
open -a "$INSTALLED_APP"

printf 'Installed: %s\n' "$INSTALLED_APP"
