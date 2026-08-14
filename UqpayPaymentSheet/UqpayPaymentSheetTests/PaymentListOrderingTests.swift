//
//  PaymentListOrderingTests.swift
//  UqpayPaymentSheetTests
//
//  Covers two defects found against the shipped 1.0.0 while testing a live
//  sandbox account with a dozen wallets enabled:
//
//  1. The method list could not scroll. `containerView` is pinned between the
//     title and the Continue button, so its height is whatever the sheet leaves
//     over, and the table was pinned to all four of its edges with
//     `isScrollEnabled = false`. Every row past the fold was clipped by
//     `clipsToBounds` and unreachable — including `card`.
//
//  2. Order came straight from the API, which put `card` below the fold.
//
//  `LayoutCompatibilityTests.testPaymentListIsReachable` did not catch (1)
//  because it renders the screen with an empty list: with no rows there is
//  nothing to clip, and the assertion passes. These tests supply rows.
//

import XCTest
import UIKit
@testable import UqpayPaymentSheet
@testable import UqpayPayments

final class PaymentListOrderingTests: XCTestCase {

    // MARK: - Ordering

    func testCardIsPinnedFirst() {
        let ordered = PaymentListViewController.cardFirst([
            .init(id: "tosspay", type: .toss, name: "Toss", icon: "qrcode"),
            .init(id: "alipaycn", type: .alipay, name: "Alipay", icon: "alipay"),
            .init(id: "card", type: .card, name: "Card", icon: "card"),
            .init(id: "grabpay", type: .grabPay, name: "GrabPay", icon: "grab_pay"),
        ])

        XCTAssertEqual(ordered.first?.type, .card,
                       "Card must lead the list — it is what most customers reach for.")
    }

    /// The API's ordering of the wallets carries meaning the SDK has no basis to
    /// second-guess, so a stable partition is required, not a sort.
    func testWalletsKeepTheOrderTheAPIGaveThem() {
        let ordered = PaymentListViewController.cardFirst([
            .init(id: "tosspay", type: .toss, name: "Toss", icon: "qrcode"),
            .init(id: "alipaycn", type: .alipay, name: "Alipay", icon: "alipay"),
            .init(id: "card", type: .card, name: "Card", icon: "card"),
            .init(id: "grabpay", type: .grabPay, name: "GrabPay", icon: "grab_pay"),
        ])

        XCTAssertEqual(ordered.map(\.id), ["card", "tosspay", "alipaycn", "grabpay"])
    }

    func testAListWithoutCardIsLeftAlone() {
        let input: [PaymentMethod] = [
            .init(id: "tosspay", type: .toss, name: "Toss", icon: "qrcode"),
            .init(id: "gcash", type: .gcash, name: "GCash", icon: "qrcode"),
        ]

        XCTAssertEqual(PaymentListViewController.cardFirst(input).map(\.id),
                       input.map(\.id),
                       "Nothing to pin means nothing should move.")
    }

    func testAnEmptyListSurvives() {
        XCTAssertTrue(PaymentListViewController.cardFirst([]).isEmpty)
    }

    // MARK: - Scrolling

    /// The regression guard for (1). A list taller than the sheet is the normal
    /// case for a merchant with many wallets enabled, and the only thing that
    /// makes those rows reachable is the table scrolling.
    @MainActor
    func testTheMethodListScrolls() {
        let controller = PaymentListViewController(
            appearance: PaymentSheet.Appearance(),
            configuration: PaymentSheet.Configuration()
        )
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()

        guard let table = Self.firstTableView(in: controller.view) else {
            return XCTFail("The payment list should render a table view.")
        }

        XCTAssertTrue(table.isScrollEnabled,
                      "The table is pinned to a fixed-height container, so with "
                      + "scrolling off every row past the fold is unreachable.")
    }

    private static func firstTableView(in view: UIView) -> UITableView? {
        if let table = view as? UITableView { return table }
        for subview in view.subviews {
            if let found = firstTableView(in: subview) { return found }
        }
        return nil
    }
}
