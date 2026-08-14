//
//  LocalizationTests.swift
//  UqpayPaymentSheetTests
//
//  U4 regression coverage: the strings table ships in the resource bundle and
//  resolves — key-fallback alone would hide a packaging mistake.
//

import XCTest
@testable import UqpayPaymentSheet

final class LocalizationTests: XCTestCase {

    func testStringsTableShipsInTheResourceBundle() {
        let resolved = UqpayResourceManager.bundle.localizedString(
            forKey: "Pay", value: "TABLE-MISSING", table: nil
        )
        XCTAssertEqual(
            resolved, "Pay",
            "Localizable.strings must be present in the resolved bundle — falling back to the key would mask a packaging failure"
        )
    }

    func testLocalizedLookupFallsBackToTheKey() {
        // A key that will never be in the table renders verbatim, so missing
        // translations can never blank out the UI.
        XCTAssertEqual(UqpayLocalized("uqpay-test-nonexistent-key"), "uqpay-test-nonexistent-key")
    }

    func testFormatKeysKeepTheirPlaceholders() {
        let formatted = String(format: UqpayLocalized("Transaction ID: %@"), "pi_123")
        XCTAssertEqual(formatted, "Transaction ID: pi_123")
    }
}
