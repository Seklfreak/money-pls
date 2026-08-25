import SwiftUI

enum Theme {
    static let bg = Color(hex: 0xfff6ea)
    static let bgTop = Color(hex: 0xffe9d6)
    static let ink = Color(hex: 0x4a3728)
    static let inkDeep = Color(hex: 0x2e2118)
    static let muted = Color(hex: 0xa98c72)
    static let body = Color(hex: 0x7a5c44)
    static let faint = Color(hex: 0xc8b39e)
    static let line = Color(hex: 0xf0dcc6)
    static let sand = Color(hex: 0xe9d9c6)
    static let paper = Color(hex: 0xfffdf8)
    static let tray = Color(hex: 0xd3a97c)
    static let trayLight = Color(hex: 0xe6c39c)
    static let trayDark = Color(hex: 0xb98a5e)
    static let trayEdge = Color(hex: 0x8f6642)
    static let pink = Color(hex: 0xff8fa3)
    static let pinkShadow = Color(hex: 0xe06a80)
    static let amber = Color(hex: 0xd99a1e)
    static let amberBg = Color(hex: 0xfff1d9)
    static let green = Color(hex: 0x3f9e5a)
    static let mint = Color(hex: 0x6cc98a)
    static let white = Color.white

    /// Avatar palette, in the order the design uses them.
    static let avatarColors: [Color] = [
        Color(hex: 0xff6b6b), Color(hex: 0xff9f43), Color(hex: 0xf9c74f), Color(hex: 0x6cc98a),
        Color(hex: 0x9b8cf5), Color(hex: 0x5ec8d8), Color(hex: 0xf48fb1), Color(hex: 0x7ccf8f),
    ]
    static func avatarColor(_ index: Int) -> Color { avatarColors[((index % avatarColors.count) + avatarColors.count) % avatarColors.count] }

    static func disp(_ size: CGFloat, _ weight: DispWeight = .semibold) -> Font {
        .custom(weight.name, size: size, relativeTo: style(for: size))
    }
    static func text(_ size: CGFloat, _ weight: TextWeight = .bold) -> Font {
        .custom(weight.name, size: size, relativeTo: style(for: size))
    }
    /// Dynamic Type anchor by design size, so every custom font scales with the user's text size setting.
    private static func style(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 28...: .largeTitle
        case 22..<28: .title
        case 17..<22: .title3
        case 15..<17: .body
        case 13..<15: .subheadline
        case 12..<13: .footnote
        default: .caption
        }
    }
    enum DispWeight {
        case medium, semibold, bold
        var name: String {
            switch self {
            case .medium: "Fredoka-Medium"
            case .semibold: "Fredoka-SemiBold"
            case .bold: "Fredoka-Bold"
            }
        }
    }
    enum TextWeight {
        case semibold, bold, extrabold
        var name: String {
            switch self {
            case .semibold: "Nunito-SemiBold"
            case .bold: "Nunito-Bold"
            case .extrabold: "Nunito-ExtraBold"
            }
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

/// Page background: warm gradient fading into cream.
struct PageBackground: View {
    var stop: CGFloat = 0.4
    var body: some View {
        LinearGradient(stops: [.init(color: Theme.bgTop, location: 0), .init(color: Theme.bg, location: stop)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// The flat "stacked paper" shadow the design uses everywhere: a solid shape offset below the fill.
struct Raised<S: InsettableShape>: ViewModifier {
    var shape: S
    var fill: Color
    var shadow: Color
    var depth: CGFloat
    func body(content: Content) -> some View {
        content.background {
            ZStack { shape.fill(shadow).offset(y: depth); shape.fill(fill) }
        }
    }
}
extension View {
    func raised<S: InsettableShape>(_ shape: S, fill: Color = .white, shadow: Color = Theme.line, depth: CGFloat = 3) -> some View {
        modifier(Raised(shape: shape, fill: fill, shadow: shadow, depth: depth))
    }
    func card(radius: CGFloat = 22, shadow: CGFloat = 4, fill: Color = .white) -> some View {
        raised(RoundedRectangle(cornerRadius: radius, style: .continuous), fill: fill, shadow: Theme.line, depth: shadow)
    }
}

extension Int {
    /// Cents → "$12.34"
    var money: String { String(format: "$%@%d.%02d", self < 0 ? "-" : "", abs(self) / 100, abs(self) % 100) }
    /// Cents → "12.34"
    var moneyPlain: String { String(format: "%@%d.%02d", self < 0 ? "-" : "", abs(self) / 100, abs(self) % 100) }
}
