import Foundation

/// The error body UQPAY returns on a failed request.
public struct UqpayAPIErrorBody: Decodable, Equatable, Sendable {

    /// Machine-readable code, e.g. `invalid_payment_method`.
    public let code: String

    /// Error family, e.g. `invalid_request_error`, `unauthorized_error`.
    public let type: String

    /// Human-readable description. The API may return this empty.
    public let message: String

    public init(code: String, type: String, message: String) {
        self.code = code
        self.type = type
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = (try? container.decode(String.self, forKey: .code)) ?? ""
        type = (try? container.decode(String.self, forKey: .type)) ?? ""
        message = (try? container.decode(String.self, forKey: .message)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case code, type, message
    }
}

/// Every failure the UQPAY SDK can surface.
public enum UqpayAPIError: Error {

    /// The SDK was used before it was configured.
    case notConfigured(String)

    /// A credential could not be obtained from the token provider.
    case authenticationFailed(underlying: Error)

    /// The API rejected the request and returned a structured error body.
    case api(status: Int, body: UqpayAPIErrorBody)

    /// The API failed with a status the SDK could not parse into an error body.
    case unexpectedStatus(status: Int, responseBody: String?)

    /// The response could not be decoded into the expected model.
    case decoding(underlying: Error)

    /// The request failed before a response arrived.
    case transport(underlying: Error)

    /// The request exceeded its time limit.
    case timedOut

    /// The operation was cancelled, typically by the customer.
    case cancelled
}

extension UqpayAPIError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let detail):
            return String(format: uqpayCoreLocalized("UQPAY SDK is not configured: %@"), detail)
        case .authenticationFailed(let underlying):
            return String(format: uqpayCoreLocalized("Could not obtain an access token: %@"), underlying.localizedDescription)
        case .api(let status, let body):
            let detail = body.message.isEmpty ? body.code : body.message
            return detail.isEmpty
                ? String(format: uqpayCoreLocalized("Request failed with status %d."), status)
                : detail
        case .unexpectedStatus(let status, _):
            return String(format: uqpayCoreLocalized("Request failed with status %d."), status)
        case .decoding:
            return uqpayCoreLocalized("The response from UQPAY could not be read.")
        case .transport(let underlying):
            return underlying.localizedDescription
        case .timedOut:
            return uqpayCoreLocalized("The request timed out.")
        case .cancelled:
            return uqpayCoreLocalized("The payment was cancelled.")
        }
    }

    /// The API error code, when the failure came from the API.
    public var apiCode: String? {
        if case .api(_, let body) = self { return body.code }
        return nil
    }

    /// The HTTP status, when the failure came from the API.
    public var httpStatus: Int? {
        switch self {
        case .api(let status, _), .unexpectedStatus(let status, _):
            return status
        default:
            return nil
        }
    }

    /// Whether retrying the identical request could plausibly succeed.
    ///
    /// Reuse the same idempotency key when retrying so a request that did reach
    /// the server is not applied twice.
    public var isRetryable: Bool {
        switch self {
        case .timedOut, .transport:
            return true
        case .api(let status, _), .unexpectedStatus(let status, _):
            return status == 429 || (500...599).contains(status)
        default:
            return false
        }
    }
}
