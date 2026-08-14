//
//  DarkModeAppearanceTests.swift
//  UqpayPaymentSheetTests
//
//  U3 (dark mode) regression coverage: light mode must stay pixel-identical
//  to the pre-dark-mode literals, dark mode must actually resolve dark, and
//  the merchant opt-out must reach the presentation container.
//

import XCTest
import UIKit
@testable import UqpayPaymentSheet

final class DarkModeAppearanceTests: XCTestCase {

    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    private func rgba(_ color: UIColor, _ traits: UITraitCollection) -> [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    private func assertLightValue(
        _ color: UIColor, red: CGFloat, green: CGFloat, blue: CGFloat,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let resolved = rgba(color, light)
        let expected = [red / 255.0, green / 255.0, blue / 255.0, 1.0]
        for (got, want) in zip(resolved, expected) {
            XCTAssertEqual(got, want, accuracy: 0.001, file: file, line: line)
        }
    }

    // MARK: - Light mode is pixel-identical to the pre-dark-mode literals

    func testLightVariantsMatchOriginalLiterals() {
        assertLightValue(UqpayColors.textPrimary, red: 10, green: 10, blue: 10)
        assertLightValue(UqpayColors.textLabel, red: 23, green: 23, blue: 23)
        assertLightValue(UqpayColors.textMuted, red: 64, green: 64, blue: 64)
        assertLightValue(UqpayColors.border, red: 229, green: 229, blue: 229)
        assertLightValue(UqpayColors.surface, red: 255, green: 255, blue: 255)
        assertLightValue(UqpayColors.uqpayBlue, red: 1, green: 119, blue: 253)
        assertLightValue(UqpayColors.statusTextPrimary, red: 17, green: 24, blue: 39)
        assertLightValue(UqpayColors.statusTextSecondary, red: 107, green: 114, blue: 128)
        assertLightValue(UqpayColors.statusTextTertiary, red: 75, green: 85, blue: 99)
        assertLightValue(UqpayColors.statusButtonBorder, red: 209, green: 213, blue: 219)
        assertLightValue(UqpayColors.statusBlue, red: 37, green: 99, blue: 235)
        assertLightValue(UqpayColors.statusGreen, red: 34, green: 197, blue: 94)
        assertLightValue(UqpayColors.statusRed, red: 239, green: 68, blue: 68)
        assertLightValue(UqpayColors.statusAmber, red: 251, green: 191, blue: 36)
        assertLightValue(UqpayColors.statusGreenBadge, red: 220, green: 252, blue: 231)
        assertLightValue(UqpayColors.statusRedBadge, red: 254, green: 226, blue: 226)
        assertLightValue(UqpayColors.statusAmberBadge, red: 254, green: 243, blue: 199)
        assertLightValue(UqpayColors.statusBlueBadge, red: 219, green: 234, blue: 254)
        assertLightValue(UqpayColors.textInstructionRawQR, red: 100, green: 100, blue: 100)
    }

    // MARK: - Dark mode genuinely resolves different chrome

    func testAdaptiveColorsResolveDifferentlyInDark() {
        let adaptive: [(String, UIColor)] = [
            ("textPrimary", UqpayColors.textPrimary),
            ("textLabel", UqpayColors.textLabel),
            ("textMuted", UqpayColors.textMuted),
            ("border", UqpayColors.border),
            ("surface", UqpayColors.surface),
            ("background", UqpayColors.background),
            ("statusTextPrimary", UqpayColors.statusTextPrimary),
            ("statusButtonBorder", UqpayColors.statusButtonBorder),
            ("statusGreenBadge", UqpayColors.statusGreenBadge),
            ("statusRedBadge", UqpayColors.statusRedBadge),
        ]
        for (name, color) in adaptive {
            XCTAssertNotEqual(
                rgba(color, light), rgba(color, dark),
                "\(name) should resolve differently in dark mode"
            )
        }
    }

    func testBrandColorsAreStableAcrossModes() {
        let stable: [(String, UIColor)] = [
            ("uqpayBlue", UqpayColors.uqpayBlue),
            ("focusBorder", UqpayColors.focusBorder),
            ("statusGreen", UqpayColors.statusGreen),
            ("statusRed", UqpayColors.statusRed),
            ("statusBlue", UqpayColors.statusBlue),
        ]
        for (name, color) in stable {
            XCTAssertEqual(
                rgba(color, light), rgba(color, dark),
                "\(name) is brand identity and must not shift between modes"
            )
        }
    }

    // MARK: - Merchant opt-out

    func testAppearanceDefaultsToFollowingTheSystem() {
        XCTAssertEqual(PaymentSheet.Appearance().userInterfaceStyle, .unspecified)
    }

    @MainActor
    func testNavigationContainerAppliesMerchantStyleChoice() {
        let appearance = PaymentSheet.Appearance()
        appearance.userInterfaceStyle = .light
        let nav = AppNavigationViewController(
            rootViewController: UIViewController(), appearance: appearance
        )
        XCTAssertEqual(nav.overrideUserInterfaceStyle, .light)

        appearance.userInterfaceStyle = .unspecified
        let followSystem = AppNavigationViewController(
            rootViewController: UIViewController(), appearance: appearance
        )
        XCTAssertEqual(followSystem.overrideUserInterfaceStyle, .unspecified)
    }

    /// The seven `overrideUserInterfaceStyle = .light` force-disables are gone:
    /// a pushed screen resolves dark when its container is dark.
    @MainActor
    func testPushedScreenResolvesDarkInsideDarkContainer() {
        let appearance = PaymentSheet.Appearance()
        appearance.userInterfaceStyle = .dark
        let list = PaymentListViewController(
            appearance: appearance, configuration: PaymentSheet.Configuration()
        )
        let nav = AppNavigationViewController(rootViewController: list, appearance: appearance)
        // Trait propagation only happens inside a window's hierarchy.
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = nav
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        XCTAssertEqual(
            list.view.traitCollection.userInterfaceStyle, .dark,
            "The list screen must inherit the container's dark style now that the force-light override is removed"
        )
    }
}
