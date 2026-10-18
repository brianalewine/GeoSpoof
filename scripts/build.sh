#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
.build/venv/bin/python scripts/check-build-lock.py
mkdir -p build/GeoSpoof.app/Contents/MacOS build/GeoSpoof.app/Contents/Resources build/module-cache
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0 -module-cache-path build/module-cache Sources/*.swift -o build/GeoSpoof.app/Contents/MacOS/GeoSpoof
cp Info.plist build/GeoSpoof.app/Contents/Info.plist
if [ ! -f build/GeoSpoof.icns ] || [ scripts/icon.swift -nt build/GeoSpoof.icns ]; then
    xcrun swift -module-cache-path build/module-cache scripts/icon.swift build/GeoSpoof.iconset
    iconutil -c icns build/GeoSpoof.iconset -o build/GeoSpoof.icns
fi
cp build/GeoSpoof.icns build/GeoSpoof.app/Contents/Resources/GeoSpoof.icns
bash scripts/bundle-helper.sh
codesign --force --options runtime --entitlements scripts/helper-entitlements.plist --sign - build/GeoSpoof.app/Contents/Resources/device-helper/geospoof-helper
codesign --force --options runtime --sign - build/GeoSpoof.app
codesign --verify --deep --strict build/GeoSpoof.app
echo "Built build/GeoSpoof.app"
