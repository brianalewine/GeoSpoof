# GeoSpoof

GeoSpoof sets a trusted iPhone's simulated location from a Mac over USB or
local Wi-Fi.

## Requirements

- Intel or Apple silicon Mac running macOS 26 or later (universal release)
- Xcode, to build from source
- A trusted iPhone with Developer Mode enabled
- A USB connection, or the Mac and iPhone on the same Wi-Fi network

## Build and run

From the project directory:

```sh
bash scripts/setup.sh
bash scripts/build.sh
open build/GeoSpoof.app
```

The setup script creates the locked Python environment used by the build. If
the project is moved, run `bash scripts/setup.sh` again.

## Use

1. Connect and unlock the iPhone, then accept the trust prompt if asked.
2. Select a location on the map, or search for one in the sidebar.
3. Click **Set Location**.
4. Click **Stop Spoofing** to clear the simulation and restore the iPhone's
   normal location.

The first connection may require an internet connection so macOS can install
Apple's developer support image on the iPhone.

## Universal DMG release

Run `bash scripts/release-universal.sh` to create
`build/GeoSpoof-0.5.0-universal.dmg` and its SHA-256 checksum. This compiles
the Swift app for arm64 and x86_64 and bundles separate, locked Python 3.13.16
helpers selected by the running app architecture. Intel helpers can be
smoke-tested under Rosetta on Apple silicon. The standard build script still
builds an Apple silicon app.

The locked Intel cryptography dependency requires compiling from source.
Install a Rust toolchain with the `x86_64-apple-darwin` target and supply an
Intel static OpenSSL build through `OPENSSL_DIR` and `OPENSSL_STATIC=1`.
The release built here uses OpenSSL 3.5.9. Build tools are not required on
recipients' Macs.

The generated app is ad-hoc signed, not Developer ID signed or notarized.
