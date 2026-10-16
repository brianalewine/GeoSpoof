import SwiftUI
import MapKit

/// Native sidebar material that keeps its look when the window is not key.
struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .withinWindow   // blurs the map behind the sidebar
        view.state = .active                // stays the same when the window isn't key
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Device badge as in Find My: a fixed-size translucent disc with a thin ring.
struct MapBadge: View {
    let image: NSImage
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let dark = colorScheme == .dark
        Image(nsImage: image).renderingMode(.original).resizable().scaledToFit()
            .frame(width: 28, height: 28).padding(7)
            .background(dark ? Color(white: 0.5, opacity: 0.45) : Color(white: 0.97, opacity: 0.6), in: Circle())
            .background(.thinMaterial, in: Circle())
            .overlay(Circle().stroke(dark ? Color(white: 0.7, opacity: 0.65) : .white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

/// Apple Maps-style current-location dot. The blue core breathes but never fills the white disc.
struct LocationDot: View {
    @State private var breathe = false
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.55, opacity: 0.55)).frame(width: 30, height: 30)
            Circle().fill(.white).frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            Circle().fill(Color(red: 0.04, green: 0.52, blue: 1.0)).frame(width: 24, height: 24)
                .scaleEffect(breathe ? 0.80 : 0.64)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

/// The Mac's marker: dot underneath, device badge on top (as in Find My, where the badge covers the dot).
/// Set dotOnTop to true to see the dot instead.
struct MacMarker: View {
    let icon: NSImage
    var dotOnTop = false
    var body: some View {
        ZStack {
            if dotOnTop { MapBadge(image: icon); LocationDot() }
            else { LocationDot(); MapBadge(image: icon) }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var location = LocationProvider()
    @FocusState private var searchFocused: Bool
    @State private var topHovered = false
    @State private var mapOptions = false
    @State private var satellite = false
    @State private var traffic = false
    @State private var is3D = false
    @State private var lastCamera: MapCamera?
    @State private var centeredInitially = false
    @State private var waitingToCenter = false
    @State private var mapHeight: CGFloat = 700
    private let sidebarWidth: CGFloat = 300

    private var macIcon: NSImage {
        NSImage(named: NSImage.computerName)
            ?? NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "This Mac")!
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $model.camera) {
                if let fix = location.location {
                    // The accuracy circle scales with zoom and gives way to the dot once it gets small.
                    if accuracyScreenRadius(fix) > 26 {
                        MapCircle(center: fix.coordinate, radius: min(fix.horizontalAccuracy, 500))
                            .foregroundStyle(.blue.opacity(0.12))
                            .stroke(.white.opacity(0.85), lineWidth: 3)
                    }
                    Annotation("This Mac", coordinate: fix.coordinate, anchor: .center) {
                        MacMarker(icon: macIcon)
                            .help("This Mac’s location")
                            .accessibilityLabel("This Mac’s current location")
                    }
                }
                if let coordinate = model.activeCoordinate, let phone = selectedPhone {
                    Annotation(phone.name, coordinate: coordinate, anchor: .center) {
                        MapBadge(image: DeviceArtwork.image(for: phone))
                            .help("Last simulated location sent to this iPhone")
                    }
                }
                if let place = model.selection, model.activePlaceID != place.id {
                    Marker(place.name, coordinate: place.coordinate).tint(.orange)
                }
            }
            .mapStyle(satellite ? .hybrid(elevation: .realistic, showsTraffic: traffic) : .standard(elevation: .realistic, showsTraffic: traffic))
            .mapControls { }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { mapHeight = $0 }
            .onMapCameraChange(frequency: .onEnd) { context in
                model.region = context.region
                lastCamera = context.camera
                is3D = context.camera.pitch > 10
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                model.pin(coordinate)
                searchFocused = false
                centeredInitially = true
            }
            .safeAreaInset(edge: .leading, spacing: 0) { sidebar.frame(width: sidebarWidth) }
            .overlay(alignment: .top) { topBar.padding(.leading, sidebarWidth) }
            .overlay(alignment: .bottomTrailing) { navigationControls.padding(.trailing, 18).padding(.bottom, 34) }
            .overlay(alignment: .bottomLeading) {
                if let place = model.selection {
                    placeCard(place).padding(.leading, sidebarWidth + 20).padding(.bottom, 34)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $model.showWelcome) {
            WelcomeView(showTroubleshooting: model.welcomeFromHelp) { model.dismissWelcome() }
                .interactiveDismissDisabled()
        }
        .task { location.start() }
        .onReceive(location.$location) { fix in
            guard let fix else { return }
            if waitingToCenter || (!centeredInitially && model.selection == nil) {
                center(on: fix.coordinate)
                centeredInitially = true
                waitingToCenter = false
            }
        }
        .onChange(of: model.query) { _, _ in model.queryChanged() }
        .background {
            Button("Search Places") { searchFocused = true }.keyboardShortcut("f").hidden().accessibilityHidden(true)
            // A shortcut works even when no view has keyboard focus (the map never does).
            Button("Dismiss Pin") { model.selection = nil; model.cancelSearch(); searchFocused = false }
                .keyboardShortcut(.escape, modifiers: []).hidden().accessibilityHidden(true)
        }
    }

    private func accuracyScreenRadius(_ fix: CLLocation) -> Double {
        let metersPerPoint = max(model.region.span.latitudeDelta * 111_320 / max(Double(mapHeight), 1), 0.01)
        return min(fix.horizontalAccuracy, 500) / metersPerPoint
    }

    private var selectedPhone: Phone? { model.phones.first { $0.id == model.selectedID } }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("GeoSpoof").font(.system(size: 25, weight: .bold))
                Spacer()
                Button { Task { await model.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 36, height: 36)
                        .glassEffect(.regular.interactive(), in: Circle())
                }.buttonStyle(.plain).disabled(model.busy)
                    .help("Refresh connected devices").accessibilityLabel("Refresh connected devices")
            }.padding(.horizontal, 16).padding(.top, 54).padding(.bottom, 18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("My Devices").font(.callout.weight(.bold)).foregroundStyle(.secondary)
                        .padding(.top, 18).padding(.bottom, 12)
                    if model.phones.isEmpty {
                        Label("Connect and trust your iPhone using USB to get started.", systemImage: "iphone")
                            .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                    ForEach(model.phones) { phone in
                        Button {
                            guard !model.busy, model.pendingID == nil else { return }
                            model.selectedID = phone.id
                            Task { await model.refresh() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: DeviceArtwork.image(for: phone)).renderingMode(.original).resizable().scaledToFit()
                                    .frame(width: 28, height: 28).padding(7)
                                    .background(.quaternary.opacity(0.65), in: Circle())
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(phone.name).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                                    Text(phone.id == model.selectedID ? connectionText : phone.model)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if phone.id == model.selectedID {
                                    Circle().fill(model.transport == nil ? .orange : .green).frame(width: 6, height: 6)
                                }
                            }.padding(.vertical, 12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .disabled(model.busy || (model.pendingID != nil && phone.id != model.selectedID))
                        Divider().padding(.leading, 52)
                    }
                    if model.pendingID != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(model.activeName == nil ? "Location status unknown" : "Location is set", systemImage: "location.fill")
                                .font(.callout.weight(.semibold))
                            if let name = model.activeName { Text(name).font(.caption).foregroundStyle(.secondary) }
                            Button(role: .destructive) { Task { await model.reset() } } label: {
                                Label("Stop Spoofing", systemImage: "stop.circle")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(model.busy ? Color.secondary : Color.red)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .glassEffect(.regular.interactive(), in: Capsule())
                            }.buttonStyle(.plain).disabled(model.busy)
                            Text("Restores your iPhone’s real location.").font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 18)
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose a Location").font(.headline)
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search places or addresses", text: $model.query)
                                .textFieldStyle(.plain).focused($searchFocused)
                                .onSubmit { Task { await model.searchNow() } }
                            if model.searching { ProgressView().controlSize(.mini) }
                            else if !model.query.isEmpty {
                                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                    .buttonStyle(.plain).accessibilityLabel("Clear search")
                            }
                        }.padding(11).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                        if model.results.isEmpty && model.searchMessage == nil {
                            Text("Search or click the map to choose a location.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.top, 22).padding(.bottom, 12)
                    ForEach(model.results) { place in
                        Button {
                            model.choose(place)
                            searchFocused = false
                            centeredInitially = true
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.name).font(.callout.weight(.medium)).foregroundStyle(.primary)
                                    Text(place.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }.padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                    if let message = model.searchMessage { Text(message).font(.caption).foregroundStyle(.secondary).padding(.vertical, 12) }
                    if let error = model.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("iPhone unavailable", systemImage: "exclamationmark.circle").font(.callout.weight(.medium)).foregroundStyle(.orange)
                            Text(error).font(.caption).textSelection(.enabled)
                            Button("Reconnect") { Task { await model.refresh() } }.disabled(model.busy)
                            Button("Open GeoSpoof Help") { model.showHelp() }
                        }.padding(.vertical, 18)
                    }
                    if let message = location.message {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("My Location", systemImage: "location").font(.callout.weight(.medium))
                            Text(message).font(.caption).foregroundStyle(.secondary)
                            Button("Location Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                            }
                        }.padding(.vertical, 18)
                    }
                }.padding(.horizontal, 16)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .background { SidebarBackground() }
        .overlay(alignment: .top) {
            // Slightly lighter header, as in Find My.
            ZStack {
                LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.08 : 0.30),
                                        .white.opacity(colorScheme == .dark ? 0.03 : 0.10), .clear],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.white.opacity(colorScheme == .dark ? 0.09 : 0.25), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 280)
            }
            .frame(height: 260).allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) { Rectangle().fill(.separator).frame(width: 0.5) }
    }

    private var connectionText: String {
        if model.busy { return "Updating…" }
        return model.transport.map { "\($0) · Connected" } ?? "No connection"
    }

    private var topBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Spacer()
                Button {
                    is3D.toggle()
                    adjustCamera(pitch: is3D ? 55 : 0)
                } label: {
                    Text(is3D ? "2D" : "3D").font(.callout.weight(.semibold)).frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: Circle())
                }.buttonStyle(.plain).help(is3D ? "Show 2D map" : "Show 3D map")
                HStack(spacing: 0) {
                    Button {
                        if let fix = location.location { center(on: fix.coordinate); centeredInitially = true }
                        else { waitingToCenter = true; location.start() }
                    } label: { Image(systemName: "location").font(.title3).frame(width: 43, height: 38) }
                        .buttonStyle(.plain).help("Show this Mac’s location").accessibilityLabel("My Location")
                    Button { mapOptions.toggle() } label: { Image(systemName: "map.fill").font(.title3).frame(width: 43, height: 38) }
                        .buttonStyle(.plain).help("Map options").accessibilityLabel("Map options")
                        .popover(isPresented: $mapOptions, arrowEdge: .bottom) { optionsPanel }
                }.padding(3).glassEffect(.regular, in: Capsule())
            }
        }
        .padding(.horizontal, 16).frame(height: 58)
        .background(alignment: .top) {
            ZStack(alignment: .bottom) {
                Rectangle().fill(.thinMaterial)
                Rectangle().fill(.white.opacity(colorScheme == .dark ? 0.12 : 0.30))
                Rectangle().fill(.white.opacity(colorScheme == .dark ? 0.16 : 0.40)).frame(height: 0.5)
            }
            .frame(height: 58)
            .opacity(topHovered || mapOptions ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: topHovered || mapOptions)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle()).onHover { topHovered = $0 }
    }

    private var optionsPanel: some View {
        VStack(spacing: 22) {
            Text("Map Modes").font(.headline)
            HStack(spacing: 14) {
                modeButton("Standard", satelliteMode: false)
                modeButton("Satellite", satelliteMode: true)
            }
            Toggle("Traffic", isOn: $traffic).toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
            Text("Map data © Apple and its providers").font(.caption2).foregroundStyle(.tertiary)
        }.padding(24).frame(width: 320)
    }

    private func modeButton(_ title: String, satelliteMode: Bool) -> some View {
        Button { satellite = satelliteMode } label: {
            VStack(spacing: 8) {
                MapModePreview(region: model.region, satellite: satelliteMode)
                    .frame(width: 144, height: 88).clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(satellite == satelliteMode ? Color.blue : .clear, lineWidth: 3))
                Text(title).font(.callout.weight(.medium))
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(satellite == satelliteMode ? .isSelected : [])
    }

    private var navigationControls: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(spacing: 0) {
                Button { zoom(0.5) } label: { Image(systemName: "plus").frame(width: 36, height: 35) }.accessibilityLabel("Zoom in")
                Divider().frame(width: 24)
                Button { zoom(2) } label: { Image(systemName: "minus").frame(width: 36, height: 35) }.accessibilityLabel("Zoom out")
            }.buttonStyle(.plain).padding(3).glassEffect(.regular, in: Capsule())
        }
    }

    private func placeCard(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mappin.circle.fill").font(.system(size: 30)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name).font(.headline)
                    Text(String(format: "%.5f, %.5f", place.coordinate.latitude, place.coordinate.longitude))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.selection = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Dismiss pin").accessibilityLabel("Dismiss pin")
            }
            Button { Task { await model.setLocation() } } label: {
                HStack {
                    if model.busy { ProgressView().controlSize(.small) }
                    Text(model.activePlaceID == place.id ? "Location Set" : "Set Location").fontWeight(.semibold)
                }.frame(maxWidth: .infinity).padding(.vertical, 3)
            }.buttonStyle(.glassProminent).tint(.blue).controlSize(.large)
                .disabled(!model.canSet || model.activePlaceID == place.id)
            Text(model.transport == nil ? "Connect your iPhone to set this location." : "Applies to \(model.phoneName).")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width: 290)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
    }

    private func moveCamera(_ camera: MapCamera) {
        withAnimation(.easeInOut(duration: 0.9)) { model.camera = .camera(camera) }
    }
    private func center(on coordinate: CLLocationCoordinate2D) {
        moveCamera(MapCamera(centerCoordinate: coordinate, distance: 1800, heading: 0, pitch: is3D ? 55 : 0))
    }
    private func adjustCamera(pitch: Double? = nil, heading: Double? = nil) {
        moveCamera(MapCamera(centerCoordinate: lastCamera?.centerCoordinate ?? model.region.center,
                             distance: lastCamera?.distance ?? 2000,
                             heading: heading ?? lastCamera?.heading ?? 0,
                             pitch: pitch ?? lastCamera?.pitch ?? 0))
    }
    private func zoom(_ factor: Double) {
        moveCamera(MapCamera(centerCoordinate: lastCamera?.centerCoordinate ?? model.region.center,
                             distance: min(40_000_000, max(80, (lastCamera?.distance ?? 2000) * factor)),
                             heading: lastCamera?.heading ?? 0, pitch: lastCamera?.pitch ?? 0))
    }
}
