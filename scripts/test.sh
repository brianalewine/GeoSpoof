#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path build/module-cache Sources/DeviceService.swift Sources/AppModel.swift Tests/Checks.swift -o build/checks
build/checks "$@"
