import FamilyControls
import Foundation
import ManagedSettings

/// Shared contract between LightBolt and its Screen Time extensions.
/// Duplicated verbatim in the app and in each extension target because
/// extensions are separate processes with their own module.
enum FocusBridge {
    static let appGroup = "group.nectar.app.60v7ufjd0cnhxmxzlcg60"

    enum Key {
        static let selection = "fit.focus.selection.v1"
        static let expiry = "fit.focus.expiry.v1"
        static let enabled = "fit.focus.enabled.v1"
        static let earnedMinutes = "fit.focus.earnedMinutes.v1"
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static var isEnabled: Bool {
        defaults.bool(forKey: Key.enabled)
    }

    static var unlockExpiry: Date? {
        let stamp = defaults.double(forKey: Key.expiry)
        guard stamp > 0 else { return nil }
        return Date(timeIntervalSince1970: stamp)
    }

    static var isUnlocked: Bool {
        guard let unlockExpiry else { return false }
        return unlockExpiry > .now
    }

    static func loadSelection() -> FamilyActivitySelection? {
        guard let data = defaults.data(forKey: Key.selection) else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
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
    static let lightBoltFocus = Self("lightBoltFocus")
}
