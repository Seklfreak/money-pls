import SwiftUI
import SwiftData

/// The Bills tab: the split history, straight from the old home screen.
struct BillsView: View {
    @Binding var path: [Route]
    @Environment(\.modelContext) private var context
    @Query(sort: \Split.createdAt, order: .reverse) private var splits: [Split]

    var body: some View {
        ZStack {
            PageBackground(stop: 0.45)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BrandHeader()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bills").font(Theme.disp(30, .bold)).foregroundStyle(Theme.ink)
                        Text("Every split, newest first. Tap to reopen.").font(Theme.text(14)).foregroundStyle(Theme.muted)
                    }
                    if splits.isEmpty {
                        Text("No bills yet. Scan a receipt and it lands here.")
                            .font(Theme.text(14)).foregroundStyle(Theme.muted).padding(.top, 12)
                    }
                    VStack(spacing: 10) {
                        ForEach(splits) { split in
                            Button { path = [split.openRoute] } label: { HistoryRow(split: split) }.buttonStyle(PressStyle())
                                // Preview shape matches the card, including its raised edge (kept inside the frame below).
                                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .contextMenu { Button(role: .destructive) { delete(split) } label: { Label("Delete", systemImage: "trash") } }
                                .swipeToDelete { delete(split) }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Analytics.screen(.bills) }
    }

    private func delete(_ split: Split) {
        Analytics.track("split_deleted")
        context.delete(split)
    }
}
