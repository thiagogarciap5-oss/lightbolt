import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation

extension DeviceActivityName {
    /// The non-repeating interval covering an earned session.
    static let focusSession = Self("lightBoltFocusSession")
}

/// Owns the real Apple Screen Time stack: Family Controls authorization, the
/// user's chosen apps/categories/sites, and the `ManagedSettings` shield that
/// actually blocks them at OS level.
///
/// Nothing here is simulated. `requestAuthorization()` triggers the genuine
/// system Screen Time prompt (Face ID / passcode confirmation included), and
/// shields are applied through `ManagedSettingsStore`, which iOS enforces
/// system-wide even when LightBolt is not running.
@Observable
final class ScreenTimeService {
    /// Where the user stands with Apple's permission prompt.
    enum Access: Equatable, Sendable {
        case notDetermined
        case approved
        case denied
        /// Screen Time cannot run here (Simulator, unsupported device, or the
        /// Family Controls entitlement is not in the signed profile yet).
        case unavailable(String)

        var isApproved: Bool { self == .approved }
    }

    private let store = ManagedSettingsStore(named: .lightBoltFocus)
    private let center = DeviceActivityCenter()

    private(set) var access: Access = .notDetermined
    private(set) var isRequesting = false

    /// The apps, categories and websites the user wants locked.
    private(set) var selection = FamilyActivitySelection()

    init() {
        selection = FocusBridge.loadSelection() ?? FamilyActivitySelection()
        refreshAccess()
    }

    // MARK: Derived state

    var blockedAppCount: Int { selection.applicationTokens.count }
    var blockedCategoryCount: Int { selection.categoryTokens.count }
    var blockedSiteCount: Int { selection.webDomainTokens.count }

    var totalBlockedCount: Int {
        blockedAppCount + blockedCategoryCount + blockedSiteCount
    }

    var hasSelection: Bool { totalBlockedCount > 0 }

    var selectionSummary: String {
        guard hasSelection else { return "No apps chosen yet" }
        var parts: [String] = []
        if blockedAppCount > 0 { parts.append("\(blockedAppCount) app\(blockedAppCount == 1 ? "" : "s")") }
        if blockedCategoryCount > 0 { parts.append("\(blockedCategoryCount) categor\(blockedCategoryCount == 1 ? "y" : "ies")") }
        if blockedSiteCount > 0 { parts.append("\(blockedSiteCount) site\(blockedSiteCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    // MARK: Authorization

    /// Re-reads Apple's authorization status (it can change in Settings).
    func refreshAccess() {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved:
            access = .approved
        case .denied:
            access = .denied
        case .notDetermined:
            if case .unavailable = access { return }
            access = .notDetermined
        @unknown default:
            access = .notDetermined
        }
    }

    /// Presents Apple's real Screen Time permission sheet. This is the system
    /// prompt — it cannot be styled, faked or bypassed.
    func requestAuthorization() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }

        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            access = .approved
        } catch {
            access = Self.classify(error)
        }
    }

    private static func classify(_ error: Error) -> Access {
        if AuthorizationCenter.shared.authorizationStatus == .approved { return .approved }
        if AuthorizationCenter.shared.authorizationStatus == .denied {
            return .denied
        }
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("cancel") { return .notDetermined }
        return .unavailable(
            "Screen Time isn't available on this build. It needs a real iPhone or iPad signed with the Family Controls capability."
        )
    }

    // MARK: Selection

    func update(selection newValue: FamilyActivitySelection, isLocking: Bool) {
        selection = newValue
        FocusBridge.save(selection: newValue)
        if isLocking { applyShield() }
    }

    // MARK: Shield control

    /// Blocks every chosen app, category and website right now.
    func applyShield() {
        guard access.isApproved else { return }
        FocusBridge.applyShield(to: store)
        center.stopMonitoring([.focusSession])
    }

    /// Lifts the shield until `expiry` and asks the system to put it back at
    /// that exact moment via the `FocusMonitor` extension — so the block
    /// returns even if LightBolt is force-quit in the meantime.
    func liftShield(until expiry: Date) {
        guard access.isApproved else { return }
        FocusBridge.clearShield(on: store)
        scheduleRelock(at: expiry)
    }

    /// Removes every restriction (Focus Lock switched off).
    func releaseEverything() {
        FocusBridge.clearShield(on: store)
        center.stopMonitoring([.focusSession])
    }

    private func scheduleRelock(at expiry: Date) {
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.hour, .minute, .second]
        // DeviceActivity requires intervals of at least 15 minutes — every
        // reward tier (15/30/60) satisfies that by design.
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: .now.addingTimeInterval(1)),
            intervalEnd: calendar.dateComponents(components, from: expiry),
            repeats: false
        )
        center.stopMonitoring([.focusSession])
        do {
            try center.startMonitoring(.focusSession, during: schedule)
        } catch {
            // Monitoring failed (rare). The in-app foreground check below is
            // the backstop: the shield reapplies the moment LightBolt runs.
            print("[ScreenTime] relock scheduling failed")
        }
    }
}
