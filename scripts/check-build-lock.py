"""Refuse packaging an environment that diverges from the reviewed lock."""
from importlib.metadata import distributions
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
normalize = lambda name: re.sub(r"[-_.]+", "-", name).lower()
locked = {normalize(name): version for name, version in re.findall(
    r"^([A-Za-z0-9_.-]+)==([^\s;\\]+)", (root / "requirements.lock").read_text(), re.MULTILINE
)}
if sys.version_info[:3] != (3, 13, 16):
    raise SystemExit("Build with Python 3.13.16 via scripts/setup.sh.")
mismatches = []
for package in distributions():
    name = package.metadata["Name"]
    if locked.get(normalize(name)) != package.version:
        mismatches.append(f"{name}=={package.version}")
if mismatches:
    raise SystemExit("Environment differs from requirements.lock: " + ", ".join(mismatches))
print("PASS: build environment matches pinned versions")
