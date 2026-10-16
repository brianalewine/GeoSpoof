import SwiftUI
import MapKit

struct Place: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var phones: [Phone] = []
    @Published var selectedID: String
    @Published var transport: String?
    @Published var busy = false
    @Published var searching = false
    @Published var query = ""
    @Published var results: [Place] = []
    @Published var searchMessage: String?
    @Published var selection: Place?
    @Published var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 38.052, longitude: -78.501),
        span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)))
    @Published var error: String?
    @Published var notice: String?
    @Published var pendingID: String?
    @Published var activeName: String?
    @Published var activePlaceID: UUID?
    @Published var activeCoordinate: CLLocationCoordinate2D?
    @Published var showWelcome = false
    @Published var welcomeFromHelp = false
    static let welcomeVersion = "0.5"   // bump to show the welcome screen again after an update
    var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 38.052, longitude: -78.501), span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
    let service: any DeviceControlling
    private let defaults: UserDefaults
    init(service: any DeviceControlling = DeviceService(), defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        selectedID = defaults.string(forKey: "selectedPhone") ?? ""
        pendingID = defaults.string(forKey: "pendingPhone")
    }
    func presentWelcomeIfNeeded() {
        if defaults.string(forKey: "welcomeSeen") != Self.welcomeVersion {
            welcomeFromHelp = false
            showWelcome = true
        }
    }
    func showHelp() { welcomeFromHelp = true; showWelcome = true }
    func dismissWelcome() {
        defaults.set(Self.welcomeVersion, forKey: "welcomeSeen")
        showWelcome = false
    }

    private var search: MKLocalSearch?
    private var searchGeneration = UUID()
    private var debounce: Task<Void, Never>?
    private var supported = false
    var quitting = false   // set while the app is quitting so no new background refresh starts
    var phoneName: String { phones.first { $0.id == selectedID }?.name ?? "Connect iPhone" }
    var canSet: Bool { selection != nil && transport != nil && !busy && (pendingID == nil || pendingID == selectedID) }

    func refresh() async {
        guard !busy, !quitting else { return }
        busy = true
        defer { busy = false }
        error = nil
        transport = nil
        do {
            if !supported {
                let help = try await service.run(["device", "simulate", "location", "coordinate", "--help"], json: false)
                guard String(decoding: help, as: UTF8.self).contains("--latitude") else {
                    throw DeviceError.message("Install and select Xcode 27 or later to control your iPhone's location.")
                }
                supported = true
            }
            phones = try await service.discover()
            if selectedID.isEmpty { selectedID = pendingID ?? (phones.count == 1 ? phones[0].id : "") }
            guard !selectedID.isEmpty else { notice = "Connect and trust your iPhone using USB to get started."; return }
            guard phones.contains(where: { $0.id == selectedID }) else {
                throw DeviceError.message("Your selected iPhone is unavailable. Keep it on the same Wi-Fi or connect it by USB.")
            }
            transport = try await service.verify(selectedID)
            defaults.set(selectedID, forKey: "selectedPhone")
            notice = nil
        } catch {
            if pendingID != nil { activeName = nil; activePlaceID = nil }
            self.error = error.localizedDescription
        }
    }

    func choose(_ place: Place) {
        selection = place
        results = []
        searchMessage = nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            camera = .region(MKCoordinateRegion(center: place.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))
        }
    }

    func pin(_ coordinate: CLLocationCoordinate2D) {
        selection = Place(name: "Dropped Pin", subtitle: "Custom location", coordinate: coordinate)
        results = []
        searchMessage = nil
    }

    func cancelSearch() {
        searchGeneration = UUID()
        search?.cancel()
        searching = false
        results = []
        searchMessage = nil
    }

    /// Called on every keystroke: waits for a short pause, then searches. Old results stay until new ones arrive.
    func queryChanged() {
        debounce?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { cancelSearch(); return }
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await searchPlaces()
        }
    }

    /// Return key: search immediately.
    func searchNow() async {
        debounce?.cancel()
        await searchPlaces()
    }

    func searchPlaces() async {
        search?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { cancelSearch(); return }
        let generation = UUID()
        searchGeneration = generation
        searching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = region
        let operation = MKLocalSearch(request: request)
        search = operation
        do {
            let response = try await operation.start()
            guard generation == searchGeneration else { return }
            results = response.mapItems.prefix(7).map {
                Place(name: $0.name ?? "Place", subtitle: $0.address?.fullAddress ?? "", coordinate: $0.location.coordinate)
            }
            searchMessage = results.isEmpty ? "No places found. Try a city or street address." : nil
        } catch {
            guard generation == searchGeneration else { return }
            searchMessage = "Search is unavailable. Check your internet connection or drop a pin on the map."
        }
        if generation == searchGeneration { searching = false }
    }

    func setLocation() async {
        guard canSet, let place = selection else { return }
        let id = selectedID
        busy = true
        error = nil
        // Write before sending: a timeout can happen after the phone applies the command.
        pendingID = id
        defaults.set(id, forKey: "pendingPhone")
        defer { busy = false }
        do {
            try await service.set(id, latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            activeName = place.name
            activePlaceID = place.id
            activeCoordinate = place.coordinate
            selection = nil   // close the pin card; the phone badge now marks the location
            notice = "Location set on your iPhone"
        } catch {
            activeName = nil
            activePlaceID = nil
            activeCoordinate = nil
            transport = nil
            self.error = "Location state is unknown. Reconnect and reset.\n\(error.localizedDescription)"
        }
    }

    @discardableResult func reset() async -> Bool {
        guard !busy else { return false }
        let id = pendingID ?? selectedID
        guard !id.isEmpty else { return false }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await service.clear(id)
            pendingID = nil
            activeName = nil
            activePlaceID = nil
            activeCoordinate = nil
            defaults.removeObject(forKey: "pendingPhone")
            notice = "Real location restored"
            return true
        } catch {
            self.error = "Couldn't reset the iPhone. Reconnect it and try Reset again.\n\(error.localizedDescription)"
            return false
        }
    }
}
