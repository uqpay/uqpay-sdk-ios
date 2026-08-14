//
//  ThreeDSPaymentUITests.swift
//  SwiftUIExampleUITests
//
//  End-to-end sandbox payment with a 3DS challenge.
//
//  Uses the sandbox test card, walks the sheet to the card form, pays, and
//  then drives the 3DS challenge web view. The pass condition is the app's
//  own "Payment successful" alert, which the sheet only shows after reading
//  the intent status back from the API — so a green run proves the full
//  create → confirm → 3DS → poll → succeeded loop.
//

import XCTest

final class ThreeDSPaymentUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCardPaymentWith3DSChallenge() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. Checkout from the cart (creates the payment intent).
        let checkout = app.buttons["Checkout"]
        XCTAssertTrue(checkout.waitForExistence(timeout: 15), "Checkout button not found")
        checkout.tap()

        // 2. Payment sheet → Card.
        let cardMethod = app.staticTexts["Card"]
        XCTAssertTrue(cardMethod.waitForExistence(timeout: 30), "Card method never appeared — intent creation may have failed")
        cardMethod.tap()

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5), "Continue button not found on method list")
        continueButton.tap()

        // 3. Card form. Personal/billing fields are prefilled by the demo.
        // 5521 9700 7999 8012 is the 3DS-enrolled sandbox card from the 3DS
        // integration guide; it authenticates frictionlessly. The quickstart
        // card (5346…8117) is NOT in the ACS BIN range and always fails
        // enforce_3ds with "Invalid Card, not in card bin range".
        let pan = app.textFields["1234 1234 1234 1234"]
        XCTAssertTrue(pan.waitForExistence(timeout: 15), "Card number field not found")
        pan.tap()
        pan.typeText("5521970079998012")

        let expiry = app.textFields["MM/YY"]
        expiry.tap()
        expiry.typeText("1028")

        // CVV is a secure entry field, so it lives under secureTextFields.
        let cvv = app.secureTextFields["CVV"]
        XCTAssertTrue(cvv.waitForExistence(timeout: 5), "CVV secure field not found")
        cvv.tap()
        cvv.typeText("001")

        attach(app, name: "01-card-form")

        let pay = app.buttons["Pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 5), "Pay button not found")
        pay.tap()

        // 4. The 3DS challenge must present. This is the regression under test:
        //    it used to silently no-op because the presenter left the window.
        let webView = app.webViews.firstMatch
        let threeDSAppeared = webView.waitForExistence(timeout: 60)
        attach(app, name: "02-after-pay")
        XCTAssertTrue(threeDSAppeared, "3DS web view never presented")

        // Let the ACS page settle, then record what it actually contains so the
        // challenge-completion step below can be adapted to the real page.
        sleep(6)
        attach(app, name: "03-3ds-page")
        dumpWebContent(webView)

        // 5. Try to complete the challenge with common ACS affordances.
        completeChallenge(in: webView, app: app)

        // 6. Success is judged by the app's alert, which the sheet raises only
        //    after polling the intent back to SUCCEEDED.
        // The SDK's own poll gives up at 300s, so wait past that to see its
        // final verdict rather than abandoning first.
        let alert = app.alerts["Payment"]
        let finished = alert.waitForExistence(timeout: 330)
        attach(app, name: "04-final")
        XCTAssertTrue(finished, "No payment outcome alert within 330s of 3DS")

        let alertText = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
        print("PAYMENT ALERT >>> \(alertText)")
        XCTAssertTrue(alertText.contains("Payment successful"), "Payment did not succeed: \(alertText)")
    }

    // MARK: - Challenge helpers

    /// Attempts the usual sandbox ACS interactions: an OTP field plus a
    /// submit-style button, or a bare approve button.
    @MainActor
    private func completeChallenge(in webView: XCUIElement, app: XCUIApplication) {
        let buttonLabels = ["SUCCESS", "Success", "Submit", "SUBMIT", "Continue", "Confirm", "Authenticate", "Approve", "OK", "Pay", "Verify"]

        // OTP-style field first: many sandbox ACS pages want a code.
        let otpField = webView.textFields.firstMatch
        if otpField.waitForExistence(timeout: 5) {
            otpField.tap()
            otpField.typeText("1234")
            attach(app, name: "3ds-otp-entered")
        }

        for label in buttonLabels {
            let button = webView.buttons[label]
            if button.exists && button.isHittable {
                print("3DS >>> tapping web button '\(label)'")
                button.tap()
                return
            }
            let link = webView.links[label]
            if link.exists && link.isHittable {
                print("3DS >>> tapping web link '\(label)'")
                link.tap()
                return
            }
        }

        // Fall back to any single button on the page.
        let anyButton = webView.buttons.firstMatch
        if anyButton.exists && anyButton.isHittable {
            print("3DS >>> tapping first web button '\(anyButton.label)'")
            anyButton.tap()
            return
        }
        print("3DS >>> no actionable element found; relying on frictionless flow")
    }

    /// Prints every element the ACS page exposes, so a failing run tells us
    /// exactly what to interact with next time.
    @MainActor
    private func dumpWebContent(_ webView: XCUIElement) {
        print("3DS WEBVIEW STATIC TEXTS >>> \(webView.staticTexts.allElementsBoundByIndex.map(\.label))")
        print("3DS WEBVIEW BUTTONS >>> \(webView.buttons.allElementsBoundByIndex.map(\.label))")
        print("3DS WEBVIEW LINKS >>> \(webView.links.allElementsBoundByIndex.map(\.label))")
        print("3DS WEBVIEW TEXTFIELDS >>> \(webView.textFields.allElementsBoundByIndex.map { $0.placeholderValue ?? $0.label })")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
