import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The blocked-app screen. iOS renders this instead of the app the user tried
/// to open, so it is styled to match LightBolt exactly: pure black, electric
/// yellow, uppercase.
final class FocusShieldConfiguration: ShieldConfigurationDataSource {
    private enum Palette {
        static let void = UIColor.black
        static let volt = UIColor(red: 1.0, green: 0.96, blue: 0.0, alpha: 1.0)
        static let ink = UIColor.white
        static let inkMuted = UIColor(white: 1.0, alpha: 0.62)
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        shield(named: application.localizedDisplayName)
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        shield(named: application.localizedDisplayName ?? category.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        shield(named: webDomain.domain)
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        shield(named: webDomain.domain ?? category.localizedDisplayName)
    }

    // MARK: Styling

    private func shield(named name: String?) -> ShieldConfiguration {
        let target = (name?.isEmpty == false ? name! : "This app").uppercased()
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: Palette.void,
            icon: boltIcon,
            title: ShieldConfiguration.Label(
                text: "\(target)\nIS LOCKED",
                color: Palette.ink
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitleText,
                color: Palette.inkMuted
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "EARN TIME IN LIGHTBOLT",
                color: .black
            ),
            primaryButtonBackgroundColor: Palette.volt,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Not now",
                color: Palette.inkMuted
            )
        )
    }

    private var subtitleText: String {
        guard let expiry = FocusBridge.unlockExpiry, expiry > .now else {
            return "Open LightBolt and finish one real-world task to unlock this app. Easy earns 15 minutes, Medium 30, Hard 60."
        }
        let minutes = max(1, Int(expiry.timeIntervalSinceNow / 60))
        return "Your session has \(minutes) min left but this app is not part of it."
    }

    private var boltIcon: UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 44, weight: .black)
        return UIImage(systemName: "bolt.fill", withConfiguration: configuration)?
            .withTintColor(Palette.volt, renderingMode: .alwaysOriginal)
    }
}
