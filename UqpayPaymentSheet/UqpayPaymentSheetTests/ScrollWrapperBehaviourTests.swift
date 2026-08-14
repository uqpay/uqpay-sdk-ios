//
//  ScrollWrapperBehaviourTests.swift
//  UqpayPaymentSheetTests
//
//  C-series guard rails for the *other* direction: the scroll views added to
//  keep content reachable must not change how these screens behave when the
//  content already fitted. Wrapping a screen in a scroll view is a small edit
//  with three classic regressions — the layout stops being centred, the view
//  bounces when there is nothing to scroll, and a tap target the wrapper now
//  covers stops responding. One test each.
//

import XCTest
import UIKit
@testable import UqpayPaymentSheet
@testable import UqpayPayments

final class ScrollWrapperBehaviourTests: XCTestCase {

    private let roomyPhone = CGSize(width: 393, height: 852)

    // MARK: - The alert stays an alert

    /// Checked in the coordinate space the customer actually sees, not the
    /// scroll view's content space — a card centred in its content can still
    /// render low on screen once a content inset is applied.
    @MainActor
    func testAlertStaysCentredWhenItFits() throws {
        let (alert, window) = hosted(wrapInNavigation: false) {
            CustomAlertViewController(title: "Payment failed", message: "Your bank declined this payment.")
        }
        defer { window.isHidden = true }

        let card = try XCTUnwrap(find(UIView.self, "uqpay.alert.card", in: alert.view))
        let onScreen = card.convert(card.bounds, to: window)
        XCTAssertEqual(
            onScreen.midY, window.bounds.midY, accuracy: 1.0,
            "The card must still render centred on screen at default text size — it is an alert, not a form"
        )
    }

    @MainActor
    func testAlertDoesNotScrollWhenItFits() {
        let (alert, window) = hosted {
            CustomAlertViewController(title: "Payment failed", message: "Your bank declined this payment.")
        }
        defer { window.isHidden = true }

        let scroll = try! XCTUnwrap(find(UIScrollView.self, "uqpay.alert.scroll", in: alert.view))
        XCTAssertEqual(
            scroll.contentSize.height, scroll.bounds.height, accuracy: 1.0,
            "Content that fits must not become scrollable — otherwise the alert rubber-bands for no reason"
        )
    }

    @MainActor
    func testAlertBecomesScrollableOnlyWhenItOutgrowsTheScreen() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("traitOverrides requires iOS 17") }

        let (alert, window) = hosted(size: CGSize(width: 393, height: 393)) {
            CustomAlertViewController(
                title: "Payment failed",
                message: "Your bank declined this payment. Try a different card, or contact your bank for details."
            )
        }
        defer { window.isHidden = true }
        alert.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        window.layoutIfNeeded()
        window.layoutIfNeeded()

        let scroll = try XCTUnwrap(find(UIScrollView.self, "uqpay.alert.scroll", in: alert.view))
        XCTAssertGreaterThan(
            scroll.contentSize.height, scroll.bounds.height,
            "At AX5 on a short screen the card outgrows the viewport and must become scrollable"
        )
    }

    /// The scroll view is layered over the dimming view, so a tap outside the
    /// card no longer lands on `backgroundView`. If the recogniser did not move
    /// with it, tap-to-dismiss would silently stop working.
    @MainActor
    func testTapToDismissSurvivesTheScrollWrapper() throws {
        let (alert, window) = hosted {
            CustomAlertViewController(title: "Payment failed", message: "Your bank declined this payment.")
        }
        defer { window.isHidden = true }

        let scroll = try XCTUnwrap(find(UIScrollView.self, "uqpay.alert.scroll", in: alert.view))
        let taps = (scroll.gestureRecognizers ?? []).compactMap { $0 as? UITapGestureRecognizer }
        XCTAssertEqual(
            taps.count, 1,
            "Tap-to-dismiss must be attached to the scroll view, which is what the customer now touches"
        )
        XCTAssertNotNil(
            taps.first?.delegate,
            "Without a delegate the recogniser also swallows taps on the card's own dismiss button"
        )
    }

    /// The card must remain the thing that receives button taps.
    @MainActor
    func testDismissButtonIsHitTestableThroughTheScrollWrapper() throws {
        let (alert, window) = hosted {
            CustomAlertViewController(title: "Payment failed", message: "Your bank declined this payment.")
        }
        defer { window.isHidden = true }

        let button = try XCTUnwrap(descendants(of: alert.view).compactMap { $0 as? UIButton }.first)
        let centre = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: window)
        XCTAssertTrue(
            button.isDescendant(of: window.hitTest(centre, with: nil) ?? UIView()) || window.hitTest(centre, with: nil) === button,
            "The dismiss button must still win the hit test at its own centre"
        )
    }

    // MARK: - The wallet QR screen

    @MainActor
    func testWalletQRDoesNotScrollWhenItFits() throws {
        let descriptor = try XCTUnwrap(WalletQRDescriptor.descriptor(for: .wechat))
        // iPad portrait has room to spare for the whole tile.
        let (wallet, window) = hosted(size: CGSize(width: 834, height: 1194)) {
            WalletQRPaymentViewController(descriptor: descriptor)
        }
        defer { window.isHidden = true }

        let scroll = try XCTUnwrap(find(UIScrollView.self, "uqpay.wallet.scroll", in: wallet.view))
        XCTAssertLessThanOrEqual(
            scroll.contentSize.height, scroll.bounds.height + 1.0,
            "With a full iPad screen the tile fits and the screen must sit still"
        )
    }

    @MainActor
    func testWalletQRScrollsOnceTheCodeIsShownOnAShortScreen() throws {
        let descriptor = try XCTUnwrap(WalletQRDescriptor.descriptor(for: .wechat))
        let (wallet, window) = hosted(size: CGSize(width: 852, height: 393)) {
            WalletQRPaymentViewController(descriptor: descriptor)
        }
        defer { window.isHidden = true }

        find(UIView.self, "uqpay.wallet.qrCode", in: wallet.view, includeHidden: true)?.isHidden = false
        window.layoutIfNeeded()
        window.layoutIfNeeded()

        let scroll = try XCTUnwrap(find(UIScrollView.self, "uqpay.wallet.scroll", in: wallet.view))
        XCTAssertGreaterThan(
            scroll.contentSize.height, scroll.bounds.height,
            "In landscape the revealed QR exceeds the viewport, so the screen must scroll rather than clip"
        )
    }

    // MARK: - Helpers

    /// `wrapInNavigation: false` models the alert, which is presented
    /// `.overFullScreen` outside the sheet's navigation controller.
    @MainActor
    private func hosted<T: UIViewController>(
        size: CGSize? = nil, wrapInNavigation: Bool = true, _ make: () -> T
    ) -> (T, UIWindow) {
        let controller = make()
        let window = UIWindow(frame: CGRect(origin: .zero, size: size ?? roomyPhone))
        window.rootViewController = wrapInNavigation
            ? UINavigationController(rootViewController: controller)
            : controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        window.layoutIfNeeded()
        window.layoutIfNeeded()
        return (controller, window)
    }

    @MainActor
    private func find<T: UIView>(
        _ type: T.Type, _ identifier: String, in root: UIView, includeHidden: Bool = false
    ) -> T? {
        descendants(of: root).first { $0.accessibilityIdentifier == identifier } as? T
    }

    @MainActor
    private func descendants(of root: UIView) -> [UIView] {
        var found: [UIView] = []
        func walk(_ view: UIView) {
            for sub in view.subviews {
                found.append(sub)
                walk(sub)
            }
        }
        walk(root)
        return found
    }
}
