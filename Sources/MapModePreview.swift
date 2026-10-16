import SwiftUI
import MapKit

/// A bitmap keeps the map-mode tile a single clickable button.
struct MapModePreview: View {
    let region: MKCoordinateRegion
    let satellite: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var preview: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let preview {
                Image(nsImage: preview).resizable().scaledToFill()
            } else {
                Image(systemName: satellite ? "globe.americas.fill" : "map.fill")
                    .font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: colorScheme) {
            let options = MKMapSnapshotter.Options()
            options.region = region
            options.size = CGSize(width: 288, height: 176)
            options.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            options.preferredConfiguration = satellite ? MKImageryMapConfiguration() : MKStandardMapConfiguration()
            let snapshotter = MKMapSnapshotter(options: options)
            do {
                let snapshot = try await withTaskCancellationHandler {
                    try await snapshotter.start()
                } onCancel: {
                    snapshotter.cancel()
                }
                guard !Task.isCancelled else { return }
                preview = snapshot.image
            } catch { /* The accessible tile remains usable if map imagery is unavailable. */ }
        }
    }
}
