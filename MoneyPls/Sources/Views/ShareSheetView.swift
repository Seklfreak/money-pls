import SwiftUI
import UIKit

/// "Ask Carmen for money pls" — a card image + plain text, handed to the system share sheet.
/// No links and no payment handles: the card is the whole message.
struct ShareSheetView: View {
    let split: Split
    let bills: [PersonBill]
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var single: PersonBill? { bills.count == 1 ? bills[0] : nil }

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(Theme.sand).frame(width: 40, height: 5).padding(.top, 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(single.map { "Ask \($0.person.name) for money pls" } ?? "Ask everyone for money pls").font(Theme.disp(24, .bold)).foregroundStyle(Theme.ink)
                Text(single != nil ? "A little card they can read without opening anything." : "\(bills.count) cards, one per person.").font(Theme.text(13)).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) { ForEach(bills) { ShareCard(split: split, bill: $0).frame(width: 320) } }.padding(.horizontal, 2).padding(.vertical, 20)
            }.scrollTargetBehavior(.viewAligned).scrollClipDisabled()
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                PrimaryButton(title: single != nil ? "Send the card" : "Send the cards", icon: "square.and.arrow.up") { share() }
                SecondaryButton(title: copied ? "Copied!" : "Copy as text") {
                    UIPasteboard.general.string = bills.map { text(for: $0) }.joined(separator: "\n\n")
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .background(Theme.bg.ignoresSafeArea())
    }

    private func text(for bill: PersonBill) -> String {
        let lines = bill.lines.map { "\($0.label) \($0.cents.money)" }.joined(separator: " · ")
        return "\(bill.person.name) — \(split.displayTitle): \(bill.totalCents.money) pls (to \(split.payer?.name ?? "me"))\n\(lines)"
    }

    private func share() {
        let images: [UIImage] = bills.compactMap { bill in
            let r = ImageRenderer(content: ShareCard(split: split, bill: bill).frame(width: 320))
            r.scale = 3
            let img = r.uiImage
            parseLog.info("share card for \(bill.person.name): \(img.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "nil")")
            return img
        }
        let items: [Any] = images + [bills.map { text(for: $0) }.joined(separator: "\n\n")]
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController?
            .topMost.present(vc, animated: true)
    }
}

struct ShareCard: View {
    let split: Split
    let bill: PersonBill
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MONEY PLS").font(Theme.disp(13)).foregroundStyle(Theme.trayDark).kerning(0.5)
                    Text("\(bill.person.name),\n\(bill.totalCents.money) pls").font(Theme.disp(26, .bold)).foregroundStyle(Theme.ink).lineSpacing(2)
                    Text("\(split.displayTitle) · to \(split.payer?.name ?? "me")").font(Theme.text(12)).foregroundStyle(Theme.muted)
                }.padding(.bottom, 16)
                Spacer()
                Logo(size: 88)
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20))
            .background(LinearGradient(colors: [Color(hex: 0xffe0cf), Color(hex: 0xffd0d8)], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 4) {
                ForEach(bill.lines) { l in HStack { Text(l.label); Spacer(); Text(l.cents.money).monospacedDigit() } }
            }
            .font(Theme.text(13)).foregroundStyle(Theme.body)
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 18, trailing: 20))
            .background(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.line).offset(y: 6))
        .shadow(color: Color(hex: 0x785028).opacity(0.15), radius: 15, y: 16)
    }
}

extension UIViewController {
    var topMost: UIViewController { presentedViewController?.topMost ?? self }
}
