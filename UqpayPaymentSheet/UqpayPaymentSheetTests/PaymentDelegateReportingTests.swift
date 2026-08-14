//
//  PaymentDelegateReportingTests.swift
//  UqpayPaymentSheetTests
//
//  Created by UQPAY on 11/08/2026.
//

import XCTest
import UIKit
@testable import UqpayCore
@testable import UqpayPayments
@testable import UqpayPaymentSheet

/// Pins the one-delegate contract.
///
/// `PaymentSheetDelegate`, `PaymentCardDelegate` and
/// `PaymentListViewControllerDelegate` were all public, all settable, and all
/// completely unreachable — a merchant who wired one got total silence. They
/// are gone, and `PaymentDelegate` is the only delegate. These assert that
/// cancellation is reported exactly once per payment and never contradicts an
/// outcome that was already reported.
@MainActor
final class PaymentDelegateReportingTests: XCTestCase {

    private final class SpyDelegate: PaymentDelegate {
        var completed = 0
        var failed = 0
        var cancelled = 0
        var actions: [RequiredAction] = []

        func paymentSheet(_ paymentSheet: PaymentSheet, didCompleteWithResult result: PaymentResult) {
            completed += 1
        }

        func paymentSheet(_ paymentSheet: PaymentSheet, didFailWithError error: PaymentError) {
            failed += 1
        }

        func paymentSheetDidCancel(_ paymentSheet: PaymentSheet) {
            cancelled += 1
        }

        func paymentSheet(_ paymentSheet: PaymentSheet, requiresAction action: RequiredAction) {
            actions.append(action)
        }
    }

    /// Walking away from the card form without paying is a cancellation.
    func testAbandoningTheCardFormReportsCancellationOnce() {
        let delegate = SpyDelegate()
        let sheet = PaymentSheet()
        sheet.paymentDelegate = delegate

        let card = PaymentCardViewController()
        card.paymentSheet = sheet
        card.paymentDelegate = delegate

        let navigation = UINavigationController(rootViewController: card)
        navigation.loadViewIfNeeded()
        card.loadViewIfNeeded()

        // Simulate the sheet being torn down with the card screen on top.
        card.handleFlowDismissal()

        XCTAssertEqual(delegate.cancelled, 1)
        XCTAssertEqual(delegate.completed, 0)
        XCTAssertEqual(delegate.failed, 0)
    }

    /// One dismissal tears down several screens. The merchant must still hear
    /// about the cancellation exactly once.
    func testSeveralScreensTornDownTogetherReportOneCancellation() {
        let delegate = SpyDelegate()
        let sheet = PaymentSheet()
        sheet.paymentDelegate = delegate

        let card = PaymentCardViewController()
        card.paymentSheet = sheet
        card.paymentDelegate = delegate
        card.loadViewIfNeeded()

        guard let descriptor = WalletQRDescriptor.descriptor(for: .grabPay) else {
            return XCTFail("GrabPay descriptor missing")
        }
        let wallet = WalletQRPaymentViewController(descriptor: descriptor)
        wallet.paymentSheet = sheet
        wallet.paymentDelegate = delegate
        wallet.loadViewIfNeeded()

        card.handleFlowDismissal()
        wallet.handleFlowDismissal()

        XCTAssertEqual(delegate.cancelled, 1, "Cancellation must be reported once per payment")
    }

    /// A payment that already reported an outcome is not a cancellation, however
    /// the screens are torn down afterwards.
    func testAReportedOutcomeSuppressesCancellation() {
        let delegate = SpyDelegate()
        let sheet = PaymentSheet()
        sheet.paymentDelegate = delegate

        let card = PaymentCardViewController()
        card.paymentSheet = sheet
        card.paymentDelegate = delegate
        card.loadViewIfNeeded()

        // Whatever reported it — success or decline — the payment is resolved.
        sheet.hasReportedOutcome = true

        card.handleFlowDismissal()

        XCTAssertEqual(delegate.cancelled, 0, "A resolved payment must not report a cancellation")
    }

    /// Merely navigating within the flow is not leaving it.
    func testPushingAStatusScreenIsNotACancellation() {
        let delegate = SpyDelegate()
        let sheet = PaymentSheet()
        sheet.paymentDelegate = delegate

        let card = PaymentCardViewController()
        card.paymentSheet = sheet
        card.paymentDelegate = delegate

        let navigation = UINavigationController(rootViewController: card)
        navigation.loadViewIfNeeded()
        card.loadViewIfNeeded()

        // A push makes the card screen disappear without it leaving the stack.
        navigation.pushViewController(UIViewController(), animated: false)
        card.viewDidDisappear(false)

        XCTAssertEqual(delegate.cancelled, 0, "Pushing a status screen is not a cancellation")
    }

    /// Without a sheet there is nothing to gate on, so nothing is reported
    /// rather than something reported twice.
    func testNoSheetMeansNoCancellationReport() {
        let delegate = SpyDelegate()
        let card = PaymentCardViewController()
        card.paymentDelegate = delegate
        card.loadViewIfNeeded()

        card.handleFlowDismissal()

        XCTAssertEqual(delegate.cancelled, 0)
    }

    // MARK: - The method list is the sheet's root

    private func makeList(sheet: PaymentSheet, delegate: PaymentDelegate) -> PaymentListViewController {
        let list = PaymentListViewController(
            appearance: PaymentSheet.Appearance(), configuration: PaymentSheet.Configuration()
        )
        list.paymentSheet = sheet
        list.paymentDelegate = delegate
        return list
    }

    /// The commonest abandonment of all: open the sheet, look at the methods,
    /// swipe it away. The customer never reaches the card or wallet screen, so
    /// neither of those can report it.
    func testAbandoningTheMethodListReportsCancellation() {
        let delegate = SpyDelegate()
        let sheet = PaymentSheet()
        sheet.paymentDelegate = delegate

        let list = makeList(sheet: sheet, delegate: delegate)
        let navigation = UINavigationController(rootViewController: list)
        navigation.loadViewIfNeeded()
        list.loadViewIfNeeded()

        list.handleFlowDismissal()

        XCTAssertEqual(delegate.cancelled, 1, "Swiping the method list away is a cancellation")
        XCTAssertEqual(delegate.completed, 0)
        XCTAssertEqual(delegate.failed, 0)
    }

    /// Choosing a method pushes a screen on top of the list. That must not be
    /// mistaken for walking out of the flow.
    func testChoosingAMethodFromTheListIsNotACancellation() {
        let delegate = SpyDelegate()
        let sheet = PaymentSheet()
        sheet.paymentDelegate = delegate

        let list = makeList(sheet: sheet, delegate: delegate)
        let navigation = UINavigationController(rootViewController: list)
        navigation.loadViewIfNeeded()
        list.loadViewIfNeeded()

        navigation.pushViewController(PaymentCardViewController(), animated: false)
        list.viewDidDisappear(false)

        XCTAssertEqual(delegate.cancelled, 0, "Picking a payment method is not abandoning the payment")
    }

    /// Dismissing from the card screen tears down the list underneath it. The
    /// shared gate must still yield exactly one callback.
    func testListAndCardTornDownTogetherReportOneCancellation() {
        let delegate = SpyDelegate()
        let sheet = PaymentSheet()
        sheet.paymentDelegate = delegate

        let list = makeList(sheet: sheet, delegate: delegate)
        list.loadViewIfNeeded()

        let card = PaymentCardViewController()
        card.paymentSheet = sheet
        card.paymentDelegate = delegate
        card.loadViewIfNeeded()

        card.handleFlowDismissal()
        list.handleFlowDismissal()

        XCTAssertEqual(delegate.cancelled, 1, "One dismissal is one cancellation, however many screens it tears down")
    }

    /// A payment that reached `PENDING` is not abandoned when the customer
    /// closes the sheet — the documented contract says no cancellation follows.
    func testPendingPaymentIsNotCancelledByClosingTheList() {
        let delegate = SpyDelegate()
        let sheet = PaymentSheet()
        sheet.paymentDelegate = delegate

        let list = makeList(sheet: sheet, delegate: delegate)
        list.loadViewIfNeeded()

        // Every pending / success / failure report goes through `reportingSheet`,
        // which sets this.
        sheet.hasReportedOutcome = true

        list.handleFlowDismissal()

        XCTAssertEqual(delegate.cancelled, 0, "A pending payment must not also be reported as cancelled")
    }
}
