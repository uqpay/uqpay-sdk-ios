//
//  ConfirmStatusReportingTests.swift
//  UqpayPaymentSheetTests
//
//  Created by UQPAY on 12/08/2026.
//

import XCTest
import UIKit
@testable import UqpayCore
@testable import UqpayPayments
@testable import UqpayPaymentSheet

/// Pins the contract that every confirm-response status produces exactly one
/// merchant report.
///
/// `FAILED` and `CANCELLED` used to update the customer's screen and tell the
/// merchant nothing — and the dismissal fallback could not save it, because a
/// status screen pushed on top swallows the card screen's `viewDidDisappear`.
/// `PENDING` and `PROCESSING` reported nothing at all. A merchant's order flow
/// hangs forever on any silent branch, which is why this suite drives every
/// branch of the status switch and counts the callbacks.
@MainActor
final class ConfirmStatusReportingTests: XCTestCase {

    private final class SpyDelegate: PaymentDelegate {
        var completed: [PaymentResult] = []
        var failed: [PaymentError] = []
        var pending: [PaymentResult] = []
        var cancelled = 0

        func paymentSheet(_ paymentSheet: PaymentSheet, didCompleteWithResult result: PaymentResult) {
            completed.append(result)
        }

        func paymentSheet(_ paymentSheet: PaymentSheet, didFailWithError error: PaymentError) {
            failed.append(error)
        }

        func paymentSheetDidCancel(_ paymentSheet: PaymentSheet) {
            cancelled += 1
        }

        func paymentSheet(_ paymentSheet: PaymentSheet, paymentDidBecomePending result: PaymentResult) {
            pending.append(result)
        }

        var totalOutcomes: Int { completed.count + failed.count + pending.count }
    }

    private var delegate: SpyDelegate!
    private var sheet: PaymentSheet!
    private var card: PaymentCardViewController!
    private var navigation: UINavigationController!

    override func setUp() async throws {
        delegate = SpyDelegate()
        sheet = PaymentSheet()
        sheet.paymentDelegate = delegate

        card = PaymentCardViewController()
        card.paymentSheet = sheet
        card.paymentDelegate = delegate

        navigation = UINavigationController(rootViewController: card)
        navigation.loadViewIfNeeded()
        card.loadViewIfNeeded()
    }

    private func response(
        status: String,
        attempt: PaymentAttempt? = nil
    ) -> ConfirmPaymentIntentResponse {
        ConfirmPaymentIntentResponse(
            paymentIntentId: "pi_test_123",
            amount: "8.98",
            currency: "SGD",
            clientSecret: "cs_test",
            merchantOrderId: "order_42",
            latestPaymentAttempt: attempt,
            intentStatus: status
        )
    }

    /// `PaymentAttempt` only exposes its lenient decoder, so fixtures decode.
    private func failedAttempt(failureCode: String?) -> PaymentAttempt {
        let json = """
        {"attempt_id": "att_1", "attempt_status": "FAILED"\(failureCode.map { ", \"failure_code\": \"\($0)\"" } ?? "")}
        """
        return try! JSONDecoder().decode(PaymentAttempt.self, from: Data(json.utf8))
    }

    // MARK: - Terminal statuses report exactly once

    func testSucceededReportsCompletionOnceAndNeverACancellation() {
        card.handleConfirmResponse(response(status: "SUCCEEDED"))

        XCTAssertEqual(delegate.completed.count, 1)
        XCTAssertEqual(delegate.totalOutcomes, 1)
        XCTAssertEqual(delegate.completed.first?.amountDecimal, Decimal(string: "8.98"),
                       "The confirm-success site must carry the exact amount")

        card.handleFlowDismissal()
        XCTAssertEqual(delegate.cancelled, 0, "A completed payment must not also report a cancellation")
    }

    func testFailedReportsFailureOnceAndNeverACancellation() {
        card.handleConfirmResponse(response(status: "FAILED"))

        XCTAssertEqual(delegate.failed.count, 1)
        XCTAssertEqual(delegate.totalOutcomes, 1)
        XCTAssertEqual(delegate.failed.first?.paymentMethodType, "card")

        // The dismissal fallback cannot fire from a status screen — the
        // report above must be the one the merchant gets.
        card.handleFlowDismissal()
        XCTAssertEqual(delegate.cancelled, 0, "A declined payment must not also report a cancellation")
    }

    func testFailedCarriesTheAttemptFailureCode() {
        card.handleConfirmResponse(response(status: "FAILED", attempt: failedAttempt(failureCode: "3ds_failed")))

        XCTAssertEqual(delegate.failed.count, 1)
        XCTAssertEqual(delegate.failed.first?.code, .threeDSFailed)
        XCTAssertEqual(delegate.failed.first?.declineCode, "3ds_failed")
    }

    func testCancelledReportsTheCancelledCode() {
        card.handleConfirmResponse(response(status: "CANCELLED"))

        XCTAssertEqual(delegate.failed.count, 1)
        XCTAssertEqual(delegate.failed.first?.code, .cancelled)
        XCTAssertEqual(delegate.totalOutcomes, 1)

        card.handleFlowDismissal()
        XCTAssertEqual(delegate.cancelled, 0)
    }

    func testDeclinedAttemptUnderRequiresPaymentMethodReportsFailure() {
        card.handleConfirmResponse(response(
            status: "REQUIRES_PAYMENT_METHOD",
            attempt: failedAttempt(failureCode: "insufficient_funds")
        ))

        XCTAssertEqual(delegate.failed.count, 1)
        XCTAssertEqual(delegate.failed.first?.code, .insufficientFunds)
        XCTAssertEqual(delegate.totalOutcomes, 1)
    }

    func testUnexpectedStatusReportsUnknownFailure() {
        card.handleConfirmResponse(response(status: "SOMETHING_NEW"))

        XCTAssertEqual(delegate.failed.count, 1)
        XCTAssertEqual(delegate.failed.first?.code, .unknown)
        XCTAssertEqual(delegate.failed.first?.declineCode, "SOMETHING_NEW")
    }

    func testCustomerActionWithoutPayloadReportsFailure() {
        // REQUIRES_CUSTOMER_ACTION with no next_action cannot proceed; it
        // must surface as a failure, not silence.
        card.handleConfirmResponse(response(status: "REQUIRES_CUSTOMER_ACTION"))

        XCTAssertEqual(delegate.failed.count, 1)
        XCTAssertEqual(delegate.totalOutcomes, 1)
    }

    // MARK: - Pre-confirm terminal-intent intercept

    /// `UqpayPaymentIntent` only decodes, and the wire is snake_case.
    private func intentFixture(status: String) -> UqpayPaymentIntent {
        let json = """
        {"payment_intent_id": "pi_test_123", "intent_status": "\(status)", "amount": "8.98", "currency": "SGD", "merchant_order_id": "order_42"}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(UqpayPaymentIntent.self, from: Data(json.utf8))
    }

    /// The relaunch-recovery UX: the customer's pre-kill confirm actually
    /// went through, so tapping Pay again is answered with their success —
    /// reported to the merchant exactly once — never a second attempt.
    func testInterceptReportsASucceededIntentAsTheSuccessItIs() {
        let intercepted = card.interceptTerminalIntent(intentFixture(status: "SUCCEEDED"))

        XCTAssertTrue(intercepted, "a settled payment must not be confirmed again")
        XCTAssertEqual(delegate.completed.count, 1)
        XCTAssertEqual(delegate.totalOutcomes, 1)
        XCTAssertEqual(delegate.completed.first?.amountDecimal, Decimal(string: "8.98"),
                       "The reconciled-outcome site must carry the exact amount")
    }

    func testInterceptReportsACancelledIntentAsAFailure() {
        let intercepted = card.interceptTerminalIntent(intentFixture(status: "CANCELLED"))

        XCTAssertTrue(intercepted)
        XCTAssertEqual(delegate.failed.count, 1)
        XCTAssertEqual(delegate.totalOutcomes, 1)
    }

    func testInterceptReportsAFailedIntentAsAFailure() {
        let intercepted = card.interceptTerminalIntent(intentFixture(status: "FAILED"))

        XCTAssertTrue(intercepted)
        XCTAssertEqual(delegate.failed.count, 1)
    }

    /// Anything non-terminal proceeds to the confirm untouched — the
    /// intercept must never become a new way to block a live payment.
    func testInterceptLetsALiveIntentProceed() {
        for status in ["REQUIRES_PAYMENT_METHOD", "REQUIRES_CUSTOMER_ACTION", "PENDING", "REQUIRES_CAPTURE"] {
            let intercepted = card.interceptTerminalIntent(intentFixture(status: status))
            XCTAssertFalse(intercepted, "\(status) is not settled; the confirm decides")
        }
        XCTAssertEqual(delegate.totalOutcomes, 0)
    }

    // MARK: - Unresolved statuses report pending, never failure or silence

    func testPendingReportsPendingExactlyOnce() {
        card.handleConfirmResponse(response(status: "PENDING"))

        XCTAssertEqual(delegate.pending.count, 1)
        XCTAssertEqual(delegate.pending.first?.status, .pending)
        XCTAssertEqual(delegate.pending.first?.paymentIntentId, "pi_test_123")
        XCTAssertEqual(delegate.pending.first?.amountDecimal, Decimal(string: "8.98"),
                       "The confirm-pending site must carry the exact amount")
        XCTAssertEqual(delegate.completed.count, 0, "Pending must never masquerade as success")
        XCTAssertEqual(delegate.failed.count, 0, "Pending must never masquerade as failure")
    }

    func testPendingSuppressesTheCancellationFallback() {
        card.handleConfirmResponse(response(status: "PENDING"))
        card.handleFlowDismissal()

        XCTAssertEqual(delegate.cancelled, 0,
                       "Closing a pending screen is not abandoning the payment — money may be moving")
    }

    func testProcessingReportsPendingAndShowsAScreen() {
        card.handleConfirmResponse(response(status: "PROCESSING"))

        XCTAssertEqual(delegate.pending.count, 1)
        XCTAssertEqual(delegate.pending.first?.status, .processing)
        // This branch used to be a no-op without a status screen up — the
        // customer stared at a disabled Pay button forever.
        XCTAssertTrue(navigation.viewControllers.last is PaymentCardStatusViewController)
    }

    // MARK: - Every branch, one report

    func testEveryTerminalOrRestingStatusProducesExactlyOneReport() {
        let statuses = ["SUCCEEDED", "FAILED", "CANCELLED", "PENDING", "PROCESSING", "SOMETHING_NEW"]

        for status in statuses {
            let delegate = SpyDelegate()
            let sheet = PaymentSheet()
            sheet.paymentDelegate = delegate

            let card = PaymentCardViewController()
            card.paymentSheet = sheet
            card.paymentDelegate = delegate
            let navigation = UINavigationController(rootViewController: card)
            navigation.loadViewIfNeeded()
            card.loadViewIfNeeded()

            card.handleConfirmResponse(response(status: status))
            XCTAssertEqual(delegate.totalOutcomes, 1, "\(status) must produce exactly one report")

            card.handleFlowDismissal()
            XCTAssertEqual(delegate.cancelled, 0, "\(status) already reported; dismissal must add nothing")
        }
    }

    // MARK: - The status screen's refresh hook

    func testRefreshOutcomeHandlerFiresForTerminalStatusesOnly() {
        let statusVC = PaymentCardStatusViewController.pending(transactionId: "pi_test_123", message: "waiting")
        statusVC.loadViewIfNeeded()

        var observed: [String] = []
        statusVC.enableRefresh(paymentIntentId: "pi_test_123") { response in
            observed.append(response.intentStatus)
        }

        statusVC.handlePaymentStatusResponse(response(status: "REQUIRES_CUSTOMER_ACTION"))
        XCTAssertTrue(observed.isEmpty, "A non-terminal status is not an outcome")

        statusVC.handlePaymentStatusResponse(response(status: "SUCCEEDED"))
        XCTAssertEqual(observed, ["SUCCEEDED"],
                       "An outcome the refresh poll discovers must reach the owning flow")
    }

    // MARK: - Pending keeps its reference data (the customer's receipt line)

    func testTransitionToPendingKeepsTransactionIdAndAmount() {
        let statusVC = PaymentCardStatusViewController.processing(message: "Processing…")
        statusVC.loadViewIfNeeded()

        statusVC.transitionFromPending(
            to: .pending,
            transactionId: "pi_test_123",
            message: "Your payment is pending."
        )

        XCTAssertEqual(statusVC.configuration.transactionId, "pi_test_123",
                       "A pending customer has nothing to quote without the reference")
    }
}
