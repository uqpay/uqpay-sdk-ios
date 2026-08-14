//
//  UqpayPaymentSheet.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 14/08/2025.
//

import Foundation
#if canImport(UIKit)
import UIKit
import Combine
import UqpayCore
import UqpayPayments

// MARK: - Public Errors

public enum PaymentSheetError: Error, Equatable {
    case notReady
    case canceled
    case failed(String)
    /// A customer step (3DS challenge, QR scan) was presented but the payment
    /// did not reach an observable outcome before the polling window closed.
    /// Distinct from `.failed`: the payment may still be live.
    case authenticationTimedOut
    /// The payment intent is already in a final state — SUCCEEDED, CANCELLED
    /// or FAILED — so there is nothing left for a customer to pay. Showing a
    /// payment form for it could only produce confusion or a second charge.
    /// Read the attached status: SUCCEEDED usually means this customer
    /// already paid (for example just before the app was killed), so treat
    /// it as an outcome to display, not an error to retry.
    case intentNotPayable(status: UqpayPaymentIntentStatus)
}

extension PaymentSheetError: LocalizedError {
    /// Without this, `localizedDescription` falls back to the generic
    /// "The operation couldn't be completed. (PaymentSheetError error 0.)"
    /// and the message carried by `.failed` is silently discarded.
    public var errorDescription: String? {
        switch self {
        case .notReady:
            return UqpayLocalized("The payment sheet is not ready yet.")
        case .canceled:
            return UqpayLocalized("The payment was cancelled.")
        case .failed(let message):
            return message
        case .authenticationTimedOut:
            return UqpayLocalized("Authentication timed out. Check the payment status before retrying.")
        case .intentNotPayable(let status):
            // `status.rawValue` is an API constant, not prose — it goes into a
            // format slot so translators never touch it.
            return String(
                format: UqpayLocalized("This payment has already finished (%@). Create a new payment intent to charge this customer again."),
                status.rawValue
            )
        }
    }
}

public enum PaymentSheetType: String {
    case cardOnly
    case paymentList
}
// MARK: - PaymentSheet

public final class PaymentSheet {
    public enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var paymentsheetType : PaymentSheetType = .paymentList
    
    public private(set) var loadingState: LoadingState = .idle
    public var isReady: Bool { if case .loaded = loadingState { return true } else { return false } }

    /// Receives the outcome of every payment run through this sheet —
    /// success, failure, and cancellation. Set it before (or right after)
    /// calling ``loadViewController(completion:)``; the sheet resolves it at
    /// payment time, so either order works.
    ///
    /// This is the only delegate the SDK calls. Three others were once exposed
    /// here — `delegate`, `paymentCardDelegate` and `paymentListDelegate` — and
    /// none of them had a single call site, so merchants who wired one received
    /// nothing at all.
    public weak var paymentDelegate: PaymentDelegate?

    /// True once this payment has reported a terminal outcome — succeeded or
    /// definitively failed.
    ///
    /// Gates ``PaymentDelegate/paymentSheetDidCancel(_:)``: leaving the flow
    /// after an outcome was reported is not a cancellation, and several screens
    /// can be torn down by the same dismissal, so only the first one reports.
    var hasReportedOutcome = false

    /// Watches an intent whose confirm was still in flight when the customer
    /// dismissed the sheet. Owned here because this object is what the merchant
    /// retains — the card screen's own watcher dies with the screen.
    private var detachedReconciliation: Task<Void, Never>?

    /// The detached watcher reports at most one outcome, however it is started.
    private var hasDeliveredDetachedOutcome = false

    deinit {
        // A merchant who releases the sheet has stopped caring about this
        // payment's UI signal; the webhook still tells their backend the truth.
        detachedReconciliation?.cancel()
    }

    /// Keeps polling `paymentIntentId` after the sheet has gone away, so a
    /// payment that settles moments after the customer swiped it closed is
    /// still reported rather than left at `paymentDidBecomePending` forever.
    ///
    /// Deliberately narrow. It reports only outcomes that need no attempt
    /// attribution — the intent as a whole succeeded, or the intent as a whole
    /// is dead — matching the on-screen watcher. It is bounded to the same
    /// ~60 second window, cancels if this sheet is released, and delivers at
    /// most once. The webhook remains the authoritative source either way; this
    /// only shortens the window in which the app is out of step with it.
    @MainActor
    func beginDetachedReconciliation(paymentIntentId: String) {
        // Newest wins, so a second dismissal cannot leave two pollers racing to
        // report the same payment.
        detachedReconciliation?.cancel()
        detachedReconciliation = Task { [weak self] in
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { return }
                guard let intent = try? await ApiClient.forConfiguredEnvironment()
                    .retrievePaymentIntent(paymentIntentId) else { continue }
                guard !Task.isCancelled else { return }

                switch intent.intentStatus {
                case .succeeded, .requiresCapture:
                    self.deliverDetachedOutcome { delegate, sheet in
                        delegate.paymentSheet(
                            sheet, didCompleteWithResult: ReconciledOutcome.successResult(for: intent)
                        )
                    }
                    return
                case .failed, .cancelled:
                    self.deliverDetachedOutcome { delegate, sheet in
                        delegate.paymentSheet(
                            sheet,
                            didFailWithError: ReconciledOutcome.failureError(for: intent, underlying: nil)
                        )
                    }
                    return
                default:
                    continue
                }
            }
            // The window closed with the payment still unsettled. The
            // `paymentDidBecomePending` already delivered remains the last word
            // from the SDK, which is the honest one.
        }
    }

    /// Internal so tests can pin the at-most-once guarantee without waiting out
    /// a poll cycle.
    @MainActor
    func deliverDetachedOutcome(_ report: (PaymentDelegate, PaymentSheet) -> Void) {
        guard !hasDeliveredDetachedOutcome, let delegate = paymentDelegate else { return }
        hasDeliveredDetachedOutcome = true
        report(delegate, self)
    }

    /// Stops the detached watcher. Used when a fresh flow takes over the same
    /// sheet, so a stale poller cannot report against a new payment.
    @MainActor
    func cancelDetachedReconciliation() {
        detachedReconciliation?.cancel()
        detachedReconciliation = nil
    }

    let configuration: Configuration
    let appearance: Appearance

    public init(configuration: Configuration = .init(), appearance: Appearance = .init(), sheetType: PaymentSheetType = .paymentList) {
        self.configuration = configuration
        self.appearance = appearance
        self.paymentsheetType = sheetType
    }

    /// Loads the payment UI and returns the view controller to present.
    ///
    /// On failure the completion carries the actual error — there is no
    /// blank fallback controller to present by mistake.
    @MainActor
    public func loadViewController(completion: @escaping (Result<UIViewController, PaymentSheetError>) -> Void) {
        // A watcher left over from a previous flow must never report against
        // the payment this load is about to start. Sheets are single-use by
        // design (`hasReportedOutcome` is never reset), so this is belt and
        // braces rather than a supported path — but attributing one payment's
        // outcome to another is the kind of wrong that reaches a customer.
        cancelDetachedReconciliation()

        loadingState = .loading
        UqpayLogger.shared.info("Loading PaymentSheet view controller")

        Task { [weak self] in
            guard let strongSelf = self else { return }
            do {
                // Use the sheet override when given, otherwise the globally
                // configured environment — never a silent test default.
                let environment = try strongSelf.configuration.environment
                    ?? UqpayConfiguration.shared.requireEnvironment()
                let apiClient = ApiClient.forEnvironment(environment)
                UqpayLogger.shared.debug("Fetching payment methods for environment: \(environment.displayName)")

                _ = try await apiClient.getPaymentMethods()

                await MainActor.run {
                    // Both sheet types are honoured here, matching the SwiftUI
                    // presenter — `.cardOnly` used to be silently ignored and
                    // hand a UIKit merchant the full method list.
                    let root: UIViewController
                    switch strongSelf.paymentsheetType {
                    case .cardOnly:
                        let card = PaymentCardViewController()
                        card.paymentSheet = strongSelf
                        card.paymentDelegate = strongSelf.paymentDelegate
                        root = card
                    case .paymentList:
                        let list = PaymentListViewController(appearance: strongSelf.appearance, configuration: strongSelf.configuration)
                        // The list resolves `paymentDelegate` through the sheet at
                        // payment time, so callbacks reach the merchant and carry
                        // this configured instance.
                        list.paymentSheet = strongSelf
                        root = list
                    }
                    let sheet = AppNavigationViewController(rootViewController: root, appearance: strongSelf.appearance)
                    strongSelf.loadingState = .loaded

                    UqpayLogger.shared.info("PaymentSheet loaded successfully")
                    completion(.success(sheet))
                }
            } catch {
                UqpayLogger.shared.logError(error, message: "Failed to load PaymentSheet")
                let failure = (error as? PaymentSheetError)
                    ?? .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                await MainActor.run {
                    self?.loadingState = .failed(failure.errorDescription ?? "Failed to load payment methods")
                    completion(.failure(failure))
                }
            }
        }
    }
    
    // MARK: - Nested Types

    public final class Appearance {
        // Layout
        public var cornerRadius: CGFloat
        public var backgroundColor: UIColor

        /// How the sheet resolves light/dark appearance.
        ///
        /// `.unspecified` (the default) follows the device and host app, so the
        /// sheet renders correctly inside a dark-mode app. Set `.light` to pin
        /// the pre-1.0 all-light look, or `.dark` to force dark regardless of
        /// the system setting.
        public var userInterfaceStyle: UIUserInterfaceStyle = .unspecified
        
        // Brand Colors
        public var primaryColor: UIColor           // Main brand color (#7C4DFF)
        public var primaryColorLight: UIColor      // Light variant for backgrounds
        
        // Text Colors
        public var titleColor: UIColor             // Main titles
        public var labelColor: UIColor             // Regular labels
        public var secondaryTextColor: UIColor     // Secondary text, placeholders
        public var closeButtonColor: UIColor       // Close button tint
        
        // Component Colors
        public var fieldBackgroundColor: UIColor   // Input field backgrounds
        public var fieldBorderColor: UIColor       // Input field borders
        public var closeButtonBackgroundColor: UIColor // Close button background
        public var payButtonColor: UIColor         // Pay button background
        public var payButtonTextColor: UIColor     // Pay button text
        public var loadingIndicatorColor: UIColor  // Loading indicator
        public var emptyViewBackgroundColor: UIColor // Empty view icon background
        public var alertBackgroundColor: UIColor   // Alert dialog background
        public var alertTitleColor: UIColor        // Alert title text
        public var alertMessageColor: UIColor      // Alert message text
        
        // Card Brand Colors
        public var cardBrand: CardBrandColors
        
        // System Colors
        public var system: SystemColors
        
        // MARK: - Nested Color Types
        public struct CardBrandColors {
            public var visa: UIColor = .systemCyan
            public var masterCard: UIColor = .systemOrange
            public var amex: UIColor = .systemGreen
            public var unknown: UIColor = .systemGray

            public init() {}
        }
        
        public struct SystemColors {
            public var toolbarBackground: UIColor = .systemBackground
            public var iconTint: UIColor = .systemGray
            public var defaultText: UIColor = .label
            public var background: UIColor = .systemBackground
            public var white: UIColor = .white
            public var separator: UIColor = .separator
            public var placeholder: UIColor = .placeholderText
            
            public init() {}
        }
        
        public init(
            cornerRadius: CGFloat = 12,
            primaryColor: UIColor = UIColor(red: 0.486, green: 0.302, blue: 1.0, alpha: 1.0), // #7C4DFF
            backgroundColor: UIColor = .systemBackground,
            cardBrand: CardBrandColors = CardBrandColors(),
            system: SystemColors = SystemColors()
        ) {
            self.cornerRadius = cornerRadius
            self.backgroundColor = backgroundColor
            self.cardBrand = cardBrand
            self.system = system
            
            // Brand colors
            self.primaryColor = primaryColor
            self.primaryColorLight = primaryColor.withAlphaComponent(0.1)
            
            // Text colors
            self.titleColor = .label
            self.labelColor = .label
            // `.systemGray` is #8E8E93 — the exact literal this used to be — and
        // is defined for both appearance modes.
        self.secondaryTextColor = .systemGray
            self.closeButtonColor = .systemGray
            
            // Component colors
            self.fieldBackgroundColor = .systemGray6
            self.fieldBorderColor = .systemGray5
            self.closeButtonBackgroundColor = .systemGray6
            self.payButtonColor = primaryColor
            self.payButtonTextColor = .white
            self.loadingIndicatorColor = .white
            self.emptyViewBackgroundColor = .systemGray4
            self.alertBackgroundColor = .systemBackground
            self.alertTitleColor = .label
            self.alertMessageColor = .secondaryLabel
        }
        
        // Convenience computed properties
        public var selectedBorderColor: UIColor {
            return primaryColor
        }
        
        public var selectedBackgroundColor: UIColor {
            return primaryColorLight
        }
        
        public var unselectedBorderColor: UIColor {
            return fieldBorderColor
        }
    }

    public final class Configuration {
        // MARK: - Business Configuration
        public var merchantDisplayName: String
        public var allowsDelayedPaymentMethods: Bool
        /// Optional per-sheet environment override. When nil (the default), the
        /// sheet uses the environment set on `UqpayConfiguration.shared`.
        public var environment: UqpayEnvironment?
        
        // MARK: - Layout Constants
        public var spacing: Spacing
        public var dimensions: Dimensions
        public var payment: Payment
        
        // MARK: - Nested Types
        public struct Spacing {
            public var small: CGFloat = 8
            public var medium: CGFloat = 12
            public var large: CGFloat = 16
            public var extraLarge: CGFloat = 24
            public var stackSpacing: CGFloat = 24
            public var buttonSpacing: CGFloat = 12
            public var iconSpacing: CGFloat = 4
            public var fieldPadding: CGFloat = 12
            
            public init() {}
        }
        
        public struct Dimensions {
            public var cornerRadius: CGFloat = 8
            public var borderWidth: CGFloat = 1
            public var heavyBorderWidth: CGFloat = 2
            public var closeButtonSize: CGFloat = 30
            public var closeButtonCornerRadius: CGFloat = 15
            public var fieldHeight: CGFloat = 48
            public var paymentButtonHeight: CGFloat = 80
            public var emptyViewHeight: CGFloat = 200
            public var cardIconWidth: CGFloat = 32
            public var cardIconHeight: CGFloat = 20
            public var cvcIconSize: CGFloat = 20
            public var iconSize: CGFloat = 24
            public var checkboxSize: CGFloat = 24
            public var checkboxRowHeight: CGFloat = 44
            public var visiblePaymentMethods: Int = 3
            public var partialButtonPercentage: CGFloat = 0.1
            
            public init() {}
        }
        
        public struct Payment {
            public var defaultAmount: Int = 1000
            public var defaultCurrency: String = "USD"
            public var maxCardNumberLength: Int = 16
            public var maxExpiryLength: Int = 4
            public var maxCvcLength: Int = 4
            public var keyboardScrollOffset: CGFloat = 50
            
            public init() {}
        }
        
        public init(
            merchantDisplayName: String = "Merchant",
            allowsDelayedPaymentMethods: Bool = false,
            environment: UqpayEnvironment? = nil,
            spacing: Spacing = Spacing(),
            dimensions: Dimensions = Dimensions(),
            payment: Payment = Payment()
        ) {
            self.merchantDisplayName = merchantDisplayName
            self.allowsDelayedPaymentMethods = allowsDelayedPaymentMethods
            self.environment = environment
            self.spacing = spacing
            self.dimensions = dimensions
            self.payment = payment
        }
    }
}


// MARK: - ApiClient Extension
extension ApiClient {
    /// Payment methods for the current payment, straight from the API.
    ///
    /// The payment intent's `available_payment_method_types` is the
    /// documented source of truth — it reflects what the merchant account
    /// has enabled for this payment's currency and amount. Nothing is
    /// assumed client-side: types the SDK cannot render are dropped, and
    /// the API's ordering is preserved.
    public func getPaymentMethods() async throws -> [PaymentMethod] {
        guard let paymentIntentId = UqpayConfiguration.shared.paymentIntentId else {
            throw PaymentSheetError.failed("No payment intent. Create one before presenting the sheet.")
        }

        let intent = try await retrievePaymentIntent(paymentIntentId)

        // The status was being discarded here, so a sheet presented for an
        // intent that already SUCCEEDED showed a working payment form. This
        // is the cheapest possible guard — the intent is in hand anyway —
        // and it covers every list-based entry path in one place.
        if let refusal = Self.presentationRefusal(for: intent) {
            throw refusal
        }

        let apiTypes = intent.availablePaymentMethodTypes ?? []
        let methods = apiTypes.compactMap { PaymentMethod(apiType: $0) }

        let unrenderable = apiTypes.filter { PaymentMethod(apiType: $0) == nil }
        if !unrenderable.isEmpty {
            UqpayLogger.shared.info("Payment methods not supported by this SDK version, hidden: \(unrenderable)")
        }

        guard !methods.isEmpty else {
            throw PaymentSheetError.failed("No payment methods are available for this payment.")
        }
        return methods
    }

    /// Why a payment UI must not be presented for this intent — or `nil`
    /// when it is payable.
    ///
    /// SUCCEEDED, CANCELLED and FAILED are all final states per the API
    /// reference ("no further action needed"): a payment form for such an
    /// intent could only confuse the customer or start a second charge.
    /// Anything non-terminal presents, including statuses this SDK version
    /// does not know — a future status wrongly refused would block real
    /// payments, while a wrongly presented one is still guarded at
    /// confirm time. Pure, so tests exercise the decision without a
    /// network.
    static func presentationRefusal(for intent: UqpayPaymentIntent) -> PaymentSheetError? {
        guard intent.intentStatus.isTerminal else { return nil }
        return .intentNotPayable(status: intent.intentStatus)
    }

    /// Re-reads a payment intent from the API.
    ///
    /// After 3D Secure the browser step tells you only that it ended, never how
    /// it ended. The authoritative outcome reaches your backend by webhook, so
    /// the client must ask the API what actually happened.
    func retrievePaymentIntent(_ paymentIntentId: String) async throws -> UqpayPaymentIntent {
        guard let token = UqpayConfiguration.shared.headerToken else {
            throw PaymentSheetError.failed("Not authenticated.")
        }
        guard let clientId = UqpayConfiguration.shared.clientId else {
            throw PaymentSheetError.failed("Client id is not configured.")
        }

        // Rides this client's own session, so intent reads share the
        // non-caching (and, in tests, stubbed) transport that confirms use.
        let client = UqpayHTTPClient(
            environment: Self.apiEnvironment(for: try UqpayConfiguration.shared.requireEnvironment()),
            clientID: clientId,
            credentials: UqpayStaticTokenProvider(token: token),
            session: session
        )

        do {
            return try await client.send(.get("api/v2/payment_intents/\(paymentIntentId)"))
        } catch let error as UqpayAPIError {
            throw PaymentSheetError.failed(error.errorDescription ?? "Could not read the payment status.")
        }
    }

    /// Waits for 3D Secure to resolve.
    ///
    /// Returns as soon as the intent reaches a terminal state, or as soon as it
    /// asks for a further step — a device fingerprint is often followed by a
    /// challenge screen, which arrives as a second `redirect_to_url`.
    ///
    /// - Parameter excludingActionType: the action already shown, so returning
    ///   the same one again is not mistaken for a new step.
    func awaitThreeDSOutcome(
        paymentIntentId: String,
        excludingActionType: String?,
        timeout: TimeInterval = 300,
        pollInterval: TimeInterval = 2
    ) async throws -> UqpayPaymentIntent {
        try await Self.pollForOutcome(
            attempts: Int(timeout / pollInterval),
            interval: pollInterval
        ) {
            let intent = try await self.retrievePaymentIntent(paymentIntentId)

            if intent.intentStatus.isTerminal || intent.intentStatus == .requiresCapture {
                return intent
            }
            // Falling back to REQUIRES_PAYMENT_METHOD means the attempt
            // failed — 3DS was declined or abandoned — and the customer
            // must retry. Waiting further would only stall them; the live
            // sandbox does exactly this when a card fails authentication
            // (attempt_status FAILED, failure_code "3ds_failed").
            if intent.intentStatus == .requiresPaymentMethod {
                return intent
            }
            if intent.intentStatus == .requiresCustomerAction,
               let type = intent.nextAction?.type,
               type != excludingActionType {
                return intent
            }
            return nil
        }
    }

    /// Polls until `poll` yields an outcome, budgeted in ATTEMPTS rather
    /// than by a wall-clock deadline.
    ///
    /// The wall clock keeps advancing while the app is suspended, but
    /// `Task.sleep` does not fire — so a deadline-based loop charged a
    /// customer's whole timeout to their trip into the banking app and
    /// greeted their return with "timed out" without one poll having run.
    /// Counting attempts spends the budget only while the app is actually
    /// running; in the foreground the two are identical (attempts ×
    /// interval = the same duration).
    ///
    /// Error handling mirrors the loop this replaced: a failed poll is held
    /// rather than thrown (a single flaky GET must not abandon a payment in
    /// flight) and cleared by the next poll that answers; on exhaustion a
    /// still-held error wins over the generic timeout.
    static func pollForOutcome<Outcome>(
        attempts: Int,
        interval: TimeInterval,
        poll: () async throws -> Outcome?
    ) async throws -> Outcome {
        var lastError: Error?

        for _ in 0..<max(1, attempts) {
            do {
                if let outcome = try await poll() {
                    return outcome
                }
                lastError = nil
            } catch {
                lastError = error
            }
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }

        if let lastError { throw lastError }
        throw PaymentSheetError.authenticationTimedOut
    }

    private static func apiEnvironment(for environment: UqpayEnvironment) -> UqpayAPIEnvironment {
        switch environment {
        case .productionMode:
            return .production
        case .sandboxMode:
            return .sandbox
        }
    }

    /// Pulls the `message` out of a UQPAY error body, e.g.
    /// `{"type":"invalid_request_error","code":"invalid_payment_method","message":"language is invalid"}`.
    /// Returns nil when the body is missing, unparsable, or the message is empty.
    static func apiMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable { let message: String? }
        guard let body = try? JSONDecoder().decode(ErrorBody.self, from: data),
              let message = body.message,
              !message.isEmpty else { return nil }
        return message
    }

    /// Confirms a card payment, building the request body from the real
    /// device's browser info.
    ///
    /// The billing address travels inside `cardDetails.billing` — that is the
    /// shape the API expects, and it is what the issuer runs AVS against.
    ///
    /// Main-actor because the browser info reads `UIScreen`/`UIDevice`.
    /// - Parameter idempotencyKey: reuse the same key when retrying a confirm
    ///   that failed without a server response, so it cannot charge twice.
    @MainActor
    public func confirmPaymentIntent(
        paymentIntentId: String,
        cardDetails: ConfirmCardDetails,
        idempotencyKey: UqpayIdempotencyKey = UqpayIdempotencyKey()
    ) async throws -> ConfirmPaymentIntentResponse {
        let paymentMethod = ConfirmPaymentMethod(type: "card", card: cardDetails)

        // Required for 3DS risk assessment; the device's real address, never a
        // fabricated one. Omitted on the rare device with no active interface,
        // in which case the API's own validation reports the missing field.
        let requestBody = ConfirmPaymentIntentRequest(
            paymentMethod: paymentMethod,
            browserInfo: BrowserInfo.currentDevice(),
            ipAddress: UqpayDeviceIP.current()
        )

        return try await confirmPaymentIntent(
            paymentIntentId: paymentIntentId,
            encodedBody: try ConfirmBodyEncoder.make().encode(requestBody),
            idempotencyKey: idempotencyKey
        )
    }

    /// Sends a confirm with a pre-encoded body.
    ///
    /// This is the single transport for every confirm — card and wallets —
    /// so header assembly and status handling exist exactly once. Taking the
    /// body as `Data` lets a retry resend byte-identical content: JSON key
    /// order is not deterministic across encodings, and an idempotent server
    /// rejects a reused key whose payload changed.
    public func confirmPaymentIntent(
        paymentIntentId: String,
        encodedBody: Data,
        idempotencyKey: UqpayIdempotencyKey
    ) async throws -> ConfirmPaymentIntentResponse {
        // Pre-flight problems throw PaymentSheetError, never URLError: no
        // request leaves the device, so the payment's outcome is not in doubt
        // and callers must not pin an idempotency key on it.
        guard let authToken = UqpayConfiguration.shared.headerToken else {
            throw PaymentSheetError.failed("Not authenticated. Create a payment intent before confirming.")
        }
        guard let clientId = UqpayConfiguration.shared.clientId else {
            throw PaymentSheetError.failed("Client id is not configured.")
        }

        let baseURLString = currentEnvironment.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURLString)/api/v2/payment_intents/\(paymentIntentId)/confirm") else {
            throw PaymentSheetError.failed("Could not build the confirm URL for this environment.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(idempotencyKey.value, forHTTPHeaderField: "x-idempotency-key")
        request.setValue(clientId, forHTTPHeaderField: "x-client-id")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "x-auth-token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = encodedBody

        do {
            // The client's session is ephemeral: card data must never pass
            // through URLSession.shared and its on-disk cache.
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                // Nothing usable came back, so the payment's fate is unknown.
                // A URLError says that; a PaymentSheetError would read as a
                // definitive failure.
                throw URLError(.badServerResponse)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                // Every answered-but-unsuccessful status becomes an
                // UqpayAPIError, so one rule covers them all: `isRetryable`
                // marks 429/5xx as "may have been processed, retry with the
                // same key", and everything else as a definitive rejection
                // whose status the caller can map to a precise error code.
                throw Self.apiFailure(status: httpResponse.statusCode, data: data)
            }
            return try JSONDecoder().decode(ConfirmPaymentIntentResponse.self, from: data)
        } catch let error as PaymentSheetError {
            throw error
        } catch let error as URLError {
            // Rethrown untranslated: a URLError means the server never
            // answered, which tells the caller to retry with the SAME
            // idempotency key. Wrapping it would erase that signal.
            throw error
        } catch let error as UqpayAPIError {
            // Likewise: carries the status the retry rule is derived from.
            throw error
        } catch let error as DecodingError {
            // Also untranslated: the server answered 2xx — the payment was
            // processed — but the response could not be read. The caller must
            // treat the outcome as unknown and keep the idempotency key, so a
            // retry replays the processed payment instead of charging again.
            throw error
        } catch is CancellationError {
            // Untranslated: a cancelled task must read as "cancelled", not
            // as a definitive failure of the payment.
            throw CancellationError()
        } catch {
            throw PaymentSheetError.failed("Failed to confirm payment: \(error.localizedDescription)")
        }
    }

    /// Builds the typed error for a status whose outcome is unknown,
    /// preferring the API's structured body.
    private static func apiFailure(status: Int, data: Data) -> UqpayAPIError {
        if let body = try? JSONDecoder().decode(UqpayAPIErrorBody.self, from: data),
           !(body.code.isEmpty && body.type.isEmpty && body.message.isEmpty) {
            return .api(status: status, body: body)
        }
        return .unexpectedStatus(status: status, responseBody: responseSummary(from: data))
    }

    /// A bounded, single-line rendering of a response body, for errors the
    /// API did not return a structured message for.
    private static func responseSummary(from data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > 300 ? String(trimmed.prefix(300)) + "…" : trimmed
    }

}

// MARK: - Return-from-bank notification

public extension PaymentSheet {

    /// Post this after your app returns from an external bank, wallet, or 3DS
    /// redirect so the payment screen re-reads the intent immediately:
    ///
    ///     NotificationCenter.default.post(name: PaymentSheet.paymentReturnedFromBank, object: nil)
    ///
    /// The raw value stays `"PaymentReturnedFromBank"`, so existing
    /// integrations posting the string keep working — but use the constant:
    /// a typo in the string silently disables 3DS reconciliation. Screens
    /// also re-read the intent on `didBecomeActiveNotification`, so this is
    /// an accelerator, not the only trigger.
    static let paymentReturnedFromBank = Notification.Name("PaymentReturnedFromBank")
}

#endif

