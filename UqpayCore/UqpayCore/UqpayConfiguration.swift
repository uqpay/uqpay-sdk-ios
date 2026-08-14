//
//  UqpayConfiguration.swift
//  UqpayCore
//
//  Created by UQPAY on 10/09/2025.
//

import Foundation

// MARK: - Payment Callback Types

/// Types of payment callback results for URL scheme handling
public enum PaymentCallbackType: String {
    case success = "success"
    case failure = "failure"
    case cancel = "cancel"
}

// MARK: - Configuration Error Types

public enum UqpayConfigurationError: Error, LocalizedError {
    case clientSecretNotSet
    case clientSecretInvalid
    case environmentNotSet
    
    public var errorDescription: String? {
        switch self {
        case .clientSecretNotSet:
            return uqpayCoreLocalized("Client secret is not configured. Please set UqpayConfiguration.shared.clientSecret before making API calls.")
        case .clientSecretInvalid:
            return uqpayCoreLocalized("Client secret format is invalid. Please check your client secret and try again.")
        case .environmentNotSet:
            return uqpayCoreLocalized("Environment is not configured. Please set UqpayConfiguration.shared.environment before making API calls.")
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .clientSecretNotSet:
            return uqpayCoreLocalized("Client secret must be configured during app initialization")
        case .clientSecretInvalid:
            return uqpayCoreLocalized("Client secret must be a non-empty string with valid format")
        case .environmentNotSet:
            return uqpayCoreLocalized("Environment must be configured during app initialization")
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .clientSecretNotSet:
            return uqpayCoreLocalized("Set UqpayConfiguration.shared.clientSecret = \"your_client_secret\" in your app's initialization code.")
        case .clientSecretInvalid:
            return uqpayCoreLocalized("Ensure your client secret is properly formatted and not empty.")
        case .environmentNotSet:
            return uqpayCoreLocalized("Set UqpayConfiguration.shared.environment = .production (or other environment) in your app's initialization code.")
        }
    }
}

// MARK: - Configuration Class

/// Global configuration singleton for the UQPAY iOS SDK
/// 
/// Use this class to configure the SDK with your client secret and other settings
/// before making any API calls.
///
/// Example usage:
/// ```swift
/// // In your AppDelegate or SwiftUI App's init
/// UqpayConfiguration.shared.clientSecret = "your_client_secret_here"
/// UqpayConfiguration.shared.environment = .production
/// ```
public final class UqpayConfiguration {
    
    // MARK: - Singleton
    
    /// Shared instance of UqpayConfiguration
    public static let shared = UqpayConfiguration()
    
    // MARK: - Private Properties
    
    private let queue = DispatchQueue(label: "com.uqpay.configuration", attributes: .concurrent)
    private var _clientSecret: String?
    private var _clientId: String?
    private var _environment: UqpayEnvironment?
    private var _isConfigured = false
    private var _headerToken: String?
    private var _paymentIntentId: String?
    private var _clientSecretForPayment: String?
    private var _appReturnScheme: String?
    
    // MARK: - Initialization
    
    /// Private initializer to enforce singleton pattern
    private init() {}
    
    
    public var clientId: String? {
        get {
            return queue.sync { _clientId }
        }
        
        set {
            queue.async(flags: .barrier) { [weak self] in
                self?._clientId = newValue
                self?.updateConfigurationStatus()
            }
        }
    }
    // MARK: - Public Properties
    
    /// The client secret for authenticating API requests
    ///
    /// - Warning: Deprecated and no longer read by the payment flow. The SDK
    ///   authenticates with short-lived tokens from your backend
    ///   (`headerToken` / `clientSecretForPayment`); embedding a long-lived
    ///   secret in an app binary is unsafe. This property will be removed in
    ///   the next major release.
    @available(*, deprecated, message: "No longer read by the payment flow. Use short-lived tokens from your backend (headerToken / clientSecretForPayment) instead. Storing a long-lived secret in the app binary is unsafe.")
    public var clientSecret: String? {
        get {
            return queue.sync { _clientSecret }
        }
        set {
            queue.async(flags: .barrier) { [weak self] in
                self?._clientSecret = newValue
                self?.updateConfigurationStatus()
            }
        }
    }
    
    /// The environment for API requests (sandbox, testing, staging, production)
    ///
    /// There is no default: this must be set explicitly during app initialization,
    /// otherwise API calls fail with `UqpayConfigurationError.environmentNotSet`.
    public var environment: UqpayEnvironment? {
        get {
            return queue.sync { _environment }
        }
        set {
            queue.async(flags: .barrier) { [weak self] in
                self?._environment = newValue
                self?.updateConfigurationStatus()
            }
        }
    }
    
    /// Whether the SDK is properly configured and ready to make API calls
    public var isConfigured: Bool {
        return queue.sync { _isConfigured }
    }
    
    /// The header token obtained from the auth API for payment requests
    public var headerToken: String? {
        get {
            return queue.sync { _headerToken }
        }
        set {
            queue.async(flags: .barrier) { [weak self] in
                self?._headerToken = newValue
            }
        }
    }
    
    /// The payment intent ID from the create payment intent API
    public var paymentIntentId: String? {
        get {
            return queue.sync { _paymentIntentId }
        }
        set {
            queue.async(flags: .barrier) { [weak self] in
                self?._paymentIntentId = newValue
            }
        }
    }
    
    /// The client secret from the create payment intent API
    public var clientSecretForPayment: String? {
        get {
            return queue.sync { _clientSecretForPayment }
        }
        set {
            queue.async(flags: .barrier) { [weak self] in
                self?._clientSecretForPayment = newValue
            }
        }
    }

    /// The app's custom URL scheme for handling payment callbacks
    ///
    /// Set this to your app's URL scheme (e.g., "myapp://payment") to handle
    /// 3DS authentication and other payment redirects back to your app.
    ///
    /// Example:
    /// ```swift
    /// UqpayConfiguration.shared.appReturnScheme = "myapp://payment"
    /// ```
    ///
    /// The SDK will append the result path (success/failure/cancel) to create
    /// the full callback URL (e.g., "myapp://payment/success")
    public var appReturnScheme: String? {
        get {
            return queue.sync { _appReturnScheme }
        }
        set {
            queue.async(flags: .barrier) { [weak self] in
                self?._appReturnScheme = newValue
            }
        }
    }

    /// Returns the return URL for payment callbacks
    ///
    /// - Parameter result: The type of payment callback (success, failure, cancel)
    /// - Returns: The full return URL with the result path appended
    public func returnURL(for result: PaymentCallbackType) -> String {
        let baseScheme = queue.sync { _appReturnScheme } ?? "https://checkout.uqpay.com"
        let separator = baseScheme.hasSuffix("/") ? "" : "/"
        return "\(baseScheme)\(separator)\(result.rawValue)"
    }

    /// Returns the base return URL without result path
    public var baseReturnURL: String {
        return queue.sync { _appReturnScheme } ?? "https://checkout.uqpay.com"
    }

    // MARK: - Public Methods
    
    /// Validates the current configuration
    /// 
    /// - Throws: `UqpayConfigurationError` if configuration is invalid
    public func validateConfiguration() throws {
        // Reads the backing field: going through the deprecated public
        // accessor would emit a warning on every build.
        guard let clientSecret = queue.sync(execute: { _clientSecret }), !clientSecret.isEmpty else {
            throw UqpayConfigurationError.clientSecretNotSet
        }
        
        // Basic client secret format validation
        if clientSecret.count < 10 {
            throw UqpayConfigurationError.clientSecretInvalid
        }
        
        guard environment != nil else {
            throw UqpayConfigurationError.environmentNotSet
        }
    }

    /// Returns the configured environment, failing loudly when none was set.
    ///
    /// - Returns: The environment the merchant configured
    /// - Throws: `UqpayConfigurationError.environmentNotSet` when no environment
    ///   has been configured — the SDK never falls back to a test environment.
    public func requireEnvironment() throws -> UqpayEnvironment {
        guard let environment = self.environment else {
            throw UqpayConfigurationError.environmentNotSet
        }
        return environment
    }

    /// Returns the authorization header value for API requests
    /// 
    /// - Returns: Authorization header value in the format "Bearer {clientSecret}"
    /// - Throws: `UqpayConfigurationError` if client secret is not configured
    public func authorizationHeader() throws -> String {
        try validateConfiguration()
        guard let clientSecret = queue.sync(execute: { _clientSecret }) else {
            throw UqpayConfigurationError.clientSecretNotSet
        }
        return "Bearer \(clientSecret)"
    }
    
    /// Resets the configuration to default values
    /// 
    /// This method is primarily useful for testing or when switching between different configurations.
    public func reset() {
        queue.async(flags: .barrier) { [weak self] in
            self?._clientSecret = nil
            self?._environment = nil
            self?._isConfigured = false
            self?._headerToken = nil
            self?._paymentIntentId = nil
            self?._clientSecretForPayment = nil
            self?._appReturnScheme = nil
        }
        UqpayLogger.shared.logConfiguration("Configuration reset")
    }
    
    /// Configures the SDK with all required parameters at once
    ///
    /// - Parameters:
    ///   - clientSecret: The client secret for API authentication
    ///   - environment: The target environment (must be chosen explicitly)
    /// - Throws: `UqpayConfigurationError` if any parameters are invalid
    public func configure(clientSecret: String, environment: UqpayEnvironment) throws {
        // Validate parameters before setting
        guard !clientSecret.isEmpty, clientSecret.count >= 10 else {
            UqpayLogger.shared.error("Invalid client secret format provided")
            throw UqpayConfigurationError.clientSecretInvalid
        }
        
        queue.async(flags: .barrier) { [weak self] in
            self?._clientSecret = clientSecret
            self?._environment = environment
            self?.updateConfigurationStatus()
        }
        
        UqpayLogger.shared.logConfiguration("SDK configured with environment: \(environment.displayName)")
        
        // Validate the complete configuration
        try validateConfiguration()
    }
    
    // MARK: - Private Methods
    
    private func updateConfigurationStatus() {
        let hasClientId = _clientId != nil && !_clientId!.isEmpty && _clientId!.count >= 5
        let hasClientSecret = _clientSecret != nil && !_clientSecret!.isEmpty && _clientSecret!.count >= 10
        let hasEnvironment = _environment != nil
        _isConfigured = hasClientId && hasClientSecret && hasEnvironment
    }
}

// MARK: - Configuration Extensions

public extension UqpayConfiguration {
    
    /// Returns the appropriate ApiClient instance configured for the current environment
    /// 
    /// - Returns: Configured ApiClient instance
    /// - Throws: `UqpayConfigurationError` if configuration is invalid
    func apiClient() throws -> ApiClient {
        try validateConfiguration()
        return ApiClient.forEnvironment(try requireEnvironment())
    }
}

// MARK: - Development Helpers

#if DEBUG
public extension UqpayConfiguration {
    
    /// Configures the SDK for development/testing against the sandbox —
    /// the only test environment the SDK ships.
    ///
    /// - Warning: This method should only be used for development and testing.
    ///            Do not use in production code.
    func configureForDevelopment() {
        do {
            try configure(
                clientSecret: "dev_sk_test_12345678901234567890",
                environment: .sandboxMode
            )
        } catch {
            UqpayLogger.shared.logError(error, message: "Failed to configure for development")
        }
    }
    
    /// Returns whether the SDK is configured with development/test credentials
    var isDevelopmentMode: Bool {
        guard let clientSecret = queue.sync(execute: { _clientSecret }) else { return false }
        return clientSecret.hasPrefix("dev_") || clientSecret.hasPrefix("test_")
    }
}
#endif
