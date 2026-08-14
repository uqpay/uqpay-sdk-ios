import Combine
import Foundation
import UqpayCore
import UqpayPayments

/// Drives the demo checkout.
///
/// The flow a real integration follows:
///
/// 1. Your backend creates a payment intent for the amount the customer owes.
/// 2. The app receives the intent id and presents the UQPAY payment sheet.
/// 3. The customer pays; UQPAY reports the outcome.
///
/// Step 1 is simulated here by ``DemoMerchantBackend`` so the example runs with
/// no server. Everything else matches production.
@MainActor
final class ContentViewModel: ObservableObject {

    @Published var resultText = ""
    @Published private(set) var isLoading = false
    @Published private(set) var paymentIntent: UqpayPaymentIntent?

    /// Short-lived secret scoped to the current intent.
    var paymentIntentClientSecret: String? { paymentIntent?.clientSecret }

    /// The environment selected in the UI. Everything — token exchange, intent
    /// creation, and the payment sheet — runs against this one environment.
    private(set) var environment: UqpayEnvironment = .sandboxMode

    /// False until credentials for the selected environment are filled into
    /// `Demo/DemoSecrets.plist`.
    var isConfigured: Bool { DemoConfiguration.isConfigured(for: environment) }

    private var backend = DemoMerchantBackend(environment: .sandboxMode)

    /// Points the SDK and the demo backend at the selected environment.
    func initializeSDK(environment: UqpayEnvironment) {
        self.environment = environment
        backend = DemoMerchantBackend(environment: environment)

        UqpayConfiguration.shared.environment = environment
        UqpayConfiguration.shared.clientId = DemoConfiguration.clientID(for: environment)
        UqpayConfiguration.shared.appReturnScheme = DemoConfiguration.returnURLScheme

        resultText = isConfigured
            ? "Ready. \(environment.displayName) environment."
            : DemoConfiguration.setupInstructions(for: environment)
    }

    /// Creates an intent for `amount` and prepares the payment sheet.
    @discardableResult
    func prepareCheckout(amount: Decimal, description: String) async throws -> UqpayPaymentIntent {
        guard isConfigured else {
            throw DemoMerchantBackend.DemoError.notConfigured(
                instructions: DemoConfiguration.setupInstructions(for: environment)
            )
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let intent = try await backend.createPaymentIntent(amount: amount, description: description)

            guard intent.intentStatus == .requiresPaymentMethod else {
                throw NSError(
                    domain: "UqpayDemo", code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Expected REQUIRES_PAYMENT_METHOD but the intent is \(intent.intentStatus.rawValue)."]
                )
            }

            try await handOffToPaymentSheet(intent)
            paymentIntent = intent
            resultText = "Payment intent ready (\(intent.intentStatus.rawValue))."
            return intent
        } catch {
            paymentIntent = nil
            resultText = Self.message(for: error)
            throw error
        }
    }

    /// Passes the intent to the payment sheet.
    ///
    /// The sheet still reads from the shared configuration singleton. Once it
    /// moves onto `UqpayHTTPClient` this bridge goes away.
    private func handOffToPaymentSheet(_ intent: UqpayPaymentIntent) async throws {
        let token = try await backend.authToken()
        UqpayConfiguration.shared.environment = environment
        UqpayConfiguration.shared.clientId = DemoConfiguration.clientID(for: environment)
        UqpayConfiguration.shared.headerToken = token
        UqpayConfiguration.shared.paymentIntentId = intent.paymentIntentId
        UqpayConfiguration.shared.clientSecretForPayment = intent.clientSecret
        UqpayConfiguration.shared.appReturnScheme = DemoConfiguration.returnURLScheme
    }

    /// Turns an error into something a person can act on.
    private static func message(for error: Error) -> String {
        guard let apiError = error as? UqpayAPIError else {
            return error.localizedDescription
        }
        switch apiError {
        case .api(let status, let body):
            switch body.code {
            case "invalid idempotency key format":
                return "The idempotency key was rejected. It must be a lowercase UUID."
            case "unauthorized_error":
                return "Your credentials were rejected. Check the client ID and API key are the sandbox pair."
            default:
                let detail = body.message.isEmpty ? body.code : body.message
                return detail.isEmpty ? "The request failed (HTTP \(status))." : detail
            }
        case .timedOut:
            return "The request timed out. Check your connection and try again."
        case .transport:
            return "Could not reach UQPAY. Check your connection."
        default:
            return apiError.localizedDescription ?? "Something went wrong."
        }
    }
}
