# GeoSpoof

GeoSpoof sets a trusted iPhone's simulated location from a Mac over USB or
local Wi-Fi.

## Requirements

- Apple silicon Mac running macOS 26 or later
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
