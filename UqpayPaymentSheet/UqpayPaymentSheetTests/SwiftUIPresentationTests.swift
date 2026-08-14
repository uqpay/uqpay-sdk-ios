//
//  SwiftUIPresentationTests.swift
//  UqpayPaymentSheetTests
//
//  Created by UQPAY on 11/08/2026.
//

import XCTest
import SwiftUI
import UIKit
@testable import UqpayCore
@testable import UqpayPayments
@testable import UqpayPaymentSheet

/// Pins the structural guarantees the SwiftUI presenter must provide.
///
/// Every one of these failed before: the `.cardOnly` path presented a bare
/// `PaymentCardViewController`, so each `navigationController?.push…` that shows
/// a receipt, a failure or a pending state resolved against nil and did nothing.
/// The customer paid and the screen never changed. Nothing about that was a
/// compile error, which is exactly why it survived — so the invariants are
/// asserted here rather than left to review.
@available(iOS 14.0, *)
@MainActor
final class SwiftUIPresentationTests: XCTestCase {

    private final class SpyDelegate: PaymentDelegate {
        var completed: [PaymentResult] = []
        var failures: [PaymentError] = []

        func paymentSheet(_ paymentSheet: PaymentSheet, didCompleteWithResult result: PaymentResult) {
            completed.append(result)
        }

        func paymentSheet(_ paymentSheet: PaymentSheet, didFailWithError error: PaymentError) {
            failures.append(error)
        }
    }

    private func makeHost(
        sheet: PaymentSheet,
        sheetType: PaymentSheetType,
        isPresented: Binding<Bool> = .constant(true)
    ) -> UqpayPaymentSheetPresenter.SheetHostView {
        UqpayPaymentSheetPresenter.SheetHostView(
            isPresented: isPresented,
            sheet: sheet,
            sheetType: sheetType
        )
    }

    // MARK: - The card screen must live inside a navigation controller

    /// The bug this file exists for. A bare card controller silently swallows
    /// every status screen it tries to push.
    func testCardOnlyEmbedsCardScreenInANavigationController() {
        let sheet = PaymentSheet(sheetType: .cardOnly)
        let host = makeHost(sheet: sheet, sheetType: .cardOnly)
        let container = host.makeContainer()

        guard let navigation = container.children.first as? UINavigationController else {
            return XCTFail("The card screen must be embedded in a UINavigationController")
        }
        XCTAssertTrue(
            navigation.viewControllers.first is PaymentCardViewController,
            "The navigation controller's root must be the card screen"
        )
    }

    /// A push must actually reach the stack — the precise thing that used to
    /// vanish.
    func testStatusScreenPushedFromCardScreenReachesTheStack() {
        let sheet = PaymentSheet(sheetType: .cardOnly)
        let host = makeHost(sheet: sheet, sheetType: .cardOnly)
        let container = host.makeContainer()

        let navigation = container.children.first as? UINavigationController
        let card = navigation?.viewControllers.first as? PaymentCardViewController
        XCTAssertNotNil(card?.navigationController, "The card screen had no navigation controller")

        card?.navigationController?.pushViewController(UIViewController(), animated: false)
        XCTAssertEqual(navigation?.viewControllers.count, 2, "The pushed status screen was dropped")
    }

    // MARK: - The merchant's delegate must reach the payment screen

    func testCardOnlyForwardsTheSheetAndItsDelegate() {
        let delegate = SpyDelegate()
        let sheet = PaymentSheet(sheetType: .cardOnly)
        sheet.paymentDelegate = delegate

        let host = makeHost(sheet: sheet, sheetType: .cardOnly)
        let container = host.makeContainer()

        let navigation = container.children.first as? UINavigationController
        let card = navigation?.viewControllers.first as? PaymentCardViewController

        XCTAssertTrue(card?.paymentDelegate === delegate, "The merchant's delegate never arrived")
        XCTAssertTrue(card?.paymentSheet === sheet, "Callbacks would carry a throwaway PaymentSheet")
    }

    /// A delegate assigned after presentation must still be picked up, because
    /// SwiftUI commonly wires one up on the next view update.
    func testDelegateAssignedAfterPresentationIsPickedUp() {
        let sheet = PaymentSheet(sheetType: .cardOnly)
        let host = makeHost(sheet: sheet, sheetType: .cardOnly)
        let container = host.makeContainer()

        let delegate = SpyDelegate()
        sheet.paymentDelegate = delegate
        container.refreshPaymentDelegate(from: sheet)

        let navigation = container.children.first as? UINavigationController
        let card = navigation?.viewControllers.first as? PaymentCardViewController
        XCTAssertTrue(card?.paymentDelegate === delegate)
    }

    /// Refreshing with no delegate set must not wipe one already delivered.
    func testRefreshWithoutADelegateDoesNotClearTheExistingOne() {
        let delegate = SpyDelegate()
        let sheet = PaymentSheet(sheetType: .cardOnly)
        sheet.paymentDelegate = delegate

        let host = makeHost(sheet: sheet, sheetType: .cardOnly)
        let container = host.makeContainer()

        sheet.paymentDelegate = nil
        container.refreshPaymentDelegate(from: sheet)

        let navigation = container.children.first as? UINavigationController
        let card = navigation?.viewControllers.first as? PaymentCardViewController
        XCTAssertTrue(card?.paymentDelegate === delegate)
    }

    // MARK: - Dismissal must flow back into SwiftUI's binding

    /// The SDK dismisses its own controllers. If that does not reach the
    /// binding, SwiftUI still believes the sheet is up and it can never be
    /// presented a second time.
    func testLeavingTheWindowReportsDismissalExactlyOnce() {
        let container = UqpayPaymentSheetPresenter.ContainerViewController()
        var dismissals = 0
        container.onDismissed = { dismissals += 1 }

        container.loadViewIfNeeded()
        XCTAssertNil(container.view.window, "Precondition: the container is not in a window")

        container.viewDidDisappear(false)
        container.viewDidDisappear(false)

        let drained = expectation(description: "deferred dismissal checks ran")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)

        XCTAssertEqual(dismissals, 1, "Dismissal must be reported once, not per disappearance")
    }

    /// Still on screen behind a presented 3DS step — not a dismissal.
    func testStayingInTheWindowIsNotReportedAsDismissal() {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let container = UqpayPaymentSheetPresenter.ContainerViewController()
        var dismissals = 0
        container.onDismissed = { dismissals += 1 }

        window.rootViewController = container
        window.makeKeyAndVisible()

        container.viewDidDisappear(false)

        let drained = expectation(description: "deferred dismissal checks ran")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)

        XCTAssertEqual(dismissals, 0, "A controller still in the window was reported as dismissed")
        window.isHidden = true
    }

    // MARK: - Embedding

    func testEmbedReplacesThePreviousChild() {
        let container = UqpayPaymentSheetPresenter.ContainerViewController()
        container.loadViewIfNeeded()

        let first = UIViewController()
        let second = UIViewController()
        container.embed(child: first)
        container.embed(child: second)

        XCTAssertEqual(container.children.count, 1, "The replaced child was left behind")
        XCTAssertTrue(container.children.first === second)
        XCTAssertNil(first.parent)
    }
}
