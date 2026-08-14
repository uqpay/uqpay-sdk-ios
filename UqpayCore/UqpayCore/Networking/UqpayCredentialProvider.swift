import Foundation

/// Supplies the access token the SDK sends on every API call.
///
/// The SDK never accepts an `x-api-key` directly. That key can issue refunds and
/// payouts, and an app binary cannot keep it secret. Global Acquiring also allows
/// only one active token per merchant — a newly issued token immediately
/// invalidates the previous one — so a device that mints its own tokens would
/// invalidate every other device and the merchant's own backend.
///
/// Your backend therefore owns token issuance, and the app receives short-lived
/// tokens from it. Implement this protocol to bridge the two, or use
/// ``UqpayBackendTokenProvider``.
public protocol UqpayCredentialProvider: AnyObject {

    /// Returns a token valid for the next request.
    ///
    /// Implementations should cache and reuse the token until shortly before it
    /// expires rather than fetching one per request.
    func authToken() async throws -> String

    /// Called when the API rejects the current token, so the next call refetches.
    func invalidateToken() async
}

/// Fetches access tokens from an endpoint on your own backend.
///
/// Expose a route that returns the token your server obtained from UQPAY:
///
/// ```json
/// { "auth_token": "…", "expired_at": 1765941179 }
/// ```
///
/// Authenticate that route with your app's own user session. It must never
/// return your `x-api-key`.
public actor UqpayBackendTokenProvider: UqpayCredentialProvider {

    private struct TokenResponse: Decodable {
        let authToken: String
        let expiresAt: Date?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            authToken = try container.decode(String.self, forKey: .authToken)
            if let epoch = try? container.decode(Double.self, forKey: .expiredAt) {
                expiresAt = Date(timeIntervalSince1970: epoch)
            } else {
                expiresAt = nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case authToken = "auth_token"
            case expiredAt = "expired_at"
        }
    }

    /// Refresh this long before expiry so a token cannot lapse mid-request.
    private static let refreshMargin: TimeInterval = 120

    /// Used when the backend omits `expired_at`. Shorter than UQPAY's 30 minutes.
    private static let assumedLifetime: TimeInterval = 20 * 60

    private let endpoint: URL
    private let session: URLSession
    private let decorate: (@Sendable (inout URLRequest) -> Void)?

    private var cachedToken: String?
    private var expiry: Date?
    private var inFlight: Task<String, Error>?

    /// - Parameters:
    ///   - endpoint: Your backend route returning `auth_token`.
    ///   - session: Session used for the fetch.
    ///   - decorate: Adds your own auth to the request, e.g. a user session header.
    public init(
        endpoint: URL,
        session: URLSession = .shared,
        decorate: (@Sendable (inout URLRequest) -> Void)? = nil
    ) {
        self.endpoint = endpoint
        self.session = session
        self.decorate = decorate
    }

    public func authToken() async throws -> String {
        if let token = cachedToken, let expiry, expiry > Date() { return token }
        if let inFlight { return try await inFlight.value }

        let task = Task<String, Error> { try await fetch() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    public func invalidateToken() async {
        cachedToken = nil
        expiry = nil
    }

    private func fetch() async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        decorate?(&request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UqpayAPIError.authenticationFailed(underlying: error)
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UqpayAPIError.authenticationFailed(
                underlying: UqpayAPIError.unexpectedStatus(status: status, responseBody: nil)
            )
        }

        let decoded: TokenResponse
        do {
            decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw UqpayAPIError.authenticationFailed(underlying: error)
        }

        let deadline = decoded.expiresAt ?? Date().addingTimeInterval(Self.assumedLifetime)
        cachedToken = decoded.authToken
        expiry = deadline.addingTimeInterval(-Self.refreshMargin)
        return decoded.authToken
    }
}

/// A fixed token, for tests and short-lived scripts.
///
/// Not for shipping apps: the token cannot refresh, so requests fail once it expires.
public final class UqpayStaticTokenProvider: UqpayCredentialProvider {

    private let token: String

    public init(token: String) {
        self.token = token
    }

    public func authToken() async throws -> String { token }

    public func invalidateToken() async {}
}
