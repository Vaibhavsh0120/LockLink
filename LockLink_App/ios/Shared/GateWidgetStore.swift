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
    case appGroupUnavailable
    case extensionUnavailable
    case keychain(OSStatus)

    var code: String {
        switch self {
        case .message: return "widget_settings"
        case .appGroupUnavailable: return "widget_app_group"
        case .extensionUnavailable: return "widget_extension_missing"
        case .keychain(let status):
            switch status {
            case errSecMissingEntitlement: return "widget_keychain_access"
            case errSecInteractionNotAllowed: return "widget_locked"
            default: return "widget_storage"
            }
        }
    }

    var text: String {
        switch self {
        case .message(let text): return text
        case .appGroupUnavailable:
            return "This installation cannot access the shared widget App Group."
        case .extensionUnavailable:
            return "The LockLink widget extension is missing from this installation."
        case .keychain(let status):
            switch status {
            case errSecMissingEntitlement:
                return "This installation cannot access the shared widget keychain."
            case errSecInteractionNotAllowed:
                return "Unlock your iPhone, then try again."
            default: return "Could not save the widget settings."
            }
        }
    }
}

enum GateWidgetStore {
    private static let originalGroup = "group.com.locklink.locklink"
    // Both targets compile this file and resolve their own installed bundle.
    // AltStore appends a signing-team suffix to App Groups during installation.
    static let group: String = {
        let bundle = Bundle.main
        let metadata = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        let profile = bundle.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }
        return resolveGroup(metadataGroups: metadata, profileData: profile) {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        } ?? originalGroup
    }()

    static func resolveGroup(metadataGroups: [String], profileData: Data?,
                             isAccessible: (String) -> Bool) -> String? {
        if isAccessible(originalGroup) { return originalGroup }
        let candidates = Set(metadataGroups + profileGroups(profileData)).filter { candidate in
            // Never select another app's group, nor invent a group from a bundle ID.
            candidate.hasPrefix(originalGroup + ".") &&
                candidate.count > originalGroup.count + 1 && isAccessible(candidate)
        }
        // Refuse an ambiguous destination for the gate credential.
        return candidates.count == 1 ? candidates.first : nil
    }

    private static func profileGroups(_ data: Data?) -> [String] {
        // Provisioning metadata discovers candidates, not authority. iOS must
        // grant container access and Keychain enforces its own entitlement check.
        guard let data = data,
              let start = data.range(of: Data("<plist".utf8)),
              let end = data.range(of: Data("</plist>".utf8),
                                   in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                from: data.subdata(in: start.lowerBound..<end.upperBound),
                options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }

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
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil else {
            throw GateWidgetError.appGroupUnavailable
        }
        let changed = (try? load()) != config
        let data = try JSONEncoder().encode(config)
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            let addStatus = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw GateWidgetError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw GateWidgetError.keychain(status)
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
