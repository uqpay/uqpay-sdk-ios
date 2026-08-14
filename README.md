# UQPAY iOS SDK

![Platform](https://img.shields.io/badge/platform-iOS%2015.0%2B-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

Accept card payments (with 3D Secure) and regional QR wallets inside your iOS app.
The SDK ships a prebuilt payment sheet you can present in a few lines, and a typed
API client for integrations that need their own UI.

> [!IMPORTANT]
> **`1.0.0` is the first stable release.** The payment engine is sandbox-verified
> end to end for card 3DS and QR wallet flows. A short list of documented
> constraints still applies — read [Known limitations](#known-limitations) before
> you ship to production.

Table of contents
=================

- [Requirements](#requirements)
- [Installation](#installation)
  - [Swift Package Manager](#swift-package-manager)
  - [CocoaPods](#cocoapods)
  - [Modules](#modules)
- [How a payment works](#how-a-payment-works)
- [Integration](#integration)
  - [Step 1 — Your backend issues the token and the intent](#step-1--your-backend-issues-the-token-and-the-intent)
  - [Step 2 — Configure the SDK](#step-2--configure-the-sdk)
  - [Step 3 — Hand the payment to the SDK](#step-3--hand-the-payment-to-the-sdk)
  - [Step 4 — Present the payment sheet](#step-4--present-the-payment-sheet)
  - [Step 5 — Receive the result](#step-5--receive-the-result)
  - [SwiftUI](#swiftui)
- [3D Secure and return URLs](#3d-secure-and-return-urls)
- [Payment methods](#payment-methods)
- [Appearance](#appearance)
- [Low-level API integration](#low-level-api-integration)
  - [Present a single payment method](#present-a-single-payment-method)
  - [Confirm a card payment yourself](#confirm-a-card-payment-yourself)
  - [Idempotency and retries](#idempotency-and-retries)
  - [Read a payment's status](#read-a-payments-status)
  - [Call the API directly](#call-the-api-directly)
- [Validating card input](#validating-card-input)
- [Error handling](#error-handling)
- [Logging](#logging)
- [Testing](#testing)
- [Security](#security)
- [Known limitations](#known-limitations)
- [Example apps](#example-apps)
- [Migrating from earlier builds](#migrating-from-earlier-builds)
- [License](#license)

## Requirements

- iOS 15.0+
- Xcode 15.4+
- Swift 5.9+
- A UQPAY merchant account ([sandbox credentials](https://developer.uqpay.com))

## Support matrix

Every row names what verifies it. A row the SDK cannot demonstrate is not
listed as supported.

| | Supported | Verified by |
|---|---|---|
| iOS | 15.0 – 26.x | CI builds at the declared floor; `deployment-floor` job fails if the manifests disagree |
| Devices | iPhone and iPad, 320pt width and up | `LayoutCompatibilityTests` renders every screen at 320/393/834pt; CI runs the full suite on both idioms |
| Orientation | Portrait and landscape, following the host app | `LayoutCompatibilityTests` asserts every control stays reachable in both |
| Split View / Stage Manager | Supported | Dismissal resolves the window from the controller, never from an arbitrary scene |
| Appearance | Light, dark, or pinned by the merchant | `DarkModeAppearanceTests` |
| Dynamic Type | Up to AX5 (`accessibilityExtraExtraExtraLarge`) | `AccessibilityDynamicTypeTests`, plus AX5 cases in `LayoutCompatibilityTests` |
| Keyboard | Form insets and scrolls the focused field clear | `KeyboardAvoidanceTests` |
| Distribution | Swift Package Manager, CocoaPods | Example apps build in CI against both |

The SDK never forces an orientation on your app. It renders correctly in
whatever orientations your app declares — so if you support landscape, so does
the payment sheet.

**iOS 15.0 caveat.** The floor is verified by compilation and by the manifest
consistency check, not by execution: current Xcode releases no longer ship an
iOS 15 simulator runtime. Running the suites on an iOS 15 device is a manual
gate before tagging a release, and CI emits a warning to that effect on every
run.

## Installation

### Swift Package Manager

In Xcode, choose **File → Add Package Dependencies…** and enter:

```
https://github.com/uqpay/uqpay-sdk-ios
```

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/uqpay/uqpay-sdk-ios", from: "1.0.0")
]
```

Then add the products you need to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "UqpaySDK", package: "uqpay-sdk-ios")
    ]
)
```

### CocoaPods

```ruby
# Everything (recommended) — an umbrella pod that pulls in all three modules
pod 'UqpayiOSSDK', '~> 1.0'

# Or pick individual modules — each brings its own dependencies
pod 'UqpayCore',         '~> 1.0'
pod 'UqpayPayments',     '~> 1.0'
pod 'UqpayPaymentSheet', '~> 1.0'
```

The three module pods pin each other to the exact same version, so mixing
versions across them is not possible.

> [!NOTE]
> The CocoaPods umbrella is `UqpayiOSSDK`, while the Swift Package Manager
> product above is `UqpaySDK`. The names differ because an unrelated, abandoned
> `UQPAYSDK` pod from 2019 still occupies that name on CocoaPods trunk, whose
> name matching is case-insensitive. The two are the same thing; only the
> package-manager namespaces differ.

Each module is a separate pod because each is a separate Swift module, so the
`import` statements are identical on both CocoaPods and Swift Package Manager.

### Modules

| Module | Description | Depends on |
|---|---|---|
| **UqpayCore** | Configuration, typed networking (`UqpayHTTPClient`), credentials, errors, logging. | — |
| **UqpayPayments** | Payment models, confirm request/response types, card validation, device info. | UqpayCore |
| **UqpayPaymentSheet** | The prebuilt payment UI: method list, card form, 3DS web step, QR wallet screens. | UqpayCore, UqpayPayments |
| **UqpaySDK** (SPM) / **UqpayiOSSDK** (CocoaPods) | Umbrella containing all three. Ships no source of its own. | — |

> [!NOTE]
> Apple Pay (`UqpayApplePay`) and the native in-app WeChat Pay hand-off
> (`UqpayWeChatPay`) are **not part of this release**. They are parked on the
> `feature/apple-pay-v2` and `feature/wechat-native-v2` branches. WeChat Pay is
> still supported in this release through the merchant-presented QR flow, which
> needs no WeChat SDK.

## How a payment works

Responsibilities are split deliberately. **Your server holds the API key; the app
never does.**

```
┌─────────────┐   1. checkout      ┌──────────────┐   2. POST /connect/token   ┌───────┐
│   Your app  │ ─────────────────► │ Your backend │ ─────────────────────────► │ UQPAY │
│             │                    │              │   3. POST /payment_intents │       │
│             │ ◄───────────────── │  (x-api-key) │ ◄───────────────────────── │       │
└─────────────┘  4. auth_token +   └──────────────┘                            └───────┘
       │            payment_intent_id + client_id
       │
       │ 5. UqpayConfiguration.shared.headerToken / .paymentIntentId / .clientId
       ▼
┌─────────────┐   6. POST /payment_intents/{id}/confirm                        ┌───────┐
│  UQPAY SDK  │ ────────────────────────────────────────────────────────────►  │ UQPAY │
│             │      7. 3DS / QR, then poll the intent for the outcome         │       │
└─────────────┘ ◄──────────────────────────────────────────────────────────    └───────┘
       │
       │ 8. PaymentDelegate callback (a UI signal)
       ▼                                              ┌──────────────┐
   Your app shows the receipt      ◄───── webhook ─── │ Your backend │  ← the authority
                                                      └──────────────┘
```

> [!WARNING]
> **Never put your `x-api-key` in the app.** It can issue refunds and payouts, and
> an app binary cannot keep a secret. Global Acquiring also allows only **one
> active access token per merchant** — a newly issued token immediately
> invalidates the previous one, so a device that mints its own tokens logs out
> every other device and your own backend.

> [!IMPORTANT]
> Treat the delegate callback as a **UI signal only**. The authoritative outcome
> reaches your backend by webhook (`acquiring.payment_intent.succeeded`). Confirm
> server-side before you ship goods — a device can lose connectivity or be
> tampered with at any point in the flow.

## Integration

### Step 1 — Your backend issues the token and the intent

Two calls, both from your server, both authenticated with your `x-api-key`:

| Call | Purpose | Returns |
|---|---|---|
| `POST /api/v1/connect/token` | Exchange the API key for a ~30-minute access token. | `auth_token`, `expired_at` |
| `POST /api/v2/payment_intents/create` | Create the payment for the real price. | `payment_intent_id`, `client_secret`, `intent_status` |

Expose one route to your app that returns what the SDK needs — and nothing more:

```jsonc
// GET https://your-api.example.com/checkout/session   (authenticated with YOUR user session)
{
  "client_id":         "your_uqpay_client_id",
  "auth_token":        "eyJhbGciOi…",
  "expired_at":        1765941179,
  "payment_intent_id": "int_1a2b3c4d5e",
  "client_secret":     "cs_1a2b3c4d5e"
}
```

> [!IMPORTANT]
> Your backend decides the amount. Never let the app choose it — a customer can
> change anything the app sends. Amounts are **decimal strings in major units**
> (`"8.98"`), never minor units: do not multiply by 100.

### Step 2 — Configure the SDK

Set the environment once, at app start. There is no default — API calls throw
`UqpayConfigurationError.environmentNotSet` if you skip this.

```swift
import UIKit
import UqpayCore

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UqpayConfiguration.shared.environment = .sandboxMode   // or .productionMode

        // Where 3D Secure returns to. Register this scheme in your Info.plist.
        UqpayConfiguration.shared.appReturnScheme = "yourapp://payment"

        return true
    }
}
```

| Environment | Host |
|---|---|
| `.sandboxMode` | `https://api-sandbox.uqpaytech.com` |
| `.productionMode` | `https://api.uqpay.com` |

### Step 3 — Hand the payment to the SDK

Fetch the session from your backend, then write the three values the SDK reads.

> [!IMPORTANT]
> `clientId`, `headerToken` and `paymentIntentId` are **all three required** before
> you present the sheet. The SDK reads them from `UqpayConfiguration.shared` on
> every API call: `headerToken` becomes the `x-auth-token` header, `clientId`
> becomes `x-client-id`, and `paymentIntentId` selects the payment to confirm.
> Miss any one and the flow fails with `PaymentSheetError.failed`.

```swift
import UqpayCore

struct CheckoutSession: Decodable {
    let clientId: String
    let authToken: String
    let paymentIntentId: String
    let clientSecret: String

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case authToken = "auth_token"
        case paymentIntentId = "payment_intent_id"
        case clientSecret = "client_secret"
    }
}

func startCheckout() async throws {
    var request = URLRequest(url: URL(string: "https://your-api.example.com/checkout/session")!)
    request.setValue(yourUserSessionToken, forHTTPHeaderField: "Authorization")

    let (data, _) = try await URLSession.shared.data(for: request)
    let session = try JSONDecoder().decode(CheckoutSession.self, from: data)

    UqpayConfiguration.shared.clientId              = session.clientId
    UqpayConfiguration.shared.headerToken           = session.authToken
    UqpayConfiguration.shared.paymentIntentId       = session.paymentIntentId
    UqpayConfiguration.shared.clientSecretForPayment = session.clientSecret
}
```

> [!NOTE]
> These values are **per payment**, and they live on a shared singleton. Set them
> immediately before presenting the sheet, and do not run two payments
> concurrently in one app process.

### Step 4 — Present the payment sheet

`loadViewController` fetches the methods enabled for this intent, then hands you a
view controller to present. It runs on the main actor and reports failures instead
of handing back a blank sheet.

```swift
import UIKit
import UqpayCore
import UqpayPaymentSheet

final class CheckoutViewController: UIViewController {

    private var paymentSheet: PaymentSheet?

    @IBAction func payButtonTapped() {
        let configuration = PaymentSheet.Configuration(
            merchantDisplayName: "ACME Store",
            environment: .sandboxMode
        )

        let appearance = PaymentSheet.Appearance(primaryColor: .systemBlue)

        let sheet = PaymentSheet(configuration: configuration, appearance: appearance)
        sheet.paymentDelegate = self
        paymentSheet = sheet

        sheet.loadViewController { [weak self] result in
            switch result {
            case .success(let viewController):
                self?.present(viewController, animated: true)
            case .failure(let error):
                self?.showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Payment", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
```

> [!TIP]
> Keep a strong reference to the `PaymentSheet`. `paymentDelegate` is `weak`, and
> the sheet is what carries it into the payment screens.

`PaymentSheet.Configuration` accepts:

| Parameter | Type | Default |
|---|---|---|
| `merchantDisplayName` | `String` | `"Merchant"` |
| `allowsDelayedPaymentMethods` | `Bool` | `false` |
| `environment` | `UqpayEnvironment?` | `nil` — falls back to `UqpayConfiguration.shared.environment` |
| `spacing` | `Configuration.Spacing` | default metrics |
| `dimensions` | `Configuration.Dimensions` | default metrics |
| `payment` | `Configuration.Payment` | default metrics |

### Step 5 — Receive the result

Conform to `PaymentDelegate`. Only two methods are required; the rest have
no-op default implementations.

```swift
import UqpayPaymentSheet

extension CheckoutViewController: PaymentDelegate {

    func paymentSheet(_ paymentSheet: PaymentSheet, didCompleteWithResult result: PaymentResult) {
        // A UI signal. Confirm server-side from the webhook before fulfilling.
        print("Paid \(result.amount) \(result.currency), intent \(result.paymentIntentId)")
    }

    func paymentSheet(_ paymentSheet: PaymentSheet, didFailWithError error: PaymentError) {
        // `error.code` categorises the failure; `error.declineCode` carries the
        // acquirer's raw code when there is one.
        showError(error.message)
    }

    // Optional. Fires once when the customer leaves without paying — never
    // alongside a success, failure or pending report for the same payment.
    func paymentSheetDidCancel(_ paymentSheet: PaymentSheet) {
        print("Customer cancelled")
    }

    // Optional. Fires when the customer is handed to an external step, so you
    // can pause your own UI. The SDK presents the step and reports the outcome
    // through the methods above.
    func paymentSheet(_ paymentSheet: PaymentSheet, requiresAction action: RequiredAction) {
        switch action {
        case .authenticate3DS: print("3D Secure challenge")
        case .scanQRCode:      print("Waiting for a wallet scan")
        default:               break
        }
    }

    // Optional. Fires when the sheet stops driving the payment while it is
    // still unresolved — the API said PENDING, or a QR/authentication step
    // timed out with the payment possibly still live. Stop your spinner and
    // wait for the webhook; no `paymentSheetDidCancel` follows. If the SDK
    // observes the settlement while the sheet stays open, `didCompleteWithResult`
    // or `didFailWithError` is still delivered.
    func paymentSheet(_ paymentSheet: PaymentSheet, paymentDidBecomePending result: PaymentResult) {
        print("Payment \(result.paymentIntentId) is pending — webhook will settle it")
    }
}
```

> [!NOTE]
> `PaymentDelegate` is the **only** delegate the SDK calls. Three others were
> once exposed on `PaymentSheet` — `delegate`, `paymentCardDelegate` and
> `paymentListDelegate` — and none of them had a single call site, so merchants
> who wired one received nothing at all. They have been removed rather than
> left as a trap.

`PaymentResult` carries:

| Property | Type |
|---|---|
| `paymentIntentId` | `String` |
| `paymentMethodType` | `String` — `"card"`, `"grabpay"`, `"wechatpay"`, … |
| `status` | `PaymentStatus` |
| `amount` | `Double` |
| `currency` | `String` |
| `merchantOrderId` | `String?` |
| `transactionId` | `String?` |
| `completedAt` | `Date?` |
| `metadata` | `[String: Any]?` |
| `receiptUrl` | `String?` |

`PaymentStatus` is one of `.succeeded`, `.failed`, `.cancelled`, `.pending`,
`.processing`, `.requiresAction`.

### SwiftUI

Use the `uqpayPaymentSheet` modifier. The binding is cleared automatically when
the sheet closes — whether the customer dismissed it or the SDK did — so it can
be presented again without any extra bookkeeping.

```swift
import SwiftUI
import UqpayCore
import UqpayPaymentSheet

struct CheckoutView: View {

    @StateObject private var handler = PaymentHandler()
    @State private var isShowingPaymentSheet = false

    // Held for the lifetime of the view: `paymentDelegate` is weak.
    private let sheet: PaymentSheet

    init() {
        let configuration = PaymentSheet.Configuration(
            merchantDisplayName: "ACME Store",
            environment: .sandboxMode
        )
        sheet = PaymentSheet(
            configuration: configuration,
            appearance: PaymentSheet.Appearance(primaryColor: .systemBlue)
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            Button("Pay") {
                sheet.paymentDelegate = handler
                isShowingPaymentSheet = true
            }
            Text(handler.message)
        }
        .uqpayPaymentSheet(isPresented: $isShowingPaymentSheet, sheet: sheet)
    }
}

@MainActor
final class PaymentHandler: ObservableObject, PaymentDelegate {
    @Published var message = ""

    nonisolated func paymentSheet(_ paymentSheet: PaymentSheet, didCompleteWithResult result: PaymentResult) {
        Task { @MainActor in message = "Paid \(result.amount) \(result.currency)" }
    }

    nonisolated func paymentSheet(_ paymentSheet: PaymentSheet, didFailWithError error: PaymentError) {
        Task { @MainActor in message = error.message }
    }

    nonisolated func paymentSheetDidCancel(_ paymentSheet: PaymentSheet) {
        Task { @MainActor in message = "Cancelled" }
    }
}
```

To show only the card form, pass `sheetType: .cardOnly` — or construct the sheet
with `PaymentSheet(sheetType: .cardOnly)`, which the modifier picks up on its own:

```swift
struct CardOnlyCheckoutView: View {

    @State private var isShowingCardForm = false
    private let sheet = PaymentSheet()

    var body: some View {
        Button("Pay by card") { isShowingCardForm = true }
            .uqpayPaymentSheet(
                isPresented: $isShowingCardForm,
                sheet: sheet,
                sheetType: .cardOnly
            )
    }
}
```

## 3D Secure and return URLs

The SDK runs the 3DS step in an in-app `WKWebView` with a non-persistent data
store. You do not need to handle the redirect yourself — but you do need to tell
the SDK which URL marks the end of the browser step:

```swift
UqpayConfiguration.shared.appReturnScheme = "yourapp://payment"
```

Register that scheme in your **Info.plist**:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array><string>yourapp</string></array>
    </dict>
</array>
```

If your app is reopened by that URL, post the SDK's notification so an in-flight
payment reconciles immediately:

```swift
func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
) -> Bool {
    if url.scheme == "yourapp" {
        NotificationCenter.default.post(name: PaymentSheet.paymentReturnedFromBank, object: nil)
        return true
    }
    return false
}
```

> [!NOTE]
> Reaching the return URL means only that the browser step **ended** — never that
> the payment succeeded. The SDK ignores any `status=…` query parameters (anyone
> who can craft the return URL can write them) and re-reads the intent from the
> API instead.

## Payment methods

The sheet renders exactly what `available_payment_method_types` on the payment
intent says, in the order the API returns it. Nothing is decided client-side; a
type this SDK version cannot render is hidden rather than breaking the sheet.

| API type | `PaymentMethodType` | Checkout flow |
|---|---|---|
| `card` | `.card` | Card form, with 3D Secure |
| `wechatpay` | `.wechat` | Merchant-presented QR |
| `alipaycn` | `.alipay` | Merchant-presented QR |
| `alipayhk` | `.alipayHK` | Merchant-presented QR |
| `grabpay` | `.grabPay` | Merchant-presented QR |
| `paynow` | `.payNow` | Merchant-presented QR |
| `unionpay` | `.unionPay` | Merchant-presented QR |
| `truemoney` | `.trueMoney` | Merchant-presented QR |
| `tng` | `.touchNGo` | Merchant-presented QR |
| `gcash` | `.gcash` | Merchant-presented QR |
| `dana` | `.dana` | Merchant-presented QR |
| `kakaopay` | `.kakaoPay` | Merchant-presented QR |
| `tosspay` | `.toss` | Merchant-presented QR |
| `naverpay` | `.naverPay` | Merchant-presented QR |

QR wallets are asynchronous: the customer scans in another app, so the SDK polls
the intent (up to 10 minutes) and reports the outcome when the scan resolves it.

## Appearance

```swift
let appearance = PaymentSheet.Appearance(
    cornerRadius: 12,
    primaryColor: UIColor(red: 0.486, green: 0.302, blue: 1.0, alpha: 1.0),
    backgroundColor: .systemBackground
)

// Individual surfaces can be overridden after construction.
appearance.payButtonColor = .systemBlue
appearance.payButtonTextColor = .white
appearance.fieldBorderColor = .systemGray5
appearance.titleColor = .label
appearance.cardBrand.visa = UIColor(red: 0, green: 0.22, blue: 0.65, alpha: 1)
```

`primaryColor` drives the pay button, selection highlights and the loading
indicator. The SDK default is violet (`#7C4DFF`).

## Low-level API integration

### Present a single payment method

Skip the method list and go straight to one wallet:

```swift
import UIKit
import UqpayPayments
import UqpayPaymentSheet

func presentGrabPay(from presenter: UIViewController, delegate: PaymentDelegate) {
    guard let descriptor = WalletQRDescriptor.descriptor(for: .grabPay) else { return }

    let wallet = WalletQRPaymentViewController(descriptor: descriptor)
    wallet.paymentDelegate = delegate

    presenter.present(UINavigationController(rootViewController: wallet), animated: true)
}
```

Or the card form on its own:

```swift
func presentCardForm(from presenter: UIViewController, delegate: PaymentDelegate) {
    let card = PaymentCardViewController()
    card.paymentDelegate = delegate

    // The card screen pushes its own status screens, so it needs a
    // navigation controller. Presenting it bare leaves the customer
    // with no receipt and no failure screen.
    presenter.present(UINavigationController(rootViewController: card), animated: true)
}
```

### Confirm a card payment yourself

For a fully custom card UI, build the confirm body and send it through the SDK's
single transport, which carries the idempotency machinery.

```swift
import UqpayCore
import UqpayPayments
import UqpayPaymentSheet

@MainActor
func payWithCard() async throws {
    let apiClient = try ApiClient.forConfiguredEnvironment()

    let billing = BillingDetails(
        firstName: "John",
        lastName: "Doe",
        email: "john.doe@example.com",
        phoneNumber: "+6591234567",
        address: Address(
            countryCode: "SG",          // ISO 3166-1 alpha-2
            state: "Singapore",
            city: "Singapore",
            street: "1 Raffles Place",
            postcode: "048616"
        )
    )

    let cardDetails = ConfirmCardDetails(
        cardName: "John Doe",
        cardNumber: "5521970079998012",
        expiryMonth: "12",
        expiryYear: "2030",             // four digits
        cvc: "123",
        network: "mastercard",
        billing: billing,
        autoCapture: true,
        authorizationType: "authorization",
        threeDsAction: "enforce_3ds",   // or "skip_3ds"
        threeDs: nil
    )

    let response = try await apiClient.confirmPaymentIntent(
        paymentIntentId: UqpayConfiguration.shared.paymentIntentId ?? "",
        cardDetails: cardDetails
    )

    switch response.intentStatus {
    case "SUCCEEDED", "REQUIRES_CAPTURE":
        print("Authorized")
    case "REQUIRES_CUSTOMER_ACTION":
        // response.nextAction carries the 3DS step to present.
        print("3DS required: \(response.nextAction?.actionType ?? "unknown")")
    default:
        print("Status: \(response.intentStatus)")
    }
}
```

> [!NOTE]
> `confirmPaymentIntent(paymentIntentId:cardDetails:)` is `@MainActor` because it
> reads real device values (`UIScreen`, `UIDevice`) for the 3DS risk payload. The
> SDK never fabricates these — canned values poison risk scoring.

### Idempotency and retries

A confirm can end three ways: answered definitively, never answered, or
cancelled. Only the middle case is dangerous — the payment may have been
processed even though you never saw the response.

```swift
import UqpayCore
import UqpayPayments
import UqpayPaymentSheet

@MainActor
func confirmWithRetry(paymentIntentId: String, request: ConfirmPaymentIntentRequest) async {
    let apiClient: ApiClient
    do { apiClient = try ApiClient.forConfiguredEnvironment() } catch { return }

    // Mint the key ONCE, outside the retry loop, and encode the body once.
    // Reusing both means a replay can never become a second charge.
    let idempotencyKey = UqpayIdempotencyKey()
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys      // byte-identical re-encodes
    guard let body = try? encoder.encode(request) else { return }

    for attempt in 0..<3 {
        do {
            let response = try await apiClient.confirmPaymentIntent(
                paymentIntentId: paymentIntentId,
                encodedBody: body,
                idempotencyKey: idempotencyKey
            )
            print("Settled: \(response.intentStatus)")
            return
        } catch let error as UqpayAPIError where error.isRetryable {
            try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
        } catch {
            // Definitive rejection — stop.
            print("Failed: \(error.localizedDescription)")
            return
        }
    }
}
```

> [!WARNING]
> Never mint a fresh `UqpayIdempotencyKey` for a retry of an unresolved confirm,
> and never re-encode the body from freshly-read device values. The server
> replays a key only for byte-identical content; anything else is a new charge.
> `UqpayIdempotencyKey` lowercases its UUID because the API rejects uppercase.

### Read a payment's status

```swift
import UqpayCore
import UqpayPayments

func checkStatus(paymentIntentId: String) async throws {
    let apiClient = try ApiClient.forConfiguredEnvironment()
    let intent = try await apiClient.getPaymentIntentById(paymentIntentId)

    print(intent.intentStatus)             // "SUCCEEDED", "REQUIRES_CAPTURE", …
    print(intent.amount, intent.currency)  // "8.98", "SGD"
    print(intent.latestPaymentAttempt?.failureCode ?? "no failure")
}
```

### Call the API directly

For endpoints the SDK does not wrap, use `UqpayHTTPClient`. It attaches
credentials, sets the idempotency header on mutating calls, and retries once on a
`401` after invalidating the token.

```swift
import UqpayCore

func makeClient(tokenEndpoint: URL, userSession: String, clientID: String) -> UqpayHTTPClient {
    // Fetches short-lived tokens from YOUR backend and caches them until
    // shortly before expiry. Never give the SDK your x-api-key.
    let credentials = UqpayBackendTokenProvider(
        endpoint: tokenEndpoint,
        decorate: { request in
            request.setValue(userSession, forHTTPHeaderField: "Authorization")
        }
    )

    return UqpayHTTPClient(
        environment: .sandbox,      // .sandbox, .production, or .custom(URL)
        clientID: clientID,
        credentials: credentials
    )
}

func fetchIntent(_ client: UqpayHTTPClient, id: String) async throws -> UqpayPaymentIntent {
    try await client.send(.get("api/v2/payment_intents/\(id)"))
}
```

`UqpayPaymentIntent` decodes unknown server statuses into
`UqpayPaymentIntentStatus.unknown(_:)`, so a new status cannot break a shipped
app:

```swift
func inspect(_ intent: UqpayPaymentIntent) {
    if intent.intentStatus.isTerminal { /* succeeded, cancelled or failed */ }
    if intent.intentStatus.needsCustomerAction { /* 3DS or a wallet scan */ }

    let amount: Decimal? = intent.amountDecimal   // "8.98" parsed for arithmetic
    print(amount as Any)
}
```

## Validating card input

If you build your own card form, validate before confirming — a typo becomes an
acquirer decline otherwise.

```swift
import UqpayPayments

let result = PaymentValidationHelper.validateCard(
    cardNumber: "5521 9700 7999 8012",
    expiryText: "12/30",
    cvc: "123"
)

if result.isValid {
    print("Brand: \(result.brand.rawValue)")
} else {
    print(result.errors.map(\.rawValue))   // ["Card number failed Luhn validation"], …
}

// Individual checks
let brand = CardValidator.brand(for: "5521970079998012")
let luhnOK = CardValidator.isValidLuhn("5521970079998012")
let expiryOK = CardValidator.isValidExpiry(month: 12, year: 2030)
let cvcOK = CardValidator.isValidCVC("123", brand: brand)

// Formatting helpers
let display = PaymentValidationHelper.formatCardNumber("5521970079998012")  // "5521 9700 7999 8012"
```

## Error handling

`UqpayAPIError` covers everything the network layer can produce:

```swift
import UqpayCore

func describe(_ error: Error) -> String {
    guard let apiError = error as? UqpayAPIError else {
        return error.localizedDescription
    }

    switch apiError {
    case .notConfigured(let detail):
        return "Set up the SDK first: \(detail)"
    case .authenticationFailed:
        return "Could not obtain an access token."
    case .api(let status, let body):
        return "\(body.code) (HTTP \(status)): \(body.message)"
    case .unexpectedStatus(let status, _):
        return "Unexpected HTTP \(status)."
    case .decoding:
        return "The response could not be read."
    case .transport, .timedOut:
        return "Network problem — safe to retry with the same idempotency key."
    case .cancelled:
        return "Cancelled."
    @unknown default:
        // `UqpayAPIError` may gain cases in a future release.
        return apiError.localizedDescription
    }
}
```

Convenience accessors:

```swift
func triage(_ apiError: UqpayAPIError) {
    let status: Int? = apiError.httpStatus    // 402
    let code: String? = apiError.apiCode      // "card_declined"

    // Only 429 and 5xx are retryable — everything else is a definitive answer.
    // Retry with the SAME idempotency key, never a fresh one.
    if apiError.isRetryable {
        print("retry \(code ?? "-") \(status ?? 0)")
    }
}
```

The payment sheet reports failures as `PaymentError`, whose `code` is one of
`.cardDeclined`, `.insufficientFunds`, `.invalidPaymentMethod`, `.threeDSFailed`,
`.authenticationFailed`, `.networkError`, `.timeout`, `.cancelled`,
`.invalidConfiguration`, `.unknown`. The taxonomy is **non-exhaustive** — new
codes can be added in a minor release, so always write a `default:` branch.

## Troubleshooting

Symptoms merchants actually hit, in the order they usually hit them.

### "Environment not set" (`UqpayConfigurationError.environmentNotSet`)

Every API call requires an explicit environment — the SDK never silently falls
back to a test host. Set it once during app start, before any payment call:

```swift
UqpayConfiguration.shared.environment = .production   // or .sandboxMode
```

### Requests fail with 401 / `.authenticationFailed`

The `headerToken` your backend issued has expired or was pasted from the wrong
environment. Tokens are short-lived by design: fetch a fresh one from your
backend right before creating the payment intent, not at app launch. Do **not**
embed a long-lived key in the app — `UqpayConfiguration.clientSecret` is
deprecated for exactly that reason.

### "Payment intent not found" / nothing to confirm

`UqpayConfiguration.shared.paymentIntentId` (and `clientSecretForPayment`) must
be set from your backend's *create intent* response before the sheet is
presented. If you present the sheet first, the card form loads but every
confirm fails.

### The sheet refuses to open: `PaymentSheetError.intentNotPayable`

The intent you passed is already settled (`SUCCEEDED` or `CANCELLED`). This is
deliberate — presenting a payment form for a settled intent is how customers
get double-charged. Create a fresh intent for a new payment; if you are
recovering after a crash or relaunch, the error's `status` tells you the
outcome to report.

### 3DS finishes in the browser but the app never updates

Two things must both be true:

1. `UqpayConfiguration.shared.appReturnScheme` is set and matches a URL scheme
   registered in your Info.plist, so the bank redirect can reopen your app.
2. Your URL handler posts the SDK's notification — use the typed constant, a
   typo in the raw string disables reconciliation silently:

```swift
NotificationCenter.default.post(name: PaymentSheet.paymentReturnedFromBank, object: nil)
```

Even without the notification the payment screens re-read the intent when the
app returns to the foreground — the notification just makes it immediate.
Reaching the return URL never means success by itself; the SDK always re-reads
the intent from the API.

### Payment-method icons or flags are missing

Under Swift Package Manager the SDK loads images from `Bundle.module`
automatically. If icons are missing you are almost certainly building the SDK
sources by dragging files into your project — integrate via SPM or CocoaPods
instead, so the resource bundles ship with the module.

### `system_error` when confirming `paynow`, `tosspay`, or `naverpay`

A known server-side limitation of the sandbox rails for these three wallets —
not an integration bug on your side. Test the QR flow with the other wallets
(e.g. GrabPay) and verify these three in production review.

### What `paymentDidBecomePending` means

The customer's payment is real but not settled — common for QR wallets where
the scan happens in another app. Do not release goods yet and do not treat it
as a failure: keep the order open and confirm the final state from the
`acquiring.payment_intent.succeeded` webhook on your backend. The delegate
will also fire again if the SDK observes the terminal state while the customer
is still on the status screen.

### The sheet is white in a dark-mode app (pre-1.0 behaviour)

Since 1.0 the sheet follows the device appearance. If you need the old
all-light look, pin it explicitly:

```swift
let appearance = PaymentSheet.Appearance()
appearance.userInterfaceStyle = .light
```

## Logging

```swift
import UqpayCore

UqpayLogger.shared.logLevel = .debug          // .verbose … .error, .none
UqpayLogger.shared.isEnabled = true

// Route SDK logs into your own logging stack.
UqpayLogger.shared.logHandler = { level, message, file, function, line in
    MyLogger.log("[UQPAY] [\(level)] \(file):\(line) \(message)")
}
```

Defaults to `.debug` in DEBUG builds and `.warning` in release. The SDK never logs
card numbers, CVCs or tokens.

## Testing

Point at `.sandboxMode` and use the UQPAY test cards.

| Card number | Behaviour |
|---|---|
| `5521970079998012` | 3D Secure enrolled — presents a challenge |

3DS failure surfaces as intent status `REQUIRES_PAYMENT_METHOD` with the attempt's
`failure_code` set to `3ds_failed`.

> [!WARNING]
> **Sandbox QR wallets settle on real rails.** WeChat Pay, Alipay and GrabPay QR
> codes generated in sandbox charge **real money** from the scanning wallet. Test
> with penny amounts only.

Run the SDK's own tests:

```bash
xcodebuild -workspace uqpay_ios_sdk.xcworkspace \
           -scheme UqpayPaymentSheet \
           -destination 'platform=iOS Simulator,name=iPhone 17' \
           test
```

## Security

- **Card data never touches disk.** Every request carrying card details or QR
  URLs goes through an ephemeral `URLSession`, so nothing is written to the shared
  URL cache, cookie store or credential store.
- **The 3DS web view uses a non-persistent data store**, cleared when it closes.
- **The SDK never accepts an `x-api-key`** — only short-lived tokens your backend
  issues.
- **Return URL parameters are ignored.** The outcome always comes from the API.
- **No fabricated device data.** Screen size, OS version, locale, timezone and IP
  are measured from the running device or omitted.

## Known limitations

Honest list for `1.0.0`. These are known and documented, not undiscovered — each
has a stated workaround, and they are the priorities for the next release:

| Area | Limitation |
|---|---|
| Card form | `autoCapture` and `threeDsAction` are hardcoded on the built-in form. Use the custom confirm path for auth-only or manual capture. |
| Tokens | The sheet uses the token in `headerToken` as-is and cannot refresh it. Set a fresh token immediately before presenting. |
| Idempotency | The prebuilt sheet pins and persists idempotency keys automatically (they survive relaunch for the server's 24h window). The custom confirm path `confirmPaymentIntent(paymentIntentId:cardDetails:)` does **not** — its `idempotencyKey` parameter defaults to a fresh key per call, so pass and hold your own key if you retry through it. |
| Wallets | `paynow`, `tosspay` and `naverpay` currently fail server-side with `system_error` in sandbox. |
| Privacy | Each module ships a `PrivacyInfo.xcprivacy` declaring what it collects (card and billing details, `identifierForVendor` and the device IP for 3DS risk scoring — no tracking, no required-reason APIs). App Store Connect aggregates these into your app's privacy report; if you fill in a nutrition label manually, include these data types. |

## Example apps

Two runnable storefronts live in `Examples/`:

- **`Examples/UIKitExample`** — UIKit, delegate-based.
- **`Examples/SwiftUIExample`** — SwiftUI, with end-to-end sandbox UI tests.

Both include a `DemoMerchantBackend` that stands in for your server. Copy
`Demo/DemoSecrets.example.plist` to `Demo/DemoSecrets.plist` and paste your
sandbox `ClientID` and `APIKey`.

> [!WARNING]
> `DemoMerchantBackend` holds an API key **in the app**, which is exactly what you
> must not ship. It exists so the example runs without a server. Delete it and
> point `UqpayBackendTokenProvider` at your real backend before going live.

## Migrating from earlier builds

| Removed / changed | Replacement |
|---|---|
| `UqpayConfiguration.shared.clientSecret` | No longer used by the payment flow. Set `clientId` + `headerToken` instead. Do not put a live key in the app. |
| `.testingMode`, `.stagingMode` | `.sandboxMode`. They pointed at UQPAY-internal hosts. Internal tools use `UqpayAPIEnvironment.custom(_:)`. |
| No default environment | `UqpayConfiguration.shared.environment` must be set explicitly, or calls throw `.environmentNotSet`. |
| `ApiClient.get`/`post` returning every status | They now throw `UqpayAPIError` on non-2xx. Read `.httpStatus` and `.apiCode`. |
| `ApiClient.confirmPaymentIntent(_:)`, `confirmAlipayPaymentIntent(paymentIntentId:request:)` | `confirmPaymentIntent(paymentIntentId:encodedBody:idempotencyKey:)`. |
| `confirmPaymentIntent`'s `billingDetails:` parameter | It was ignored. The address travels in `ConfirmCardDetails.billing`. |
| `BrowserInfo` initialiser defaults | `BrowserInfo.currentDevice()`. The old defaults (1920×1080, "iOS 14.5", lat/lon 0) were fabrications. |

## License

MIT. See [LICENSE](LICENSE).
