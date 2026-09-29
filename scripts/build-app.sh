#!/usr/bin/env bash
# Builds Dustpan.app from the Swift package.
#
#   scripts/build-app.sh            # release build → build/Dustpan.app
#   VERSION=1.2.0 scripts/build-app.sh
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
#
# Without SIGN_IDENTITY the app is ad-hoc signed: fine on your own Mac,
# but Gatekeeper will complain on others (right-click › Open the first time).
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="build/Dustpan.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Dustpan"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dustpan"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>            <string>com.gabripalmyro.dustpan</string>
    <key>CFBundleName</key>                  <string>Dustpan</string>
    <key>CFBundleDisplayName</key>           <string>Dustpan</string>
    <key>CFBundleExecutable</key>            <string>Dustpan</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>${VERSION}</string>
    <key>CFBundleVersion</key>               <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
    <key>LSApplicationCategoryType</key>     <string>public.app-category.utilities</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSHumanReadableCopyright</key>      <string>MIT License</string>
</dict>
</plist>
PLIST

codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"
