import SwiftUI
import SwiftData
import PhotosUI

enum Route: Hashable { case items(UUID), assign(UUID), bill(UUID), friend(UUID) }

/// The three tabs of the shell.
enum HomeTab: String, CaseIterable, Identifiable {
    case friends, activity, bills
    var id: String { rawValue }
    var title: String {
        switch self {
        case .friends: "Friends"
        case .activity: "Activity"
        case .bills: "Bills"
        }
    }
    var icon: String {
        switch self {
        case .friends: "person.2"
        case .activity: "clock"
        case .bills: "doc.plaintext"
        }
    }
}

extension Split {
    /// Where tapping a split lands: back where it was left off, not always at the bill.
    var openRoute: Route {
        if people.count < 2 { return .items(id) }
        return unassignedItems.isEmpty ? .bill(id) : .assign(id)
    }
}

/// The shell: three tabs, each with its own navigation stack. Scanning lives here rather than in
/// the Friends tab so the camera, the picker and the processing cover survive a tab switch.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Split.createdAt, order: .reverse) private var splits: [Split]
    @Query private var friends: [Friend]
    @State private var tab: HomeTab = .friends
    @State private var path: [Route] = []
    @State private var activityPath: [Route] = []
    @State private var billsPath: [Route] = []
    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var photoItem: PhotosPickerItem?
    @State private var processing: UIImage?
    @State private var processingCropped = false

    var body: some View {
        ZStack {
            switch tab {
            case .friends:
                NavigationStack(path: $path) {
                    FriendsView(path: $path, onScan: startCamera, onPickPhotos: startPhotos)
                        .safeAreaInset(edge: .bottom) { TabBar(selection: $tab) }
                        .navigationDestination(for: Route.self) { destination($0, path: $path) }
                }
            case .activity:
                NavigationStack(path: $activityPath) {
                    ActivityView(path: $activityPath)
                        .safeAreaInset(edge: .bottom) { TabBar(selection: $tab) }
                        .navigationDestination(for: Route.self) { destination($0, path: $activityPath) }
                }
            case .bills:
                NavigationStack(path: $billsPath) {
                    BillsView(path: $billsPath)
                        .safeAreaInset(edge: .bottom) { TabBar(selection: $tab) }
                        .navigationDestination(for: Route.self) { destination($0, path: $billsPath) }
                }
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera, onDismiss: { if processing == nil { Analytics.screen(.friends) } }, content: {
            DocumentCamera { image in showCamera = false; if let image { processingCropped = true; processing = image } }
                .ignoresSafeArea()
        })
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { processingCropped = false; processing = img }
                photoItem = nil
            }
        }
        .fullScreenCover(item: $processing, onDismiss: { if path.isEmpty { Analytics.screen(.friends) } }, content: { image in
            ProcessingView(image: image, alreadyCropped: processingCropped) { result in
                processing = nil
                if let result { let s = makeSplit(from: result, image: image); tab = .friends; path = [.items(s.id)] }
            } retry: {
                // Reopen whichever source the failed photo came from.
                let fromCamera = processingCropped
                processing = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { if fromCamera { showCamera = true } else { showPhotos = true } }
            }
        })
    }

    @ViewBuilder private func destination(_ route: Route, path: Binding<[Route]>) -> some View {
        switch route {
        case .items(let id): if let s = split(id) { ItemsView(split: s, path: path) }
        case .assign(let id): if let s = split(id) { AssignView(split: s, path: path) }
        case .bill(let id): if let s = split(id) { BillView(split: s, path: path) }
        case .friend(let id): if let f = friends.first(where: { $0.id == id }) { FriendDetailView(friend: f, path: path) }
        }
    }

    private func startCamera() {
        Analytics.track("scan_started", ["source": "camera"])
        showCamera = true
    }
    private func startPhotos() {
        Analytics.track("scan_started", ["source": "photos"])
        showPhotos = true
    }

    private func split(_ id: UUID) -> Split? { splits.first { $0.id == id } }

    private func makeSplit(from r: ParsedReceipt, image: UIImage) -> Split {
        // No merchant → empty title so the tray shows its "Where was this?" placeholder instead of a fake name.
        let raw = r.merchant ?? ""
        let s = Split(title: raw == raw.uppercased() ? raw.capitalized : raw)
        s.taxCents = r.taxCents ?? 0
        s.tipCents = r.tipCents ?? 0
        s.printedSubtotalCents = r.subtotalCents
        s.currencyCode = r.currencyCode
        s.receiptImage = image.jpegData(compressionQuality: 0.6)
        s.parseTrace = ScanTrace.shared.text
        for (i, it) in r.items.enumerated() { s.items.append(LineItem(name: it.name, quantity: it.quantity, priceCents: it.priceCents, order: i)) }
        context.insert(s)
        return s
    }
}

extension UIImage: @retroactive Identifiable { public var id: ObjectIdentifier { ObjectIdentifier(self) } }

/// The bar itself: the same white 28pt shelf the Footer uses, so the two read as one family.
private struct TabBar: View {
    @Binding var selection: HomeTab
    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeTab.allCases) { tab in
                Button {
                    if selection != tab { UISelectionFeedbackGenerator().selectionChanged() }
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon).font(.system(size: 22, weight: .semibold))
                        Text(tab.title).font(Theme.text(11, .extrabold))
                    }
                    .foregroundStyle(selection == tab ? Theme.pink : Theme.faint)
                    .frame(maxWidth: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.top, 12).padding(.bottom, 8).padding(.horizontal, 16)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28).fill(.white)
                .shadow(color: Color(hex: 0x785028).opacity(0.12), radius: 15, y: -8).ignoresSafeArea(edges: .bottom)
        )
    }
}

struct HistoryRow: View {
    let split: Split
    var body: some View {
        let outstanding = Money.outstanding(for: split)
        let owing = split.sortedPeople.filter { $0.id != split.payer?.id && !$0.settled }
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(split.displayTitle).font(Theme.disp(17)).foregroundStyle(Theme.ink).lineLimit(2)
                HStack(spacing: 8) {
                    Text(split.createdAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)).capitalizedFirst)
                        .font(Theme.text(12)).foregroundStyle(Theme.muted).lineLimit(1).fixedSize()
                    if !split.people.isEmpty {
                        Text("·").foregroundStyle(Theme.muted)
                        AvatarStack(people: split.sortedPeople, size: 24)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(split.totalCents.money(split.currencyCode)).font(Theme.disp(18)).foregroundStyle(Theme.ink).monospacedDigit()
                if split.people.count < 2 {
                    StatusTag(text: "unfinished", color: Theme.muted)
                } else if outstanding == 0 {
                    StatusTag(text: "all paid", color: Theme.green)
                } else if owing.count == 1 {
                    StatusTag(text: "\(owing[0].name) owes \(outstanding.money(split.currencyCode))", color: Theme.amber)
                } else {
                    StatusTag(text: "\(owing.count) still owe", color: Theme.amber)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .card()
        .padding(.bottom, 4)   // room for the raised edge so the context-menu preview doesn't cut it off
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
