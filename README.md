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
- **Friends**: the people you split with are friends across bills, picked from Contacts (the system picker, no
  permission prompt) or typed. The Friends tab shows who owes whom, per currency and never converted
  ("$42.10 + €18.00"); a friend's page lists every bill and payment between you; "Settle up" records what came back.
- **Typed expenses**: no receipt? Add an expense — amount, who paid, split equally, by shares or exact — and it becomes a
  bill like any other.
- **Activity and Bills**: every bill and payment newest first; tap the circle on a bill card to mark paid.
- Still no accounts: friends are names, balances are your own ledger, the card is how you ask.

## Build

    brew install xcodegen swiftlint
    cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # DEVELOPMENT_TEAM for device builds, SENTRY_DSN optional
    xcodegen generate
    open MoneyPls.xcodeproj        # or:
    xcodebuild -project MoneyPls.xcodeproj -scheme MoneyPls -destination 'generic/platform=iOS Simulator' build

Fonts (Fredoka, Nunito — OFL) are bundled under `MoneyPls/Resources/Fonts`. Regenerate the icon with
`swift scripts/gen-icon.swift`.

## Simulator notes

- Document segmentation returns nothing in the simulator; the text-cluster fallback kicks in (slower, still correct).
- Seed test photos with `xcrun simctl addmedia <udid> photo.jpeg` and use "Pick from photos".
- Parser logs: `xcrun simctl spawn <udid> log show --info --last 2m --predicate 'subsystem == "dev.winktech.moneypls"'`.

## CI / releases

`test.yaml` lints (`swiftlint --strict`) and compile-checks every push and PR on macOS 26. A green `main`
auto-cuts a versioned release (`release.yaml`, [ai-release-action](https://github.com/Seklfreak/ai-release-action)
proposes the semver bump and writes the notes), and the version tag triggers `testflight.yaml`, which archives with a
stored distribution certificate, uploads dSYMs to Sentry, and ships to TestFlight with the release notes as "What to
Test" — dormant until the App Store Connect secrets listed in that file exist. `testflight-refresh.yaml` re-uploads
the latest tag monthly so the build never hits TestFlight's 90-day expiry. Renovate keeps the Swift package current.

Crash reporting is Sentry (`SENTRY_DSN` build setting, Release builds only, `sendDefaultPii = false`). Receipts and
names never leave the phone — only crashes do.

Analytics is a self-hosted [Umami](https://umami.is) instance, reached directly from
`MoneyPls/Sources/App/Umami.swift` — no SDK, no third party. It records which screens are reached and whether a scan
parsed, plus counts: never a merchant, an item name or an amount. The visitor id is a random UUID per install, gone
when the app is deleted, so there is no IDFA and no tracking prompt. `UMAMI_URL` / `UMAMI_WEBSITE_ID` are build
settings like the Sentry DSN; leaving either empty ships the app without analytics, as Debug builds always do.
