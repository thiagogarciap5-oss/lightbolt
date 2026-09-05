import SwiftUI

nonisolated enum LightBoltTab: Int, CaseIterable, Identifiable, Sendable {
    case today, nutrition, body, train, family, profile

    nonisolated var id: Int { rawValue }

    /// The dock without the Family tab — the default for everyone who isn't
    /// the billing owner of an active Family Plan.
    static let standard: [LightBoltTab] = [.today, .nutrition, .body, .train, .profile]
    static let withFamily: [LightBoltTab] = [.today, .nutrition, .body, .train, .family, .profile]

    var title: String {
        switch self {
        case .today: "Today"
        case .nutrition: "Food"
        case .body: "Body"
        case .train: "Train"
        case .family: "Family"
        case .profile: "You"
        }
    }

    var symbol: String {
        switch self {
        case .today: "bolt.horizontal.fill"
        case .nutrition: "fork.knife"
        case .body: "figure.stand"
        case .train: "dumbbell.fill"
        case .family: "person.2.fill"
        case .profile: "person.fill"
        }
    }
}

/// Floating black tab dock with a sliding volt indicator.
struct LightBoltTabBar: View {
    @Binding var selection: LightBoltTab
    var tabs: [LightBoltTab] = LightBoltTab.standard
    @Namespace private var indicator

    private var pillWidth: CGFloat { tabs.count > 5 ? 40 : 46 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    guard selection != tab else { return }
                    Haptics.tap()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.74)) { selection = tab }
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(LightBoltTheme.volt)
                                    .matchedGeometryEffect(id: "tabPill", in: indicator)
                                    .frame(width: pillWidth, height: 32)
                            }
                            Image(systemName: tab.symbol)
                                .font(.system(size: tabs.count > 5 ? 15 : 16, weight: .bold))
                                .foregroundStyle(selection == tab ? .black : LightBoltTheme.inkFaint)
                                .frame(width: pillWidth, height: 32)
                        }
                        Text(tab.title.uppercased())
                            .font(.fitLabel(tabs.count > 5 ? 7.5 : 8))
                            .tracking(tabs.count > 5 ? 0.7 : 1.1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(selection == tab ? LightBoltTheme.volt : LightBoltTheme.inkFaint)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(VoltPressStyle(scale: 0.92))
                .accessibilityLabel(tab.title)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: tabs)
        .padding(.horizontal, 6)
        .padding(.vertical, 11)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LightBoltTheme.obsidian)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(LightBoltTheme.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.6), radius: 22, y: 8)
        )
        .padding(.horizontal, 14)
    }
}
