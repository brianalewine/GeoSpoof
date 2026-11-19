#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/GeoSpoof.app/Contents/{MacOS,Resources} build/module-cache
for arch in arm64 x86_64; do
    runtime_arch="$arch"
    if [ "$arch" = arm64 ]; then runtime_arch=aarch64; fi
    uv python install "cpython-3.13.16-macos-$runtime_arch-none" --install-dir build/python-runtime --no-bin --cache-dir build/uv-cache
    runtime="$PWD/build/python-runtime/cpython-3.13.16-macos-$runtime_arch-none/bin/python3"
    if [ ! -x ".build/venv-$arch/bin/python" ]; then
        uv venv ".build/venv-$arch" --python "$runtime" --cache-dir build/uv-cache
    fi
    uv pip sync requirements.lock --python ".build/venv-$arch/bin/python" --require-hashes --cache-dir build/uv-cache
    /usr/bin/arch -"$arch" ".build/venv-$arch/bin/python" scripts/check-build-lock.py
    PYINSTALLER_CONFIG_DIR="$PWD/build/pyinstaller-cache-$arch" /usr/bin/arch -"$arch" ".build/venv-$arch/bin/python" -m PyInstaller --noconfirm --clean --onedir --target-architecture "$arch" --name geospoof-helper --distpath "build/python-dist-$arch" --workpath "build/python-work-$arch" --specpath "build/spec-$arch" --collect-data developer_disk_image --recursive-copy-metadata pymobiledevice3 Sources/geospoof_helper.py
    ditto "build/python-dist-$arch/geospoof-helper" "build/GeoSpoof.app/Contents/Resources/device-helper-$arch"
    codesign --force --options runtime --entitlements scripts/helper-entitlements.plist --sign - "build/GeoSpoof.app/Contents/Resources/device-helper-$arch/geospoof-helper"
    xcrun swiftc -swift-version 5 -O -target "$arch-apple-macos26.0" -module-cache-path build/module-cache Sources/*.swift -o "build/GeoSpoof-$arch"
done
lipo -create build/GeoSpoof-arm64 build/GeoSpoof-x86_64 -output build/GeoSpoof.app/Contents/MacOS/GeoSpoof
cp Info.plist build/GeoSpoof.app/Contents/Info.plist
xcrun swift -module-cache-path build/module-cache scripts/icon.swift build/GeoSpoof.iconset
iconutil -c icns build/GeoSpoof.iconset -o build/GeoSpoof.icns
cp build/GeoSpoof.icns build/GeoSpoof.app/Contents/Resources/GeoSpoof.icns
codesign --force --options runtime --sign - build/GeoSpoof.app
codesign --verify --deep --strict build/GeoSpoof.app
mkdir -p build/dmg-root
 ditto build/GeoSpoof.app build/dmg-root/GeoSpoof.app
ln -sfn /Applications build/dmg-root/Applications
hdiutil create -volname GeoSpoof -srcfolder build/dmg-root -ov -format UDZO build/GeoSpoof-0.5.0-universal.dmg
hdiutil verify build/GeoSpoof-0.5.0-universal.dmg
shasum -a 256 build/GeoSpoof-0.5.0-universal.dmg > build/GeoSpoof-0.5.0-universal.dmg.sha256
