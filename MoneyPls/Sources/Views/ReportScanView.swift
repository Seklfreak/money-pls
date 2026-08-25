import SwiftUI
import MessageUI
import UIKit

/// "Report this scan": mails the receipt photo and the parse log to the developer. The photo is the
/// only thing that lets a parser bug be reproduced, so it is attached as-is — the user sees exactly
/// what goes out in the mail composer and can remove it. Falls back to the share sheet where Mail
/// isn't set up.
struct ReportScanButton: View {
    let image: UIImage
    let trace: String
    /// One line of context from the caller (the error shown, or the item count after parsing).
    let context: String
    var title = "Report this scan"
    @State private var showMail = false
    @State private var showShare = false

    static let address = "money-pls@winktech.dev"

    var body: some View {
        Button(title) { if MFMailComposeViewController.canSendMail() { showMail = true } else { showShare = true } }
            .foregroundStyle(Theme.pink)
            .sheet(isPresented: $showMail) { MailComposer(report: report).ignoresSafeArea() }
            .sheet(isPresented: $showShare) { ActivitySheet(items: report.shareItems).ignoresSafeArea() }
    }

    private var report: ScanReport { ScanReport(image: image, trace: trace, context: context) }
}

struct ScanReport {
    let image: UIImage
    let trace: String
    let context: String

    var subject: String { "Money pls: scan report" }
    var body: String {
        """
        What went wrong?
        (Please tell me what the receipt says versus what the app read — a line or two is plenty.)



        The receipt photo and the parse log are attached; remove anything you'd rather not share.

        \(context)
        \(environment)
        """
    }
    var log: String { environment + "\n" + context + "\n\n" + (trace.isEmpty ? "(no parse log)" : trace) }
    var jpeg: Data? { image.jpegData(compressionQuality: 0.85) }

    private var environment: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))"
        return "Money pls \(version) · iOS \(UIDevice.current.systemVersion) · \(ScanReport.model) · \(image.size.width.formatted())×\(image.size.height.formatted())px"
    }
    private static var model: String {
        var sys = utsname(); uname(&sys)
        return withUnsafePointer(to: &sys.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
    }

    /// Files for the share-sheet fallback, so the attachments survive whatever app the user picks.
    var shareItems: [Any] {
        let dir = FileManager.default.temporaryDirectory
        var items: [Any] = [body]
        let logURL = dir.appendingPathComponent("money-pls-parse.log")
        if (try? log.write(to: logURL, atomically: true, encoding: .utf8)) != nil { items.append(logURL) }
        let imgURL = dir.appendingPathComponent("receipt.jpg")
        if let jpeg, (try? jpeg.write(to: imgURL)) != nil { items.append(imgURL) }
        return items
    }
}

struct MailComposer: UIViewControllerRepresentable {
    let report: ScanReport
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([ReportScanButton.address])
        vc.setSubject(report.subject)
        vc.setMessageBody(report.body, isHTML: false)
        if let jpeg = report.jpeg { vc.addAttachmentData(jpeg, mimeType: "image/jpeg", fileName: "receipt.jpg") }
        if let log = report.log.data(using: .utf8) { vc.addAttachmentData(log, mimeType: "text/plain", fileName: "money-pls-parse.log") }
        return vc
    }
    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) { dismiss() }
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
