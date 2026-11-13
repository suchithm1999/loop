#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="LoopApp"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
DIST_DIR="$SCRIPT_DIR/dist"
TAG="${GITHUB_REF_NAME:-1.0.0}"
VERSION="${TAG#v}"
DMG_NAME="Loop-v${VERSION}.dmg"
ZIP_NAME="Loop-v${VERSION}.zip"

# Ensure app is built
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "==> LoopApp.app not found. Running build.sh first..."
    bash "$SCRIPT_DIR/build.sh"
fi

echo "==> Creating release distribution directory..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 1. Create ZIP
echo "==> Creating $ZIP_NAME..."
ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_DIR/$ZIP_NAME"
echo "    ✓ Created $DIST_DIR/$ZIP_NAME"

# 2. Create DMG
echo "==> Creating $DMG_NAME..."
DMG_STAGING=$(mktemp -d)
cp -R "$APP_BUNDLE" "$DMG_STAGING/Loop.app"
ln -s /Applications "$DMG_STAGING/Applications"

# Remove any previous dmg
rm -f "$DIST_DIR/$DMG_NAME"

# Create compressed DMG image
hdiutil create \
    -volname "Loop" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DIST_DIR/$DMG_NAME" \
    2>&1

rm -rf "$DMG_STAGING"
echo "    ✓ Created $DIST_DIR/$DMG_NAME"

echo ""
echo "=== Distribution Artifacts Ready ==="
ls -lh "$DIST_DIR"
echo ""
echo "You can attach these files directly to your GitHub Release:"
echo "  1. $DIST_DIR/$DMG_NAME (Drag-and-drop installer for users)"
echo "  2. $DIST_DIR/$ZIP_NAME (Portable zip archive)"

