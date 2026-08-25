import SwiftUI
import VisionKit

/// VisionKit's document camera: live edge detection, auto-capture, perspective-corrected output.
struct DocumentCamera: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController(); vc.delegate = context.coordinator; return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: (UIImage?) -> Void
        init(_ c: @escaping (UIImage?) -> Void) { completion = c }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            completion(scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { completion(nil) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { completion(nil) }
    }
}

/// Dark "reading the receipt" screen shown while Vision runs.
struct ProcessingView: View {
    let image: UIImage
    let alreadyCropped: Bool
    let done: (ParsedReceipt?) -> Void
    let retry: () -> Void
    @State private var status = "Reading the receipt…"
    @State private var failed = false
    @State private var started = false

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .rotationEffect(.degrees(-2))
                    .shadow(color: .black.opacity(0.35), radius: 15, y: 14)
                    .padding(.horizontal, 48)
                HStack(spacing: 8) {
                    if failed { Circle().fill(Theme.amber).frame(width: 10, height: 10) } else { ProgressView().tint(Theme.ink).scaleEffect(0.8) }
                    Text(status).font(Theme.text(13, .extrabold)).foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .raised(Capsule(), fill: Theme.bg, shadow: Theme.line, depth: 3)
                if failed {
                    VStack(spacing: 10) {
                        PrimaryButton(title: "Try another photo", icon: "camera.fill", action: retry)
                        SecondaryButton(title: "Add items by hand") { done(ParsedReceipt()) }
                        HStack(spacing: 18) {
                            Button("Cancel") { done(nil) }
                            ReportScanButton(image: image, trace: ScanTrace.shared.text, context: status)
                        }.font(Theme.text(14, .extrabold)).foregroundStyle(Theme.faint).padding(.top, 4)
                    }.padding(.horizontal, 32)
                }
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            let image = image, cropped = alreadyCropped
            // Detached on purpose: SwiftUI cancels a view-bound `.task` when the cover is re-identified,
            // and that cancellation propagates into Vision as `requestCancelled`.
            Task.detached(priority: .userInitiated) {
                do {
                    var r = try await ReceiptParser.parse(image, alreadyCropped: cropped)
                    trace("parsed \(r.items.count) items sum=\(r.itemSumCents) subtotal=\(r.subtotalCents ?? -1)")
                    if !r.reconciles, r.subtotalCents != nil, ReceiptRepair.isAvailable {
                        await MainActor.run { status = "Double-checking the numbers…" }
                        if let fixed = await ReceiptRepair.repair(r) { r = fixed }
                    }
                    let result = r
                    await MainActor.run {
                        if result.items.isEmpty { status = "Couldn't find any prices on that one"; failed = true } else { done(result) }
                    }
                } catch {
                    traceError("parse failed: \(error)")
                    await MainActor.run { status = "Couldn't read that photo"; failed = true }
                }
            }
        }
    }
}
