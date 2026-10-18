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
    /// Checks that the backend can run at all (tool installed, helper reachable).
    func prepare() async throws
    func discover() async throws -> [Phone]
    func verify(_ id: String) async throws -> String
    func set(_ id: String, latitude: Double, longitude: Double) async throws
    func clear(_ id: String) async throws
    /// Whether a simulated location is still in effect; nil when the backend cannot tell.
    func simulationActive(_ id: String) async -> Bool?
}

extension DeviceControlling {
    func simulationActive(_ id: String) async -> Bool? { nil }
}
