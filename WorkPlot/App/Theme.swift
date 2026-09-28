import SwiftUI
import UIKit

enum AppAccent: String, CaseIterable, Identifiable {
    case blue
    case indigo
    case teal
    case orange
    case pink

    var id: String { rawValue }

    var name: String {
        switch self {
        case .blue: return "Blue"
        case .indigo: return "Indigo"
        case .teal: return "Teal"
        case .orange: return "Orange"
        case .pink: return "Pink"
        }
    }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .indigo: return .indigo
        case .teal: return .teal
        case .orange: return .orange
        case .pink: return .pink
        }
    }

    static var current: AppAccent {
        AppAccent(rawValue: UserDefaults.standard.string(forKey: "accentColor") ?? "blue") ?? .blue
    }
}

enum Theme {
    static var accent: Color {
        if UserDefaults.standard.bool(forKey: "useCustomColor") {
            let hue = UserDefaults.standard.double(forKey: "customColor")
            return Color(hue: hue, saturation: 0.75, brightness: 0.9)
        }
        return AppAccent.current.color
    }
    static let caution = Color(.systemOrange)
    static let destructive = Color(.systemRed)
    static let affirmative = Color(.systemGreen)

    static let pagePadding: CGFloat = 20
    static let cardRadius: CGFloat = 24

    // MARK: - WorkSlop light-blue design language
    //
    // Solid surfaces only — no Liquid Glass, no translucent materials.
    // Cards are solid light blue with a blue-tinted border and a soft
    // drop shadow; the page itself is a lighter blue wash.

    /// Brand blue used for banners, primary actions and highlights.
    static let wsBlue = Color(red: 0.16, green: 0.44, blue: 0.85)

    /// Page background: a light blue wash.
    static let page = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.043, green: 0.078, blue: 0.145, alpha: 1.0)
            : UIColor(red: 0.878, green: 0.933, blue: 0.984, alpha: 1.0)
    })

    /// Solid card fill: light blue, never white.
    static let card = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.145, blue: 0.251, alpha: 1.0)
            : UIColor(red: 0.769, green: 0.871, blue: 0.965, alpha: 1.0)
    })

    /// Blue-tinted card border.
    static let cardBorder = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.153, green: 0.271, blue: 0.427, alpha: 1.0)
            : UIColor(red: 0.588, green: 0.745, blue: 0.902, alpha: 1.0)
    })
}

extension View {
    /// Solid light-blue card surface: rounded corners, blue-tinted border,
    /// soft shadow. This is the replacement for the old liquid-glass cards.
    func wsCard(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 3)
    }

    /// Solid button styling. `prominent` fills with the brand blue (or red
    /// for destructive actions); otherwise the button is a light-blue
    /// outline chip with tinted text.
    func wsAction(prominent: Bool = false) -> some View {
        buttonStyle(WSButtonStyle(prominent: prominent))
    }
}

/// Solid (non-glass) button style for WorkSlop.
struct WSButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        let tint: Color = configuration.role == .destructive ? Theme.destructive : Theme.wsBlue
        configuration.label
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                prominent ? tint : tint.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.45), lineWidth: 1)
                }
            }
            .foregroundStyle(prominent ? .white : tint)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
