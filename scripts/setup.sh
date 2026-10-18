#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# uv is a developer-only tool; none of these steps run on recipients' Macs.
uv python install 3.13.16 --install-dir build/python-runtime --no-bin --cache-dir build/uv-cache
uv venv .build/venv --python build/python-runtime/cpython-3.13.16-macos-aarch64-none/bin/python3 --cache-dir build/uv-cache
uv pip sync requirements.lock --python .build/venv/bin/python --require-hashes --cache-dir build/uv-cache
