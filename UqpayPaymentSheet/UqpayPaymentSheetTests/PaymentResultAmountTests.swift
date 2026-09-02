//
//  PaymentResultAmountTests.swift
//  UqpayPaymentSheetTests
//
//  Created by UQPAY on 02/09/2026.
//

import XCTest
@testable import UqpayCore
@testable import UqpayPayments
@testable import UqpayPaymentSheet

/// Pins `PaymentResult.amountDecimal` and the parsing behind it.
///
/// The API sends amounts as decimal strings in major units (`"8.98"`).
/// `PaymentResult.amount` turned that into a `Double`, which cannot hold most
/// decimal amounts exactly — `Double("19.99") * 100` is `1998.9999999999998`,
/// so a merchant converting to cents got 1998. Worse, every conversion site
/// fell back to `0` silently when the string could not be parsed, so a
/// succeeded payment could be reported with an amount of zero and no trace.
///
/// `amountDecimal` is exact, `amount` keeps its old value bit for bit, and an
/// unparseable amount is now logged.
final class PaymentResultAmountTests: XCTestCase {

    override func tearDown() {
        UqpayLogger.shared.reset()
        super.tearDown()
    }

    private func response(amount: String) -> ConfirmPaymentIntentResponse {
        ConfirmPaymentIntentResponse(
            paymentIntentId: "pi_amount_123",
            amount: amount,
            currency: "SGD",
            clientSecret: "cs_test",
            merchantOrderId: "order_42",
            intentStatus: "SUCCEEDED"
        )
    }

    // MARK: - The public initializer carries the exact amount

    func testAmountDecimalIsExactWhereTheDoubleIsNot() {
        let result = PaymentResult(from: response(amount: "19.99"))

        XCTAssertEqual(result.amountDecimal, Decimal(string: "19.99"))
        XCTAssertEqual(result.amountDecimal.map { $0 * 100 }, Decimal(1999),
                       "Cents conversion must be exact — this is the whole point of the field")
        XCTAssertNotEqual(Double("19.99")! * 100, 1999,
                          "The Double really does lose the cent; if this ever passes, revisit the design")
    }

    func testEveryDocumentedShapeParsesExactly() {
        let cases: [(wire: String, cents: Decimal)] = [
            ("8.98", 898), ("100", 10000), ("0.07", 7), ("1.15", 115), ("0", 0), ("00012.50", 1250)
        ]
        for (wire, cents) in cases {
            let result = PaymentResult(from: response(amount: wire))
            XCTAssertEqual(result.amountDecimal, Decimal(string: wire), wire)
            XCTAssertEqual(result.amountDecimal.map { $0 * 100 }, cents, "\(wire) in cents")
        }
    }

    func testTheDoubleKeepsItsPreviousValue() {
        // Deprecated, not removed: a merchant on 1.0.x must see nothing move.
        let result = PaymentResult(from: response(amount: "8.98"))

        XCTAssertEqual(result.amount, 8.98)
    }

    // MARK: - An unparseable amount is nil, still 0 for the Double, and logged

    func testAnUnparseableAmountIsNilNotZero() {
        for wire in ["", "8,98", " 8.98", "8.98abc", "abc", "1.2.3"] {
            let result = PaymentResult(from: response(amount: wire))

            XCTAssertNil(result.amountDecimal, "\(wire.debugDescription) must not parse to a plausible number")
            XCTAssertEqual(result.amount, 0, "\(wire.debugDescription): the Double fallback is unchanged")
            XCTAssertEqual(result.status, .succeeded, "\(wire.debugDescription): the amount never decides the status")
        }
    }

    /// `Double` accepts a few shapes the strict decimal parser does not. The
    /// Double must keep returning exactly what 1.0.x returned for them — it is
    /// never tightened alongside the new field — while the exact value is nil.
    func testTheDoubleIsNeverTightenedWhereItUsedToParse() {
        for wire in [".5", "8."] {
            let result = PaymentResult(from: response(amount: wire))

            XCTAssertEqual(result.amount, Double(wire), "\(wire.debugDescription): what 1.0.x reported")
            XCTAssertNil(result.amountDecimal, "\(wire.debugDescription) is not a plain decimal string")
        }
    }

    /// `Decimal(string:)` alone would read `"8,98"` as 8 — a wrong number
    /// presented as exact is worse than no number.
    func testALenientParseIsNeverAcceptedAsExact() {
        XCTAssertEqual(Decimal(string: "8,98"), 8, "Precondition: Foundation is lenient here")
        XCTAssertNil(PaymentResult(from: response(amount: "8,98")).amountDecimal)
    }

    func testAnUnparseableAmountIsLoggedWithTheIntentId() {
        let logged = expectation(description: "an error line reaches the merchant's log handler")
        var captured: (level: UqpayLogLevel, message: String)?
        UqpayLogger.shared.logHandler = { level, message, _, _, _ in
            guard message.contains("pi_amount_123") else { return }
            captured = (level, message)
            logged.fulfill()
        }

        _ = PaymentResult(from: response(amount: "8,98"))

        wait(for: [logged], timeout: 2)
        XCTAssertEqual(captured?.level, .error)
        XCTAssertTrue(captured?.message.contains("\"8,98\"") == true, "the raw wire value is what a merchant needs to see")
        XCTAssertTrue(captured?.message.contains("amountDecimal nil") == true)
    }

    func testAParseableAmountIsNotLogged() {
        let logged = expectation(description: "no log line for a good amount")
        logged.isInverted = true
        UqpayLogger.shared.logHandler = { _, message, _, _, _ in
            if message.contains("pi_amount_123") { logged.fulfill() }
        }

        _ = PaymentResult(from: response(amount: "8.98"))

        wait(for: [logged], timeout: 0.5)
    }

    // MARK: - Source compatibility for merchants who build results themselves

    func testExistingCallSitesCompileAndGetNilDecimal() {
        // Exactly the 1.0.x signature — no amountDecimal argument.
        let result = PaymentResult(
            paymentIntentId: "pi_amount_123",
            paymentMethodType: "card",
            status: .succeeded,
            amount: 8.98,
            currency: "SGD",
            metadata: ["k": "v"],
            merchantOrderId: "order_42",
            completedAt: nil,
            transactionId: "att_1",
            receiptUrl: nil
        )

        XCTAssertNil(result.amountDecimal, "Never derived from the Double")
        XCTAssertEqual(result.amount, 8.98)
    }

    func testTheDecimalIsCarriedWhenSupplied() {
        let result = PaymentResult(
            paymentIntentId: "pi_amount_123",
            paymentMethodType: "card",
            status: .succeeded,
            amount: 8.98,
            currency: "SGD",
            amountDecimal: Decimal(string: "8.98")
        )

        XCTAssertEqual(result.amountDecimal, Decimal(string: "8.98"))
    }

    // MARK: - The shared parser every sheet site goes through

    func testParserFallsBackToTheSecondWireStringExactlyAsTheOldSiteDid() {
        // The 3DS result site always had `intent.amount ?? amount`; the Double
        // must follow the same chain and the Decimal must agree with it.
        let fromFallback = WireAmount.parse(nil, fallback: "8.98", paymentIntentId: "pi_amount_123")
        XCTAssertEqual(fromFallback.double, 8.98)
        XCTAssertEqual(fromFallback.decimal, Decimal(string: "8.98"))

        let rawWins = WireAmount.parse("1.15", fallback: "8.98", paymentIntentId: "pi_amount_123")
        XCTAssertEqual(rawWins.double, 1.15)
        XCTAssertEqual(rawWins.decimal, Decimal(string: "1.15"))

        let neither = WireAmount.parse("abc", fallback: "", paymentIntentId: "pi_amount_123")
        XCTAssertEqual(neither.double, 0)
        XCTAssertNil(neither.decimal)
    }

    func testParserTreatsAMissingAmountAsUnknown() {
        let missing = WireAmount.parse(nil, paymentIntentId: "pi_amount_123")

        XCTAssertEqual(missing.double, 0, "What 1.0.x reported for a missing amount")
        XCTAssertNil(missing.decimal)
    }

    func testParserAcceptsANegativeDecimal() {
        // Not something the API sends for a payment, but "as sent by the API,
        // parsed exactly" must not quietly nil a well-formed value.
        XCTAssertEqual(WireAmount.parse("-1.50", paymentIntentId: "pi").decimal, Decimal(string: "-1.50"))
    }
}
