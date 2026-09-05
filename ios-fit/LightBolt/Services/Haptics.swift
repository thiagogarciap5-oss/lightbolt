import AudioToolbox
import UIKit

/// Centralised feedback so logging a set feels physical.
enum Haptics {
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notifier = UINotificationFeedbackGenerator()
    private static let selector = UISelectionFeedbackGenerator()

    static func prepare() {
        impactLight.prepare()
        impactRigid.prepare()
        notifier.prepare()
        selector.prepare()
    }

    static func tick() {
        selector.selectionChanged()
        selector.prepare()
    }

    static func tap() {
        impactLight.impactOccurred(intensity: 0.7)
        impactLight.prepare()
    }

    static func thud() {
        impactRigid.impactOccurred(intensity: 1.0)
        impactRigid.prepare()
    }

    static func success() {
        notifier.notificationOccurred(.success)
        notifier.prepare()
    }

    static func warning() {
        notifier.notificationOccurred(.warning)
        notifier.prepare()
    }

    static func failure() {
        notifier.notificationOccurred(.error)
        notifier.prepare()
    }
}

/// Native system chimes for the workout timer.
enum LightBoltChime {
    static func intervalEnd() {
        AudioServicesPlaySystemSound(1057)
    }

    static func countdownBeep() {
        AudioServicesPlaySystemSound(1103)
    }

    static func sessionComplete() {
        AudioServicesPlaySystemSound(1025)
    }
}
