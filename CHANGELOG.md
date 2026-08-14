# Changelog

All notable changes to the UQPAY iOS SDK are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] — 2026-08-14

### Fixed

- **The payment method list could not be scrolled, making methods below the
  fold unreachable — including `card`.** `PaymentListViewController` pins its
  container between the title and the Continue button, so the container's
  height is whatever the sheet leaves over and cannot grow with the row count.
  The table view inside it was pinned to all four container edges with
  `isScrollEnabled = false`, so every row past that height was clipped by
  `clipsToBounds` with no way to reach it. On a merchant account with a dozen
  wallets enabled the customer could not select card at all. The table now
  scrolls.

  `LayoutCompatibilityTests.testPaymentListIsReachable` did not catch this: it
  renders the screen with an empty method list, and with no rows there is
  nothing to clip. The new `PaymentListOrderingTests.testTheMethodListScrolls`
  supplies the missing coverage.

### Changed

- **`card` is now pinned to the top of the payment method list.** The order
  previously came straight from the payment intent's
  `available_payment_method_types`, which placed card below several wallets.
  This is a stable partition, not a sort: only `card` moves, and the wallets
  keep the relative order the API sent. Membership is still entirely the API's
  — the SDK adds and removes nothing.

## [1.0.0] — 2026-08-14

First public release, and the first version published to CocoaPods and tagged
for Swift Package Manager. The notes below cover everything that changed since
the unpublished `1.0.0-rc.1` development cycle.

### Changed

- **The deployment floor is now iOS 15.0** (was 14.0), across `Package.swift`,
  all four podspecs and all three framework targets. The two `#available(iOS
  15.0, *)` fallbacks in the sheet container — the branch that decided how the
  sheet presented itself when `UISheetPresentationController` was unavailable —
  had never been executed on any machine, because no current Xcode ships an
  iOS 14 simulator runtime. They are deleted rather than left as untestable
  code. A new CI job fails the build if the manifests ever disagree about the
  floor again.

### Fixed

- **The wallet QR code could not be reached in landscape, or on a small phone.**
  `WalletQRPaymentViewController` pinned ~490pt of content directly to its view
  with no scroll view; an iPhone in landscape gives the sheet roughly 325pt, and
  `.large` is the largest detent there is. The QR the customer is asked to scan
  and the button that reveals it sat off-screen with no way to get to them.
  The screen now scrolls.
- **The alert's only dismiss button could sit off-screen at accessibility text
  sizes** on a small phone in portrait, and on any phone in landscape.
  `CustomAlertViewController` now scrolls when the card outgrows the screen and
  stays centred whenever it fits.
- **Closing the payment-method list reported nothing to the merchant.** The card
  and wallet screens already reported interactive dismissal, but the list is the
  sheet's root: a customer who opened the sheet, looked at the methods and swiped
  it away left the merchant waiting on a callback that never arrived.
  `paymentSheetDidCancel(_:)` is now reported from there too, still exactly once
  per payment and still suppressed for a payment that already reported an
  outcome (including `PENDING`).
- **Dismissal could target the wrong window on iPad.** Two fallback paths
  resolved the key window from `UIApplication.shared.connectedScenes.first`.
  `connectedScenes` is a `Set` — unordered — so with more than one window of the
  same app on screen (Split View, Stage Manager) that could be a different
  window than the one the customer was paying in. The window is now resolved
  from the view controller itself.
- **Dismissing the sheet mid-payment was reported as a cancellation.** If the
  customer tapped Pay and swiped the sheet away before the confirm answered, the
  SDK cancelled the in-flight task and reported `paymentSheetDidCancel(_:)` —
  but the request had already reached the server and the card could still be
  charged. Worse, the same teardown cancelled the reconciliation watcher, so the
  settlement was never observed. That case now reports
  `paymentSheet(_:paymentDidBecomePending:)` with `.processing`, which is what
  that callback documents, and the SDK keeps polling the intent for ~60 seconds
  **after** the UI is gone so a late settlement still arrives as
  `didCompleteWithResult` / `didFailWithError`. The background poll is owned by
  the `PaymentSheet` instance and stops if you release it.

  *Integration note:* a merchant handling `paymentSheetDidCancel(_:)` for this
  path will now receive `paymentDidBecomePending` instead. Both have default
  protocol implementations, so nothing breaks — but if you release a cart or
  void an order on cancellation, this is the case you were previously getting
  wrong.
- **The keyboard could cover the field the customer just tapped.**
  `setupKeyboardHandling()` was an empty stub and
  `Configuration.Payment.keyboardScrollOffset` was a documented setting wired to
  nothing. The card form now insets for the keyboard's real overlap and scrolls
  the focused field clear, honouring `keyboardScrollOffset`.

### Added

- **A published support matrix** in the README, where every row names what
  verifies it.
- **Layout compatibility tests.** `LayoutCompatibilityTests` renders every
  screen across iPhone SE / iPhone / iPad, portrait and landscape, at default
  and AX5 text sizes, and fails if any control or the QR code ends up
  unreachable — including the case where a scroll view exists but its content
  layout is ambiguous and it scrolls nowhere. `ScrollWrapperBehaviourTests`
  pins the other direction: content that fits must not start scrolling or lose
  its centring.
- **CI now runs every suite on iPad as well as iPhone**, and checks that all
  manifests declare the same deployment floor.
- **Dark mode.** The sheet now follows the device appearance; light mode is
  pixel-identical to previous builds (pinned by test). QR codes deliberately
  stay on a white tile in both modes so scanners keep their contrast. Merchants
  can pin a style with the new `Appearance.userInterfaceStyle` (`.light`
  restores the old behaviour).
- **Dynamic Type and VoiceOver.** Every font scales with the user's text-size
  setting (identical at the default size), fixed heights became minimums, the
  sheet opens full-height at accessibility text sizes, every card-form field
  carries a VoiceOver label, and status screens announce their outcome.
- **Localizability.** All customer-facing copy now resolves through per-module
  `Localizable.strings` (English shipped; a missing entry falls back to the
  English key verbatim). `CardValidationResult.ValidationError` gained a
  localized `errorDescription`; its raw values are frozen as stable codes.
- **`PaymentSheet.paymentReturnedFromBank`** — a typed `Notification.Name` for
  the return-from-bank hand-off (the raw string keeps working).
- **`sheetType: .cardOnly` now works on the UIKit path** — `loadViewController`
  previously ignored it and always built the method list.
- **CI workflow** (`.github/workflows/tests.yml`): all three test schemes plus
  both example-app builds on every push/PR.
- **Stubbed-server integration tests** covering confirm → poll → outcome
  against a scripted transport — the flow the live sandbox exercises, without
  charging real money.
- README troubleshooting guide and real DocC landing pages for all three
  modules.

### Changed

- **Public API lockdown before 1.0.** All view controllers and the internal
  utilities (`UIComponentFactory`, `APIResponseHandler`, `KeyboardToolbarManager`,
  `AnalyticsClient`) are now internal; integrate through `PaymentSheet`. The
  example apps show the supported paths. `UqpayConfigurationExamples` was
  removed from the shipped framework; `PaymentError.recoverySuggestionError`
  (a duplicate of `recoverySuggestion`) was removed.
- **Wallet failures now map through the same error-code table as card
  failures**, so one server response produces one `PaymentError.code` on every
  screen — this also makes `.insufficientFunds`/`.cardDeclined`/`.threeDSFailed`
  reachable from wallet traffic. `PaymentError.ErrorCode` is documented as
  non-exhaustive and now conforms to `CaseIterable`.

### Deprecated

- `UqpayConfiguration.clientSecret` — the payment flow no longer reads it; use
  short-lived tokens from your backend. Will be removed in the next major.

### Fixed

- **A killed app can no longer double-charge on relaunch.** Idempotency pins now
  survive process death: pending confirm attempts (key + frozen device values)
  persist to the Keychain within the server's 24-hour idempotency window, so
  paying again with the same details replays the same request instead of minting
  a fresh key. The payload identity is a stable SHA-256 digest that deliberately
  contains nothing derivable from the full card number or CVC.
- **Leaving the app mid-payment no longer causes spurious timeouts.** The 3DS
  and QR outcome polls count attempts instead of holding a wall-clock deadline,
  so time suspended in a banking or wallet app is not charged against the
  payment. In-flight confirms hold a background-task assertion (~30s of
  protected runtime), and the status screen re-checks immediately when the app
  returns to the foreground.
- **An already-finished payment can no longer be paid again.** Presenting the
  sheet for a SUCCEEDED/CANCELLED/FAILED intent now fails fast with the new
  `PaymentSheetError.intentNotPayable(status:)`, and both confirm paths re-check
  the intent just before sending: a payment that settled before the app was
  killed is reported as its outcome (success screens and delegate callbacks
  included) rather than confirmed a second time. A wallet intent still holding
  an issued QR after relaunch re-serves that QR instead of opening a second
  attempt.

### Added

- `UqpayIdempotencyKey.init(restoring:)` (UqpayCore) — restores a key persisted
  by an earlier launch, verbatim.
- `PaymentSheetError.intentNotPayable(status:)` (UqpayPaymentSheet). **Note for
  exhaustive `switch` statements over `PaymentSheetError`:** this is a new case
  and will require a new arm when you update.

### Planned for `1.0.0`

- Remove `UIComponentFactory` (unused) and `UqpayConfigurationExamples`
  (placeholder-key sample code shipping inside the framework binary).

---

## 1.0.0-rc.1 — 2026-08-12 (never published)

Release candidate that was tagged internally but never pushed to CocoaPods and
never made available to integrators; its tag no longer exists. Kept here as a
development record only — there is no version of this SDK before `1.0.0`.

The payment path was verified end to end against the sandbox for card 3DS and
QR wallet flows at this point.

### Added

- **Prebuilt payment sheet** (`UqpayPaymentSheet`) covering the method list, the
  card form, the in-app 3D Secure step and merchant-presented QR wallets.
- **Fourteen payment methods**, all driven by the payment intent's
  `available_payment_method_types`: card, WeChat Pay, Alipay, Alipay HK, GrabPay,
  PayNow, UnionPay, TrueMoney, Touch 'n Go, GCash, DANA, KakaoPay, Toss and
  Naver Pay.
- **Typed networking layer** (`UqpayHTTPClient`) with a backend-token credential
  model: `UqpayCredentialProvider`, `UqpayBackendTokenProvider` (caches and
  refreshes ahead of expiry) and `UqpayStaticTokenProvider` for tests.
- **Idempotency machinery.** `UqpayIdempotencyKey` (lowercased — the API rejects
  uppercase UUIDs), per-payload attempt pinning, frozen device snapshots and a
  sorted-keys encoder, so replaying an unresolved confirm re-sends
  byte-identical content and cannot become a second charge.
- **Typed errors.** `UqpayAPIError` with `.httpStatus`, `.apiCode` and
  `.isRetryable`, plus `UqpayAPIErrorBody` for the API's structured error body.
- **Forward-compatible status enums.** `UqpayPaymentIntentStatus` and
  `UqpayPaymentAttemptStatus` decode unrecognised server values into
  `.unknown(_:)` so a new status cannot break a shipped app.
- **`PaymentDelegate`** reporting success, failure, cancellation and required
  actions to the merchant app.
- **`paymentSheet(_:paymentDidBecomePending:)`** on `PaymentDelegate` (optional,
  default no-op). Fires when the sheet stops actively driving a payment that is
  still unresolved — the API returned `PENDING`/`PROCESSING`, or a QR /
  authentication poll timed out with the payment possibly live. The merchant's
  app can stop waiting; the webhook settles it. No `paymentSheetDidCancel`
  follows for that payment, and a settlement the SDK still observes is
  delivered through `didCompleteWithResult`/`didFailWithError` as usual.
- `PaymentSheetError.authenticationTimedOut`, thrown by the outcome poll in
  place of an indistinguishable `.failed(String)`.
- **`WalletQRDescriptor`** registry driving every QR wallet from one screen.
- **Structured logging** via `UqpayLogger` with a `logHandler` hook.
- **`PrivacyInfo.xcprivacy` in each module**, shipped through SwiftPM resources
  and CocoaPods resource bundles. They declare the data the SDK actually
  handles — card and billing details, `identifierForVendor` and the device IP
  for 3D Secure risk scoring — with no tracking and no tracking domains. No
  module uses any required-reason API, so every `NSPrivacyAccessedAPITypes`
  list is empty.
- **Two example storefronts** (`Examples/UIKitExample`, `Examples/SwiftUIExample`)
  with a demo merchant backend and end-to-end sandbox UI tests.

### Changed

- **BREAKING —** `UqpayEnvironment` has no default. `environment` must be set
  explicitly or API calls throw `UqpayConfigurationError.environmentNotSet`. The
  SDK never silently falls back to a test server.
- **BREAKING —** `ApiClient.get`/`post` now throw `UqpayAPIError` on any non-2xx
  response instead of returning `(Data, URLResponse)` for every status. An
  unconfigured SDK throws rather than sending an unauthenticated request.
- **BREAKING —** all confirms go through
  `confirmPaymentIntent(paymentIntentId:encodedBody:idempotencyKey:)`, which
  carries the idempotency machinery.
- **BREAKING —** `confirmPaymentIntent`'s `billingDetails:` parameter is gone. It
  was silently ignored; the address the issuer runs AVS against travels inside
  `ConfirmCardDetails.billing`.
- **BREAKING —** `BrowserInfo`, `BrowserDetails`, `MobileInfo` and `LocationInfo`
  initialisers no longer default the device fields. Use
  `BrowserInfo.currentDevice()`.
- The payment method list, its membership and its order now come from the
  payment intent rather than a hardcoded client-side list.
- The six near-identical QR wallet screens were replaced by one descriptor-driven
  screen (−3,663 lines). Two had asked for icon assets that do not exist, and the
  Alipay pair reported a different method type to the merchant than the one they
  confirmed with.
- Card payments that return `display_qr_code` now run through the polling browser
  step, so the outcome is read from the API.

### Removed

- **BREAKING —** `PaymentSheetDelegate`, `PaymentCardDelegate` and
  `PaymentListViewControllerDelegate`, together with the `delegate`,
  `paymentCardDelegate` and `paymentListDelegate` properties on `PaymentSheet`.
  All three were public and settable and had **zero call sites**, so a merchant
  who wired one received nothing at all. `PaymentDelegate` is the only delegate,
  and it now also reports `paymentSheetDidCancel(_:)` — exactly once per
  payment, and never alongside a success or failure — and
  `paymentSheet(_:requiresAction:)` when the customer is handed to a 3D Secure
  challenge or a wallet QR.
- **BREAKING —** `PaymentDelegate`'s `paymentSheetWillPresent(_:)`,
  `paymentSheetDidPresent(_:)`, `paymentSheetWillDismiss(_:)` and
  `paymentSheetDidDismiss(_:)`. They were never called either. Your app presents
  the sheet, so it already knows; SwiftUI users get the `isPresented` binding
  back instead.
- **BREAKING —** `.testingMode` and `.stagingMode`. They pointed at
  UQPAY-internal hosts that had no business shipping in a merchant binary. Use
  `.sandboxMode`, or `UqpayAPIEnvironment.custom(_:)` for internal tooling.
- **BREAKING —** the `UqpayApplePay` module, parked on `feature/apple-pay-v2`.
- **BREAKING —** the `UqpayWeChatPay` native hand-off module, parked on
  `feature/wechat-native-v2`. WeChat Pay remains available through the
  merchant-presented QR flow, which needs no WeChat SDK.

### Fixed

- **`PaymentSheetType.cardOnly` no longer takes a payment and then shows
  nothing.** The SwiftUI card presenter put a bare `PaymentCardViewController`
  on screen with no navigation controller and never set `paymentDelegate` or
  `paymentSheet`. Every receipt, failure and pending screen it tried to push
  resolved against a nil navigation controller and vanished, and no outcome
  reached the merchant. Both sheet types now run through one presenter that
  embeds the payment screen in a navigation controller and wires the delegate.
- **The SwiftUI binding is cleared when the sheet closes.** The SDK dismisses
  its own view controllers; SwiftUI never observed that, so `isPresented` stayed
  `true` and the sheet could not be presented a second time.
- **A delegate assigned after presentation now reaches the payment screens**,
  which is the common SwiftUI ordering.
- **The card form validates before it charges.** It counted digits and nothing
  else; it now runs `PaymentValidationHelper` — the Luhn check, expiry dates in
  the past, and brand-sized security codes — so a mistyped digit or an expired
  card is an inline message instead of an acquirer decline.
- **The billing country is the customer's own ISO selection.** The region field
  was free text run through a nine-entry lookup that returned `US` for anything
  unlisted, so every customer outside those nine markets had the wrong
  `country_code` sent to the issuer for AVS and risk scoring. It is now a picker
  over the full ISO 3166-1 alpha-2 list, defaulting to the device's region.
- **19-digit UnionPay card numbers can be entered.** The field capped input at
  16 digits.
- **The deployment target is genuinely iOS 14.0.** The module targets declared
  iOS 14 (and `Package.swift` advertised it) while the code did not compile
  below iOS 17, so any SPM or CocoaPods consumer targeting iOS 14–16 hit a build
  error rather than a warning. Three unguarded APIs caused it, all now availability-gated:
  - `UIComponentFactory.createCVCField` used `.creditCardSecurityCode` (iOS 17).
    Below iOS 17 the field is left untyped — there is no equivalent content type,
    so autofill simply does not offer the security code.
  - `PaymentSheet.Appearance.CardBrandColors.visa` defaulted to `.systemCyan`
    (iOS 15). Earlier releases get its light-mode value, so the default is
    visually identical.
  - The SwiftUI presenter applied `.presentationDetents` (iOS 16) unguarded.
  The Xcode project targets, which had drifted to iOS 26.0, are back to 14.0.
- **SwiftUI sheet detents now take effect.** `presentationDetents` and
  `presentationDragIndicator` were attached to the presenting view rather than
  the sheet's content, where they do nothing. They now sit on the sheet content,
  guarded for iOS 16.
- **Removed every fake-success path.** The sheet previously showed
  "your payment has been received" without consulting the API. Outcomes are now
  always re-read from the payment intent.
- **Every confirm-response status now reports to the merchant exactly once.**
  `FAILED` and `CANCELLED` updated the customer's screen and told the merchant
  nothing — and the dismissal fallback could not save it, because a status
  screen pushed on top swallows the card screen's `viewDidDisappear`. A
  declined payment now delivers `didFailWithError` the moment it is known,
  carrying the attempt's `failure_code`.
- `PROCESSING` with no status screen on the stack was a complete no-op: the Pay
  button stayed disabled on "Processing..." forever. It now shows the
  processing screen, reports pending, keeps the bounded settlement watcher
  running and re-enables the button.
- `PENDING` reported nothing and stopped watching. It now reports pending and
  keeps the bounded watcher on the intent so a settlement inside the window is
  still delivered.
- The raw card-QR screen built its timeout explanation, discarded it, and
  silently popped back to the card form after ten minutes. It now parks on a
  pending screen with a working Refresh button and reports pending; its failure
  branches report `didFailWithError` instead of only pushing a failure screen.
- Raw EMVCo `qr_code` payloads render locally in the wallet screen. They were
  fed to the image downloader, which "succeeded" in parsing them as schemeless
  relative URLs and then failed with "unsupported URL" — relevant to PayNow and
  every EMVCo-native wallet.
- The wallet QR timeout screen said "Refresh to check the status" while the
  refresh button stayed hidden — it was never given the intent id. Refresh now
  works, the merchant hears `paymentDidBecomePending`, and an outcome the
  refresh poll discovers is reported through the delegate.
- A wallet intent that returns to `PENDING`/`REQUIRES_CUSTOMER_ACTION` after
  the scan is no longer reported to the merchant as a failure.
- 3D Secure results are resolved by polling the intent, never inferred from the
  browser step closing. Return-URL query parameters are ignored — anyone able to
  craft the return URL can write them.
- 3D Secure failures are no longer uniformly reported as `.cardDeclined`:
  timeouts map to `.timeout`, customer cancellations to `.cancelled`, and
  declined authentications carry the attempt's `failure_code` through the same
  mapping the non-3DS path uses.
- Pending and cancelled status screens keep the transaction id and amount;
  `transitionFromPending` dropped both, leaving customers with no reference to
  quote.
- An unobserved confirm is reported as pending, never as failure, and a bounded
  watcher keeps polling so a late settlement is still reported.
- Card data and QR image URLs now travel on ephemeral `URLSession`s, so request
  and response bodies are never written to the shared on-disk URL cache. The 3DS
  web view uses a non-persistent data store.
- Confirm requests send only measured device data. The previous defaults
  (1920×1080, `"iOS 14.5"`, lat/lon `0`) were fabrications that poisoned 3DS risk
  scoring.
- The production host was corrected.
- `PaymentSheetError` gained `errorDescription`, so the message carried by
  `.failed` is no longer discarded by `localizedDescription`.
- Payment brand marks render instead of blue placeholder squares.

### Distribution

- Every module loads its asset catalog through one channel-aware bundle
  accessor (`Bundle.module` under SwiftPM), so images render for SPM consumers.
  Nine `Bundle(for:)` call sites returned the host app's bundle under static
  linking and every image silently missed.
- **Each module ships as its own CocoaPods pod** — `UqpayCore`,
  `UqpayPayments` and `UqpayPaymentSheet` — with `UqpaySDK` as an umbrella pod
  depending on all three. They were previously subspecs of a single `UqpaySDK`
  pod, and CocoaPods compiles every subspec of a pod into **one** module, so the
  sources' `import UqpayCore` / `import UqpayPayments` could not resolve and the
  pod did not build at all. The `import` statements are now identical on
  CocoaPods and SwiftPM.

### Security

- The SDK never accepts an `x-api-key`. That key can issue refunds and payouts,
  and Global Acquiring allows only one active token per merchant — a device that
  mints its own tokens invalidates every other device and the merchant's own
  backend. Tokens are issued by the merchant's backend.
- The Keychain payment context (which carries a client secret mid-payment) is
  stored `ThisDeviceOnly`, so it cannot ride an encrypted backup onto another
  device.
- Card QR URLs handed to the browser step must be `https`; a plain-`http` QR
  URL is now rejected instead of loaded.
- Unified-log messages are marked `%{private}` (Apple's own default for
  dynamic strings), so release log lines cannot be read off a customer's
  device with a cable and Console.app. Debug builds still print in full, and
  the `logHandler` hook receives every message unredacted.
- The 3DS resolution failure log no longer interpolates the raw `Error` — a
  `URLError` description carries the failing URL, and with it the payment
  intent id.
- Credentials are no longer read from hardcoded literals in example code;
  `DemoSecrets.plist` is git-ignored.

[1.0.1]: https://github.com/uqpay/uqpay-ios-sdk/releases/tag/1.0.1
[1.0.0]: https://github.com/uqpay/uqpay-ios-sdk/releases/tag/1.0.0
