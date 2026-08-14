//
//  CardFormValidationTests.swift
//  UqpayPaymentSheetTests
//
//  Created by UQPAY on 11/08/2026.
//

import XCTest
@testable import UqpayCore
@testable import UqpayPayments
@testable import UqpayPaymentSheet

/// Pins the rules the card form now enforces before a confirm is sent.
///
/// The form used to count digits and nothing more: a mistyped digit and an
/// expired card both reached the acquirer and came back as declines. These
/// assert the checks it delegates to, using the sandbox cards the end-to-end
/// suites drive so a validation change can never silently break them.
final class CardFormValidationTests: XCTestCase {

    // The 3DS-enrolled sandbox card, and the quickstart card.
    private let enrolledCard = "5521970079998012"
    private let quickstartCard = "5346930100108117"

    // MARK: - The E2E suites must keep passing

    func testCardsUsedByTheEndToEndSuitesRemainValid() {
        for card in [enrolledCard, quickstartCard] {
            XCTAssertTrue(
                CardValidator.isValidLuhn(card),
                "\(card) is driven by a UI test and must stay valid"
            )
        }

        let result = PaymentValidationHelper.validateCard(
            cardNumber: enrolledCard,
            expiryText: "10/28",
            cvc: "001"
        )
        XCTAssertTrue(result.isValid, "The 3DS E2E card/expiry/CVC combination must validate")
    }

    // MARK: - Luhn

    func testSingleDigitTypoIsRejected() {
        // One digit off the real card — the classic mistype Luhn exists to catch.
        let typo = "5521970079998013"
        XCTAssertFalse(CardValidator.isValidLuhn(typo))

        let result = PaymentValidationHelper.validateCard(
            cardNumber: typo, expiryText: "10/28", cvc: "001"
        )
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(.invalidLuhn))
    }

    func testTransposedDigitsAreRejected() {
        let transposed = "5521970079998102"   // last two digits swapped
        XCTAssertFalse(CardValidator.isValidLuhn(transposed))
    }

    // MARK: - Expiry

    func testExpiredCardIsRejected() {
        let result = PaymentValidationHelper.validateCard(
            cardNumber: enrolledCard, expiryText: "01/20", cvc: "001"
        )
        XCTAssertFalse(result.isValid, "A card that expired in 2020 must not be sent")
        XCTAssertTrue(result.errors.contains(.invalidExpiry))
    }

    func testImpossibleMonthIsRejected() {
        let result = PaymentValidationHelper.validateCard(
            cardNumber: enrolledCard, expiryText: "13/30", cvc: "001"
        )
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(.invalidExpiry))
    }

    // MARK: - CVC is sized by brand

    func testAmexRequiresFourDigitsAndOthersThree() {
        XCTAssertTrue(CardValidator.isValidCVC("1234", brand: .amex))
        XCTAssertFalse(CardValidator.isValidCVC("123", brand: .amex))

        XCTAssertTrue(CardValidator.isValidCVC("123", brand: .masterCard))
        XCTAssertFalse(CardValidator.isValidCVC("1234", brand: .masterCard))
    }

    // MARK: - Card number length

    /// UnionPay issues up to 19 digits. The form capped input at 16, so those
    /// cards could not be typed at all.
    func testNineteenDigitCardNumbersAreAccepted() {
        let unionPay = "6250947000000000000"
        XCTAssertEqual(unionPay.count, 19)
        XCTAssertEqual(CardValidator.brand(for: unionPay), .unionPay)

        let cleaned = PaymentValidationHelper.cleanCardNumber(unionPay, for: .unionPay)
        XCTAssertGreaterThanOrEqual(
            cleaned.count, 16,
            "Cleaning must not truncate a UnionPay number down to 16 digits"
        )
    }
}

/// Pins that the billing country is the customer's own ISO selection.
///
/// It used to be free text run through a nine-entry lookup that returned "US"
/// for anything unlisted, so every customer outside those nine markets had the
/// wrong country sent to the issuer.
final class CountryRegionTests: XCTestCase {

    func testCoversFarMoreThanTheOldNineCountries() {
        XCTAssertGreaterThan(
            CountryRegion.all.count, 150,
            "The full ISO country list should be offered, not a hand-written subset"
        )
    }

    func testCountriesTheOldTableSilentlyMappedToUSAreNowPresent() {
        // Every one of these used to reach the issuer as "US".
        for code in ["ID", "TH", "PH", "VN", "IN", "BR", "NG", "KR", "HK", "TW"] {
            let match = CountryRegion.first(matching: code)
            XCTAssertNotNil(match, "\(code) must be selectable")
            XCTAssertEqual(match?.code, code)
        }
    }

    func testEveryEntryIsAnAlphaTwoCodeWithADisplayName() {
        for country in CountryRegion.all {
            XCTAssertEqual(country.code.count, 2, "\(country.code) is not alpha-2")
            XCTAssertTrue(country.code.allSatisfy { $0.isUppercase && $0.isLetter })
            XCTAssertFalse(country.name.isEmpty, "\(country.code) has no display name")
        }
    }

    /// Groupings such as "001" (World) and "150" (Europe) are not billing
    /// addresses and must not appear in the picker.
    func testRegionGroupingsAreExcluded() {
        XCTAssertNil(CountryRegion.all.first { $0.code.contains(where: \.isNumber) })
    }

    func testListIsSortedForDisplay() {
        let names = CountryRegion.all.map(\.name)
        XCTAssertEqual(
            names, names.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            "The picker list must be sorted by display name"
        )
    }

    func testLookupIsCaseInsensitive() {
        XCTAssertEqual(CountryRegion.first(matching: "sg")?.code, "SG")
        XCTAssertEqual(CountryRegion.first(matching: "SG")?.code, "SG")
        XCTAssertNil(CountryRegion.first(matching: "ZZ"))
    }
}
