import Foundation
import Observation

// MARK: - Task model

nonisolated enum FocusDifficulty: String, Codable, CaseIterable, Sendable, Identifiable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"

    var id: String { rawValue }

    /// Strict reward contract: Easy 15 / Medium 30 / Hard 60 minutes.
    var unlockMinutes: Int {
        switch self {
        case .easy: 15
        case .medium: 30
        case .hard: 60
        }
    }

    var blurb: String {
        switch self {
        case .easy: "Quick win"
        case .medium: "Real effort"
        case .hard: "Earn it properly"
        }
    }

    var weight: Int {
        switch self {
        case .easy: 1
        case .medium: 2
        case .hard: 3
        }
    }
}

nonisolated struct FocusTask: Codable, Equatable, Sendable {
    let taskDescription: String
    let difficulty: FocusDifficulty
    let unlockMinutes: Int
    /// Position in the 10,000-strong vault for this tier — shown on the card
    /// so the user can see the catalogue is real, not improvised.
    let vaultIndex: Int

    init(taskDescription: String, difficulty: FocusDifficulty, vaultIndex: Int) {
        self.taskDescription = taskDescription
        self.difficulty = difficulty
        // The reward always derives from the tier — never from arbitrary input.
        self.unlockMinutes = difficulty.unlockMinutes
        self.vaultIndex = vaultIndex
    }
}

// MARK: - Session manager

/// Focus Lock blocks the *other* apps on the device — games, social, whatever
/// the user picks — using Apple's Screen Time stack. LightBolt itself always
/// stays open; it is the place you come to earn your way back in.
///
/// The reward window is a wall-clock timestamp stored in the App Group, so
/// force-quitting, rebooting or reinstalling never extends a session. The
/// `FocusMonitor` extension re-applies the shield the instant the window ends.
@Observable
final class FocusLock {
    /// Tasks per tier in the offline vault.
    static let vaultSize = FocusTaskVault.perDifficulty

    private let defaults: UserDefaults
    private var ticker: Task<Void, Never>?

    let screenTime: ScreenTimeService

    /// Wall-clock heartbeat driving countdown UI and the auto-relock.
    private(set) var now: Date = .now

    private(set) var isEnabled: Bool {
        didSet { FocusBridge.isEnabled = isEnabled }
    }

    /// Absolute end of the earned session. Persisted as epoch seconds in the
    /// App Group so both extensions can read it.
    private(set) var unlockExpiry: Date? {
        didSet { FocusBridge.unlockExpiry = unlockExpiry }
    }

    /// The task currently on offer. Persisted so a relaunch presents the same
    /// task instead of letting the user reroll by force-quitting.
    private(set) var currentTask: FocusTask? {
        didSet {
            if let currentTask, let data = try? JSONEncoder().encode(currentTask) {
                defaults.set(data, forKey: Key.task)
            } else {
                defaults.removeObject(forKey: Key.task)
            }
        }
    }

    /// Recent task texts so a reroll never repeats what you just saw.
    private var recentDescriptions: [String] {
        didSet { defaults.set(recentDescriptions, forKey: Key.recent) }
    }

    /// Total minutes the user has earned, all time.
    private(set) var lifetimeEarnedMinutes: Int {
        didSet { defaults.set(lifetimeEarnedMinutes, forKey: Key.lifetime) }
    }

    /// Tasks completed, all time.
    private(set) var completedTaskCount: Int {
        didSet { defaults.set(completedTaskCount, forKey: Key.completed) }
    }

    private enum Key {
        static let task = "fit.focus.task.v2"
        static let recent = "fit.focus.recentTasks.v1"
        static let lifetime = "fit.focus.lifetimeMinutes.v1"
        static let completed = "fit.focus.completedCount.v1"
    }

    init(defaults: UserDefaults = .standard, screenTime: ScreenTimeService = ScreenTimeService()) {
        self.defaults = defaults
        self.screenTime = screenTime
        isEnabled = FocusBridge.isEnabled
        unlockExpiry = FocusBridge.unlockExpiry
        if let data = defaults.data(forKey: Key.task),
           let task = try? JSONDecoder().decode(FocusTask.self, from: data) {
            currentTask = task
        }
        recentDescriptions = defaults.stringArray(forKey: Key.recent) ?? []
        lifetimeEarnedMinutes = defaults.integer(forKey: Key.lifetime)
        completedTaskCount = defaults.integer(forKey: Key.completed)
        if isEnabled { startTicking() }
    }

    // MARK: State

    /// True while an earned session is still running.
    var isUnlocked: Bool {
        guard let unlockExpiry else { return false }
        return unlockExpiry > now
    }

    /// True when the chosen apps are currently shielded.
    var isShielding: Bool { isEnabled && !isUnlocked }

    /// Everything is wired up and Apple has granted permission.
    var isArmed: Bool { isEnabled && screenTime.access.isApproved && screenTime.hasSelection }

    var remainingSeconds: Int {
        guard let unlockExpiry else { return 0 }
        return max(0, Int(unlockExpiry.timeIntervalSince(now).rounded()))
    }

    var remainingLabel: String {
        let total = remainingSeconds
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: Toggle

    /// Arms the lock and shields the chosen apps immediately.
    func enable() {
        isEnabled = true
        unlockExpiry = nil
        screenTime.applyShield()
        if currentTask == nil { drawTask(.medium) }
        startTicking()
    }

    func disable() {
        isEnabled = false
        unlockExpiry = nil
        screenTime.releaseEverything()
        stopTicking()
    }

    // MARK: Task lifecycle

    /// Pulls a fresh task from the 10,000-deep vault for that tier. Instant,
    /// offline, and identical on every device for a given index.
    func drawTask(_ difficulty: FocusDifficulty) {
        let task = FocusTaskVault.draw(difficulty, excluding: recentDescriptions)
        currentTask = task
        recentDescriptions.append(task.taskDescription)
        if recentDescriptions.count > 40 {
            recentDescriptions.removeFirst(recentDescriptions.count - 40)
        }
    }

    /// The user attests the task is done: unshield the chosen apps for exactly
    /// the tier's reward window, measured from the current wall clock.
    func completeCurrentTask() {
        guard let task = currentTask else { return }
        now = .now
        let expiry = now.addingTimeInterval(TimeInterval(task.unlockMinutes * 60))
        unlockExpiry = expiry
        FocusBridge.earnedMinutes = task.unlockMinutes
        lifetimeEarnedMinutes += task.unlockMinutes
        completedTaskCount += 1
        currentTask = nil
        screenTime.liftShield(until: expiry)
        startTicking()
    }

    /// Ends an active session early and puts the shield straight back.
    func endSessionEarly() {
        unlockExpiry = nil
        screenTime.applyShield()
    }

    /// Re-syncs against the system clock and reconciles the shield. Called on
    /// foreground so a window that expired in the background applies at once.
    func resync() {
        now = .now
        screenTime.refreshAccess()
        guard isEnabled else { return }
        if !isUnlocked {
            unlockExpiry = nil
            screenTime.applyShield()
        }
    }

    // MARK: Heartbeat

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.now = .now
                // The moment a session expires, re-shield from inside the app
                // too — belt and braces alongside the monitor extension.
                if self.isEnabled, self.unlockExpiry != nil, !self.isUnlocked {
                    self.unlockExpiry = nil
                    self.screenTime.applyShield()
                    Haptics.warning()
                }
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }
}
