# GeoSpoof: feasibility and implementation plan

Prepared October 16, 2026. Research and proposed design only; no application code or device changes have been made.

Update: the information-collection stage and preliminary device testing are recorded in [RESEARCH.md](RESEARCH.md). That report supersedes the initial backend recommendation: this Mac's installed Xcode 27 tool successfully set device location both over USB and Wi-Fi, with user confirmation in Apple Maps. Use SwiftUI plus devicectl for the implementation stage; retain Xcode on this Mac. Python is an investigated fallback, not a required app component. Device testing has now begun; the original no-device-changes statement above describes the planning stage only.

## Recommendation

Build a small native Mac app that controls the iPhone's developer location-simulation service. Aim for **USB setup followed by Wi-Fi operation**, with USB available for recovery. No companion iPhone app, jailbreak, or paid Apple Developer membership is planned.

This is technically plausible, but not yet verified on your hardware. The next stage should prove setting and clearing a location on your exact iPhone/iOS version before investing in the interface.

“Spoof GPS” here means supplying simulated location through iOS developer services, not altering GPS radio signals. It does not change your IP address or guarantee that every app or Apple service will report the selected place. Apple exposes a software-simulation flag to apps, so this design cannot promise undetectable locations. [Apple location-source documentation](https://developer.apple.com/documentation/corelocation/cllocationsourceinformation/issimulatedbysoftware)

## How wireless can it be?

| Mode | Assessment for this project |
| --- | --- |
| USB connected during use | Baseline to validate first; simplest recovery path. |
| USB once, then local Wi-Fi | Recommended target. Current pymobiledevice3 documentation describes enabling Wi-Fi over USB and subsequently using the device wirelessly on macOS. |
| Never connect a cable, including initial setup | Not a supported onboarding promise. Start with explicit USB trust and pairing. |
| Phone away from the Mac on cellular or another network | Outside the initial design. Local Wi-Fi discovery does not provide internet connectivity to the phone. |
| Set a location, disconnect, and expect it to remain indefinitely | Unverified and unsuitable as a product guarantee. Measure persistence and recovery on the actual phone. |

The relevant backend supports developer-service tunnels and Wi-Fi discovery; its documentation also describes version-dependent transport behavior. Its current no-admin paths are promising, but the released version we choose must actually contain those features. Do not copy older tutorials that assume every tunnel needs sudo. [pymobiledevice3 tunnel guide](https://doronz88.github.io/pymobiledevice3/guides/ios17-tunnels/)

Apple documents initial USB setup followed by Finder's “Show this [device] when on Wi-Fi” setting. Both devices then need a reachable local network. Finder visibility is a useful onboarding check, not proof that developer location simulation works. [Apple Finder guide](https://support.apple.com/en-gb/102471)

Your AltStore comparison is sound for the connection pattern: AltServer supports USB or the same Wi-Fi network. Its app-installation/signing workflow is separate from the location-simulation service proposed here. We do not need to install AltStore. [AltServer documentation](https://faq.altstore.io/altstore-classic/altserver)

## No developer profile: what that means

- **Paid Apple Developer membership:** not expected for the proposed host-to-device service workflow. It does not involve signing and installing an iPhone app. Confirm this during the hardware proof with no developer-account login.
- **iPhone provisioning or developer profile:** none planned. There is no sideloaded app to refresh every seven days.
- **Developer Mode:** expect to enable this on supported modern iOS versions. It is a device setting, distinct from membership or a provisioning profile. Apple describes pairing, enabling the setting, restarting, and confirming on the phone. [Apple Developer Mode guide](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- **Developer support image:** expect the backend to prepare/mount a compatible Developer Disk Image. This is developer support material, not an installed home-screen app. The backend documents Developer Mode and the support image as prerequisites for developer services, including location simulation; modern image preparation can need network access. [Protocol and image documentation](https://doronz88.github.io/pymobiledevice3/internals/idevice-protocol-layers/)

For the first version, plan a locally built Mac application. Public distribution and its signing/notarization requirements are a separate future decision, not a prerequisite for this personal prototype.

## Proposed app

A native SwiftUI window with an optional menu-bar shortcut. Start with one selected iPhone, coordinate entry, saved places, and prominent Set Location and Restore Real Location buttons. Add a map picker after the connection proof succeeds.

Show the device name, iOS version, USB/Wi-Fi transport, and a plain-language connection state. Distinguish “command accepted” from a location actually observed on the phone. If the connection disappears, show “Disconnected — location state unknown,” not “Restored.”

Keep the Mac awake during an active session only if testing establishes that this is needed; release that assertion when the session ends. Attempt an explicit clear before normal app exit. A crash or loss of connectivity cannot guarantee cleanup, so the recovery UI must support reconnecting and clearing again.

Defer route playback, joystick controls, multi-device operation, remote internet control, and automatic startup until fixed-location operation is reliable.

## Implementation approach

Use **SwiftUI for the interface and a bundled pymobiledevice3 helper for device communication**. The project provides location set/clear functionality, including a DVT path for modern iOS. [Backend repository](https://github.com/doronz88/pymobiledevice3) and [location command recipes](https://github.com/doronz88/pymobiledevice3/blob/master/docs/guides/cli-recipes.md)

This is a proposed tradeoff: a Python runtime adds bundle size, but avoids implementing Apple's device protocols from scratch. Keep the UI native, run the helper only when needed, and measure package size, idle CPU, and active memory before calling the result lightweight. A fully Swift protocol implementation is a later optimization only if measurements justify its maintenance cost.

The helper should own discovery, the selected device connection, developer-service preparation, simulation, and cleanup. Communicate through structured messages over local pipes; do not construct shell commands from user input or expose a network control server. Keep session resources in the same helper process where the backend requires that.

Pin a tested backend release and its dependencies. Verify its license and bundled dependency notices before packaging. Treat the backend boundary as replaceable because iOS updates may change behavior. Avoid adding a privileged background service unless hardware testing shows a concrete requirement.

Pairing records are sensitive credentials: reuse the backend's supported storage, restrict any app-owned copies, and exclude pairing data and precise coordinates from routine logs. Store favorites locally. Initial support downloads should have visible progress and actionable failure messages.

## Next-stage sequence and acceptance criteria

1. **Record the environment.** Obtain iPhone model, exact iOS version/build, Mac model/architecture, and macOS version. Identify the apps whose location behavior matters. Set the initial support scope to this hardware rather than claiming universal iOS compatibility.
2. **Prove USB operation.** Pair and trust the phone, enable Developer Mode as needed, prepare developer support, set a clearly distinguishable coordinate, and observe it in Apple Maps and the intended app. Clear it and verify that real location resumes. Record whether Xcode, an Apple login, or administrator privileges were actually needed.
3. **Prove Wi-Fi independently.** Enable wireless connectivity while wired, remove the cable, rediscover the same device, establish a fresh session, then set, change, and clear the location. This must work from a fresh app/helper launch, not just an already-open USB session.
4. **Test lifecycle behavior.** Repeat with the phone locked, Wi-Fi interrupted, Mac sleep/wake, helper termination, and phone restart. Record persistence and recovery; never assume disconnection clears simulation. Check whether a cable is needed again after trust or OS changes.
5. **Build the minimal interface.** Implement onboarding, selected-device identity, coordinate validation, favorites, clear/reset, and errors based on the observed failures. Use explicit states: disconnected, needs trust, needs Developer Mode, preparing, ready, simulating, clearing, and unknown/error.
6. **Package and verify.** Bundle the helper so normal use does not require Homebrew or manual Python installation. Test launching without the development environment. Measure footprint and document the exact tested OS/backend combination.

The go/no-go gate is successful set/change/clear over USB and over a new Wi-Fi connection with no paid account or phone app. If only USB succeeds, report a wired prototype and the specific wireless blocker before changing the product scope.

## Open questions for the implementation stage

- What are your iPhone model and exact iOS version?
- What Mac and macOS version will run the app?
- Which apps need to observe the simulated location?
- Is “wireless while near the Mac on the same network” sufficient, or is operation away from the Mac essential?

These do not block this writeup. They determine the compatibility test and whether the proposed local-wireless design satisfies the intended use.
