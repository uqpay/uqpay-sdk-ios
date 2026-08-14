//
//  PaymentContext.swift
//  UqpayPayments
//
//  Created by UQPAY on 09/10/2025.
//

import Foundation

/// Payment context to persist payment state across app launches
public struct PaymentContext: Codable {

    // MARK: - Properties

    /// Payment intent ID
    public let paymentIntentId: String

    /// Client secret for authentication
    public let clientSecret: String

    /// Timestamp when payment was initiated
    public let timestamp: TimeInterval

    /// Payment amount
    public let amount: Double?

    /// Payment currency
    public let currency: String?

    /// Payment method type
    public let paymentMethodType: String?

    // MARK: - Initialization

    public init(
        paymentIntentId: String,
        clientSecret: String,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        amount: Double? = nil,
        currency: String? = nil,
        paymentMethodType: String? = nil
    ) {
        self.paymentIntentId = paymentIntentId
        self.clientSecret = clientSecret
        self.timestamp = timestamp
        self.amount = amount
        self.currency = currency
        self.paymentMethodType = paymentMethodType
    }

    // MARK: - Helper Methods

    /// Check if payment context is expired (older than 30 minutes)
    public var isExpired: Bool {
        let currentTime = Date().timeIntervalSince1970
        let elapsedTime = currentTime - timestamp
        let thirtyMinutesInSeconds: TimeInterval = 30 * 60
        return elapsedTime > thirtyMinutesInSeconds
    }

    /// Get elapsed time since payment was initiated
    public var elapsedTime: TimeInterval {
        return Date().timeIntervalSince1970 - timestamp
    }
}
