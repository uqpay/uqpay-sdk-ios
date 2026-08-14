import XCTest
@testable import UqpayCore

/// Fixtures copied from live sandbox responses so decoding is tested against
/// what the API actually returns, not against what the documentation implies.
private enum Fixture {

    static let succeededIntent = """
    {
      "amount": "8.98",
      "available_payment_method_types": ["card", "alipaycn"],
      "cancel_time": null,
      "cancellation_reason": "",
      "captured_amount": "8.98",
      "client_secret": "eyJhbGciOiJIUzI1NiJ9.payload.sig",
      "complete_time": "2026-08-06T10:31:02+08:00",
      "create_time": "2026-08-06T10:30:58+08:00",
      "currency": "SGD",
      "customer_id": "",
      "description": "sdk e2e card test",
      "intent_status": "SUCCEEDED",
      "latest_payment_attempt": {
        "advice_code": "",
        "amount": "8.98",
        "arn": "",
        "attempt_id": "PA2085201776000000000",
        "attempt_status": "CAPTURE_REQUESTED",
        "auth_code": "648590",
        "authentication_data": {
          "avs_result": "",
          "cvv_result": "",
          "three_ds": {
            "cavv": "", "ds_transaction_id": "", "eci": "",
            "three_ds_authentication_status": "",
            "three_ds_cancellation_reason": "", "three_ds_version": ""
          }
        },
        "captured_amount": "8.98",
        "complete_time": "2026-08-06T10:31:02+08:00",
        "create_time": "2026-08-06T10:30:58+08:00",
        "currency": "SGD",
        "failure_code": "",
        "failure_message": "",
        "refunded_amount": "0",
        "rrn": "080600000001",
        "update_time": "2026-08-06T10:31:02+08:00"
      },
      "merchant_order_id": "8f1c1b1e-0000-4000-8000-000000000000",
      "metadata": null,
      "next_action": null,
      "payment_intent_id": "PI2085201775714897920",
      "return_url": "https://example.com/uqpay/callback",
      "update_time": "2026-08-06T10:31:02+08:00"
    }
    """.data(using: .utf8)!

    static let requiresActionIntent = """
    {
      "amount": "8.88",
      "captured_amount": "0",
      "currency": "SGD",
      "intent_status": "REQUIRES_CUSTOMER_ACTION",
      "next_action": {
        "type": "redirect_iframe",
        "redirect_iframe": {
          "iframe": "<form id=\\"threeDSRedirectForm\\" method=\\"POST\\" action=\\"https://acs.example/3ds\\"></form>"
        }
      },
      "payment_intent_id": "PI2085203000000000000"
    }
    """.data(using: .utf8)!

    static let errorBody = """
    {"type":"invalid_request_error","code":"invalid_payment_method","message":""}
    """.data(using: .utf8)!
}

final class UqpayIdempotencyKeyTests: XCTestCase {

    /// The API rejects uppercase UUIDs, and `UUID().uuidString` is uppercase.
    func testKeyIsAlwaysLowercase() {
        for _ in 0..<200 {
            let key = UqpayIdempotencyKey().value
            XCTAssertEqual(key, key.lowercased())
        }
    }

    func testKeyFromUUIDIsLowercased() {
        let uuid = UUID()
        XCTAssertEqual(UqpayIdempotencyKey(uuid).value, uuid.uuidString.lowercased())
        XCTAssertNotEqual(UqpayIdempotencyKey(uuid).value, uuid.uuidString)
    }

    func testKeysAreUnique() {
        let keys = Set((0..<500).map { _ in UqpayIdempotencyKey().value })
        XCTAssertEqual(keys.count, 500)
    }
}

final class UqpayStatusTests: XCTestCase {

    /// All seven documented statuses must map to a distinct case.
    func testAllDocumentedIntentStatusesDecode() {
        let expected: [String: UqpayPaymentIntentStatus] = [
            "REQUIRES_PAYMENT_METHOD": .requiresPaymentMethod,
            "REQUIRES_CUSTOMER_ACTION": .requiresCustomerAction,
            "REQUIRES_CAPTURE": .requiresCapture,
            "PENDING": .pending,
            "SUCCEEDED": .succeeded,
            "CANCELLED": .cancelled,
            "FAILED": .failed,
        ]
        for (raw, status) in expected {
            XCTAssertEqual(UqpayPaymentIntentStatus(rawValue: raw), status, "failed for \(raw)")
            XCTAssertEqual(status.rawValue, raw)
        }
    }

    /// A status the app has never heard of must not be mistaken for a failure.
    func testUnknownStatusIsPreservedAndNotTerminal() {
        let status = UqpayPaymentIntentStatus(rawValue: "REQUIRES_SOMETHING_NEW")
        XCTAssertEqual(status, .unknown("REQUIRES_SOMETHING_NEW"))
        XCTAssertEqual(status.rawValue, "REQUIRES_SOMETHING_NEW")
        XCTAssertFalse(status.isTerminal)
        XCTAssertFalse(status.needsCustomerAction)
    }

    /// Regression: the SDK previously compared against "REQUIRES_ACTION", which the
    /// API never sends, so a payment awaiting 3DS was reported to merchants as failed.
    func testInFlightThreeDSIsNotTerminal() {
        let status = UqpayPaymentIntentStatus(rawValue: "REQUIRES_CUSTOMER_ACTION")
        XCTAssertTrue(status.needsCustomerAction)
        XCTAssertFalse(status.isTerminal)
        XCTAssertNotEqual(status, .failed)
        XCTAssertEqual(UqpayPaymentIntentStatus(rawValue: "REQUIRES_ACTION"), .unknown("REQUIRES_ACTION"))
    }

    func testTerminalStatuses() {
        XCTAssertTrue(UqpayPaymentIntentStatus.succeeded.isTerminal)
        XCTAssertTrue(UqpayPaymentIntentStatus.failed.isTerminal)
        XCTAssertTrue(UqpayPaymentIntentStatus.cancelled.isTerminal)
        XCTAssertFalse(UqpayPaymentIntentStatus.pending.isTerminal)
        XCTAssertFalse(UqpayPaymentIntentStatus.requiresCapture.isTerminal)
        XCTAssertFalse(UqpayPaymentIntentStatus.requiresPaymentMethod.isTerminal)
    }

    func testAllDocumentedAttemptStatusesDecode() {
        let raws = ["INITIATED", "AUTHENTICATION_REDIRECTED", "PENDING_AUTHORIZATION",
                    "AUTHORIZED", "CAPTURE_REQUESTED", "SETTLED", "SUCCEEDED",
                    "CANCELLED", "EXPIRED", "FAILED"]
        for raw in raws {
            let status = UqpayPaymentAttemptStatus(rawValue: raw)
            XCTAssertEqual(status.rawValue, raw)
            if case .unknown = status { XCTFail("\(raw) should be a known case") }
        }
    }
}

final class UqpayDecodingTests: XCTestCase {

    private let decoder = UqpayHTTPClient.defaultDecoder

    func testDecodesSucceededIntent() throws {
        let intent = try decoder.decode(UqpayPaymentIntent.self, from: Fixture.succeededIntent)

        XCTAssertEqual(intent.paymentIntentId, "PI2085201775714897920")
        XCTAssertEqual(intent.intentStatus, .succeeded)
        XCTAssertEqual(intent.amount, "8.98")
        XCTAssertEqual(intent.currency, "SGD")
        XCTAssertEqual(intent.capturedAmount, "8.98")
        XCTAssertNil(intent.nextAction)
        XCTAssertEqual(intent.availablePaymentMethodTypes, ["card", "alipaycn"])
        XCTAssertNotNil(intent.clientSecret)
    }

    /// Amounts are decimal strings in major units. The old code divided by 100.
    func testAmountIsMajorUnitsNotMinor() throws {
        let intent = try decoder.decode(UqpayPaymentIntent.self, from: Fixture.succeededIntent)
        XCTAssertEqual(intent.amountDecimal, Decimal(string: "8.98"))
        XCTAssertEqual(intent.capturedAmountDecimal, Decimal(string: "8.98"))
        XCTAssertNotEqual(intent.amountDecimal, Decimal(string: "0.0898"))
    }

    /// Live responses nest the attempt id as `attempt_id`; webhooks use `payment_attempt_id`.
    func testAttemptIdAcceptsBothSpellings() throws {
        let intent = try decoder.decode(UqpayPaymentIntent.self, from: Fixture.succeededIntent)
        XCTAssertEqual(intent.latestPaymentAttempt?.attemptId, "PA2085201776000000000")
        XCTAssertEqual(intent.latestPaymentAttempt?.attemptStatus, .captureRequested)
        XCTAssertEqual(intent.latestPaymentAttempt?.authCode, "648590")

        let webhookShape = #"{"payment_attempt_id":"PA999","attempt_status":"FAILED"}"#.data(using: .utf8)!
        let attempt = try decoder.decode(UqpayPaymentAttempt.self, from: webhookShape)
        XCTAssertEqual(attempt.attemptId, "PA999")
        XCTAssertEqual(attempt.attemptStatus, .failed)
    }

    func testDecodesRequiresActionWithIframe() throws {
        let intent = try decoder.decode(UqpayPaymentIntent.self, from: Fixture.requiresActionIntent)

        XCTAssertEqual(intent.intentStatus, .requiresCustomerAction)
        XCTAssertTrue(intent.intentStatus.needsCustomerAction)
        XCTAssertEqual(intent.nextAction?.type, "redirect_iframe")

        let iframe = try XCTUnwrap(intent.nextAction?.redirectIframe?.iframe)
        XCTAssertTrue(iframe.contains("method=\"POST\""),
                      "The ACS form is a POST; loading it as a GET drops the body and 3DS fails.")
    }

    /// Absent optional fields must not fail the whole decode.
    func testMinimalIntentStillDecodes() throws {
        let minimal = #"{"payment_intent_id":"PI1","intent_status":"PENDING"}"#.data(using: .utf8)!
        let intent = try decoder.decode(UqpayPaymentIntent.self, from: minimal)
        XCTAssertEqual(intent.paymentIntentId, "PI1")
        XCTAssertEqual(intent.intentStatus, .pending)
        XCTAssertNil(intent.amount)
        XCTAssertNil(intent.latestPaymentAttempt)
    }

    func testDecodesErrorBody() throws {
        let body = try JSONDecoder().decode(UqpayAPIErrorBody.self, from: Fixture.errorBody)
        XCTAssertEqual(body.code, "invalid_payment_method")
        XCTAssertEqual(body.type, "invalid_request_error")
        XCTAssertEqual(body.message, "")
    }

    /// The API returns an empty `message` on some errors, so the code must still surface.
    func testErrorDescriptionFallsBackToCode() {
        let error = UqpayAPIError.api(
            status: 400,
            body: UqpayAPIErrorBody(code: "invalid_payment_method", type: "invalid_request_error", message: "")
        )
        XCTAssertEqual(error.errorDescription, "invalid_payment_method")
        XCTAssertEqual(error.apiCode, "invalid_payment_method")
        XCTAssertEqual(error.httpStatus, 400)
    }
}

final class UqpayRetryPolicyTests: XCTestCase {

    func testServerAndRateLimitErrorsAreRetryable() {
        let body = UqpayAPIErrorBody(code: "x", type: "y", message: "z")
        XCTAssertTrue(UqpayAPIError.api(status: 500, body: body).isRetryable)
        XCTAssertTrue(UqpayAPIError.api(status: 503, body: body).isRetryable)
        XCTAssertTrue(UqpayAPIError.api(status: 429, body: body).isRetryable)
        XCTAssertTrue(UqpayAPIError.timedOut.isRetryable)
    }

    /// Retrying a declined card or a bad request cannot succeed and must not be retried.
    func testClientErrorsAreNotRetryable() {
        let body = UqpayAPIErrorBody(code: "invalid_payment_method", type: "invalid_request_error", message: "")
        XCTAssertFalse(UqpayAPIError.api(status: 400, body: body).isRetryable)
        XCTAssertFalse(UqpayAPIError.api(status: 401, body: body).isRetryable)
        XCTAssertFalse(UqpayAPIError.cancelled.isRetryable)
    }
}

final class UqpayEnvironmentTests: XCTestCase {

    func testDocumentedHosts() {
        XCTAssertEqual(UqpayAPIEnvironment.sandbox.baseURL.absoluteString,
                       "https://api-sandbox.uqpaytech.com")
        XCTAssertEqual(UqpayAPIEnvironment.production.baseURL.absoluteString,
                       "https://api.uqpay.com")
    }

    func testOnlyProductionIsLive() {
        XCTAssertTrue(UqpayAPIEnvironment.production.isLive)
        XCTAssertFalse(UqpayAPIEnvironment.sandbox.isLive)
        XCTAssertFalse(UqpayAPIEnvironment.custom(URL(string: "https://example.com")!).isLive)
    }
}
