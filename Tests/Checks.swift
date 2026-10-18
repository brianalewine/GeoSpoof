import Foundation
import MapKit

final class FakeDevice: DeviceControlling {
    var fails = false
    var clearedID: String?
    var setCount = 0
    func prepare() async throws {}
    func discover() async throws -> [Phone] { [Phone(id: "test-phone", name: "Test iPhone", model: "iPhone")] }
    func verify(_ id: String) async throws -> String { "Wi-Fi" }
    func set(_ id: String, latitude: Double, longitude: Double) async throws {
        setCount += 1
        if fails { throw DeviceError.message("Test connection loss") }
    }
    func clear(_ id: String) async throws {
        clearedID = id
        if fails { throw DeviceError.message("Test connection loss") }
    }
}

@main struct Checks {
    @MainActor static func main() async throws {
        let suite = "GeoSpoofTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = FakeDevice()
        let model = AppModel(service: fake, defaults: defaults)
        await model.refresh()
        precondition(model.selectedID == "test-phone" && model.transport == "Wi-Fi")
        model.pin(CLLocationCoordinate2D(latitude: 38.0544087, longitude: -78.499656))
        precondition(model.canSet && model.pendingID == nil) // Preview never sends.
        precondition(fake.setCount == 0)
        await model.setLocation()
        precondition(model.pendingID == "test-phone" && model.activeName == "Dropped Pin")
        precondition(fake.setCount == 1 && model.activeCoordinate != nil)
        let activeID = model.activePlaceID
        model.pin(CLLocationCoordinate2D(latitude: 38.0545, longitude: -78.4997))
        precondition(fake.setCount == 1 && model.selection?.id != activeID && model.activePlaceID == activeID)
        let restarted = AppModel(service: fake, defaults: defaults)
        precondition(restarted.pendingID == "test-phone" && restarted.activeName == nil)
        fake.fails = true
        let failedReset = await restarted.reset()
        precondition(!failedReset && defaults.string(forKey: "pendingPhone") == "test-phone")
        fake.fails = false
        restarted.selectedID = "different-phone"
        let reset = await restarted.reset()
        precondition(reset && fake.clearedID == "test-phone" && defaults.string(forKey: "pendingPhone") == nil)
        precondition(restarted.activeCoordinate == nil)
        fake.fails = true
        await model.setLocation()
        precondition(model.pendingID != nil && model.activeName == nil && model.transport == nil)
        print("PASS: preview isolation, persistence, failed reset, recovery device identity, uncertain set")

        // The Swift side of the Python helper protocol, against a stand-in helper (no phone needed).
        if ProcessInfo.processInfo.environment["GEOSPOOF_PYTHON"] != nil {
            let python = PythonDeviceService()
            try await python.prepare()
            let found = try await python.discover()
            precondition(found.count == 1 && found[0].id == "stub-phone" && found[0].productType == "iPhone14,2")
            let transport = try await python.verify("stub-phone")
            precondition(transport == "USB")
            try await python.set("stub-phone", latitude: 38.0544087, longitude: -78.499656)
            let active = await python.simulationActive("stub-phone")
            precondition(active == true)
            try await python.clear("stub-phone")
            let inactive = await python.simulationActive("stub-phone")
            precondition(inactive == false)
            do { try await python.set("bad", latitude: 1, longitude: 1); fatalError("Accepted a bad device") }
            catch { precondition(error.localizedDescription.contains("wasn't found")) }
            print("PASS: Python helper protocol (stand-in helper)")
        }

        if CommandLine.arguments.contains("--live") {
            // Use the real helper for live checks.
            if let real = ProcessInfo.processInfo.environment["GEOSPOOF_LIVE_HELPER"] { setenv("GEOSPOOF_HELPER", real, 1) }
            let service = PythonDeviceService()
            try await service.prepare()
            let devices = try await service.discover()
            print("Live discovery: \(devices.count) iPhone(s)")
            if let phone = devices.first { print("Live verification: \(try await service.verify(phone.id))") }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "Barracks Road Shopping Center Charlottesville"
            let response = try await MKLocalSearch(request: request).start()
            precondition(!response.mapItems.isEmpty)
            print("Live MapKit search: \(response.mapItems.count) result(s)")
        }
    }
}
