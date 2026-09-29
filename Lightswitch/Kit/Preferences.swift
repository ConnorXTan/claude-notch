import Foundation

/// Every user setting, as a key with a default. Views bind with
/// `@AppStorage(Preferences.someKey)`; non-view code reads the static
/// accessors, so the two can never disagree about a default.
public enum Preferences {
    public static let showOnAllDisplaysKey = "showOnAllDisplays"
    public static let openOnHoverKey = "openOnHover"
    public static let alertSoundKey = "alertSound"

    public static var defaults: [String: Any] {
        [
            showOnAllDisplaysKey: true,
            openOnHoverKey: true,
            alertSoundKey: true,
        ]
    }

    /// Call once at launch so `UserDefaults` answers with these defaults
    /// before any setting has been touched.
    public static func register(in store: UserDefaults = .standard) {
        store.register(defaults: defaults)
    }

    public static var showOnAllDisplays: Bool { UserDefaults.standard.bool(forKey: showOnAllDisplaysKey) }
    public static var openOnHover: Bool { UserDefaults.standard.bool(forKey: openOnHoverKey) }
    public static var alertSound: Bool { UserDefaults.standard.bool(forKey: alertSoundKey) }
}
