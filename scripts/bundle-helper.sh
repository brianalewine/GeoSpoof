#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PYINSTALLER_CONFIG_DIR="$PWD/build/pyinstaller-cache"
.build/venv/bin/python -c 'import sys; assert sys.version_info >= (3, 13, 16), "Update the build Python runtime"'
.build/venv/bin/python -m PyInstaller --noconfirm --clean --onedir \
    --name geospoof-helper --distpath build/python-dist --workpath build/python-work \
    --specpath build --collect-data developer_disk_image \
    --recursive-copy-metadata pymobiledevice3 Sources/geospoof_helper.py
target="build/GeoSpoof.app/Contents/Resources/device-helper"
if [ -d "$target" ]; then
    mv "$target" "build/previous-device-helper-$(date +%s)"
fi
mkdir -p "$target"
# ditto preserves the framework symlinks required by the embedded Python runtime.
ditto build/python-dist/geospoof-helper "$target"
