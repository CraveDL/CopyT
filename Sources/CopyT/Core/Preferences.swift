import Foundation

/// 用户设置（UserDefaults），SwiftUI 中通过 @AppStorage 使用相同的 key
enum Preferences {
    enum Key {
        static let storagePath = "storagePath"
        static let retentionDays = "retentionDays"
        static let maxImageMB = "maxImageMB"
        static let ignoredApps = "ignoredApps"
        static let hotKeyEnabled = "hotKeyEnabled"
        static let paused = "paused"
    }

    static let defaultIgnoredApps = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
    ].joined(separator: "\n")

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.retentionDays: 0,          // 0 = 永久保存
            Key.maxImageMB: 20,
            Key.ignoredApps: defaultIgnoredApps,
            Key.hotKeyEnabled: true,
            Key.paused: false,
        ])
    }

    static var defaultStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CopyT", isDirectory: true)
    }

    static var storageURL: URL {
        get {
            if let p = defaults.string(forKey: Key.storagePath), !p.isEmpty {
                return URL(fileURLWithPath: p, isDirectory: true)
            }
            return defaultStorageURL
        }
        set { defaults.set(newValue.path, forKey: Key.storagePath) }
    }

    static var retentionDays: Int { defaults.integer(forKey: Key.retentionDays) }
    static var maxImageBytes: Int { max(1, defaults.integer(forKey: Key.maxImageMB)) * 1024 * 1024 }
    static var hotKeyEnabled: Bool { defaults.bool(forKey: Key.hotKeyEnabled) }
    static var paused: Bool { defaults.bool(forKey: Key.paused) }

    static var ignoredBundleIDs: Set<String> {
        parseBundleIDs(defaults.string(forKey: Key.ignoredApps) ?? "")
    }

    /// 解析忽略列表：每行或逗号分隔一个 Bundle ID
    static func parseBundleIDs(_ raw: String) -> Set<String> {
        Set(raw.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }
}
