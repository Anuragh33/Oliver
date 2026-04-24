#!/bin/bash
# Oliver Auto-Deploy Script
# Builds release binary, creates .app bundle, signs, packages .dmg, and pushes to GitHub
# Usage: ./build_and_deploy.sh [version] [commit message]
# Example: ./build_and_deploy.sh v1.3.0 "added new feature"

set -e
cd "$(dirname "$0")/.."

VERSION="${1:-}"
COMMIT_MSG="${2:-auto-deploy: build and release}"

# Force a version from git tag if not provided
if [ -z "$VERSION" ]; then
    # Get latest tag and increment
    LATEST_TAG=$(git tag --sort=-v:refname | head -1)
    echo "Latest tag: $LATEST_TAG"
    echo "Usage: $0 <version> [commit message]"
    echo "Example: $0 v1.3.0 \"added new feature\""
    exit 1
fi

echo "=== Oliver Build & Deploy ==="
echo "Version: $VERSION"

# 1. Build release
echo "[1/6] Building release binary..."
swift build -c release

# 2. Create .app bundle
echo "[2/6] Creating .app bundle..."
BUNDLE="build/Oliver.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
cp .build/release/Oliver "$BUNDLE/Contents/MacOS/Oliver"
cp Sources/Oliver/Info.plist "$BUNDLE/Contents/Info.plist"
chmod +x "$BUNDLE/Contents/MacOS/Oliver"

# 3. Add icon if available
if [ -f "build/Oliver.icns" ]; then
    cp build/Oliver.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

# 4. Code sign
echo "[3/6] Code signing..."
xattr -cr "$BUNDLE"
codesign --force --deep --sign - "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"

# 5. Create .dmg
echo "[4/6] Creating .dmg..."
DMG_STAGING=$(mktemp -d)
cp -R "$BUNDLE" "$DMG_STAGING/"
ln -sf /Applications "$DMG_STAGING/Applications"
rm -f build/Oliver.dmg
hdiutil create -volname "Oliver" -srcfolder "$DMG_STAGING" -ov -format UDZO build/Oliver.dmg
rm -rf "$DMG_STAGING"

echo "[5/6] Git commit & push..."
git add -A
git commit -m "$COMMIT_MSG" || echo "Nothing to commit"
git push origin main

# 6. Create GitHub release
echo "[6/6] Creating GitHub release $VERSION..."
gh release create "$VERSION" build/Oliver.dmg \
    --title "Oliver $VERSION" \
    --notes "Auto-deployed release $VERSION. Download Oliver.dmg, drag to Applications, right-click > Open."

echo "=== Done! Release: https://github.com/Anuragh33/Oliver/releases/tag/$VERSION ==="