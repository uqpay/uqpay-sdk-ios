//
//  UqpayPaymentsTests.swift
//  UqpayPaymentsTests
//
//  Created by UQPAY on 14/08/2025.
//

import XCTest
@testable import UqpayPayments

final class CardValidatorBrandTests: XCTestCase {

    func testVisa() {
        XCTAssertEqual(CardValidator.brand(for: "4242424242424242"), .visa)
        XCTAssertEqual(CardValidator.brand(for: "4000056655665556"), .visa)
    }

    func testMasterCardFiveSeries() {
        XCTAssertEqual(CardValidator.brand(for: "5100000000000000"), .masterCard)
        XCTAssertEqual(CardValidator.brand(for: "5555555555554444"), .masterCard)
        XCTAssertEqual(CardValidator.brand(for: "5521970079998012"), .masterCard)
    }

    /// Regression: 2-series MasterCards (issued since 2017) classified as
    /// `.unknown`, so a large share of real MasterCards failed brand checks.
    func testMasterCardTwoSeries() {
        XCTAssertEqual(CardValidator.brand(for: "2221000000000009"), .masterCard)
        XCTAssertEqual(CardValidator.brand(for: "2500000000000001"), .masterCard)
        XCTAssertEqual(CardValidator.brand(for: "2720990000000007"), .masterCard)
    }

    func testTwoSeriesBoundariesAreNotMasterCard() {
        XCTAssertEqual(CardValidator.brand(for: "2220990000000000"), .unknown)
        XCTAssertEqual(CardValidator.brand(for: "2721000000000000"), .unknown)
    }

    func testAmex() {
        XCTAssertEqual(CardValidator.brand(for: "340000000000009"), .amex)
        XCTAssertEqual(CardValidator.brand(for: "378282246310005"), .amex)
    }

    func testDiscover() {
        XCTAssertEqual(CardValidator.brand(for: "6011111111111117"), .discover)
        XCTAssertEqual(CardValidator.brand(for: "6445644564456445"), .discover)
        XCTAssertEqual(CardValidator.brand(for: "6500000000000002"), .discover)
    }

    /// Regression: any "60" prefix used to read as Discover, swallowing
    /// non-Discover 60xx ranges.
    func testBare60IsNotDiscover() {
        XCTAssertEqual(CardValidator.brand(for: "6099999999999999"), .unknown)
    }

    func testJCB() {
        XCTAssertEqual(CardValidator.brand(for: "3528000000000007"), .jcb)
        XCTAssertEqual(CardValidator.brand(for: "3589000000000003"), .jcb)
    }

    /// Regression: any "35" prefix used to read as JCB; only 3528–3589 is JCB.
    func testNon35xxJCBRangesAreUnknown() {
        XCTAssertEqual(CardValidator.brand(for: "3500000000000000"), .unknown)
        XCTAssertEqual(CardValidator.brand(for: "3527999999999999"), .unknown)
        XCTAssertEqual(CardValidator.brand(for: "3590000000000000"), .unknown)
    }

    func testDinersClub() {
        XCTAssertEqual(CardValidator.brand(for: "36700102000000"), .dinersClub)
        XCTAssertEqual(CardValidator.brand(for: "30569309025904"), .dinersClub)
        XCTAssertEqual(CardValidator.brand(for: "38520000023237"), .dinersClub)
    }

    func testUnionPay() {
        XCTAssertEqual(CardValidator.brand(for: "6200000000000005"), .unionPay)
    }

    func testPartialNumbersNeedEnoughDigitsForRangeBrands() {
        // Two digits cannot distinguish the MasterCard 2-series yet.
        XCTAssertEqual(CardValidator.brand(for: "22"), .unknown)
        XCTAssertEqual(CardValidator.brand(for: "2221"), .masterCard)
        // Prefix-based brands resolve immediately.
        XCTAssertEqual(CardValidator.brand(for: "4"), .visa)
        XCTAssertEqual(CardValidator.brand(for: "51"), .masterCard)
    }

    func testFormattingCharactersAreIgnored() {
        XCTAssertEqual(CardValidator.brand(for: "2221 0000 0000 0009"), .masterCard)
        XCTAssertEqual(CardValidator.brand(for: "5555-5555-5555-4444"), .masterCard)
    }
}

final class CardValidatorLuhnTests: XCTestCase {

    func testValidNumbersPass() {
        XCTAssertTrue(CardValidator.isValidLuhn("4242424242424242"))
        XCTAssertTrue(CardValidator.isValidLuhn("5555555555554444"))
        XCTAssertTrue(CardValidator.isValidLuhn("2223003122003222"))
        XCTAssertTrue(CardValidator.isValidLuhn("378282246310005"))
    }

    func testInvalidNumbersFail() {
        XCTAssertFalse(CardValidator.isValidLuhn("4242424242424241"))
        XCTAssertFalse(CardValidator.isValidLuhn(""))
        XCTAssertFalse(CardValidator.isValidLuhn("1234"))
    }
}

final class CardValidatorCVCTests: XCTestCase {

    func testAmexRequiresFourDigits() {
        XCTAssertTrue(CardValidator.isValidCVC("1234", brand: .amex))
        XCTAssertFalse(CardValidator.isValidCVC("123", brand: .amex))
    }

    func testOtherBrandsRequireThreeDigits() {
        XCTAssertTrue(CardValidator.isValidCVC("123", brand: .visa))
        XCTAssertTrue(CardValidator.isValidCVC("123", brand: .masterCard))
        XCTAssertFalse(CardValidator.isValidCVC("1234", brand: .visa))
        XCTAssertFalse(CardValidator.isValidCVC("12", brand: .unionPay))
    }
}
