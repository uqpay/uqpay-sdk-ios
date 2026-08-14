//
//  MidConfirmDismissalTests.swift
//  UqpayPaymentSheetTests
//
//  A customer who taps Pay and swipes the sheet away has not cancelled: the
//  `POST /confirm` already reached the server, and cancelling a Swift task does
//  not un-charge a card. This used to report `paymentSheetDidCancel` — telling
//  the merchant the customer walked away from a payment their card was about to
//  be charged for.
//
//  These pin the corrected contract, and the boundaries around it: a dismissal
//  with no confirm in flight is still a cancellation, and a payment that already
//  reported an outcome still reports nothing.
//

import XCTest
import UIKit
@testable import UqpayCore
@testable import UqpayPayments
@testable import UqpayPaymentSheet

@MainActor
final class MidConfirmDismissalTests: XCTestCase {

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
        func paymentSheetDidCancel(_ paymentSheet: PaymentSheet) { cancelled += 1 }
        func paymentSheet(_ paymentSheet: PaymentSheet, requiresAction action: RequiredAction) {}
        func paymentSheet(_ paymentSheet: PaymentSheet, paymentDidBecomePending result: PaymentResult) {
            pending.append(result)
        }
    }

    private var savedIntentId: String?

    override func setUp() {
        super.setUp()
        savedIntentId = UqpayConfiguration.shared.paymentIntentId
        UqpayConfiguration.shared.paymentIntentId = "pi_mid_confirm"
    }

    override func tearDown() {
        UqpayConfiguration.shared.paymentIntentId = savedIntentId
        super.tearDown()
    }

    // MARK: - The corrected report

    func testDismissingMidConfirmReportsPendingNotCancelled() {
        let (card, sheet, delegate) = makeCard()

        // A confirm that has not answered yet. The task's body is irrelevant —
        // what matters is that one is in the air.
        card.confirmTask = Task { try? await Task.sleep(nanoseconds: 60_000_000_000) }
        card.handleFlowDismissal()
        sheet.cancelDetachedReconciliation()

        XCTAssertEqual(
            delegate.cancelled, 0,
            "A payment mid-authorization has not been cancelled — the card may well be charged"
        )
        XCTAssertEqual(delegate.pending.count, 1, "The merchant must hear that the outcome is unresolved")
        XCTAssertEqual(delegate.pending.first?.status, .processing)
        XCTAssertEqual(delegate.pending.first?.paymentIntentId, "pi_mid_confirm")
    }

    /// The pending report marks the payment as reported, so a second screen
    /// torn down by the same dismissal cannot follow it with a cancellation.
    func testPendingReportSuppressesALaterCancellation() {
        let (card, sheet, delegate) = makeCard()

        card.confirmTask = Task { try? await Task.sleep(nanoseconds: 60_000_000_000) }
        card.handleFlowDismissal()
        sheet.cancelDetachedReconciliation()

        let list = PaymentListViewController(
            appearance: PaymentSheet.Appearance(), configuration: PaymentSheet.Configuration()
        )
        list.paymentSheet = sheet
        list.paymentDelegate = delegate
        list.loadViewIfNeeded()
        list.handleFlowDismissal()

        XCTAssertEqual(delegate.cancelled, 0)
        XCTAssertEqual(delegate.pending.count, 1, "Exactly one report for one dismissal")
    }

    // MARK: - The boundaries stay put

    func testDismissingWithNoConfirmInFlightIsStillACancellation() {
        // `paymentSheet` is weak, so the sheet must stay bound for the duration
        // — a released sheet reports nothing at all, which is a different
        // (already covered) contract.
        let (card, sheet, delegate) = makeCard()
        withExtendedLifetime(sheet) {
            // Never tapped Pay.
            card.handleFlowDismissal()
        }

        XCTAssertEqual(delegate.cancelled, 1, "Walking away before paying is still a cancellation")
        XCTAssertEqual(delegate.pending.count, 0)
    }

    func testDismissingAfterAReportedOutcomeReportsNothing() {
        let (card, sheet, delegate) = makeCard()

        card.confirmTask = Task { }
        sheet.hasReportedOutcome = true   // the confirm answered and was reported
        card.handleFlowDismissal()

        XCTAssertEqual(delegate.cancelled, 0)
        XCTAssertEqual(delegate.pending.count, 0, "A resolved payment is not pending")
    }

    // MARK: - The detached watcher

    func testDetachedOutcomeIsDeliveredAtMostOnce() {
        let (_, sheet, delegate) = makeCard()
        let intent = intentFixture(status: "SUCCEEDED")

        for _ in 0..<3 {
            sheet.deliverDetachedOutcome { deleg, subject in
                deleg.paymentSheet(subject, didCompleteWithResult: ReconciledOutcome.successResult(for: intent))
            }
        }

        XCTAssertEqual(
            delegate.completed.count, 1,
            "A poller that observes the same settlement twice must not report it twice"
        )
    }

    func testDetachedOutcomeIsNotDeliveredWithoutADelegate() {
        let sheet = PaymentSheet()
        let intent = intentFixture(status: "SUCCEEDED")

        // No delegate set; must not trap, and must not consume the one delivery.
        sheet.deliverDetachedOutcome { deleg, subject in
            deleg.paymentSheet(subject, didCompleteWithResult: ReconciledOutcome.successResult(for: intent))
        }

        let delegate = SpyDelegate()
        sheet.paymentDelegate = delegate
        sheet.deliverDetachedOutcome { deleg, subject in
            deleg.paymentSheet(subject, didCompleteWithResult: ReconciledOutcome.successResult(for: intent))
        }

        XCTAssertEqual(
            delegate.completed.count, 1,
            "A delegate attached late must still receive the outcome — the slot is not burned by a no-op"
        )
    }

    func testCancellingDetachedReconciliationIsSafeWhenNoneIsRunning() {
        let sheet = PaymentSheet()
        sheet.cancelDetachedReconciliation()
        sheet.cancelDetachedReconciliation()
    }

    // MARK: - Payload agreement

    /// The on-screen watcher and the detached watcher must describe the same
    /// payment the same way.
    func testSuccessPayloadCarriesTheIntentsFields() {
        let result = ReconciledOutcome.successResult(for: intentFixture(status: "SUCCEEDED"))

        XCTAssertEqual(result.paymentIntentId, "pi_test_123")
        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.amount, 8.98, accuracy: 0.001)
        XCTAssertEqual(result.currency, "SGD")
        XCTAssertEqual(result.merchantOrderId, "order_42")
        XCTAssertEqual(result.paymentMethodType, "card")
    }

    /// The API commonly returns "" rather than omitting a failure field.
    func testEmptyFailureFieldsFallBackRatherThanSurfacingBlanks() {
        let intent = intentFixture(status: "FAILED", failureCode: "", failureMessage: "")

        XCTAssertNil(ReconciledOutcome.failureCode(for: intent), "An empty code is no code")
        XCTAssertFalse(
            ReconciledOutcome.failureMessage(for: intent).isEmpty,
            "A blank message must fall back to the SDK's own copy, never reach the customer empty"
        )
    }

    func testRealFailureFieldsAreCarriedThrough() {
        let intent = intentFixture(
            status: "FAILED", failureCode: "card_declined", failureMessage: "Your bank declined this payment."
        )
        let error = ReconciledOutcome.failureError(for: intent, underlying: nil)

        XCTAssertEqual(error.declineCode, "card_declined")
        XCTAssertEqual(error.message, "Your bank declined this payment.")
        XCTAssertEqual(error.paymentMethodType, "card")
    }

    // MARK: - Helpers

    private func makeCard() -> (PaymentCardViewController, PaymentSheet, SpyDelegate) {
        let delegate = SpyDelegate()
        let sheet = PaymentSheet()
        sheet.paymentDelegate = delegate

        let card = PaymentCardViewController()
        card.paymentSheet = sheet
        card.paymentDelegate = delegate
        card.loadViewIfNeeded()
        return (card, sheet, delegate)
    }

    private func intentFixture(
        status: String, failureCode: String? = nil, failureMessage: String? = nil
    ) -> UqpayPaymentIntent {
        let attempt: String
        if failureCode != nil || failureMessage != nil {
            attempt = """
            , "latest_payment_attempt": {"failure_code": "\(failureCode ?? "")", "failure_message": "\(failureMessage ?? "")"}
            """
        } else {
            attempt = ""
        }
        let json = """
        {"payment_intent_id": "pi_test_123", "intent_status": "\(status)", "amount": "8.98", "currency": "SGD", "merchant_order_id": "order_42"\(attempt)}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(UqpayPaymentIntent.self, from: Data(json.utf8))
    }
}
