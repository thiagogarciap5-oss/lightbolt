import DeviceActivity
import Foundation
import ManagedSettings

/// Runs outside LightBolt. When an earned session's interval ends, this
/// re-applies the shield immediately — so the block returns even if LightBolt
/// was force-quit or the phone stayed locked the whole time.
final class FocusMonitorExtension: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: .lightBoltFocus)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // The reward window opened; LightBolt already lifted the shield.
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        FocusBridge.applyShield(to: store)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        FocusBridge.applyShield(to: store)
    }
}
