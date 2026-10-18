#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -D GEOSPOOF_DEVELOPMENT -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path build/module-cache Sources/DeviceService.swift Sources/PythonDeviceService.swift Sources/AppModel.swift Tests/Checks.swift -o build/checks
# Offline checks use a stand-in helper; --live uses the real one.
if [ -x .build/venv/bin/python ]; then
    export GEOSPOOF_PYTHON="$PWD/.build/venv/bin/python"
    export GEOSPOOF_HELPER="$PWD/Sources/stub_helper.py"
    export GEOSPOOF_LIVE_HELPER="$PWD/Sources/geospoof_helper.py"
else
    echo "Run scripts/setup.sh before running tests."
    exit 1
fi
.build/venv/bin/python -m unittest discover -s Tests -p 'test_*.py'
build/checks "$@"
