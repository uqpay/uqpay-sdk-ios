//
//  KeyboardAvoidanceTests.swift
//  UqpayPaymentSheetTests
//
//  C-5 coverage. `setupKeyboardHandling()` was an empty stub and
//  `Configuration.Payment.keyboardScrollOffset` was a documented knob wired to
//  nothing, so a focused field could sit under the keyboard — worst in
//  landscape, where the keyboard takes about half the screen.
//

import XCTest
import UIKit
@testable import UqpayPaymentSheet

@MainActor
final class KeyboardAvoidanceTests: XCTestCase {

    private let phone = CGSize(width: 393, height: 852)

    // MARK: - Insets track the keyboard

    func testKeyboardInsetsTheFormByItsOverlap() throws {
        let (card, window) = hostedCard()
        defer { window.isHidden = true }
        let scroll = try XCTUnwrap(cardScrollView(in: card))

        XCTAssertEqual(scroll.contentInset.bottom, 0, "No keyboard, no inset")

        postKeyboardFrame(CGRect(x: 0, y: 452, width: 393, height: 400), in: window)

        XCTAssertGreaterThan(
            scroll.contentInset.bottom, 0,
            "A keyboard overlapping the form must inset it, or the focused field stays hidden underneath"
        )
    }

    func testDismissingTheKeyboardRestoresTheForm() throws {
        let (card, window) = hostedCard()
        defer { window.isHidden = true }
        let scroll = try XCTUnwrap(cardScrollView(in: card))

        postKeyboardFrame(CGRect(x: 0, y: 452, width: 393, height: 400), in: window)
        XCTAssertGreaterThan(scroll.contentInset.bottom, 0)

        NotificationCenter.default.post(
            name: UIResponder.keyboardWillHideNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(
                    cgRect: CGRect(x: 0, y: 852, width: 393, height: 400)
                )
            ]
        )

        XCTAssertEqual(
            scroll.contentInset.bottom, 0,
            "Leaving a field must give the form its full height back"
        )
    }

    /// A keyboard that does not overlap this view — undocked or floating on
    /// iPad, or a hardware keyboard's accessory bar off-screen — must not
    /// inset anything.
    func testNonOverlappingKeyboardLeavesTheFormAlone() throws {
        let (card, window) = hostedCard()
        defer { window.isHidden = true }
        let scroll = try XCTUnwrap(cardScrollView(in: card))

        postKeyboardFrame(CGRect(x: 0, y: 900, width: 393, height: 300), in: window)

        XCTAssertEqual(
            scroll.contentInset.bottom, 0,
            "A keyboard below the form does not overlap it and must not inset it"
        )
    }

    /// The taller the keyboard, the deeper the inset — the handler reads the
    /// real frame rather than assuming a fixed height.
    func testInsetTracksKeyboardHeight() throws {
        let (card, window) = hostedCard()
        defer { window.isHidden = true }
        let scroll = try XCTUnwrap(cardScrollView(in: card))

        postKeyboardFrame(CGRect(x: 0, y: 652, width: 393, height: 200), in: window)
        let shallow = scroll.contentInset.bottom

        postKeyboardFrame(CGRect(x: 0, y: 452, width: 393, height: 400), in: window)
        let deep = scroll.contentInset.bottom

        XCTAssertGreaterThan(deep, shallow, "A taller keyboard must inset the form further")
    }

    // MARK: - The merchant knob is wired up

    func testKeyboardScrollOffsetIsReadFromConfiguration() {
        var configuration = PaymentSheet.Configuration()
        configuration.payment.keyboardScrollOffset = 120
        let sheet = PaymentSheet(configuration: configuration)

        XCTAssertEqual(
            sheet.configuration.payment.keyboardScrollOffset, 120,
            "The offset a merchant sets must survive into the configuration the form reads"
        )
    }

    // MARK: - Helpers

    private func hostedCard() -> (PaymentCardViewController, UIWindow) {
        let card = PaymentCardViewController()
        card.paymentSheet = PaymentSheet()
        let window = UIWindow(frame: CGRect(origin: .zero, size: phone))
        window.rootViewController = UINavigationController(rootViewController: card)
        window.makeKeyAndVisible()
        card.loadViewIfNeeded()
        window.layoutIfNeeded()
        return (card, window)
    }

    private func postKeyboardFrame(_ frame: CGRect, in window: UIWindow) {
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: frame),
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.0,
            ]
        )
        window.layoutIfNeeded()
    }

    private func cardScrollView(in card: PaymentCardViewController) -> UIScrollView? {
        func search(_ view: UIView) -> UIScrollView? {
            for subview in view.subviews {
                if let scroll = subview as? UIScrollView,
                   scroll.accessibilityIdentifier == "uqpay.card.scroll" {
                    return scroll
                }
                if let match = search(subview) { return match }
            }
            return nil
        }
        return search(card.view)
    }
}
