import Foundation
import MapKit

final class FakeDevice: DeviceControlling {
    var fails = false
    var clearedID: String?
    var setCount = 0
    func run(_ arguments: [String], json: Bool) async throws -> Data { Data("--latitude".utf8) }
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
        let fixture = Data("""
        {"result":{"devices":[
        {"identifier":"core-id","properties":{"hardware":{"deviceType":"iPhone","udid":"phone","marketingName":"iPhone 13 Pro","productType":"iPhone14,2"},"state":{"name":"Phone"}}},
        {"identifier":"duplicate","hardwareProperties":{"deviceType":"iPhone","udid":"phone"},"deviceProperties":{"name":"Duplicate"}},
        {"identifier":"tablet","hardwareProperties":{"deviceType":"iPad"}}
        ]}}
        """.utf8)
        let phones = try DeviceService.phones(from: fixture)
        precondition(phones.count == 1 && phones[0].id == "phone")
        precondition(phones[0].productType == "iPhone14,2")
        for latitude in [Double.nan, .infinity, 91, -91] {
            do { _ = try DeviceService.coordinateArguments(id: "a", latitude: latitude, longitude: 0); fatalError("Accepted invalid latitude") }
            catch { }
        }
        do { _ = try DeviceService.coordinateArguments(id: "a", latitude: 0, longitude: 181); fatalError("Accepted invalid longitude") } catch { }
        let args = try DeviceService.coordinateArguments(id: "name with spaces;literal", latitude: 38, longitude: -78)
        precondition(args.contains("name with spaces;literal") && args.last == "--longitude=-78.0")
        do { _ = try DeviceService.result(Data("{}".utf8)); fatalError("Accepted invalid schema") } catch { }

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
        print("PASS: decoding, deduplication, coordinate validation, preview isolation, persistence, failed reset, recovery device identity, uncertain set")

        if CommandLine.arguments.contains("--live") {
            let service = DeviceService()
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
