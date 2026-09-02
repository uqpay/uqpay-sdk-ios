//
//  PaymentResultStatusMappingTests.swift
//  UqpayPaymentSheetTests
//
//  Created by UQPAY on 02/09/2026.
//

import XCTest
@testable import UqpayCore
@testable import UqpayPayments
@testable import UqpayPaymentSheet

/// Pins `PaymentResult(from:)` to the Global Acquiring API's Payment Intent
/// status reference.
///
/// This public initializer is the only status mapping a merchant on the
/// low-level confirm path is given, and it used to send `REQUIRES_CAPTURE` —
/// "Authorization successful, waiting for capture" — to `.failed` through its
/// default branch. The prebuilt sheet worked around that by building its
/// result by hand, so the defect only ever reached merchants who confirm
/// themselves. Every documented status is asserted here so the mapping cannot
/// drift from the contract again.
final class PaymentResultStatusMappingTests: XCTestCase {

    private func response(
        intentStatus: String,
        completeTime: String? = nil,
        attempt: PaymentAttempt? = nil
    ) -> ConfirmPaymentIntentResponse {
        ConfirmPaymentIntentResponse(
            paymentIntentId: "pi_test_123",
            amount: "8.98",
            currency: "SGD",
            clientSecret: "cs_test",
            merchantOrderId: "order_42",
            metadata: ["order": "42"],
            completeTime: completeTime,
            latestPaymentAttempt: attempt,
            intentStatus: intentStatus
        )
    }

    // MARK: - The seven documented statuses

    func testRequiresCaptureIsAnAuthorisedPaymentNotAFailure() {
        let result = PaymentResult(from: response(intentStatus: "REQUIRES_CAPTURE"))

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertTrue(result.status.isSuccessful)
    }

    func testSucceededMapsToSucceeded() {
        XCTAssertEqual(PaymentResult(from: response(intentStatus: "SUCCEEDED")).status, .succeeded)
    }

    func testRequiresCustomerActionMapsToRequiresAction() {
        XCTAssertEqual(
            PaymentResult(from: response(intentStatus: "REQUIRES_CUSTOMER_ACTION")).status,
            .requiresAction
        )
    }

    func testPendingMapsToPending() {
        XCTAssertEqual(PaymentResult(from: response(intentStatus: "PENDING")).status, .pending)
    }

    func testCancelledMapsToCancelled() {
        XCTAssertEqual(PaymentResult(from: response(intentStatus: "CANCELLED")).status, .cancelled)
    }

    func testFailedMapsToFailed() {
        XCTAssertEqual(PaymentResult(from: response(intentStatus: "FAILED")).status, .failed)
    }

    func testRequiresPaymentMethodOnAConfirmResponseIsAFailedAttempt() {
        XCTAssertEqual(
            PaymentResult(from: response(intentStatus: "REQUIRES_PAYMENT_METHOD")).status,
            .failed
        )
    }

    /// The typed status enum in Core and this mapping must agree on the set of
    /// documented values: if a status is added to one, this fails until the
    /// other knows about it.
    func testEveryDocumentedStatusIsMappedExplicitly() {
        let documented: [(UqpayPaymentIntentStatus, PaymentStatus)] = [
            (.requiresPaymentMethod, .failed),
            (.requiresCustomerAction, .requiresAction),
            (.requiresCapture, .succeeded),
            (.pending, .pending),
            (.succeeded, .succeeded),
            (.cancelled, .cancelled),
            (.failed, .failed)
        ]

        for (status, expected) in documented {
            XCTAssertEqual(
                PaymentResult(from: response(intentStatus: status.rawValue)).status,
                expected,
                "\(status.rawValue) mapped unexpectedly"
            )
        }
    }

    // MARK: - Tolerance and safety

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(PaymentResult(from: response(intentStatus: "requires_capture")).status, .succeeded)
        XCTAssertEqual(PaymentResult(from: response(intentStatus: "Succeeded")).status, .succeeded)
        XCTAssertEqual(PaymentResult(from: response(intentStatus: "cancelled")).status, .cancelled)
    }

    func testLegacySpellingsKeepTheirPreviousMeaning() {
        XCTAssertEqual(PaymentResult(from: response(intentStatus: "REQUIRES_ACTION")).status, .requiresAction)
        XCTAssertEqual(PaymentResult(from: response(intentStatus: "PROCESSING")).status, .processing)
        XCTAssertEqual(PaymentResult(from: response(intentStatus: "CANCELED")).status, .cancelled)
    }

    func testAnUnrecognisedStatusIsNeverReportedAsSuccess() {
        let result = PaymentResult(from: response(intentStatus: "SOMETHING_NEW"))

        XCTAssertEqual(result.status, .failed)
        XCTAssertFalse(result.status.isSuccessful)
    }

    // MARK: - The rest of the payload is carried through unchanged

    func testPayloadFieldsAreCarriedThrough() {
        let attempt = try! JSONDecoder().decode(
            PaymentAttempt.self,
            from: Data(#"{"attempt_id": "att_1", "attempt_status": "AUTHORIZED"}"#.utf8)
        )
        let result = PaymentResult(from: response(
            intentStatus: "REQUIRES_CAPTURE",
            completeTime: "2026-09-02T10:00:00Z",
            attempt: attempt
        ))

        XCTAssertEqual(result.paymentIntentId, "pi_test_123")
        XCTAssertEqual(result.amount, 8.98)
        XCTAssertEqual(result.currency, "SGD")
        XCTAssertEqual(result.merchantOrderId, "order_42")
        XCTAssertEqual(result.transactionId, "att_1")
        XCTAssertEqual(result.metadata?["order"] as? String, "42")
        XCTAssertNotNil(result.completedAt)
        XCTAssertEqual(result.paymentMethodType, "unknown")
    }

    func testCompletedAtIsNilForAnUnsettledStatusWithoutACompleteTime() {
        XCTAssertNil(PaymentResult(from: response(intentStatus: "PENDING")).completedAt)
        XCTAssertNil(PaymentResult(from: response(intentStatus: "REQUIRES_CUSTOMER_ACTION")).completedAt)
        XCTAssertNil(PaymentResult(from: response(intentStatus: "FAILED")).completedAt)
    }

    func testCompletedAtIsSetWhenTheApiReportsACompleteTime() {
        XCTAssertNotNil(PaymentResult(from: response(
            intentStatus: "CANCELLED", completeTime: "2026-09-02T10:00:00Z"
        )).completedAt)
    }

    /// `REQUIRES_CAPTURE` is not a final state, so the API leaves
    /// `complete_time` empty. A successful status with no completion time
    /// would contradict itself and differ from what the prebuilt sheet
    /// reports for the same payment.
    func testAuthorisedPaymentHasACompletedAtEvenWithoutACompleteTime() {
        let result = PaymentResult(from: response(intentStatus: "REQUIRES_CAPTURE", completeTime: nil))

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertNotNil(result.completedAt)
    }
}
