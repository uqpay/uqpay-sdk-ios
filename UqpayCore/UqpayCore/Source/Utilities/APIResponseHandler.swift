//
//  APIResponseHandler.swift
//  UqpayCore
//
//  Created by UQPAY on 14/08/2025.
//

import Foundation

final class APIResponseHandler {
    
    // MARK: - Response Types
    
    public struct APIResult<T> {
        public let isSuccess: Bool
        public let data: T?
        public let error: APIError?
        public let httpStatusCode: Int?
        
        public var isFailure: Bool { !isSuccess }
    }
    
    public enum APIError: Error, LocalizedError {
        case networkError(String)
        case decodingError(String)
        case serverError(Int, String)
        case invalidResponse
        case unauthorized
        case forbidden
        case notFound
        case tooManyRequests
        case internalServerError
        case badRequest(String)
        case paymentRequired
        case custom(String)
        
        public var errorDescription: String? {
            switch self {
            case .networkError(let message):
                return "Network error: \(message)"
            case .decodingError(let message):
                return "Data parsing error: \(message)"
            case .serverError(let code, let message):
                return "Server error (\(code)): \(message)"
            case .invalidResponse:
                return "Invalid response from server"
            case .unauthorized:
                return "Authentication failed. Please check your credentials."
            case .forbidden:
                return "Access forbidden. Please contact support."
            case .notFound:
                return "The requested resource was not found."
            case .tooManyRequests:
                return "Too many requests. Please try again later."
            case .internalServerError:
                return "Server error. Please try again later."
            case .badRequest(let message):
                return "Invalid request: \(message)"
            case .paymentRequired:
                return "Payment required. Please check your account status."
            case .custom(let message):
                return message
            }
        }
        
        public var isRetryable: Bool {
            switch self {
            case .networkError, .tooManyRequests, .internalServerError, .serverError(500...599, _):
                return true
            default:
                return false
            }
        }
    }
    
    // MARK: - HTTP Response Handling
    
    /// Processes HTTP response and extracts data or error
    /// - Parameters:
    ///   - data: Response data
    ///   - response: URL response
    ///   - error: Network error, if any
    /// - Returns: Processed API result
    public static func processHTTPResponse<T: Codable>(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        responseType: T.Type
    ) -> APIResult<T> {
        
        // Handle network errors first
        if let error = error {
            let apiError = mapNetworkError(error)
            return APIResult(isSuccess: false, data: nil, error: apiError, httpStatusCode: nil)
        }
        
        // Ensure we have data and response
        guard let data = data, let httpResponse = response as? HTTPURLResponse else {
            return APIResult(isSuccess: false, data: nil, error: .invalidResponse, httpStatusCode: nil)
        }
        
        let statusCode = httpResponse.statusCode
        
        // Handle successful responses
        if 200...299 ~= statusCode {
            do {
                let decodedData = try JSONDecoder().decode(responseType, from: data)
                return APIResult(isSuccess: true, data: decodedData, error: nil, httpStatusCode: statusCode)
            } catch {
                let apiError = APIError.decodingError(error.localizedDescription)
                return APIResult(isSuccess: false, data: nil, error: apiError, httpStatusCode: statusCode)
            }
        }
        
        // Handle error responses
        let apiError = mapHTTPStatusCode(statusCode, data: data)
        return APIResult(isSuccess: false, data: nil, error: apiError, httpStatusCode: statusCode)
    }
    
    /// Processes a response that returns a simple success/failure with message
    /// - Parameters:
    ///   - data: Response data
    ///   - response: URL response
    ///   - error: Network error, if any
    /// - Returns: Simple result with success flag and message
    public static func processSimpleResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> (success: Bool, message: String?, statusCode: Int?) {
        
        // Handle network errors
        if let error = error {
            let apiError = mapNetworkError(error)
            return (false, apiError.errorDescription, nil)
        }
        
        guard let data = data, let httpResponse = response as? HTTPURLResponse else {
            return (false, "Invalid response from server", nil)
        }
        
        let statusCode = httpResponse.statusCode
        
        // Success case
        if 200...299 ~= statusCode {
            let message = extractMessageFromData(data) ?? "Request completed successfully"
            return (true, message, statusCode)
        }
        
        // Error case
        let errorMessage = extractErrorMessageFromData(data) ?? mapHTTPStatusCode(statusCode, data: data).errorDescription
        return (false, errorMessage, statusCode)
    }
    
    // MARK: - Error Mapping
    
    private static func mapNetworkError(_ error: Error) -> APIError {
        let nsError = error as NSError
        
        switch nsError.domain {
        case NSURLErrorDomain:
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return .networkError("No internet connection")
            case NSURLErrorTimedOut:
                return .networkError("Request timed out")
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
                return .networkError("Cannot connect to server")
            default:
                return .networkError(error.localizedDescription)
            }
        default:
            return .networkError(error.localizedDescription)
        }
    }
    
    private static func mapHTTPStatusCode(_ statusCode: Int, data: Data) -> APIError {
        // Try to extract custom error message from response
        let customMessage = extractErrorMessageFromData(data)
        
        switch statusCode {
        case 400:
            return .badRequest(customMessage ?? "Invalid request parameters")
        case 401:
            return .unauthorized
        case 402:
            return .paymentRequired
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 429:
            return .tooManyRequests
        case 500...599:
            return .serverError(statusCode, customMessage ?? "Internal server error")
        default:
            return .serverError(statusCode, customMessage ?? "Unknown error occurred")
        }
    }
    
    // MARK: - Data Extraction
    
    private static func extractErrorMessageFromData(_ data: Data) -> String? {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Try common error message keys
                if let message = json["message"] as? String { return message }
                if let error = json["error"] as? String { return error }
                if let errorDescription = json["error_description"] as? String { return errorDescription }
                
                // Try nested error object
                if let errorObj = json["error"] as? [String: Any],
                   let message = errorObj["message"] as? String {
                    return message
                }
            }
        } catch {
            // If JSON parsing fails, return nil
        }
        
        return nil
    }
    
    private static func extractMessageFromData(_ data: Data) -> String? {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let message = json["message"] as? String { return message }
                if let success = json["success"] as? String { return success }
            }
        } catch {
            // If JSON parsing fails, return nil
        }
        
        return nil
    }
    
    // MARK: - Retry Logic
    
    /// Determines if a request should be retried based on the error
    /// - Parameter error: The API error
    /// - Returns: Whether the request should be retried
    public static func shouldRetry(error: APIError) -> Bool {
        return error.isRetryable
    }
    
    /// Calculates retry delay with exponential backoff
    /// - Parameter attemptNumber: Current attempt number (starts at 0)
    /// - Returns: Delay in seconds
    public static func retryDelay(for attemptNumber: Int) -> TimeInterval {
        let baseDelay: TimeInterval = 1.0
        let maxDelay: TimeInterval = 30.0
        let delay = baseDelay * pow(2.0, Double(attemptNumber))
        return min(delay, maxDelay)
    }
}

// MARK: - Payment-Specific Helpers

extension APIResponseHandler {
    
    /// Payment response structure
    public struct PaymentResult {
        public let success: Bool
        public let paymentId: String?
        public let message: String
        public let redirectUrl: String?
        public let clientSecret: String?
        
        public init(success: Bool, paymentId: String? = nil, message: String, redirectUrl: String? = nil, clientSecret: String? = nil) {
            self.success = success
            self.paymentId = paymentId
            self.message = message
            self.redirectUrl = redirectUrl
            self.clientSecret = clientSecret
        }
    }
    
    /// Processes payment-specific API responses
    /// - Parameters:
    ///   - data: Response data
    ///   - response: URL response
    ///   - error: Network error
    /// - Returns: Payment result
    public static func processPaymentResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> PaymentResult {
        
        // Handle network errors
        if let error = error {
            let apiError = mapNetworkError(error)
            return PaymentResult(success: false, message: apiError.errorDescription ?? "Payment failed")
        }
        
        guard let data = data, let httpResponse = response as? HTTPURLResponse else {
            return PaymentResult(success: false, message: "Invalid response from server")
        }
        
        let statusCode = httpResponse.statusCode
        
        // Parse payment response
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let success = statusCode == 200 && (json["success"] as? Bool ?? false)
                let paymentId = json["paymentId"] as? String ?? json["payment_id"] as? String
                let message = json["message"] as? String ?? (success ? "Payment completed successfully" : "Payment failed")
                let redirectUrl = json["redirectUrl"] as? String ?? json["redirect_url"] as? String
                let clientSecret = json["clientSecret"] as? String ?? json["client_secret"] as? String
                
                return PaymentResult(
                    success: success,
                    paymentId: paymentId,
                    message: message,
                    redirectUrl: redirectUrl,
                    clientSecret: clientSecret
                )
            }
        } catch {
            // JSON parsing failed
        }
        
        // Fallback error handling
        let errorMessage = extractErrorMessageFromData(data) ?? mapHTTPStatusCode(statusCode, data: data).errorDescription ?? "Payment processing failed"
        return PaymentResult(success: false, message: errorMessage)
    }
}
