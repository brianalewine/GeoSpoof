import AppKit

enum DeviceArtwork {
    private static let root = URL(fileURLWithPath: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/MobileDevices.bundle/Contents")
    private static let declarations: [[String: Any]] = {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [] }
        return plist["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []
    }()
    private static var cache: [String: NSImage] = [:]

    /// "iPhone 13 Pro" for productType "iPhone14,2", read from macOS's own device list.
    static func displayName(for phone: Phone) -> String {
        guard !phone.productType.isEmpty else { return phone.model }
        let match = declarations.first { entry in
            let tags = entry["UTTypeTagSpecification"] as? [String: Any] ?? [:]
            return (tags["com.apple.device-model-code"] as? [String] ?? []).contains(phone.productType)
        }
        return match?["UTTypeDescription"] as? String ?? phone.model
    }

    static func image(for phone: Phone) -> NSImage {
        let key = phone.productType.isEmpty ? phone.model : phone.productType
        if let image = cache[key] { return image }
        let match = declarations.first { entry in
            let tags = entry["UTTypeTagSpecification"] as? [String: Any] ?? [:]
            let codes = tags["com.apple.device-model-code"] as? [String] ?? []
            return (!phone.productType.isEmpty && codes.contains(phone.productType)) || entry["UTTypeDescription"] as? String == phone.model
        }
        let file = match?["UTTypeIconFile"] as? String ?? "com.apple.iphone.icns"
        let image = NSImage(contentsOf: root.appendingPathComponent("Resources").appendingPathComponent(file))
            ?? NSImage(systemSymbolName: "iphone", accessibilityDescription: phone.model)!
        cache[key] = image
        return image
    }
}
