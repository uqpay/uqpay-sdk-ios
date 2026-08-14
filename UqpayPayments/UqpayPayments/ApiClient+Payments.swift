//
//  ApiClient+Payments.swift
//  UqpayPayments
//
//  Created by UQPAY on 14/08/2025.
//

import Foundation
import UqpayCore

// MARK: - ApiClient Payment Extensions

@available(iOS 13.0, macOS 10.15, *)
public extension ApiClient {

    /// Gets payment intent details by ID
    /// - Parameter paymentIntentId: The payment intent ID to query
    /// - Returns: PaymentIntentCreateResponse with current payment status
    /// - Note: Calls GET /api/v2/payment_intents/{id} to retrieve payment intent details
    func getPaymentIntentById(_ paymentIntentId: String) async throws -> PaymentIntentCreateResponse {
        guard let authToken = UqpayConfiguration.shared.headerToken else {
            UqpayLogger.shared.error("Auth token not found in configuration")
            throw URLError(.userAuthenticationRequired)
        }

        guard let clientId = UqpayConfiguration.shared.clientId else {
            UqpayLogger.shared.error("Client ID not found in configuration")
            throw URLError(.userAuthenticationRequired)
        }

        // The environment must be configured explicitly — no silent fallback.
        let currentEnvironment = try UqpayConfiguration.shared.requireEnvironment()

        let baseURLString = currentEnvironment.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURLString)/api/v2/payment_intents/\(paymentIntentId)") else {
            UqpayLogger.shared.error("Failed to construct payment intent URL")
            throw URLError(.badURL)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue(clientId, forHTTPHeaderField: "x-client-id")
        urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "x-auth-token")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Same non-caching session as every other payment call.
        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            UqpayLogger.shared.error("Payment intent lookup returned a non-HTTP response")
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            UqpayLogger.shared.error("Payment intent lookup failed with status \(httpResponse.statusCode)")

            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let message = errorData["message"] as? String {
                    throw NSError(domain: "UqpayAPIError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
                }
            }
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        do {
            let response = try decoder.decode(PaymentIntentCreateResponse.self, from: data)
            return response
        } catch {
            UqpayLogger.shared.error("Failed to decode payment intent response: \(error)")
            throw error
        }
    }
}
