# GeoSpoof research notes

Updated October 16, 2026. Supersedes the earlier collection-stage report.

## Status

- The native SwiftUI app is built (`build/GeoSpoof.app`; usage in `README.md`). It sets and clears an iPhone's simulated location over USB and Wi-Fi by calling Apple's `devicectl`.
- **Known limitation:** `devicectl` ships with Xcode, so every Mac running the app needs Xcode 27 installed and selected.
- **Current goal:** remove that requirement by replacing the backend with a bundled `pymobiledevice3` helper. This has **not** been proven yet. Only device discovery has ever been run through Python.

## Test environment

| Item | Value |
| --- | --- |
| Mac | Mac17,9, arm64, 64 GiB, macOS 27.0 (26A428) |
| Xcode | 27.0 (27A266a), Swift 6.4 |
| iPhone | iPhone 13 Pro (iPhone14,2), iOS 27.2 (24B5099f) |
| Phone state | Paired and trusted, Developer Mode on |
| Python | 3.13.1 |

Device identifiers are intentionally left out. No Apple ID, passcode, pairing keys or app inventory is needed or collected.

## What has been verified (devicectl backend)

| Test | Result |
| --- | --- |
| Device discovery, USB and Wi-Fi | Passed |
| Set location over USB | Passed; user saw the blue dot at Barracks Road Shopping Center in Apple Maps |
| Clear over USB | Passed; real location returned |
| Set and clear over Wi-Fi, cable unplugged, fresh process | Passed |
| App-level checks (`scripts/test.sh`) | Parsing, deduplication, coordinate bounds, session persistence, failed reset, recovery targeting |

No paid developer account, provisioning profile, phone-side app or sudo was needed. Test coordinates: 38.0544087, -78.499656 (Barracks Road Shopping Center, Charlottesville).

**Not yet tested:** other apps' behavior, phone lock, reboot, Mac sleep/wake, network loss mid-session, long sessions. Apple Maps results must not be read as universal compatibility.

## Current backend contract

```text
xcrun devicectl list devices
xcrun devicectl device info details --device <id>
xcrun devicectl device simulate location coordinate --device <id> --latitude <lat> --longitude=<lon>
xcrun devicectl device simulate location clear --device <id>
```

- The simulation persists until cleared; closing the process does not restore real location.
- Success means the command was accepted, not that every app shows the new position.
- The app calls the tool with argument arrays and timeouts, validates coordinates, serializes operations, and remembers an "unknown state" flag until a clear succeeds.

## Removing the Xcode requirement

Plan: add a second implementation of the existing `DeviceControlling` protocol that drives a bundled Python helper. The UI and `AppModel` should not need to change.

**Candidate:** `pymobiledevice3` 11.32.0 (pinned in `research-requirements.txt`).
- Licence: GPL-3.0, so a distributed app would need GPL-compatible terms and source.
- Size: the research venv is about 132 MB, before any bundling work.
- iOS 27 mounts its developer image through a Cryptex path that needs a tunnel, and 11.20.0 release notes mention iOS 27.2 peer-connection fixes. Whether set/clear works on this phone is unknown.
- Older documentation lists `mounter auto-mount` and `developer dvt simulate-location set/clear`. Syntax in 11.32 must be checked with `--help`.

**Open questions the test must answer**
1. Does it need `sudo` or an always-running tunnel daemon?
2. Does the location survive after the setting process exits, or must a helper stay alive until Stop Spoofing?
3. Where does the developer disk image come from: a download, or Xcode's install folder? If Xcode's folder, a Mac without Xcode would fail.
4. Does it work over Wi-Fi with no cable?

**Test procedure (Xcode stays installed)**
1. Recreate the venv in the current folder (see below).
2. Restart the iPhone so any developer image mounted by Xcode is removed.
3. Optionally hide Xcode: `sudo xcode-select -s /Library/Developer/CommandLineTools` and, for a stronger test, rename `/Applications/Xcode.app`. Confirm `xcrun devicectl list devices` now fails. Undo both afterwards.
4. Run `usbmux list`, `mounter auto-mount`, then set and clear Barracks Road; confirm in Apple Maps. Repeat over Wi-Fi.
5. Record answers to the four questions above here.

Results: _not yet run._

## Distribution notes

- The app is ad-hoc signed, arm64-only, and targets macOS 26 or later. It is not notarized.
- A recipient on another Mac must approve it once: open it, then System Settings, Privacy & Security, Open Anyway. Or remove the quarantine flag with `xattr -dr com.apple.quarantine`. Building on their own Mac avoids the prompt.
- Removing the prompt requires a paid Apple Developer Program membership (Developer ID signing and notarization). Not planned.
- Today the recipient also needs Xcode 27, a trusted iPhone with Developer Mode, and a compatible iOS version.

## Practical notes

- Moving the project folder breaks cached paths. After a move, delete `build/module-cache` before building, and recreate the venv: `rm -rf .venv && python3 -m venv .venv && .venv/bin/pip install -r research-requirements.txt`. Use Python 3.13.
- Command-line tools may need access to macOS device services outside a restrictive sandbox; this is an execution limit, not a phone incompatibility.

## References

- [Apple: Get the most out of Device Hub](https://developer.apple.com/videos/play/wwdc2026/260/)
- [pymobiledevice3 repository](https://github.com/doronz88/pymobiledevice3) and [v11.20.0 release notes](https://github.com/doronz88/pymobiledevice3/releases/tag/v11.20.0)
- [Barracks Road Shopping Center listing](https://properties.federalrealty.com/property/barracks-road-shopping-center/3313948) (test coordinates)
