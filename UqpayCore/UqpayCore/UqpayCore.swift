//
//  UqpayCore.swift
//  UqpayCore
//
//  Created by UQPAY on 14/08/2025.
//

import Foundation
import UIKit

// MARK: - Environment Configuration

/// Environment configuration for UQPAY SDK API endpoints
///
/// The SDK exposes exactly the two merchant-facing environments:
/// - `sandboxMode`: Safe testing environment with test credentials
/// - `productionMode`: Live production environment for real transactions
///
/// UQPAY-internal hosts (testing/staging) are deliberately not part of this
/// enum: they are not a merchant surface, and shipping them here would embed
/// internal hostnames in every release binary. Internal tools that need them
/// use `UqpayAPIEnvironment.custom(_:)`.
public enum UqpayEnvironment: String, CaseIterable {
    case sandboxMode = "sandbox"
    case productionMode = "production"

    public var baseURL: URL {
        switch self {
        case .sandboxMode:
            // Sandbox environment for safe testing with test data
            return URL(string: "https://api-sandbox.uqpaytech.com/")!
        case .productionMode:
            // Production environment for live transactions
            return URL(string: "https://api.uqpay.com/")!
        }
    }

    /// Returns the auth service base URL for this environment
    public var authBaseURL: URL {
        switch self {
        case .sandboxMode:
            // Sandbox uses regular API URL for auth
            return URL(string: "https://api-sandbox.uqpaytech.com/")!
        case .productionMode:
            // Production uses regular API URL for auth
            return URL(string: "https://api.uqpay.com/")!
        }
    }

    public var displayName: String {
        switch self {
        case .sandboxMode:
            return "Sandbox"
        case .productionMode:
            return "Production"
        }
    }

    /// Returns true if this is a test/development environment
    public var isTestEnvironment: Bool {
        switch self {
        case .sandboxMode:
            return true
        case .productionMode:
            return false
        }
    }

    /// Returns the auth token endpoint for this environment
    /// Note: This endpoint uses the authBaseURL, not the regular baseURL
    public var authTokenEndpoint: String {
        return "api/v1/connect/token"
    }

    /// Returns the full auth token URL for this environment
    public var authTokenURL: URL {
        return authBaseURL.appendingPathComponent(authTokenEndpoint)
    }

    /// Returns the payment intent creation endpoint for this environment
    public var createPaymentIntentEndpoint: String {
        return "api/v2/payment_intents/create"
    }

    /// Returns the payment intent confirmation endpoint for this environment
    /// - Parameter paymentIntentId: The payment intent ID to confirm
    public func confirmPaymentIntentEndpoint(paymentIntentId: String) -> String {
        return "api/v2/payment_intents/\(paymentIntentId)/confirm"
    }
}

public final class ApiClient {

    private let urlSession: URLSession
    private let baseURL: URL
    private let environment: UqpayEnvironment

    /// The default session for payment traffic: ephemeral, so request and
    /// response bodies — which carry card data — are never written to the
    /// shared URL cache, cookie store, or credential store on disk. The
    /// timeouts match `URLSession.shared`'s defaults so slow-network payments
    /// behave exactly as they did on the shared session.
    private static let ephemeralSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: configuration)
    }()

    public init(urlSession: URLSession? = nil, environment: UqpayEnvironment) {
        self.urlSession = urlSession ?? ApiClient.ephemeralSession
        self.baseURL = environment.baseURL
        self.environment = environment
    }

    /// The session this client sends requests on. Exposed so payment
    /// extensions in other SDK modules use the same non-caching session
    /// instead of falling back to `URLSession.shared`.
    public var session: URLSession {
        return urlSession
    }

    /// Creates an ApiClient configured for a specific environment
    /// - Parameters:
    ///   - environment: The environment to configure the client for
    ///   - urlSession: URLSession instance; defaults to the SDK's ephemeral session
    /// - Returns: ApiClient instance configured for the specified environment
    public static func forEnvironment(_ environment: UqpayEnvironment, urlSession: URLSession? = nil) -> ApiClient {
        return ApiClient(urlSession: urlSession, environment: environment)
    }

    /// Creates an ApiClient for the environment set on `UqpayConfiguration.shared`.
    /// - Throws: `UqpayConfigurationError.environmentNotSet` when the merchant
    ///   never configured an environment — there is no silent default.
    public static func forConfiguredEnvironment(urlSession: URLSession? = nil) throws -> ApiClient {
        return ApiClient(urlSession: urlSession, environment: try UqpayConfiguration.shared.requireEnvironment())
    }
    
    /// Current environment of this ApiClient instance
    public var currentEnvironment: UqpayEnvironment {
        return environment
    }
    
    /// Validates that the SDK is properly configured before making API calls
    /// - Throws: `UqpayConfigurationError` if configuration is invalid
    public func validateConfiguration() throws {
        try UqpayConfiguration.shared.validateConfiguration()
    }
    
    /// Convenience method to get a properly configured ApiClient instance
    /// - Returns: ApiClient configured with the current UqpayConfiguration settings
    /// - Throws: `UqpayConfigurationError` if configuration is invalid
    public static func configured() throws -> ApiClient {
        return try UqpayConfiguration.shared.apiClient()
    }

    /// Performs an authenticated GET and returns the body of a successful
    /// (2xx) response.
    ///
    /// - Throws: `UqpayConfigurationError` when the SDK has no credentials
    ///   configured and no explicit `Authorization` header was passed — the
    ///   request is never sent unauthenticated. Throws `UqpayAPIError` for any
    ///   non-2xx status; inspect `UqpayAPIError.httpStatus` and `.apiCode`
    ///   instead of the raw status code.
    @available(iOS 13.0, macOS 10.15, *)
    public func get(path: String, queryItems: [URLQueryItem]? = nil, headers: [String: String]? = nil) async throws -> (Data, URLResponse) {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        UqpayLogger.shared.logAPIRequest(method: "GET", path: path)

        // The Authorization header comes from the configuration. An
        // unconfigured SDK fails loudly here — an unauthenticated request
        // would only ever produce a confusing 401 from the server.
        var allHeaders = headers ?? [:]
        if allHeaders["Authorization"] == nil {
            allHeaders["Authorization"] = try UqpayConfiguration.shared.authorizationHeader()
        }

        allHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        return try await send(request, path: path)
    }

    /// Performs an authenticated POST and returns the body of a successful
    /// (2xx) response.
    ///
    /// - Throws: `UqpayConfigurationError` when the SDK has no credentials
    ///   configured and no explicit `Authorization` header was passed — the
    ///   request is never sent unauthenticated. Throws `UqpayAPIError` for any
    ///   non-2xx status; inspect `UqpayAPIError.httpStatus` and `.apiCode`
    ///   instead of the raw status code.
    @available(iOS 13.0, macOS 10.15, *)
    public func post(path: String, body: Encodable? = nil, headers: [String: String]? = nil) async throws -> (Data, URLResponse) {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        UqpayLogger.shared.logAPIRequest(method: "POST", path: path)

        // The Authorization header comes from the configuration. An
        // unconfigured SDK fails loudly here — an unauthenticated request
        // would only ever produce a confusing 401 from the server.
        var allHeaders = headers ?? [:]
        if allHeaders["Authorization"] == nil {
            allHeaders["Authorization"] = try UqpayConfiguration.shared.authorizationHeader()
        }

        if let body = body {
            allHeaders["Content-Type"] = "application/json"
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }

        allHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        return try await send(request, path: path)
    }

    /// Sends the request and validates the HTTP status, so no caller can
    /// mistake an error body for a successful payload.
    @available(iOS 13.0, macOS 10.15, *)
    private func send(_ request: URLRequest, path: String) async throws -> (Data, URLResponse) {
        let data: Data
        let response: URLResponse
        if #available(iOS 15.0, macOS 12.0, *) {
            (data, response) = try await urlSession.data(for: request)
        } else {
            (data, response) = try await withCheckedThrowingContinuation { continuation in
                let task = urlSession.dataTask(with: request) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data, let response = response {
                        continuation.resume(returning: (data, response))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                task.resume()
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UqpayAPIError.unexpectedStatus(status: -1, responseBody: nil)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            UqpayLogger.shared.logAPIResponse(path: path, statusCode: httpResponse.statusCode)
            if let body = try? JSONDecoder().decode(UqpayAPIErrorBody.self, from: data),
               !(body.code.isEmpty && body.type.isEmpty && body.message.isEmpty) {
                throw UqpayAPIError.api(status: httpResponse.statusCode, body: body)
            }
            throw UqpayAPIError.unexpectedStatus(
                status: httpResponse.statusCode,
                responseBody: String(data: data, encoding: .utf8)
            )
        }
        return (data, response)
    }
}

private struct AnyEncodable: Encodable {
    private let encodeFunction: (Encoder) throws -> Void

    init(_ value: Encodable) {
        self.encodeFunction = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunction(encoder)
    }
}

public struct AnalyticsEvent: Codable {
    public let name: String
    public let properties: [String: String]

    public init(name: String, properties: [String: String] = [:]) {
        self.name = name
        self.properties = properties
    }
}

final class AnalyticsClient {
    private let apiClient: ApiClient

    public init(apiClient: ApiClient) {
        self.apiClient = apiClient
    }

    public func track(_ event: AnalyticsEvent) async {
        if #available(iOS 13.0, macOS 10.15, *) {
            do {
                _ = try await apiClient.post(path: "analytics/track", body: event)
            } catch {
                // Intentionally ignore analytics failures
            }
        }
    }
}

