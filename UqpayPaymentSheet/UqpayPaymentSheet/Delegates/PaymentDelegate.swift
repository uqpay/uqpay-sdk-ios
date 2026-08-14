//
//  PaymentDelegate.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 26/09/2025.
//

import Foundation
import UqpayPayments
import UqpayCore

// MARK: - Payment Result

/// Contains information about a completed payment attempt
public struct PaymentResult {
    /// Unique identifier for the payment intent
    public let paymentIntentId: String

    /// The payment method type used (e.g., "card", "apple_pay", "wechat_pay")
    public let paymentMethodType: String

    /// The status of the payment
    public let status: PaymentStatus

    /// The amount that was charged or attempted
    public let amount: Double

    /// The currency code (e.g., "SGD", "USD")
    public let currency: String

    /// Additional metadata about the payment
    public let metadata: [String: Any]?

    /// Optional merchant order ID
    public let merchantOrderId: String?

    /// Timestamp when the payment was completed
    public let completedAt: Date?

    /// Optional transaction ID from the payment processor
    public let transactionId: String?

    /// Optional receipt URL if available
    public let receiptUrl: String?

    public init(
        paymentIntentId: String,
        paymentMethodType: String,
        status: PaymentStatus,
        amount: Double,
        currency: String,
        metadata: [String: Any]? = nil,
        merchantOrderId: String? = nil,
        completedAt: Date? = nil,
        transactionId: String? = nil,
        receiptUrl: String? = nil
    ) {
        self.paymentIntentId = paymentIntentId
        self.paymentMethodType = paymentMethodType
        self.status = status
        self.amount = amount
        self.currency = currency
        self.metadata = metadata
        self.merchantOrderId = merchantOrderId
        self.completedAt = completedAt
        self.transactionId = transactionId
        self.receiptUrl = receiptUrl
    }
}

// MARK: - Payment Error

/// Represents an error that occurred during payment processing
public struct PaymentError: Error, LocalizedError {
    /// Error code for categorizing the error type.
    ///
    /// This taxonomy is **non-exhaustive**: new codes can be added in a minor
    /// release as the API grows. Always include a `default:` branch when
    /// switching over it.
    public enum ErrorCode: String, CaseIterable {
        case invalidPaymentMethod = "invalid_payment_method"
        case insufficientFunds = "insufficient_funds"
        case cardDeclined = "card_declined"
        case networkError = "network_error"
        case authenticationFailed = "authentication_failed"
        case threeDSFailed = "3ds_failed"
        case cancelled = "cancelled"
        case timeout = "timeout"
        case invalidConfiguration = "invalid_configuration"
        case unknown = "unknown"
    }

    /// The error code
    public let code: ErrorCode

    /// Human-readable error message
    public let message: String

    /// Optional underlying error
    public let underlyingError: Error?

    /// Optional decline code from payment processor
    public let declineCode: String?

    /// Recovery suggestion for the user
    public let recoverySuggestion: String?

    /// Payment method type that failed
    public let paymentMethodType: String?

    public var errorDescription: String? {
        return message
    }

    public init(
        code: ErrorCode,
        message: String,
        underlyingError: Error? = nil,
        declineCode: String? = nil,
        recoverySuggestion: String? = nil,
        paymentMethodType: String? = nil
    ) {
        self.code = code
        self.message = message
        self.underlyingError = underlyingError
        self.declineCode = declineCode
        self.recoverySuggestion = recoverySuggestion
        self.paymentMethodType = paymentMethodType
    }
}

// MARK: - Payment Delegate Protocol

/// Main delegate protocol for receiving payment activity results
/// Merchants should implement this protocol to handle payment success and failure callbacks
public protocol PaymentDelegate: AnyObject {

    /// Called when a payment is successfully completed
    /// - Parameters:
    ///   - paymentSheet: The payment sheet instance
    ///   - result: Details about the successful payment
    func paymentSheet(_ paymentSheet: PaymentSheet, didCompleteWithResult result: PaymentResult)

    /// Called when a payment fails
    /// - Parameters:
    ///   - paymentSheet: The payment sheet instance
    ///   - error: Details about the payment failure
    func paymentSheet(_ paymentSheet: PaymentSheet, didFailWithError error: PaymentError)

    /// Called when the user cancels the payment.
    ///
    /// Reported when the customer leaves the flow — closing the sheet, or
    /// swiping it away — **without a payment attempt in the air**. Reaching the
    /// method list and dismissing it counts; so does abandoning the card form
    /// before tapping Pay.
    ///
    /// Dismissing the sheet *during* a confirm is deliberately **not** a
    /// cancellation: the request already reached the server and the card may
    /// still be charged. That case reports
    /// ``paymentSheet(_:paymentDidBecomePending:)`` instead, and the SDK keeps
    /// reconciling in the background.
    /// - Parameter paymentSheet: The payment sheet instance
    func paymentSheetDidCancel(_ paymentSheet: PaymentSheet)

    /// Called when the customer must do something before the payment can
    /// continue — complete a 3D Secure challenge, or scan a wallet QR code.
    ///
    /// Informational: the SDK presents the step itself and reports the outcome
    /// through the methods above. Useful for analytics, or to pause your own
    /// UI while the customer is in the issuer's flow.
    /// - Parameters:
    ///   - paymentSheet: The payment sheet instance
    ///   - action: The type of action required
    func paymentSheet(_ paymentSheet: PaymentSheet, requiresAction action: RequiredAction)

    /// Called when the sheet stops actively driving the payment while its
    /// outcome is still unresolved — the API returned `PENDING`, a QR /
    /// authentication step timed out with the payment possibly still live, or
    /// **the customer dismissed the sheet while a confirm was in flight**.
    ///
    /// In that last case the SDK keeps polling the intent for about a minute
    /// after the UI has gone, so a payment that settles moments later still
    /// reaches you as `didCompleteWithResult` or `didFailWithError`. That
    /// background poll is owned by the ``PaymentSheet`` instance: keep your
    /// reference to it alive until you have an outcome, or the reconciliation
    /// stops with it.
    ///
    /// The customer sees an honest "payment pending" screen; this tells your
    /// app the same thing so it can stop waiting. The authoritative outcome
    /// arrives on your backend by webhook. `result.status` is `.pending` or
    /// `.processing`, and no `paymentSheetDidCancel` follows for this payment
    /// — a customer closing a pending screen has not abandoned the payment.
    /// If the SDK does observe the settlement while the sheet is still open
    /// (it keeps polling briefly), `didCompleteWithResult` or
    /// `didFailWithError` is still delivered.
    /// - Parameters:
    ///   - paymentSheet: The payment sheet instance
    ///   - result: What is known about the unresolved payment
    func paymentSheet(_ paymentSheet: PaymentSheet, paymentDidBecomePending result: PaymentResult)
}

// MARK: - Default Protocol Implementations (Making methods optional)
public extension PaymentDelegate {
    /// Default implementation - does nothing
    func paymentSheetDidCancel(_ paymentSheet: PaymentSheet) {}

    /// Default implementation - does nothing
    func paymentSheet(_ paymentSheet: PaymentSheet, requiresAction action: RequiredAction) {}

    /// Default implementation - does nothing
    func paymentSheet(_ paymentSheet: PaymentSheet, paymentDidBecomePending result: PaymentResult) {}
}

// MARK: - Required Action

/// Represents an action required from the user to complete the payment
public enum RequiredAction {
    /// 3D Secure authentication required
    case authenticate3DS(url: String)

    /// QR code scan required (e.g., for WeChat Pay)
    case scanQRCode(qrCodeUrl: String)

    /// Bank transfer details to display
    case displayBankDetails(details: BankTransferDetails)

    /// OTP verification required
    case verifyOTP

    /// Custom action with details
    case custom(type: String, details: [String: Any])
}

// MARK: - Bank Transfer Details

/// Contains bank transfer information for display to the user
public struct BankTransferDetails {
    public let bankName: String
    public let accountNumber: String
    public let accountName: String
    public let swiftCode: String?
    public let referenceNumber: String
    public let amount: Double
    public let currency: String

    public init(
        bankName: String,
        accountNumber: String,
        accountName: String,
        swiftCode: String? = nil,
        referenceNumber: String,
        amount: Double,
        currency: String
    ) {
        self.bankName = bankName
        self.accountNumber = accountNumber
        self.accountName = accountName
        self.swiftCode = swiftCode
        self.referenceNumber = referenceNumber
        self.amount = amount
        self.currency = currency
    }
}

// MARK: - Convenience Extensions

extension PaymentResult {
    /// Creates a PaymentResult from a ConfirmPaymentIntentResponse
    public init(from response: ConfirmPaymentIntentResponse) {
        let status: PaymentStatus
        switch response.intentStatus.uppercased() {
        case "SUCCEEDED":
            status = .succeeded
        case "REQUIRES_ACTION":
            status = .requiresAction
        case "PROCESSING":
            status = .processing
        case "PENDING":
            status = .pending
        case "CANCELLED", "CANCELED":
            status = .cancelled
        default:
            status = .failed
        }

        self.init(
            paymentIntentId: response.paymentIntentId,
            paymentMethodType: response.paymentMethod?.type ?? "unknown",
            status: status,
            amount: Double(response.amount) ?? 0.0,
            currency: response.currency,
            metadata: response.metadata,
            merchantOrderId: response.merchantOrderId,
            completedAt: response.completeTime != nil ? Date() : nil,
            transactionId: response.latestPaymentAttempt?.attemptId,
            receiptUrl: nil
        )
    }
}

// MARK: - Legacy Support

///// Legacy delegate for card-specific payments (deprecated)
///// Use PaymentDelegate instead for all payment methods
//@available(*, deprecated, message: "Use PaymentDelegate instead for handling all payment methods")
//public protocol PaymentCardDelegate: AnyObject {
//    func paymentCard(didCompleteWithResult result: PaymentResult)
//    func paymentCard(didFailWithError error: PaymentError)
//    func paymentCardDidCancel()
//}
