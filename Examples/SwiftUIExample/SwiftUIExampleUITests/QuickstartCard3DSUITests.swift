//
//  QuickstartCard3DSUITests.swift
//  SwiftUIExampleUITests
//
//  Pays with the quickstart sandbox card (5346 9301 0010 8117) under the
//  app's behavior of enforcing 3DS on every confirm.
//
//  This card is NOT in the sandbox ACS's enrolled BIN range, so enforced 3DS
//  can never succeed for it — verified empirically 2026-08-07: the device
//  fingerprint step presents, authentication is rejected, and the sheet shows
//  "Card authentication failed." This test asserts that documented behavior,
//  proving the SDK surfaces a clean failure instead of hanging or crashing.
//  Only 5521 9700 7999 8012 is 3DS-enrolled; ThreeDSPaymentUITests covers the
//  success path with it.
//

import XCTest

final class QuickstartCard3DSUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testQuickstartCardWithEnforce3DS() throws {
        let app = XCUIApplication()
        app.launch()

        let checkout = app.buttons["Checkout"]
        XCTAssertTrue(checkout.waitForExistence(timeout: 15), "Checkout button not found")
        checkout.tap()

        let cardMethod = app.staticTexts["Card"]
        XCTAssertTrue(cardMethod.waitForExistence(timeout: 30), "Card method never appeared")
        cardMethod.tap()

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5), "Continue button not found")
        continueButton.tap()

        let pan = app.textFields["1234 1234 1234 1234"]
        XCTAssertTrue(pan.waitForExistence(timeout: 15), "Card number field not found")
        pan.tap()
        pan.typeText("5346930100108117")

        let expiry = app.textFields["MM/YY"]
        expiry.tap()
        expiry.typeText("1226")

        let cvv = app.secureTextFields["CVV"]
        XCTAssertTrue(cvv.waitForExistence(timeout: 5), "CVV secure field not found")
        cvv.tap()
        cvv.typeText("811")

        attach(app, name: "q-01-card-form")

        let pay = app.buttons["Pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 5), "Pay button not found")
        pay.tap()

        // The challenge may or may not present for this card — drive it if it does.
        let webView = app.webViews.firstMatch
        if webView.waitForExistence(timeout: 45) {
            print("QUICKSTART >>> 3DS challenge presented for this card")
            sleep(6)
            attach(app, name: "q-02-3ds-page")
            completeChallenge(in: webView, app: app)
        } else {
            print("QUICKSTART >>> no 3DS challenge presented within 45s")
            attach(app, name: "q-02-no-challenge")
        }

        // Verdict: the app's payment alert, or whatever the sheet shows instead.
        let alert = app.alerts["Payment"]
        let finished = alert.waitForExistence(timeout: 330)
        attach(app, name: "q-03-final")

        if finished {
            let alertText = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
            print("QUICKSTART PAYMENT ALERT >>> \(alertText)")
            XCTAssertTrue(
                alertText.contains("authentication failed"),
                "Expected the documented 3DS authentication failure for the non-enrolled card, got: \(alertText)"
            )
        } else {
            let texts = app.staticTexts.allElementsBoundByIndex.map(\.label)
            print("QUICKSTART FINAL SCREEN TEXTS >>> \(texts)")
            XCTFail("No payment outcome alert; final screen: \(texts)")
        }
    }

    // MARK: - Challenge helpers (same approach as ThreeDSPaymentUITests)

    @MainActor
    private func completeChallenge(in webView: XCUIElement, app: XCUIApplication) {
        let buttonLabels = ["SUCCESS", "Success", "Submit", "SUBMIT", "Continue", "Confirm", "Authenticate", "Approve", "OK", "Pay", "Verify"]

        let otpField = webView.textFields.firstMatch
        if otpField.waitForExistence(timeout: 5) {
            otpField.tap()
            otpField.typeText("1234")
            attach(app, name: "q-3ds-otp-entered")
        }

        for label in buttonLabels {
            let button = webView.buttons[label]
            if button.exists && button.isHittable {
                print("QUICKSTART >>> tapping web button '\(label)'")
                button.tap()
                return
            }
            let link = webView.links[label]
            if link.exists && link.isHittable {
                print("QUICKSTART >>> tapping web link '\(label)'")
                link.tap()
                return
            }
        }

        let anyButton = webView.buttons.firstMatch
        if anyButton.exists && anyButton.isHittable {
            print("QUICKSTART >>> tapping first web button '\(anyButton.label)'")
            anyButton.tap()
            return
        }
        print("QUICKSTART >>> no actionable element found; relying on frictionless flow")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
