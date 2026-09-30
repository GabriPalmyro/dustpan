#!/usr/bin/env bash
# Packages build/Dustpan.app into a drag-to-install disk image: build/Dustpan-<version>.dmg
#
#   scripts/make-dmg.sh                 # builds the app first
#   VERSION=1.2.0 scripts/make-dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed "s/^v//" || echo 0.1.0)}"
export VERSION

scripts/build-app.sh

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R build/Dustpan.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="build/Dustpan-${VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname "Dustpan" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
[ -n "${SIGN_IDENTITY:-}" ] && codesign --force --sign "$SIGN_IDENTITY" "$DMG"
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
