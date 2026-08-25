import SwiftUI
import Translation

/// Translates item names with Apple's on-device Translation framework. iOS asks to download the language
/// pack the first time; after that nothing leaves the phone. Source language is detected per name.
///
/// The session closure is not main-actor isolated, so it only sees plain strings: names go in keyed by item
/// id, translations come back through `results`, and the caller applies them to the models.
struct TranslateNames: ViewModifier {
    @Binding var configuration: TranslationSession.Configuration?
    let names: [String: String]   // item id → name
    @Binding var results: [String: String]
    @Binding var failure: String?

    func body(content: Content) -> some View {
        let names = names
        return content.translationTask(configuration) { session in
            guard !names.isEmpty else { return }
            let requests = names.map { TranslationSession.Request(sourceText: $0.value, clientIdentifier: $0.key) }
            do {
                var out: [String: String] = [:]
                for try await response in session.translate(batch: requests) {
                    if let id = response.clientIdentifier { out[id] = response.targetText }
                }
                results = out
            } catch {
                trace("translation failed: \(error)")
                failure = "Couldn't translate these names on this device. iOS may still be downloading the language, or the pair isn't supported yet."
            }
        }
    }
}

extension View {
    func translateNames(_ configuration: Binding<TranslationSession.Configuration?>, names: [String: String],
                        results: Binding<[String: String]>, failure: Binding<String?>) -> some View {
        modifier(TranslateNames(configuration: configuration, names: names, results: results, failure: failure))
    }
}
