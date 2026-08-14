//
//  BottomSheetViewController.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 19/08/2025.
//
import Foundation
import UIKit

// MARK: - Bottom Sheet (UINavigationController)

final class AppNavigationViewController: UINavigationController {
    private let sheetAppearance: PaymentSheet.Appearance

    init(rootViewController: UIViewController, appearance: PaymentSheet.Appearance) {
        self.sheetAppearance = appearance
        super.init(rootViewController: rootViewController)

        // `.unspecified` follows the device/host app; merchants can pin
        // `.light` or `.dark` via `Appearance.userInterfaceStyle`. Children
        // pushed onto this controller inherit the resolved style.
        overrideUserInterfaceStyle = appearance.userInterfaceStyle

        if let sheet = sheetPresentationController {
            // Medium-only pinned the sheet at half height: with four or more
            // payment methods the list was clipped and could not be dragged
            // up — the card row was simply unreachable.
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = appearance.cornerRadius
            sheet.selectedDetentIdentifier = .medium
            sheet.largestUndimmedDetentIdentifier = .medium
        }
        view.backgroundColor = UqpayColors.background
        navigationBar.tintColor = appearance.primaryColor
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyAccessibilityDetents()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            applyAccessibilityDetents()
        }
    }

    /// The medium detent is a fixed fraction of the screen: at accessibility
    /// text sizes it clips the form, so the sheet goes full-height instead.
    private func applyAccessibilityDetents() {
        guard let sheet = sheetPresentationController else { return }
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            sheet.detents = [.large()]
            sheet.selectedDetentIdentifier = .large
        } else {
            sheet.detents = [.medium(), .large()]
        }
    }
}



