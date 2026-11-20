#!/bin/sh
# Builds "build/PXN V10 Pro Tuner.app" (Apple silicon + Intel) and the pxntuner command-line tool beside it.
set -eu
cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
APP="build/PXN V10 Pro Tuner.app"

swift build -c release --arch arm64 --arch x86_64
PRODUCTS="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf build
mkdir -p "$APP/Contents/MacOS"
cp "$PRODUCTS/TunerApp" "$APP/Contents/MacOS/TunerApp"
cp "$PRODUCTS/pxntuner" build/pxntuner
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PXN V10 Pro Tuner</string>
    <key>CFBundleDisplayName</key><string>PXN V10 Pro Tuner</string>
    <key>CFBundleIdentifier</key><string>io.github.nexstead-games.pxn-v10-pro-tuner-mac</string>
    <key>CFBundleExecutable</key><string>TunerApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
# Ad-hoc signature: enough to run on the Mac that built it.
codesign --force --sign - "$APP"
echo "built $APP and build/pxntuner"
