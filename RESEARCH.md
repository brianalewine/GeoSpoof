# GeoSpoof device research and preliminary tests

October 16, 2026. This document updates the initial PLAN.md. No app implementation has begun.

Implementation update: the native app is now built in `build/GeoSpoof.app`; see `README.md` for usage and checks. The user confirmed location changes from the app. The redesigned version uses a Find My-inspired sidebar and a distinct custom icon. Read-only integration checks passed for Wi-Fi discovery/verification and MapKit search. Session recovery tests and signature verification passed. The user reported a one- or two-second transition in Apple Maps; GeoSpoof sends one static coordinate, but whether Maps animates the dot or iOS supplies intermediate fixes has not been independently measured. The research narrative below describes the earlier collection stage.

## Selected approach

Use a SwiftUI app that calls Apple's installed `devicectl` through `Process`. This Mac's Xcode 27.0 includes `device simulate location coordinate` and `clear`. Setting a location succeeded both wired and wirelessly, and the user visually confirmed both results in Apple Maps. This is a simpler first backend for this single-Mac project than bundling Python.

Xcode is therefore **already installed and useful for both building and running this proposed version**. The Xcode window need not remain open. Do not remove Xcode if the app relies on its tools. This is a design choice for the smallest app on this particular Mac, not a claim that all location simulators require Xcode. A bundled pymobiledevice3 backend remains the alternative if eliminating the Xcode dependency becomes a requirement.

No paid developer login, provisioning profile, sideloaded iPhone app, or root/sudo command was used in the successful coordinate test. The execution environment required permission to access macOS device services outside its sandbox; that is distinct from requiring an administrator daemon in the finished app.

Apple describes Device Hub location simulation and the related devicectl tool in [Get the most out of Device Hub](https://developer.apple.com/videos/play/wwdc2026/260/). Exact command syntax and behavior below were checked against this Mac's installed tool help, rather than inferred from an older tutorial.

## Collected environment

| Item | Finding | Evidence |
| --- | --- | --- |
| Mac OS | macOS 27.0, build 26A428 | `sw_vers` |
| Architecture | arm64 | `uname -m` |
| Mac model identifier | Mac17,9 | `sysctl hw.model` |
| Memory | 64 GiB | `sysctl hw.memsize` |
| Xcode | 27.0, build 27A266a | `xcodebuild -version` |
| Selected developer directory | /Applications/Xcode.app/Contents/Developer | `xcode-select -p` |
| Swift | 6.4 | `xcrun swift --version` |
| iPhone | iPhone 13 Pro, iPhone14,2 | devicectl and backend discovery |
| iOS | 27.2, build 24B5099f | read directly from phone |
| Pairing | Paired/trusted | devicectl; user confirmed |
| Developer Mode | Enabled | devicectl device info |
| Initial active transport | Wired, TCP tunnel | devicectl device info |
| Network discovery | Same phone listed as USB and Network | pymobiledevice3 usbmux list |
| Developer image | Build 27A266a; compatible, usable, Cryptex DDI | ddiServices with auto-mount disabled |
| Python available | 3.13.1 | local interpreter |

Stable device identifiers were used for tests but are intentionally omitted from this report. There is no need to collect an Apple ID, password, phone passcode, pairing private keys, photos, contacts, or installed-app inventory.

The user confirmed same-network operation near this Mac is sufficient. The desired behavior is system location simulation, rather than a modification inside one particular app. This sets the implementation scope but cannot establish that every app accepts the result.

## Tests and evidence

| Test | Result |
| --- | --- |
| Apple device discovery | Passed: trusted phone available |
| Independent backend discovery | Passed: USB and Network entries for the same phone |
| Developer Mode query | Enabled; no toggle/reboot needed |
| Existing developer-image inspection | Compatible and usable; no manual image download needed for Apple-tool test |
| Initial USB coordinate command | Exit 0; initial landmark was subsequently cleared at user's request |
| Requested USB coordinate command | Exit 0: set 38.0544087, -78.499656 (Barracks Road Shopping Center, Charlottesville) |
| Visual confirmation in Apple Maps | Passed: user confirmed blue dot at Barracks Road Shopping Center |
| Explicit clear and real-location observation | Passed: clear exited 0 and user confirmed normal location returned |
| Fresh connection with USB physically disconnected | Passed: user unplugged; Apple reports localNetwork/connected; usbmux lists only Network |
| Wi-Fi location set | Passed: exit 0 from a new devicectl invocation; user confirmed blue dot at Barracks Road |
| Wi-Fi clear | Passed: exit 0; user confirmed actual location returned with cable unplugged |

The initial sandboxed devicectl attempt timed out initializing CoreDeviceService. The same discovery command worked outside the execution sandbox. Likewise, backend discovery was blocked from the usbmux socket until run outside that sandbox. These were execution-access limitations, not evidence of phone incompatibility.

Use Barracks Road Shopping Center for all further location tests, per the user's correction. Coordinates come from the [property owner's listing](https://properties.federalrealty.com/property/barracks-road-shopping-center/3313948). The wired simulation was explicitly cleared after the user confirmed it.

## Apple-tool backend contract

Verified command family:

```text
xcrun devicectl list devices
xcrun devicectl device info details --device <selected-device>
xcrun devicectl device info ddiServices --device <selected-device> --no-auto-mount-ddis
xcrun devicectl device simulate location coordinate --device <selected-device> --latitude <latitude> --longitude=<longitude>
xcrun devicectl device simulate location clear --device <selected-device>
```

The installed help states coordinate simulation continues until cleared. Treat successful command completion as acceptance, not independent verification of the location seen by all apps. Do not depend on closing the child process to restore real location.

Implementation proposal:

- Discover tool capability at startup, not just an Xcode version string.
- Spawn `/usr/bin/xcrun` with an argument array, bounded timeout, and JSON output for structured results. Validate finite latitude/longitude and legal ranges before invoking it.
- Select by stable device identity and deduplicate wired/network sightings. Never silently switch to a different phone.
- Serialize set/clear operations. Persist an “app may have left simulation active” flag and offer recovery after an interrupted session.
- Use explicit clear on normal stop/quit. If unreachable, preserve an unknown-state warning until reconnect and successful clear.
- Build a local, non-App-Store utility first. Validate subprocess and device-service access from the actual app; do not assume the agent's sandbox behavior predicts app entitlements.
- Native SwiftUI and optional MapKit picker/search; UserDefaults or a local file for favorites. No server, account system, Electron runtime, or continuous Python process is needed for this path.
- Route playback can remain a later UI feature even though the installed tool exposes it.

The Xcode 27.0 / iOS 27.2 pairing should not be declared generally supported solely from version numbers. In this case, live device capability, compatible DDI metadata, and the successful command are stronger evidence for the narrow operation we need. No Xcode upgrade is currently justified.

## Python alternative investigated

Installed pymobiledevice3 11.32.0 into the project-only `.venv`, using Python 3.13.1. No global Python packages were changed. `research-requirements.txt` records the resolved versions for reproduction. The environment occupies approximately 132 MB on disk, excluding the base Python interpreter and support-image downloads; this is not a finished app bundle-size estimate.

The package metadata declares Python >=3.9 and GPL 3.0. The installed DVT location implementation exposes set and clear, while its CLI set command waits for input to retain the session. A future helper should own a service session explicitly rather than repeatedly launching that interactive CLI. Distribution licensing and packaging would need consideration if this fallback is shipped.

iOS 27 changes developer-image installation to a Cryptex path requiring an RSD tunnel. The implementation contains that version branch. [Pinned image-mounter source](https://github.com/doronz88/pymobiledevice3/blob/v11.32.0/pymobiledevice3/services/mobile_image_mounter.py)

iOS 27.2 also changed peer connection behavior. The project's v11.20.0 notes describe fixes for peer identity and prefer its userspace tunnel over competing with Apple's native tunnel. This supports choosing a recent pin, but does not itself prove our fallback's set/clear operation. [Release notes](https://github.com/doronz88/pymobiledevice3/releases/tag/v11.20.0)

Only discovery has been exercised through Python. The successful location command used Apple's tool. Keep these results separate. Do not install another tunnel daemon or alter system services while the simpler Apple path is working.

## Remaining collection and validation

The hardware versions and Developer Mode state are now known, so no additional device specifications are needed from the user. Preliminary sequence:

1. Confirm the actual blue location dot moves in Apple Maps after the wired command — passed.
2. Clear and confirm real location returns — passed.
3. Unplug USB, retain both devices on the same network, verify wireless transport, and issue a new location command — passed.
4. Confirm that new location and then clear over Wi-Fi — passed, including user's confirmation of actual location restored.
5. During implementation validation, check phone lock, Mac sleep/wake, network loss, app restart, and cleanup behavior. Do not deliberately interrupt the connection until the clear/recovery path has passed.

Do not request Wi-Fi passwords or collect the current geographic location. A named public landmark and the user's yes/no observation are sufficient for preliminary validation.

## Stage outcome

The preliminary USB/Wi-Fi feasibility gate passed on this Mac and iPhone. Simulation is cleared, and the user confirmed real location is restored. No app code has been written. Next stage: implement the native interface and Apple-tool adapter, then test lifecycle/recovery from the packaged app. Other apps, phone lock, reboot, sleep/wake, and extended-session reliability remain untested; do not convert the Apple Maps result into a universal compatibility claim.
