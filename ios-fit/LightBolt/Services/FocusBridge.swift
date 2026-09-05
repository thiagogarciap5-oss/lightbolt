import FamilyControls
import Foundation
import ManagedSettings

/// Shared contract between LightBolt and its two Screen Time extensions
/// (`FocusMonitor`, `FocusShield`). Duplicated verbatim in each extension
/// target — extensions are separate processes with their own modules, so the
/// only thing they can share is the App Group container.
nonisolated enum FocusBridge {
    static let appGroup = "group.nectar.app.60v7ufjd0cnhxmxzlcg60"

    enum Key {
        static let selection = "fit.focus.selection.v1"
        static let expiry = "fit.focus.expiry.v1"
        static let enabled = "fit.focus.enabled.v1"
        static let earnedMinutes = "fit.focus.earnedMinutes.v1"
    }

    /// App Group defaults, falling back to standard defaults if the group is
    /// unavailable (e.g. entitlement not yet provisioned on a dev build).
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    static var unlockExpiry: Date? {
        get {
            let stamp = defaults.double(forKey: Key.expiry)
            return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.expiry) }
    }

    static var earnedMinutes: Int {
        get { defaults.integer(forKey: Key.earnedMinutes) }
        set { defaults.set(newValue, forKey: Key.earnedMinutes) }
    }

    static func loadSelection() -> FamilyActivitySelection? {
        guard let data = defaults.data(forKey: Key.selection) else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    static func save(selection: FamilyActivitySelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: Key.selection)
    }

    static func applyShield(to store: ManagedSettingsStore) {
        guard isEnabled, let selection = loadSelection() else {
            clearShield(on: store)
            return
        }
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
    }

    static func clearShield(on store: ManagedSettingsStore) {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
    }
}

extension ManagedSettingsStore.Name {
    /// Dedicated store so LightBolt never clobbers other Screen Time settings.
    static let lightBoltFocus = Self("lightBoltFocus")
}
