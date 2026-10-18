import SwiftUI

struct WelcomeView: View {
    let showTroubleshooting: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 84, height: 84)
            Text(showTroubleshooting ? "GeoSpoof Help" : "Welcome to GeoSpoof")
                .font(.system(size: 28, weight: .bold))
            VStack(alignment: .leading, spacing: 18) {
                row("cable.connector", "Connect your iPhone",
                    "Plug it in with USB, unlock it, and tap Trust. Refresh in GeoSpoof once over USB to enable Wi-Fi connections. Then unplug it and refresh on the same Wi-Fi.")
                row("hammer", "Turn on Developer Mode",
                    "On the iPhone: Settings → Privacy & Security → Developer Mode. It will restart once.")
                row("mappin.and.ellipse", "Choose a place",
                    "Search in the sidebar and press Return, or click anywhere on the map.")
                row("location.fill", "Press Set Location",
                    "Choosing a pin never changes your phone. Use Stop Spoofing to restore your real location.")
            }
            if showTroubleshooting {
                VStack(alignment: .leading, spacing: 8) {
                    Label("iPhone not connecting?", systemImage: "exclamationmark.triangle").font(.headline)
                    Text("""
                    1. Restart the iPhone.
                    2. Reconnect it by USB, unlock it, and tap Trust when asked.
                    3. In GeoSpoof, press ⇧⌘R to refresh.
                    """).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            }
            Button(action: onContinue) { Text("Continue").fontWeight(.semibold).frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent).tint(.blue).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(36).frame(width: 460)
    }

    private func row(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.blue).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
