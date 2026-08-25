import SwiftUI

/// The tray-bill-coins-dashes mark from the design canvas.
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
            let dashes: [((CGFloat, CGFloat), (CGFloat, CGFloat), CGFloat)] = [
                ((12.4, 30.8), (9.2, 27.7), 2.0), ((21.0, 25.4), (19.1, 20.2), 2.2), ((32.0, 23.5), (32.0, 17.0), 2.4),
                ((43.0, 25.4), (44.9, 20.2), 2.2), ((51.6, 30.8), (54.8, 27.7), 2.0),
            ]
            for (a, b, w) in dashes {
                var d = Path(); d.move(to: p(a.0, a.1)); d.addLine(to: p(b.0, b.1))
                ctx.stroke(d, with: .color(Theme.pink), style: StrokeStyle(lineWidth: w * s, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

struct Avatar: View {
    let initial: String
    let color: Color
    var size: CGFloat = 26
    var dim = false
    var check = false
    var body: some View {
        ZStack {
            Circle().fill(dim ? Color(hex: 0xf3e6d6) : color)
            if check {
                Image(systemName: "checkmark").font(.system(size: size * 0.36, weight: .heavy)).foregroundStyle(.white)
            } else {
                Text(initial).font(Theme.disp(size * 0.42)).foregroundStyle(dim ? Theme.faint : .white)
            }
        }
        .overlay(Circle().stroke(Theme.paper, lineWidth: 2))
        .frame(width: size, height: size)
    }
}
extension Avatar {
    init(_ person: Person, size: CGFloat = 26, dim: Bool = false, check: Bool = false) {
        self.init(initial: person.initial, color: Theme.avatarColor(person.colorIndex), size: size, dim: dim, check: check)
    }
}

/// Overlapping avatar stack, rightmost on top like the design.
struct AvatarStack: View {
    let people: [Person]
    var size: CGFloat = 26
    var body: some View {
        HStack(spacing: -8) { ForEach(people) { Avatar($0, size: size) } }
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String?
    var height: CGFloat = 56
    var fontSize: CGFloat = 18
    var fill: Color = Theme.pink
    var shadow: Color = Theme.pinkShadow
    var fg: Color = .white
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: fontSize, weight: .bold)) }
                Text(title).font(Theme.disp(fontSize))
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity).frame(height: height)
            .raised(Capsule(), fill: fill, shadow: shadow, depth: 5)
        }
        .buttonStyle(PressStyle())
    }
}

struct SecondaryButton: View {
    let title: String
    var icon: String?
    var height: CGFloat = 48
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .bold)) }
                Text(title).font(Theme.text(15, .extrabold))
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity).frame(height: height)
            .raised(Capsule(), fill: .white, shadow: Theme.line, depth: 3)
        }
        .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(y: configuration.isPressed ? 3 : 0).opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct RoundIconButton: View {
    let system: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .raised(Circle(), fill: .white, shadow: Theme.line, depth: 3)
        }.buttonStyle(PressStyle())
    }
}

struct Pill<Content: View>: View {
    var bg: Color = .white
    var fg: Color = Theme.body
    var shadow = true
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 6) { content }
            .font(Theme.text(12, .extrabold)).foregroundStyle(fg)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .raised(Capsule(), fill: bg, shadow: shadow ? Theme.line : .clear, depth: 2)
    }
}

/// Header with back button and the logo lockup.
struct BrandHeader: View {
    var back: (() -> Void)?
    var body: some View {
        HStack {
            if let back { RoundIconButton(system: "chevron.left", action: back) } else { Color.clear.frame(width: 44, height: 44) }
            Spacer()
            HStack(spacing: 8) { Logo(size: 28); Text("Money pls").font(Theme.disp(18)).foregroundStyle(Theme.ink) }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }
}

/// The wooden tray with a paper receipt on it.
struct Tray<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.paper).shadow(color: Color(hex: 0x785028).opacity(0.15), radius: 5, y: 3))
            .padding(EdgeInsets(top: 14, leading: 10, bottom: 18, trailing: 10))
            .raised(RoundedRectangle(cornerRadius: 22, style: .continuous), fill: Theme.tray, shadow: Theme.trayDark, depth: 8)
            // Top-edge highlight, inset past the corners so nothing overlaps the rounded rim.
            .overlay(alignment: .top) { Capsule().fill(Theme.trayLight).frame(height: 3).padding(.horizontal, 24).padding(.top, 2) }
            // Flatten first: without this SwiftUI shadows every child separately and every label and field on the paper gets its own halo.
            .compositingGroup()
            .shadow(color: Color(hex: 0x785028).opacity(0.25), radius: 15, y: 16)
    }
}

/// Scroll container for a Tray. Spans the full screen width so the tray's shadow isn't clipped at the
/// sides, and fades both edges so lines slide under the header and footer softly instead of hitting a hard cut.
struct TrayScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            content.padding(.horizontal, 30).padding(.top, 20)
        }
        .scrollClipDisabled()   // the mask is the clip; the scroll view's own would cut the shadow at its edges
        .mask(VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 20)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 24)
        })
        // Mask first, then bleed past the page padding: a negative padding reports the *smaller* frame, so a
        // mask applied after it would be 32 pt narrower than the scroll view and cut the shadow anyway.
        .padding(.horizontal, -16)
    }
}

/// Swipe-left-to-delete for rows that live in a ScrollView (List's swipeActions aren't available there).
/// A short swipe parks the row with a trash button showing; a long one deletes straight away.
struct SwipeToDelete: ViewModifier {
    let onDelete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var parked = false
    private let reveal: CGFloat = 84
    private let commit: CGFloat = 180

    func body(content: Content) -> some View {
        content
            .overlay { if parked { Color.clear.contentShape(Rectangle()).onTapGesture { close() } } }   // tap a parked row to close it, not open it
            .offset(x: offset)
            .background(alignment: .trailing) {
                Button(action: remove) {
                    Image(systemName: "trash.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        .frame(width: reveal - 12).frame(maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.pink))
                }
                .buttonStyle(PressStyle())
                .padding(.bottom, 4)   // sits under the card, which reserves this for its raised edge
                .opacity(offset < -8 ? 1 : 0)
                .scaleEffect(min(1, max(0.6, -offset / reveal)), anchor: .trailing)
            }
            .highPriorityGesture(   // beats the row's Button: a sideways drag is a swipe, a touch without one is still a tap
                DragGesture(minimumDistance: 24, coordinateSpace: .local)
                    .onChanged { g in
                        guard abs(g.translation.width) > abs(g.translation.height) else { return }
                        let x = g.translation.width + (parked ? -reveal : 0)
                        offset = min(0, x < -commit ? -commit - (-(x + commit)) * 0.2 : x)
                    }
                    .onEnded { g in
                        let x = g.translation.width + (parked ? -reveal : 0)
                        if x < -commit { remove(); return }
                        withAnimation(.snappy) { parked = x < -reveal / 2; offset = parked ? -reveal : 0 }
                    }
            )
    }
    private func close() { withAnimation(.snappy) { parked = false; offset = 0 } }
    private func remove() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy) { offset = -600 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.snappy) { onDelete() } }
    }
}
extension View { func swipeToDelete(_ action: @escaping () -> Void) -> some View { modifier(SwipeToDelete(onDelete: action)) } }

struct DottedRule: View {
    var body: some View {
        Line().stroke(style: StrokeStyle(lineWidth: 2, dash: [2, 3])).foregroundStyle(Theme.line).frame(height: 2)
    }
    struct Line: Shape { func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: r.width, y: r.midY)); return p } }
}

/// White bottom sheet-ish footer with the call to action.
struct Footer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 16) { content }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28).fill(.white)
                    .shadow(color: Color(hex: 0x785028).opacity(0.12), radius: 15, y: -8).ignoresSafeArea(edges: .bottom)
            )
    }
}

extension View {
    func hideKeyboardOnTap() -> some View {
        onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }
}
