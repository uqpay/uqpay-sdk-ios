//
//  ErrorCodeMappingTests.swift
//  UqpayPaymentSheetTests
//
//  E1/E2 regression coverage: the card, wallet-QR and raw-QR screens all
//  report through the same failure-code mapping, and every declared
//  `PaymentError.ErrorCode` is produced by at least one real path.
//

import XCTest
import UqpayCore
@testable import UqpayPaymentSheet

final class ErrorCodeMappingTests: XCTestCase {

    // MARK: - The attempt failure-code table (card, wallet QR, raw QR)

    func testCancelledIntentAlwaysMapsToCancelled() {
        XCTAssertEqual(
            PaymentCardViewController.errorCode(forFailureCode: "3ds_failed", intentStatus: .cancelled),
            .cancelled,
            "A cancelled intent wins over whatever failure code the attempt carries"
        )
        XCTAssertEqual(
            PaymentCardViewController.errorCode(forFailureCode: nil, intentStatus: .cancelled),
            .cancelled
        )
    }

    func testFailureCodeTable() {
        let cases: [(String?, PaymentError.ErrorCode)] = [
            ("3ds_failed", .threeDSFailed),
            ("insufficient_funds", .insufficientFunds),
            ("do_not_honor", .cardDeclined),
            ("anything_else", .cardDeclined),
            (nil, .cardDeclined),
        ]
        for (failureCode, expected) in cases {
            XCTAssertEqual(
                PaymentCardViewController.errorCode(forFailureCode: failureCode, intentStatus: .failed),
                expected,
                "failure_code \(failureCode ?? "nil") should map to \(expected)"
            )
        }
    }

    // MARK: - The API rejection table

    private func apiError(code: String = "", status: Int = 400) -> UqpayAPIError {
        .api(status: status, body: UqpayAPIErrorBody(code: code, type: "", message: ""))
    }

    func testAPIRejectionTable() {
        let cases: [(UqpayAPIError?, PaymentError.ErrorCode)] = [
            (apiError(code: "card_declined"), .cardDeclined),
            (apiError(code: "do_not_honor"), .cardDeclined),
            (apiError(code: "insufficient_funds"), .insufficientFunds),
            (apiError(code: "invalid_payment_method"), .invalidPaymentMethod),
            (apiError(code: "3ds_failed"), .threeDSFailed),
            (apiError(status: 401), .authenticationFailed),
            (apiError(status: 403), .authenticationFailed),
            (apiError(status: 402), .cardDeclined),
            (apiError(status: 400), .invalidPaymentMethod),
            (apiError(status: 404), .invalidPaymentMethod),
            (apiError(status: 422), .invalidPaymentMethod),
            (apiError(status: 500), .unknown),
            (nil, .unknown),
        ]
        for (error, expected) in cases {
            XCTAssertEqual(PaymentCardViewController.errorCode(for: error), expected)
        }
    }

    // MARK: - E2: every declared code is produced by at least one path

    /// Codes produced by the two shared mapping tables (exercised above).
    private var mappedCodes: Set<PaymentError.ErrorCode> {
        var produced: Set<PaymentError.ErrorCode> = []
        for status in [UqpayPaymentIntentStatus.failed, .cancelled] {
            for code in ["3ds_failed", "insufficient_funds", "other", ""] {
                produced.insert(PaymentCardViewController.errorCode(forFailureCode: code, intentStatus: status))
            }
        }
        for error in [apiError(code: "invalid_payment_method"), apiError(status: 401), apiError(status: 500), nil] {
            produced.insert(PaymentCardViewController.errorCode(for: error))
        }
        return produced
    }

    /// Codes reported directly at their event sites rather than through a
    /// mapping table: transport failures and QR timeouts
    /// (`PaymentCardViewController.swift` confirm/QR outcome paths) and
    /// pre-flight configuration failures (missing intent id).
    private var directlyReportedCodes: Set<PaymentError.ErrorCode> {
        [.networkError, .timeout, .invalidConfiguration]
    }

    func testEveryDeclaredErrorCodeIsReachable() {
        let reachable = mappedCodes.union(directlyReportedCodes)
        for code in PaymentError.ErrorCode.allCases {
            XCTAssertTrue(
                reachable.contains(code),
                "\(code) is declared but produced by no mapping table or direct-report site — either wire it up or remove it"
            )
        }
    }
}
