import Foundation

struct Phone: Identifiable, Equatable {
    let id: String
    let name: String
    let model: String
    var productType: String = ""
}

enum DeviceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

protocol DeviceControlling {
    func run(_ arguments: [String], json: Bool) async throws -> Data
    func discover() async throws -> [Phone]
    func verify(_ id: String) async throws -> String
    func set(_ id: String, latitude: Double, longitude: Double) async throws
    func clear(_ id: String) async throws
}

struct DeviceService: DeviceControlling {
    // Run off the main thread. Files avoid pipe-buffer deadlocks on verbose errors.
    func run(_ arguments: [String], json: Bool = true) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let output = directory.appendingPathComponent("result.json")
                    let log = directory.appendingPathComponent("output.txt")
                    FileManager.default.createFile(atPath: log.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: log)
                    defer { try? handle.close() }
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                    process.arguments = ["devicectl"] + arguments + (json ? ["--timeout", "20", "--json-output", output.path] : [])
                    process.standardOutput = handle
                    process.standardError = handle
                    try process.run()
                    let deadline = Date().addingTimeInterval(25)
                    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                    if process.isRunning {
                        process.terminate()
                        throw DeviceError.message("The iPhone did not respond. Unlock it, check Wi-Fi or connect USB, then try again.")
                    }
                    let logData = (try? Data(contentsOf: log)) ?? Data()
                    guard process.terminationStatus == 0 else {
                        let raw = String(decoding: logData, as: UTF8.self)
                        throw DeviceError.message(String(raw.suffix(1600)).trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    continuation.resume(returning: json ? try Data(contentsOf: output) : logData)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    static func result(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else {
            throw DeviceError.message("The device tool returned an unreadable response. Check the selected Xcode installation.")
        }
        return result
    }

    static func phones(from data: Data) throws -> [Phone] {
        let rows = try result(data)["devices"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        return rows.compactMap { row in
            let properties = row["properties"] as? [String: Any] ?? [:]
            let hardware = properties["hardware"] as? [String: Any] ?? row["hardwareProperties"] as? [String: Any] ?? [:]
            let state = properties["state"] as? [String: Any] ?? row["deviceProperties"] as? [String: Any] ?? [:]
            guard hardware["deviceType"] as? String == "iPhone",
                  let id = hardware["udid"] as? String ?? row["identifier"] as? String,
                  seen.insert(id).inserted else { return nil }
            return Phone(id: id, name: state["name"] as? String ?? "iPhone", model: hardware["marketingName"] as? String ?? "iPhone", productType: hardware["productType"] as? String ?? "")
        }
    }

    func discover() async throws -> [Phone] {
        try await Self.phones(from: run(["list", "devices"]))
    }

    func verify(_ id: String) async throws -> String {
        let result = try await Self.result(run(["device", "info", "details", "--device", id]))
        let properties = result["properties"] as? [String: Any] ?? [:]
        let connection = properties["connection"] as? [String: Any] ?? result["connectionProperties"] as? [String: Any] ?? [:]
        let state = connection["state"] as? String ?? connection["tunnelState"] as? String
        if let state, state != "connected" {
            throw DeviceError.message("The iPhone is paired but not connected. Unlock it and check Wi-Fi, or connect USB.")
        }
        let transport = connection["transportType"] as? String ?? ""
        return transport == "wired" ? "USB" : transport == "localNetwork" ? "Wi-Fi" : "Connected"
    }

    static func coordinateArguments(id: String, latitude: Double, longitude: Double) throws -> [String] {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw DeviceError.message("Choose a valid location on the map.")
        }
        return ["device", "simulate", "location", "coordinate", "--device", id,
                "--latitude", String(latitude), "--longitude=\(longitude)"]
    }

    func set(_ id: String, latitude: Double, longitude: Double) async throws {
        _ = try await run(Self.coordinateArguments(id: id, latitude: latitude, longitude: longitude))
    }

    func clear(_ id: String) async throws {
        _ = try await run(["device", "simulate", "location", "clear", "--device", id])
    }
}
