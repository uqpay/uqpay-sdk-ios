import Foundation
import UqpayCore

// ─────────────────────────────────────────────────────────────────────────────
//  ⚠️  THIS FILE SIMULATES YOUR SERVER. DO NOT SHIP ANYTHING LIKE IT IN AN APP.
//
//  Everything here belongs on your backend, for two reasons:
//
//  1. `x-api-key` can issue refunds and payouts. An app binary cannot keep a
//     secret — anyone can extract it from a download with `strings`.
//
//  2. Global Acquiring allows only ONE active access token per merchant. Issuing
//     a new token immediately invalidates the previous one. If every device mints
//     its own token, each customer logs out every other customer and your own
//     backend. This looks fine with one tester and fails constantly in production.
//
//  To go to production, delete this file and swap in the real thing:
//
//      let credentials = UqpayBackendTokenProvider(
//          endpoint: URL(string: "https://your-api.example.com/uqpay/token")!,
//          decorate: { $0.setValue(userSession, forHTTPHeaderField: "Authorization") }
//      )
//
//  Your server keeps the API key, exchanges it for a token, creates the payment
//  intent, and returns only the intent id and its status to the app.
// ─────────────────────────────────────────────────────────────────────────────

/// Stands in for your backend so the example runs without one.
actor DemoMerchantBackend: UqpayCredentialProvider {

    enum DemoError: LocalizedError {
        case notConfigured(instructions: String)
        case tokenRequestFailed(status: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .notConfigured(let instructions):
                return instructions
            case .tokenRequestFailed(let status, let message):
                return message.isEmpty
                    ? "Could not get an access token (HTTP \(status))."
                    : "Could not get an access token: \(message)"
            }
        }
    }

    private struct TokenResponse: Decodable {
        let authToken: String
        let expiredAt: Double?

        private enum CodingKeys: String, CodingKey {
            case authToken = "auth_token"
            case expiredAt = "expired_at"
        }
    }

    private struct CreateIntentBody: Encodable {
        let amount: String
        let currency: String
        let merchantOrderId: String
        let description: String
        let returnUrl: String

        private enum CodingKeys: String, CodingKey {
            case amount, currency, description
            case merchantOrderId = "merchant_order_id"
            case returnUrl = "return_url"
        }
    }

    /// The environment this backend talks to. A real deployment has one per
    /// server; the demo makes a fresh backend when you switch environments.
    private let environment: UqpayEnvironment

    private let session = URLSession(configuration: .ephemeral)
    private var cachedToken: String?
    private var tokenExpiry: Date?

    private lazy var apiClient = UqpayHTTPClient(
        environment: DemoConfiguration.apiEnvironment(for: environment),
        clientID: DemoConfiguration.clientID(for: environment),
        credentials: self
    )

    init(environment: UqpayEnvironment) {
        self.environment = environment
    }

    // MARK: - UqpayCredentialProvider

    /// Exchanges the API key for a 30-minute access token.
    ///
    /// On a real backend this runs once per server, not once per customer.
    func authToken() async throws -> String {
        guard DemoConfiguration.isConfigured(for: environment) else {
            throw DemoError.notConfigured(
                instructions: DemoConfiguration.setupInstructions(for: environment)
            )
        }

        if let cachedToken, let tokenExpiry, tokenExpiry > Date() {
            return cachedToken
        }

        // authBaseURL differs from baseURL on the testing environment, which
        // runs its token service on a separate host.
        let url = environment.authBaseURL
            .appendingPathComponent(environment.authTokenEndpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(DemoConfiguration.clientID(for: environment), forHTTPHeaderField: "x-client-id")
        request.setValue(DemoConfiguration.apiKey(for: environment), forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1

        guard status == 200 else {
            let message = (try? JSONDecoder().decode(UqpayAPIErrorBody.self, from: data))?.message ?? ""
            throw DemoError.tokenRequestFailed(status: status, message: message)
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiry = token.expiredAt.map { Date(timeIntervalSince1970: $0) }
            ?? Date().addingTimeInterval(20 * 60)

        cachedToken = token.authToken
        tokenExpiry = expiry.addingTimeInterval(-120)
        return token.authToken
    }

    func invalidateToken() {
        cachedToken = nil
        tokenExpiry = nil
    }

    // MARK: - Payment intents

    /// Creates a payment intent for the amount the customer is about to pay.
    ///
    /// Your backend owns this call because it decides the real price. Never let
    /// the app choose the amount — a customer could change it.
    func createPaymentIntent(amount: Decimal, description: String) async throws -> UqpayPaymentIntent {
        let body = CreateIntentBody(
            amount: Self.format(amount),
            currency: DemoConfiguration.currency,
            merchantOrderId: UUID().uuidString.lowercased(),
            description: description,
            returnUrl: DemoConfiguration.returnURLScheme
        )
        let request = try UqpayRequest.post(
            "api/v2/payment_intents/create",
            body: body,
            encoder: JSONEncoder()
        )
        return try await apiClient.send(request)
    }

    /// The API expects a decimal string in major units, e.g. `"8.98"` — never cents.
    private static func format(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: amount as NSDecimalNumber) ?? "0.00"
    }
}
