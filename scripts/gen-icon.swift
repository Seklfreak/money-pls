// Renders the app icon from the same Logo drawing the app uses. Run: swift scripts/gen-icon.swift
import SwiftUI
import AppKit
enum Theme {
    static let bg = Color(hex: 0xfff6ea), bgTop = Color(hex: 0xffe9d6), tray = Color(hex: 0xd3a97c), trayDark = Color(hex: 0xb98a5e)
    static let trayEdge = Color(hex: 0x8f6642), pink = Color(hex: 0xff8fa3), amber = Color(hex: 0xd99a1e), green = Color(hex: 0x3f9e5a)
}
extension Color { init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: 1) } }
struct Logo: View {
    var size: CGFloat = 64
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 64
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            // tray body
            var body = Path(); body.move(to: p(11, 46)); body.addLine(to: p(53, 46)); body.addLine(to: p(53, 55))
            body.addQuadCurve(to: p(50, 58), control: p(53, 58)); body.addLine(to: p(14, 58)); body.addQuadCurve(to: p(11, 55), control: p(11, 58)); body.closeSubpath()
            ctx.fill(body, with: .color(Theme.trayDark)); ctx.stroke(body, with: .color(Theme.trayEdge), lineWidth: 2 * s)
            let rim = Path(roundedRect: CGRect(x: 9 * s, y: 40 * s, width: 46 * s, height: 8 * s), cornerRadius: 4 * s)
            ctx.fill(rim, with: .color(Theme.tray)); ctx.stroke(rim, with: .color(Theme.trayEdge), lineWidth: 2 * s)
            ctx.fill(Path(roundedRect: CGRect(x: 13 * s, y: 42 * s, width: 38 * s, height: 4 * s), cornerRadius: 2 * s), with: .color(Theme.trayDark.opacity(0.85)))
            // coins
            for cx in [20.0, 44.0] {
                let c = Path(ellipseIn: CGRect(x: (cx - 5.5) * s, y: 34.5 * s, width: 11 * s, height: 11 * s))
                ctx.fill(c, with: .color(Color(hex: 0xf6c453))); ctx.stroke(c, with: .color(Theme.amber), lineWidth: 2 * s)
                ctx.stroke(Path(ellipseIn: CGRect(x: (cx - 2.5) * s, y: 37.5 * s, width: 5 * s, height: 5 * s)), with: .color(Theme.amber.opacity(0.7)), lineWidth: 1.5 * s)
            }
            // bill
            ctx.drawLayer { l in
                l.translateBy(x: 32 * s, y: 38 * s); l.rotate(by: .degrees(-12)); l.translateBy(x: -32 * s, y: -38 * s)
                let b = Path(roundedRect: CGRect(x: 22 * s, y: 32.5 * s, width: 20 * s, height: 11 * s), cornerRadius: 2.5 * s)
                l.fill(b, with: .color(Color(hex: 0x7ccf8f))); l.stroke(b, with: .color(Theme.green), lineWidth: 2 * s)
                l.stroke(Path(roundedRect: CGRect(x: 25 * s, y: 35.5 * s, width: 14 * s, height: 5 * s), cornerRadius: 1.5 * s), with: .color(Theme.green.opacity(0.7)), lineWidth: 1.2 * s)
                l.fill(Path(ellipseIn: CGRect(x: 30 * s, y: 36 * s, width: 4 * s, height: 4 * s)), with: .color(Theme.green.opacity(0.7)))
            }
            // dashes
            for (a, b, w) in [((12.4, 30.8), (9.2, 27.7), 2.0), ((21.0, 25.4), (19.1, 20.2), 2.2), ((32.0, 23.5), (32.0, 17.0), 2.4), ((43.0, 25.4), (44.9, 20.2), 2.2), ((51.6, 30.8), (54.8, 27.7), 2.0)] {
                var d = Path(); d.move(to: p(a.0, a.1)); d.addLine(to: p(b.0, b.1))
                ctx.stroke(d, with: .color(Theme.pink), style: StrokeStyle(lineWidth: w * s, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}
struct Icon: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bg], startPoint: .top, endPoint: .bottom)
            Logo(size: 820).offset(y: 20)
        }.frame(width: 1024, height: 1024)
    }
}
@MainActor func run() {
    let r = ImageRenderer(content: Icon()); r.scale = 1
    let img = r.nsImage!
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "MoneyPls/Assets.xcassets/AppIcon.appiconset/icon-1024.png"))
    print("wrote icon")
}
MainActor.assumeIsolated { run() }
