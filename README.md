# Money pls

Scan the receipt, tap who had what, send everyone their share. iOS 26, iPhone only.

Everything runs on the phone — no accounts, no server, no per-receipt AI cost:

- **Capture**: VisionKit document camera (auto-crop + deskew) or a photo from the library.
- **Read**: Vision `DetectDocumentSegmentationRequest` crop (with a text-cluster fallback) → `RecognizeTextRequest` at full
  resolution in four rotations → phrase/price line builder that tolerates curved receipts → deterministic parser
  (`Parsing/ReceiptParser.swift`). Validated exact on real handheld photos: bilingual hot-pot receipt, dot-matrix,
  dark Toast print, Eataly with `× 3` lines.
- **Repair**: only when items don't add up to the printed subtotal, Foundation Models (on-device, Apple Intelligence)
  gets one try, and its answer is used only if it reconciles better (`Parsing/ReceiptRepair.swift`).
- **Split**: everything is shared unless you tap it; tax + tip pro-rata on each person's items; cents always sum exactly.
- **Share**: a rendered card image + plain text through the system share sheet. No links, no payment handles.
- **History**: SwiftData; "usual suspects" come from earlier splits; tap the circle on a bill card to mark paid.

## Build

    brew install xcodegen
    cp Config/Local.xcconfig.example Config/Local.xcconfig   # add your DEVELOPMENT_TEAM for device builds
    xcodegen generate
    open MoneyPls.xcodeproj        # or:
    xcodebuild -project MoneyPls.xcodeproj -scheme MoneyPls -destination 'generic/platform=iOS Simulator' build

Fonts (Fredoka, Nunito — OFL) are bundled under `MoneyPls/Resources/Fonts`. Regenerate the icon with
`swift scripts/gen-icon.swift`.

## Simulator notes

- Document segmentation returns nothing in the simulator; the text-cluster fallback kicks in (slower, still correct).
- Seed test photos with `xcrun simctl addmedia <udid> photo.jpeg` and use "Pick from photos".
- Parser logs: `xcrun simctl spawn <udid> log show --info --last 2m --predicate 'subsystem == "dev.winktech.moneypls"'`.
