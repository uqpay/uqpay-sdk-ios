//
//  PaymentStatus.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 26/09/2025.
//

import Foundation

// MARK: - Payment Status

/// Represents the status of a payment operation
/// This enum is used throughout the payment flow to track the current state
public enum PaymentStatus {
    /// Payment completed successfully
    case succeeded

    /// Payment failed due to an error
    case failed

    /// Payment was cancelled by the user
    case cancelled

    /// Payment requires additional action (e.g., 3D Secure authentication)
    case requiresAction

    /// Payment is currently being processed
    case processing

    /// Payment is pending clearance (completed but awaiting final confirmation)
    case pending
}

// MARK: - Convenience Properties

public extension PaymentStatus {
    /// Returns true if the payment is in a terminal state (completed, failed, or cancelled)
    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled, .pending:
            return true
        case .requiresAction, .processing:
            return false
        }
    }

    /// Returns true if the payment was successful
    var isSuccessful: Bool {
        return self == .succeeded
    }

    /// Returns true if the payment is still in progress
    var isInProgress: Bool {
        switch self {
        case .processing, .requiresAction:
            return true
        case .succeeded, .failed, .cancelled, .pending:
            return false
        }
    }

    /// Returns a user-friendly display string for the status
    var displayString: String {
        switch self {
        case .succeeded:
            return UqpayLocalized("Payment Successful")
        case .failed:
            return UqpayLocalized("Payment Failed")
        case .cancelled:
            return UqpayLocalized("Payment Cancelled")
        case .requiresAction:
            return UqpayLocalized("Action Required")
        case .processing:
            return UqpayLocalized("Processing Payment")
        case .pending:
            return UqpayLocalized("Payment Pending")
        }
    }
}
