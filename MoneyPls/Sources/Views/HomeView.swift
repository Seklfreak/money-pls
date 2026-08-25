import SwiftUI
import SwiftData
import PhotosUI

enum Route: Hashable { case items(UUID), assign(UUID), bill(UUID) }

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Split.createdAt, order: .reverse) private var splits: [Split]
    @State private var path: [Route] = []
    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var photoItem: PhotosPickerItem?
    @State private var processing: UIImage?
    @State private var processingCropped = false
    @State private var error: String?

    var owed: Int { splits.reduce(0) { $0 + Money.outstanding(for: $1) } }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                PageBackground(stop: 0.45)
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 10) {
                            Logo(size: 96)
                            Text("Money pls").font(Theme.disp(34, .bold)).foregroundStyle(Theme.ink)
                            Text("Scan the receipt, tap who had what,\nsend everyone their share.")
                                .font(Theme.text(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        }.padding(.top, 12)
                        VStack(spacing: 10) {
                            PrimaryButton(title: "Scan a receipt", icon: "camera.fill", height: 68, fontSize: 20) { showCamera = true }
                            Button { showPhotos = true } label: { PickPhotosLabel() }.buttonStyle(PressStyle())
                        }
                        if !splits.isEmpty {
                            VStack(spacing: 10) {
                                HStack {
                                    Text("History").font(Theme.disp(18)).foregroundStyle(Theme.ink)
                                    Spacer()
                                    if owed > 0 { Text("\(owed.money) still owed to you").font(Theme.text(12, .extrabold)).foregroundStyle(Theme.muted) }
                                }.padding(.horizontal, 4)
                                ForEach(splits) { split in
                                    Button { path = [route(for: split)] } label: { HistoryRow(split: split) }.buttonStyle(PressStyle())
                                        .contextMenu { Button(role: .destructive) { context.delete(split) } label: { Label("Delete", systemImage: "trash") } }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 32)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .items(let id): if let s = split(id) { ItemsView(split: s, path: $path) }
                case .assign(let id): if let s = split(id) { AssignView(split: s, path: $path) }
                case .bill(let id): if let s = split(id) { BillView(split: s, path: $path) }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCamera { image in showCamera = false; if let image { processingCropped = true; processing = image } }
                .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { processingCropped = false; processing = img }
                photoItem = nil
            }
        }
        .fullScreenCover(item: $processing) { image in
            ProcessingView(image: image, alreadyCropped: processingCropped) { result in
                processing = nil
                if let result { let s = makeSplit(from: result, image: image); path = [.items(s.id)] }
            } retry: {
                // Reopen whichever source the failed photo came from.
                let fromCamera = processingCropped
                processing = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { if fromCamera { showCamera = true } else { showPhotos = true } }
            }
        }
    }

    private func split(_ id: UUID) -> Split? { splits.first { $0.id == id } }
    private func route(for s: Split) -> Route {
        if s.people.count < 2 { return .items(s.id) }
        return s.unassignedItems.isEmpty ? .bill(s.id) : .assign(s.id)
    }

    private func makeSplit(from r: ParsedReceipt, image: UIImage) -> Split {
        // No merchant → empty title so the tray shows its "Where was this?" placeholder instead of a fake name.
        let raw = r.merchant ?? ""
        let s = Split(title: raw == raw.uppercased() ? raw.capitalized : raw)
        s.taxCents = r.taxCents ?? 0
        s.tipCents = r.tipCents ?? 0
        s.printedSubtotalCents = r.subtotalCents
        s.receiptImage = image.jpegData(compressionQuality: 0.6)
        s.parseTrace = ScanTrace.shared.text
        for (i, it) in r.items.enumerated() { s.items.append(LineItem(name: it.name, quantity: it.quantity, priceCents: it.priceCents, order: i)) }
        context.insert(s)
        return s
    }
}

extension UIImage: @retroactive Identifiable { public var id: ObjectIdentifier { ObjectIdentifier(self) } }

struct HistoryRow: View {
    let split: Split
    var body: some View {
        let outstanding = Money.outstanding(for: split)
        let owing = split.sortedPeople.filter { $0.id != split.payer?.id && !$0.settled }
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(split.displayTitle).font(Theme.disp(17)).foregroundStyle(Theme.ink).lineLimit(2)
                HStack(spacing: 8) {
                    Text(split.createdAt.formatted(.relative(presentation: .named)).capitalizedFirst).font(Theme.text(12)).foregroundStyle(Theme.muted)
                    if !split.people.isEmpty {
                        Text("·").foregroundStyle(Theme.muted)
                        AvatarStack(people: split.sortedPeople, size: 24)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(split.totalCents.money).font(Theme.disp(18)).foregroundStyle(Theme.ink).monospacedDigit()
                if split.people.count < 2 {
                    StatusTag(text: "unfinished", color: Theme.muted)
                } else if outstanding == 0 {
                    StatusTag(text: "all paid", color: Theme.green)
                } else if owing.count == 1 {
                    StatusTag(text: "\(owing[0].name) owes \(outstanding.money)", color: Theme.amber)
                } else {
                    StatusTag(text: "\(owing.count) still owe", color: Theme.amber)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .card()
    }
}

struct StatusTag: View {
    let text: String; let color: Color
    var body: some View {
        Text(text).font(Theme.text(11, .extrabold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(color.opacity(0.12)))
    }
}

extension String { var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() } }

struct PickPhotosLabel: View {
    var body: some View {
        HStack(spacing: 8) { Image(systemName: "photo").font(.system(size: 15, weight: .bold)); Text("Pick from photos").font(Theme.text(15, .extrabold)) }
            .foregroundStyle(Theme.ink).frame(maxWidth: .infinity).frame(height: 48)
            .raised(Capsule(), fill: .white, shadow: Theme.line, depth: 3)
    }
}
