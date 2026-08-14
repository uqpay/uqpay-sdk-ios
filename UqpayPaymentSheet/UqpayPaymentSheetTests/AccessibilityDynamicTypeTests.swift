//
//  AccessibilityDynamicTypeTests.swift
//  UqpayPaymentSheetTests
//
//  U5 regression coverage: fonts scale with the user's text size (while
//  staying pixel-identical at the default size), and the payment form is
//  labelled for VoiceOver.
//

import XCTest
import UIKit
@testable import UqpayPaymentSheet

final class AccessibilityDynamicTypeTests: XCTestCase {

    // MARK: - Fonts

    func testScaledFontIsIdenticalAtDefaultContentSize() {
        UITraitCollection(preferredContentSizeCategory: .large).performAsCurrent {
            let scaled = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
            XCTAssertEqual(
                scaled.pointSize, 16, accuracy: 0.01,
                "`.large` is the default setting — the scaled font must render exactly like the fixed font it replaced"
            )
        }
    }

    /// Exercises the real mechanism: a label using the scaled font plus
    /// `adjustsFontForContentSizeCategory` must grow when its trait
    /// environment switches to an accessibility text size.
    @MainActor
    func testScaledFontGrowsAtAccessibilitySizes() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("traitOverrides requires iOS 17")
        }
        let label = UILabel()
        label.text = "Pay"
        label.font = UqpayFonts.scaled(size: 16, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true

        let host = UIViewController()
        host.view.addSubview(label)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        window.layoutIfNeeded()

        XCTAssertGreaterThan(
            label.font.pointSize, 16 * 1.5,
            "AX5 must render meaningfully larger text (got \(label.font.pointSize))"
        )
    }

    // MARK: - The card form is labelled and scales

    @MainActor
    func testCardFormFieldsAreLabelledAndScale() {
        let card = PaymentCardViewController()
        card.loadViewIfNeeded()

        let fields = findViews(of: UITextField.self, in: card.view)
        XCTAssertEqual(fields.count, 13, "The card form has 13 input fields")

        for field in fields {
            XCTAssertNotNil(
                field.accessibilityLabel,
                "Every field needs an accessibilityLabel — placeholder text is not a substitute (\(field.placeholder ?? "?"))"
            )
            XCTAssertTrue(
                field.adjustsFontForContentSizeCategory,
                "Every field must scale with Dynamic Type (\(field.accessibilityLabel ?? "?"))"
            )
        }
    }

    @MainActor
    func testCardFormLabelsScale() {
        let card = PaymentCardViewController()
        card.loadViewIfNeeded()

        let labels = findViews(of: UILabel.self, in: card.view)
        XCTAssertFalse(labels.isEmpty)
        for label in labels where label.font.pointSize >= 10 {
            XCTAssertTrue(
                label.adjustsFontForContentSizeCategory,
                "Label \"\(label.text ?? "?")\" must scale with Dynamic Type"
            )
        }
    }

    // MARK: - Helpers

    private func findViews<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        var found: [T] = []
        for subview in root.subviews {
            if let match = subview as? T { found.append(match) }
            found.append(contentsOf: findViews(of: type, in: subview))
        }
        return found
    }
}
