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

    /// Where the checkout currently is. The UI renders from this alone.
    enum State: Equatable {
        case idle
        case preparing
        case ready(UqpayPaymentIntent)
        case failed(String)

        var isPreparing: Bool { self == .preparing }

        var intent: UqpayPaymentIntent? {
            if case .ready(let intent) = self { return intent }
            return nil
        }

        var errorMessage: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    @Published private(set) var state: State = .idle

    /// False until credentials are filled into ``DemoConfiguration``.
    let isConfigured = DemoConfiguration.isConfigured

    /// Message shown while credentials are still placeholders.
    let setupInstructions = DemoConfiguration.setupInstructions

    private let backend = DemoMerchantBackend()

    /// Prepares a payment intent for `amount` and readies the payment sheet.
    func prepareCheckout(amount: Decimal, description: String) async {
        guard isConfigured else {
            state = .failed(setupInstructions)
            return
        }

        state = .preparing
        do {
            let intent = try await backend.createPaymentIntent(amount: amount, description: description)

            guard intent.intentStatus == .requiresPaymentMethod else {
                state = .failed(
                    "Expected a new intent to be REQUIRES_PAYMENT_METHOD but it is "
                    + "\(intent.intentStatus.rawValue). It may already have been paid."
                )
                return
            }

            try await handOffToPaymentSheet(intent)
            state = .ready(intent)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    func reset() {
        state = .idle
    }

    /// Passes the intent to the payment sheet.
    ///
    /// The sheet still reads from the shared configuration singleton. Once it
    /// moves onto `UqpayHTTPClient` this bridge goes away and the intent is
    /// handed over directly.
    private func handOffToPaymentSheet(_ intent: UqpayPaymentIntent) async throws {
        let token = try await backend.authToken()
        UqpayConfiguration.shared.environment = .sandboxMode
        UqpayConfiguration.shared.clientId = DemoConfiguration.clientID
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
