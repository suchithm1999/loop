#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="LoopApp"
BUNDLE_DIR="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SRC_DIR="$SCRIPT_DIR/Sources/Loop"

SAVER_NAME="LoopSaver"
SAVER_BUNDLE="$SCRIPT_DIR/$SAVER_NAME.saver"
SAVER_SRC_DIR="$SCRIPT_DIR/Sources/LoopSaver"
SAVER_INSTALL_DIR="$HOME/Library/Screen Savers"

SDK_PATH=$(xcrun --show-sdk-path)

# ─────────────────────────────────────────────
# 1. Build LoopSaver screensaver
# ─────────────────────────────────────────────
echo "==> Building LoopSaver screensaver..."

SAVER_OBJ="$SCRIPT_DIR/LoopSaverView.o"

# Step 1: Compile Swift to object file
swiftc \
    -c \
    -O \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macosx14.0 \
    -parse-as-library \
    -module-name LoopSaver \
    -o "$SAVER_OBJ" \
    "$SAVER_SRC_DIR/LoopSaverView.swift" \
    2>&1

# Step 2: Link as a loadable bundle (.saver)
rm -rf "$SAVER_BUNDLE"
mkdir -p "$SAVER_BUNDLE/Contents/MacOS"

clang -bundle \
    -target arm64-apple-macosx14.0 \
    -isysroot "$SDK_PATH" \
    -o "$SAVER_BUNDLE/Contents/MacOS/$SAVER_NAME" \
    "$SAVER_OBJ" \
    -framework ScreenSaver \
    -framework AVFoundation \
    -framework AppKit \
    -framework QuartzCore \
    -framework CoreMedia \
    -L "$SDK_PATH/usr/lib/swift" \
    -L /usr/lib/swift \
    -lswiftCore \
    -lswiftFoundation \
    -lswiftObjectiveC \
    -lswiftCoreFoundation \
    -lswiftDispatch \
    -lswiftCoreGraphics \
    -rpath /usr/lib/swift \
    2>&1

rm -f "$SAVER_OBJ"

# Screensaver Info.plist
cat > "$SAVER_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LoopSaver</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.loop.saver</string>
    <key>CFBundleName</key>
    <string>LoopSaver</string>
    <key>CFBundleDisplayName</key>
    <string>Loop Video Wallpaper</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>NSPrincipalClass</key>
    <string>LoopSaverView</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$SAVER_BUNDLE"
echo "    ✓ LoopSaver.saver built and signed"

# ─────────────────────────────────────────────
# 2. Build Loop app
# ─────────────────────────────────────────────
echo ""
echo "==> Building Loop app with swiftc..."
echo "    SDK: $SDK_PATH"

SOURCES=(
    "$SRC_DIR/Settings.swift"
    "$SRC_DIR/PowerMonitor.swift"
    "$SRC_DIR/WallpaperWindow.swift"
    "$SRC_DIR/WallpaperController.swift"
    "$SRC_DIR/SettingsView.swift"
    "$SRC_DIR/AppDelegate.swift"
    "$SRC_DIR/LoopApp.swift"
)

swiftc \
    -O \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macosx14.0 \
    -parse-as-library \
    -framework AppKit \
    -framework AVFoundation \
    -framework CoreMedia \
    -framework IOKit \
    -framework ServiceManagement \
    -framework QuartzCore \
    -framework SwiftUI \
    -framework ScreenSaver \
    -o "$SCRIPT_DIR/Loop" \
    "${SOURCES[@]}" \
    2>&1

echo "==> Assembling $APP_NAME.app bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mv "$SCRIPT_DIR/Loop" "$MACOS_DIR/Loop"

# Embed the screensaver bundle directly inside the app bundle
cp -R "$SAVER_BUNDLE" "$RESOURCES_DIR/LoopSaver.saver"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Loop</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.loop</string>
    <key>CFBundleName</key>
    <string>Loop</string>
    <key>CFBundleDisplayName</key>
    <string>Loop</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$BUNDLE_DIR"
echo "    ✓ Loop app built and signed (with embedded LoopSaver.saver)"

# ─────────────────────────────────────────────
# 3. Install screensaver locally
# ─────────────────────────────────────────────
echo ""
echo "==> Installing screensaver to ~/Library/Screen Savers/..."
mkdir -p "$SAVER_INSTALL_DIR"
rm -rf "$SAVER_INSTALL_DIR/$SAVER_NAME.saver"
cp -R "$SAVER_BUNDLE" "$SAVER_INSTALL_DIR/"
echo "    ✓ Installed to: $SAVER_INSTALL_DIR/$SAVER_NAME.saver"

# ─────────────────────────────────────────────
# 4. Optional DMG creation
# ─────────────────────────────────────────────
if [[ "${1:-}" == "--dmg" || "${1:-}" == "-d" ]]; then
    echo ""
    echo "==> Packaging into DMG..."
    bash "$SCRIPT_DIR/package.sh"
fi

# ─────────────────────────────────────────────
# 5. Launch (skip if running in CI or --no-open)
# ─────────────────────────────────────────────
if [[ "${CI:-}" != "true" && "${1:-}" != "--no-open" ]]; then
    echo ""
    echo "==> Launching $APP_NAME.app..."
    open "$BUNDLE_DIR"
fi

echo ""
echo "=== Build Complete ==="
echo "  Loop app:    $BUNDLE_DIR"
echo "  Screensaver: $SAVER_INSTALL_DIR/$SAVER_NAME.saver"
