//
//  QRPaymentUITests.swift
//  SwiftUIExampleUITests
//
//  Sandbox verification for QR-based payment methods.
//
//  Each test walks the sheet to a QR method and passes only when the SDK
//  renders the QR image (`uqpay.qr.image`), which requires the whole chain to
//  work against the live sandbox: create intent → confirm with the method's
//  flow "qrcode" → parse next_action.display_qr_code → download the image.
//
//  No payment is completed: a QR that nobody scans moves no money, which is
//  what keeps this safe to run even for methods that ride real rails in
//  sandbox (WeChat). The outcome poll it starts simply gets abandoned when
//  the app exits.
//

import XCTest

final class QRPaymentUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWeChatQRCodeRenders() throws {
        try assertQRRenders(forMethod: "WeChat", name: "wechat")
    }

    @MainActor
    func testAlipayHKQRCodeRenders() throws {
        try assertQRRenders(forMethod: "Alipay HK", name: "alipayhk")
    }

    @MainActor
    func testAlipayQRCodeRenders() throws {
        try assertQRRenders(forMethod: "Alipay", name: "alipaycn")
    }

    @MainActor
    func testUnionPayQRCodeRenders() throws {
        try assertQRRenders(forMethod: "UnionPay", name: "unionpay")
    }

    @MainActor
    func testGrabPayQRCodeRenders() throws {
        try assertQRRenders(forMethod: "GrabPay", name: "grabpay")
    }

    // MARK: - Regional wallets
    //
    // These confirm a shape the API reference does not document: it accepts
    // these methods as payment_method variants without listing their object
    // fields, so `{flow, os_type, is_present}` was taken from the response
    // schema. A rendered QR is the proof the server accepted it.

    @MainActor
    func testGCashQRCodeRenders() throws {
        try assertQRRenders(forMethod: "GCash", name: "gcash")
    }

    @MainActor
    func testTrueMoneyQRCodeRenders() throws {
        try assertQRRenders(forMethod: "TrueMoney", name: "truemoney")
    }

    @MainActor
    func testTouchNGoQRCodeRenders() throws {
        try assertQRRenders(forMethod: "Touch 'n Go", name: "tng")
    }

    @MainActor
    func testDanaQRCodeRenders() throws {
        try assertQRRenders(forMethod: "DANA", name: "dana")
    }

    @MainActor
    func testKakaoPayQRCodeRenders() throws {
        try assertQRRenders(forMethod: "KakaoPay", name: "kakaopay")
    }

    // MARK: - Blocked on the merchant account, not on the SDK

    /// PayNow, Toss and Naver Pay are offered in
    /// `available_payment_method_types` but cannot complete a confirm on this
    /// sandbox merchant. Verified 2026-08-11 straight against the API with the
    /// CLI, with no SDK in the path: the request shape is accepted, an attempt
    /// is created, and it comes back `intent_status REQUIRES_PAYMENT_METHOD`,
    /// `attempt_status FAILED`, `failure_code system_error`, no `next_action`.
    ///
    /// Delete the skip once the account has them provisioned — the SDK side is
    /// already in place and identical to the five wallets that do work.
    @MainActor
    func testPayNowQRCodeRenders() throws {
        throw XCTSkip("PayNow confirms fail server-side (failure_code system_error) on this sandbox merchant")
    }

    // MARK: - Shared drive

    @MainActor
    private func assertQRRenders(forMethod methodLabel: String, name: String) throws {
        let app = XCUIApplication()
        app.launch()

        let checkout = app.buttons["Checkout"]
        XCTAssertTrue(checkout.waitForExistence(timeout: 15), "Checkout button not found")
        checkout.tap()

        let method = app.staticTexts[methodLabel]
        XCTAssertTrue(method.waitForExistence(timeout: 30),
                      "\(methodLabel) never appeared — intent creation may have failed")
        method.tap()

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5), "Continue button not found")
        continueButton.tap()

        attach(app, name: "\(name)-01-method-screen")

        // Some QR screens confirm immediately; others wait behind a button.
        let showQR = app.buttons["Show QR Code"]
        if showQR.waitForExistence(timeout: 5), showQR.isHittable {
            showQR.tap()
        }

        let qrImage = app.images["uqpay.qr.image"]
        let rendered = qrImage.waitForExistence(timeout: 60)
        attach(app, name: "\(name)-02-after-confirm")

        if !rendered {
            // Capture what the screen says so a failure explains itself.
            let texts = app.staticTexts.allElementsBoundByIndex.map(\.label)
            print("QR-TEST >>> \(methodLabel) visible texts: \(texts)")
        }
        XCTAssertTrue(rendered, "\(methodLabel) QR image was not rendered within 60s")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
