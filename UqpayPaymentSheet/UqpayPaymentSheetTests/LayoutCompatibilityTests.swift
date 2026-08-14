//
//  LayoutCompatibilityTests.swift
//  UqpayPaymentSheetTests
//
//  C-series regression coverage: every control the customer must be able to
//  reach has to stay reachable on every geometry the SDK claims to support.
//
//  The assertion is deliberately *not* a pixel snapshot. Pixel diffs across OS
//  versions are a maintenance tax, and the bugs this suite exists to catch are
//  boolean: "can the customer get to the Pay button, yes or no". A control is
//  reachable when it sits inside the visible bounds, or inside a scroll view
//  whose `contentSize` actually covers it.
//
//  The second half of that sentence is load-bearing. Wrapping a screen in a
//  scroll view is the standard fix for clipping, and the standard way to get it
//  wrong is an ambiguous content layout that leaves `contentSize` at zero —
//  which looks fine in a screenshot and scrolls nowhere. That case fails here.
//

import XCTest
import UIKit
@testable import UqpayPaymentSheet
@testable import UqpayPayments

final class LayoutCompatibilityTests: XCTestCase {

    // MARK: - The matrix

    /// Full-screen device geometries. The sheet is presented inside a
    /// navigation controller, so each case also exercises the ~44pt nav bar and
    /// the safe-area insets the real chrome imposes.
    ///
    /// iPhone SE is the 320pt floor — the narrowest device in the support
    /// matrix. iPhone landscape is the tightest *height*: UIKit adapts sheets to
    /// full screen in a compact-height environment, so `.large` is all the room
    /// there will ever be. There is no drag-to-recover the way portrait has.
    struct Viewport {
        let name: String
        let size: CGSize

        static let all: [Viewport] = [
            Viewport(name: "iPhone SE portrait",   size: CGSize(width: 320,  height: 568)),
            Viewport(name: "iPhone SE landscape",  size: CGSize(width: 568,  height: 320)),
            Viewport(name: "iPhone 15 portrait",   size: CGSize(width: 393,  height: 852)),
            Viewport(name: "iPhone 15 landscape",  size: CGSize(width: 852,  height: 393)),
            Viewport(name: "iPad 11in portrait",   size: CGSize(width: 834,  height: 1194)),
            Viewport(name: "iPad 11in landscape",  size: CGSize(width: 1194, height: 834)),
        ]
    }

    // MARK: - Screens under test

    @MainActor
    func testWalletQRScreenIsReachable() {
        // The QR is revealed after "Show QR Code" is tapped; that tap needs a
        // live intent, so the test unhides it directly. This is the geometry the
        // customer is actually asked to scan.
        assertReachable("wallet QR (code shown)") {
            WalletQRPaymentViewController(
                descriptor: XCTUnwrap_descriptor(for: .wechat)
            )
        } prepare: { root in
            Self.view(withIdentifier: "uqpay.wallet.qrCode", in: root)?.isHidden = false
        }
    }

    @MainActor
    func testWalletQRScreenIsReachableBeforeQRIsShown() {
        assertReachable("wallet QR (initial)") {
            WalletQRPaymentViewController(descriptor: XCTUnwrap_descriptor(for: .grabPay))
        }
    }

    @MainActor
    func testPaymentStatusScreensAreReachable() {
        // Terminal states carry the most chrome: icon, title, message, and up to
        // two action buttons.
        assertReachable("status: failed") {
            PaymentCardStatusViewController(
                configuration: .failed(errorCode: "card_declined", message: "Your bank declined this payment.")
            )
        }
        assertReachable("status: success") {
            PaymentCardStatusViewController(
                configuration: .success(amount: "SGD 12.34", transactionId: "pi_test_123456789")
            )
        }
        assertReachable("status: pending") {
            PaymentCardStatusViewController(
                configuration: .pending(amount: "SGD 12.34", transactionId: "pi_test_123456789", message: nil)
            )
        }
    }

    @MainActor
    func testCustomAlertIsReachable() {
        assertReachable("custom alert") {
            CustomAlertViewController(
                title: "Payment failed",
                message: "Your bank declined this payment. Try a different card, or contact your bank for details.",
                buttonTitle: "OK"
            )
        }
    }

    @MainActor
    func testCardFormIsReachable() {
        assertReachable("card form") { PaymentCardViewController() }
    }

    @MainActor
    func testPaymentListIsReachable() {
        assertReachable("payment list") {
            PaymentListViewController(
                appearance: PaymentSheet.Appearance(),
                configuration: PaymentSheet.Configuration()
            )
        }
    }

    // MARK: - Accessibility text sizes

    /// The tightest case in the whole matrix: the largest text on the shortest
    /// screen. Labels grow, buttons grow, the room does not.
    @MainActor
    func testScreensAreReachableAtAccessibilityTextSizes() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("traitOverrides requires iOS 17")
        }
        assertReachable("status: failed @ AX5", contentSizeCategory: .accessibilityExtraExtraExtraLarge) {
            PaymentCardStatusViewController(
                configuration: .failed(errorCode: "card_declined", message: "Your bank declined this payment.")
            )
        }
        assertReachable("custom alert @ AX5", contentSizeCategory: .accessibilityExtraExtraExtraLarge) {
            CustomAlertViewController(
                title: "Payment failed",
                message: "Your bank declined this payment. Try a different card, or contact your bank for details.",
                buttonTitle: "OK"
            )
        }
        assertReachable("wallet QR @ AX5", contentSizeCategory: .accessibilityExtraExtraExtraLarge) {
            WalletQRPaymentViewController(descriptor: XCTUnwrap_descriptor(for: .wechat))
        } prepare: { root in
            Self.view(withIdentifier: "uqpay.wallet.qrCode", in: root)?.isHidden = false
        }
    }

    // MARK: - The assertion

    @MainActor
    private func assertReachable(
        _ label: String,
        contentSizeCategory: UIContentSizeCategory = .large,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ make: () -> UIViewController,
        prepare: ((UIView) -> Void)? = nil
    ) {
        for viewport in Viewport.all {
            let subject = make()
            let nav = UINavigationController(rootViewController: subject)
            let window = UIWindow(frame: CGRect(origin: .zero, size: viewport.size))
            window.rootViewController = nav
            window.makeKeyAndVisible()
            defer { window.isHidden = true }

            subject.loadViewIfNeeded()
            if contentSizeCategory != .large, #available(iOS 17.0, *) {
                nav.traitOverrides.preferredContentSizeCategory = contentSizeCategory
            }
            prepare?(subject.view)
            window.layoutIfNeeded()
            // A second pass: unhiding a stack-view child re-runs the layout, and
            // scroll views only settle their contentSize after their content has
            // its final intrinsic size.
            window.layoutIfNeeded()

            for problem in Self.reachabilityProblems(in: subject) {
                XCTFail("[\(label)] \(viewport.name): \(problem)", file: file, line: line)
            }
        }
    }

    // MARK: - Reachability

    @MainActor
    private static func reachabilityProblems(in controller: UIViewController) -> [String] {
        let root = controller.view!
        let visible = root.bounds
        guard visible.height > 0 else { return ["view has zero height — layout did not run"] }

        var problems: [String] = []

        // A scroll view that lays out its content ambiguously reports a zero
        // content height and scrolls nowhere. Catch it directly rather than
        // inferring it from the controls inside.
        for scroll in descendants(of: root, matching: { $0 is UIScrollView }) as! [UIScrollView] {
            guard scroll.bounds.height > 0, !scroll.subviews.isEmpty else { continue }
            if scroll.contentSize.height <= 0 {
                problems.append(
                    "scroll view \(scroll.accessibilityIdentifier ?? "<untagged>") has contentSize.height == 0 — its content layout is ambiguous and it will not scroll"
                )
            }
        }

        for candidate in reachabilityCandidates(in: root) {
            let frame = candidate.convert(candidate.bounds, to: root)
            guard frame.height > 0.5, frame.width > 0.5 else { continue }

            let fits = frame.minY >= -0.5 && frame.maxY <= visible.height + 0.5
            if fits { continue }

            guard let scroll = scrollAncestor(of: candidate) else {
                problems.append(
                    "\(describe(candidate)) spans y \(round(frame.minY))…\(round(frame.maxY)) "
                    + "but only 0…\(round(visible.height)) is visible, and it has no scroll ancestor — "
                    + "the customer cannot reach it"
                )
                continue
            }

            // Inside a scroll view it only counts as reachable if the content
            // rect actually extends far enough to bring it on screen.
            let inContent = candidate.convert(candidate.bounds, to: scroll)
            let covered = inContent.minY >= -0.5
                && inContent.maxY <= scroll.contentSize.height + 0.5
            if !covered {
                problems.append(
                    "\(describe(candidate)) sits at y \(round(inContent.minY))…\(round(inContent.maxY)) "
                    + "inside a scroll view whose contentSize.height is \(round(scroll.contentSize.height)) — "
                    + "scrolling will never reveal it"
                )
            }
        }
        return problems
    }

    /// Controls the customer interacts with, anything the SDK tagged for UI
    /// testing, and large imagery (the QR code and the status glyph) — the
    /// things whose clipping is a functional failure rather than cosmetic.
    @MainActor
    private static func reachabilityCandidates(in root: UIView) -> [UIView] {
        descendants(of: root) { view in
            if view is UIControl { return true }
            if (view.accessibilityIdentifier ?? "").hasPrefix("uqpay.") { return true }
            if view is UIImageView, min(view.bounds.width, view.bounds.height) >= 80 { return true }
            return false
        }
    }

    @MainActor
    private static func descendants(
        of root: UIView, matching predicate: (UIView) -> Bool
    ) -> [UIView] {
        var found: [UIView] = []
        func walk(_ view: UIView) {
            for sub in view.subviews {
                // A hidden or fully transparent view is not something the
                // customer is being asked to reach.
                guard !sub.isHidden, sub.alpha > 0.01 else { continue }
                if predicate(sub) { found.append(sub) }
                walk(sub)
            }
        }
        walk(root)
        return found
    }

    @MainActor
    private static func scrollAncestor(of view: UIView) -> UIScrollView? {
        var cursor = view.superview
        while let current = cursor {
            if let scroll = current as? UIScrollView { return scroll }
            cursor = current.superview
        }
        return nil
    }

    @MainActor
    private static func view(withIdentifier identifier: String, in root: UIView) -> UIView? {
        descendants(of: root, matching: { $0.accessibilityIdentifier == identifier }).first
            // The QR image view starts hidden, and `descendants` skips hidden
            // views by design — find it the unfiltered way.
            ?? unfilteredDescendants(of: root).first { $0.accessibilityIdentifier == identifier }
    }

    @MainActor
    private static func unfilteredDescendants(of root: UIView) -> [UIView] {
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

    @MainActor
    private static func describe(_ view: UIView) -> String {
        if let identifier = view.accessibilityIdentifier { return "\(type(of: view))[\(identifier)]" }
        if let button = view as? UIButton, let title = button.title(for: .normal) {
            return "button \"\(title)\""
        }
        if let field = view as? UITextField, let label = field.accessibilityLabel {
            return "field \"\(label)\""
        }
        return "\(type(of: view))"
    }

    // MARK: - Fixtures

    private func XCTUnwrap_descriptor(for type: PaymentMethodType) -> WalletQRDescriptor {
        guard let descriptor = WalletQRDescriptor.descriptor(for: type) else {
            preconditionFailure("\(type) is expected to be a QR wallet")
        }
        return descriptor
    }
}
