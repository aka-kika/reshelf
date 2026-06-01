#!/bin/bash
set -euo pipefail

# SCHEME is the Xcode scheme/target name (internal, unchanged).
# APP_NAME is the product/bundle name (PRODUCT_NAME) — the built ".app" file.
SCHEME="OpenSource Shelf"
APP_NAME="reshelf"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
OUTPUT_APP="$BUILD_DIR/$APP_NAME.app"

echo "🔨 Building $APP_NAME..."

mkdir -p "$BUILD_DIR"

xcodebuild \
    -project "$PROJECT_DIR/OpenSourceShelf.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    build

rm -rf "$OUTPUT_APP"
cp -R "$BUILT_APP" "$OUTPUT_APP"

echo ""
echo "✅ Build complete!"
echo "   App: $OUTPUT_APP"
echo ""
echo "   Run: open \"$OUTPUT_APP\""
echo ""
