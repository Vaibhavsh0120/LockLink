import Foundation
import Security

struct GateWidgetConfiguration: Codable, Equatable {
    let address: String
    let signingKey: String

    func validate() throws {
        guard let url = URLComponents(string: address), url.scheme == "http",
              let host = url.host?.lowercased(), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty else {
            throw GateWidgetError.message("Check the device address in LockLink.")
        }
        let segments = host.split(separator: ".", omittingEmptySubsequences: false)
        let parts = segments.compactMap { Int($0) }
        let ipv4 = segments.count == 4 && parts.count == 4 && parts.allSatisfy { (0...255).contains($0) }
        let local = host == "localhost" || host.hasSuffix(".local") || (ipv4 &&
            (parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) ||
             (parts[0] == 172 && (16...31).contains(parts[1]))))
        guard local, signingKey.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
            throw GateWidgetError.message("Check the pairing key in LockLink.")
        }
    }
}

enum GateWidgetError: Error {
    case message(String)
    var text: String {
        switch self { case .message(let text): return text }
    }
}

enum GateWidgetStore {
    static let group = "group.com.locklink.locklink"
    static let kind = "LockLinkGate"
    static var defaults: UserDefaults? { UserDefaults(suiteName: group) }
    private static var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.locklink.widgets",
        kSecAttrAccount as String: "activeGate",
        kSecAttrAccessGroup as String: group
    ] }

    static func save(_ config: GateWidgetConfiguration) throws {
        try config.validate()
        let changed = (try? load()) != config
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil else {
            throw GateWidgetError.message("Enable the shared App Group for LockLink and its widget.")
        }
        let data = try JSONEncoder().encode(config)
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            let addStatus = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw GateWidgetError.message("Could not share widget settings.") }
        } else if status != errSecSuccess {
            throw GateWidgetError.message("Could not share widget settings.")
        }
        defaults?.set(true, forKey: "configured")
        if changed {
            defaults?.removeObject(forKey: "result")
            defaults?.removeObject(forKey: "resultDate")
        }
    }

    static func load() throws -> GateWidgetConfiguration {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw GateWidgetError.message(status == errSecInteractionNotAllowed
                ? "Unlock your iPhone, then try again." : "Open LockLink to set up widgets.")
        }
        let config = try JSONDecoder().decode(GateWidgetConfiguration.self, from: data)
        try config.validate()
        return config
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
        defaults?.set(false, forKey: "configured")
        setResult("Open LockLink to set up widgets.")
    }

    static func setResult(_ message: String) {
        defaults?.set(message, forKey: "result")
        defaults?.set(Date().timeIntervalSince1970, forKey: "resultDate")
    }
}
