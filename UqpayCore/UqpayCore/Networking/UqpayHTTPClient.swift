import Foundation

/// An idempotency key for a mutating request.
///
/// UQPAY rejects uppercase UUIDs, and Swift's `UUID().uuidString` is uppercase,
/// so this type lowercases on construction. Reuse the same key when retrying a
/// request so it is not applied twice.
public struct UqpayIdempotencyKey: Hashable, CustomStringConvertible {

    public let value: String

    public init() {
        value = UUID().uuidString.lowercased()
    }

    public init(_ uuid: UUID) {
        value = uuid.uuidString.lowercased()
    }

    /// Restores a key that this type minted in an earlier launch.
    ///
    /// The server matches idempotency keys as opaque strings, so a restored
    /// key must round-trip byte-identically — no lowercasing or UUID
    /// validation is applied here. Only pass values previously read from
    /// ``value``; minting new keys stays the job of ``init()``.
    public init(restoring value: String) {
        self.value = value
    }

    public var description: String { value }
}

/// A single API call, independent of how it is sent.
public struct UqpayRequest {

    public enum Method: String {
        case get = "GET"
        case post = "POST"
    }

    /// Path below the host, e.g. `api/v2/payment_intents/create`.
    public let path: String
    public let method: Method
    public let query: [URLQueryItem]
    public let body: Data?

    /// Sent on mutating requests. `nil` on reads, which need no key.
    public let idempotencyKey: UqpayIdempotencyKey?

    public init(
        path: String,
        method: Method,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        idempotencyKey: UqpayIdempotencyKey? = nil
    ) {
        self.path = path
        self.method = method
        self.query = query
        self.body = body
        self.idempotencyKey = idempotencyKey
    }

    public static func get(_ path: String, query: [URLQueryItem] = []) -> UqpayRequest {
        UqpayRequest(path: path, method: .get, query: query)
    }

    public static func post<Body: Encodable>(
        _ path: String,
        body: Body,
        idempotencyKey: UqpayIdempotencyKey = UqpayIdempotencyKey(),
        encoder: JSONEncoder = UqpayHTTPClient.defaultEncoder
    ) throws -> UqpayRequest {
        UqpayRequest(
            path: path,
            method: .post,
            body: try encoder.encode(body),
            idempotencyKey: idempotencyKey
        )
    }
}

/// Performs every UQPAY API call for the SDK.
///
/// This is the only place that builds URLs, attaches credentials, and turns
/// responses into typed values or ``UqpayAPIError``.
public final class UqpayHTTPClient {

    public static let defaultEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    public static let defaultDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private let environment: UqpayAPIEnvironment
    private let clientID: String
    private let credentials: UqpayCredentialProvider
    private let session: URLSession
    private let decoder: JSONDecoder

    /// Sub-account this client acts for, sent as `x-on-behalf-of`.
    private let onBehalfOf: String?

    public init(
        environment: UqpayAPIEnvironment,
        clientID: String,
        credentials: UqpayCredentialProvider,
        onBehalfOf: String? = nil,
        session: URLSession? = nil,
        decoder: JSONDecoder = UqpayHTTPClient.defaultDecoder
    ) {
        self.environment = environment
        self.clientID = clientID
        self.credentials = credentials
        self.onBehalfOf = onBehalfOf
        self.decoder = decoder

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 90
            configuration.httpAdditionalHeaders = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Sends a request and decodes the response.
    ///
    /// On a `401` the token is invalidated and the call retried once, which covers
    /// a token expiring between issue and use.
    public func send<Response: Decodable>(_ request: UqpayRequest) async throws -> Response {
        let data = try await sendReturningData(request)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw UqpayAPIError.decoding(underlying: error)
        }
    }

    /// Sends a request and returns the raw body, for callers decoding themselves.
    public func sendReturningData(_ request: UqpayRequest) async throws -> Data {
        do {
            return try await perform(request)
        } catch let error as UqpayAPIError {
            guard case .api(401, _) = error else { throw error }
            await credentials.invalidateToken()
            return try await perform(request)
        }
    }

    private func perform(_ request: UqpayRequest) async throws -> Data {
        let token: String
        do {
            token = try await credentials.authToken()
        } catch let error as UqpayAPIError {
            throw error
        } catch {
            throw UqpayAPIError.authenticationFailed(underlying: error)
        }

        var urlRequest = URLRequest(url: try url(for: request))
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body

        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "x-auth-token")
        urlRequest.setValue(clientID, forHTTPHeaderField: "x-client-id")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        if request.body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let key = request.idempotencyKey {
            urlRequest.setValue(key.value, forHTTPHeaderField: "x-idempotency-key")
        }
        if let onBehalfOf, !onBehalfOf.isEmpty {
            urlRequest.setValue(onBehalfOf, forHTTPHeaderField: "x-on-behalf-of")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .timedOut {
            throw UqpayAPIError.timedOut
        } catch let error as URLError where error.code == .cancelled {
            throw UqpayAPIError.cancelled
        } catch {
            throw UqpayAPIError.transport(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UqpayAPIError.unexpectedStatus(status: -1, responseBody: nil)
        }
        guard (200...299).contains(http.statusCode) else {
            throw Self.failure(status: http.statusCode, data: data)
        }
        return data
    }

    private func url(for request: UqpayRequest) throws -> URL {
        let base = environment.baseURL.absoluteString.hasSuffix("/")
            ? String(environment.baseURL.absoluteString.dropLast())
            : environment.baseURL.absoluteString
        let path = request.path.hasPrefix("/") ? String(request.path.dropFirst()) : request.path

        guard var components = URLComponents(string: "\(base)/\(path)") else {
            throw UqpayAPIError.notConfigured("Could not build a URL for \(request.path).")
        }
        if !request.query.isEmpty {
            components.queryItems = request.query
        }
        guard let url = components.url else {
            throw UqpayAPIError.notConfigured("Could not build a URL for \(request.path).")
        }
        return url
    }

    private static func failure(status: Int, data: Data) -> UqpayAPIError {
        if let body = try? JSONDecoder().decode(UqpayAPIErrorBody.self, from: data),
           !(body.code.isEmpty && body.type.isEmpty && body.message.isEmpty) {
            return .api(status: status, body: body)
        }
        return .unexpectedStatus(status: status, responseBody: String(data: data, encoding: .utf8))
    }
}
