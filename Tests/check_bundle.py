"""Run the distributed helper without a virtualenv, developer tools, or project cwd."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

helper = Path(__file__).resolve().parents[1] / "build/GeoSpoof.app/Contents/Resources/device-helper/geospoof-helper"
with tempfile.TemporaryDirectory() as directory:
    result = subprocess.run(
        [str(helper)], cwd=directory,
        env={"HOME": os.environ["HOME"], "PATH": "/usr/bin:/bin", "DEVELOPER_DIR": "/nonexistent"},
        input='{"id":1,"cmd":"hello"}\n{"id":2,"cmd":"quit"}\n',
        text=True, capture_output=True, timeout=30, check=True,
    )
    replies = [json.loads(line) for line in result.stdout.splitlines()]
    assert replies[0]["ok"] and replies[0]["result"]["protocol"] == 1, replies
    assert replies[0]["result"]["pymobiledevice3"] == "11.32.0", replies
    assert replies[1]["ok"], replies
print("PASS: bundled runtime starts without project cwd, virtualenv, or Xcode")
