//
//  ReconciledOutcome.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 13/08/2026.
//

import Foundation
import UqpayCore
import UqpayPayments

/// The merchant-facing payload for an intent observed by polling rather than by
/// a confirm response.
///
/// Two paths now do that polling: the card screen's `watchUnsettledIntent`
/// while the flow is still on screen, and ``PaymentSheet``'s detached
/// reconciliation after the customer has dismissed the sheet. Both build their
/// payloads here, so the same payment cannot describe itself one way to a
/// merchant who stayed on the screen and another way to one who did not.
///
/// This type holds **only** payload construction. Deciding which statuses count
/// as settled, and what the UI does about it, deliberately stays with each
/// caller — those rules legitimately differ (the pre-confirm interceptor treats
/// `REQUIRES_CAPTURE` as unsettled, the watchers treat it as an authorization).
enum ReconciledOutcome {

    /// The failure code the API actually returned, or nil when it returned the
    /// empty string — which it commonly does instead of omitting the field.
    static func failureCode(for intent: UqpayPaymentIntent) -> String? {
        let attempt = intent.latestPaymentAttempt
        return (attempt?.failureCode?.isEmpty == false) ? attempt?.failureCode : nil
    }

    /// The customer-facing failure message, falling back to the SDK's own copy
    /// when the API supplied none.
    static func failureMessage(for intent: UqpayPaymentIntent) -> String {
        let attempt = intent.latestPaymentAttempt
        let message = (attempt?.failureMessage?.isEmpty == false) ? attempt?.failureMessage : nil
        return message ?? UqpayLocalized("The payment could not be completed. Please try again.")
    }

    /// The result reported for an intent whose authorization succeeded.
    static func successResult(for intent: UqpayPaymentIntent) -> PaymentResult {
        PaymentResult(
            paymentIntentId: intent.paymentIntentId,
            paymentMethodType: "card",
            status: .succeeded,
            amount: intent.amount.flatMap(Double.init) ?? 0,
            currency: intent.currency ?? "",
            merchantOrderId: intent.merchantOrderId,
            completedAt: Date(),
            transactionId: intent.paymentIntentId
        )
    }

    /// The error reported for an intent that is dead as a whole — `FAILED` or
    /// `CANCELLED` — which needs no attempt attribution.
    static func failureError(
        for intent: UqpayPaymentIntent, underlying: Error?
    ) -> PaymentError {
        PaymentError(
            code: PaymentCardViewController.errorCode(
                forFailureCode: failureCode(for: intent),
                intentStatus: intent.intentStatus
            ),
            message: failureMessage(for: intent),
            underlyingError: underlying,
            declineCode: failureCode(for: intent),
            paymentMethodType: "card"
        )
    }
}
