//
//  UqpayColors.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 13/08/2026.
//

import UIKit

/// The sheet's internal color palette.
///
/// Every color is dynamic: the light variant is the exact literal the screens
/// used before dark-mode support, so light mode is pixel-identical to 1.0.0-rc.1.
/// The dark variant is the same design-scale hue at an inverted step
/// (Tailwind neutrals on the form screens, Tailwind grays on the status screen).
///
/// Brand colors (`uqpayBlue`, wallet accents, card-network colors) are the same
/// in both modes on purpose — they are identity, not chrome.
enum UqpayColors {

    // MARK: Form screens (Tailwind Neutral scale)

    /// Headings and dark icons. Light: Neutral-950 `#0A0A0A`.
    static let textPrimary = dynamic(light: rgb(10, 10, 10), dark: rgb(250, 250, 250))

    /// Field labels. Light: Neutral-900 `#171717`.
    static let textLabel = dynamic(light: rgb(23, 23, 23), dark: rgb(237, 237, 237))

    /// De-emphasised labels (state/postal captions). Light: Neutral-600 `#404040`.
    static let textMuted = dynamic(light: rgb(64, 64, 64), dark: rgb(163, 163, 163))

    /// Raw-QR instruction text. Light: `#646464`.
    static let textInstructionRawQR = dynamic(light: rgb(100, 100, 100), dark: rgb(163, 163, 163))

    /// Field and container borders. Light: Neutral-200 `#E5E5E5`.
    static let border = dynamic(light: rgb(229, 229, 229), dark: rgb(64, 64, 64))

    /// Full-screen backgrounds. `.systemBackground` is pure white in light mode
    /// (identical to the old `.white`) and elevates correctly inside a sheet
    /// presentation in dark mode.
    static let background: UIColor = .systemBackground

    /// Bordered cards/containers sitting on `background` (method rows, QR card,
    /// bank-details card, secondary buttons). Light: white, exactly as before.
    static let surface = dynamic(light: .white, dark: rgb(44, 44, 46))

    /// The Pay button. Brand color — identical in both modes.
    static let uqpayBlue = rgb(1, 119, 253)

    /// Focused-field border and glow. Same blue in both modes; it reads well
    /// on dark and keeping it constant avoids a second focus style to test.
    static let focusBorder = rgb(59, 130, 246)
    static let focusGlow = rgba(59, 130, 246, 0.25)

    // MARK: Status screen (Tailwind Gray scale)

    /// Status titles. Light: Gray-900 `#111827`.
    static let statusTextPrimary = dynamic(light: rgb(17, 24, 39), dark: rgb(243, 244, 246))

    /// Status detail text. Light: Gray-500 `#6B7280`.
    static let statusTextSecondary = dynamic(light: rgb(107, 114, 128), dark: rgb(156, 163, 175))

    /// Failure detail text emphasis. Light: Gray-600 `#4B5563`.
    static let statusTextTertiary = dynamic(light: rgb(75, 85, 99), dark: rgb(209, 213, 219))

    /// Secondary-button border. Light: Gray-300 `#D1D5DB`.
    static let statusButtonBorder = dynamic(light: rgb(209, 213, 219), dark: rgb(75, 85, 99))

    /// Neutral action color (retry spinner, gray primary button). Same both modes.
    static let statusNeutral = rgb(107, 114, 128)

    // MARK: Status accents — icon tints and buttons keep their brand-strength
    // 500/600 values in both modes; only the soft icon-badge backgrounds swap
    // to a dark shade so the badge stays a badge instead of a glowing slab.

    static let statusBlue = rgb(37, 99, 235)                                  // Blue-600
    static let statusGreen = rgb(34, 197, 94)                                 // Green-500
    static let statusRed = rgb(239, 68, 68)                                   // Red-500
    static let statusAmber = rgb(251, 191, 36)                                // Amber-500

    static let statusGreenBadge = dynamic(light: rgb(220, 252, 231), dark: rgb(20, 83, 45))    // Green-100 / Green-900
    static let statusRedBadge = dynamic(light: rgb(254, 226, 226), dark: rgb(127, 29, 29))     // Red-100 / Red-900
    static let statusAmberBadge = dynamic(light: rgb(254, 243, 199), dark: rgb(120, 53, 15))   // Amber-100 / Amber-900
    static let statusBlueBadge = dynamic(light: rgb(219, 234, 254), dark: rgb(30, 58, 138))    // Blue-100 / Blue-900

    static let statusGreenGlow = rgba(34, 197, 94, 0.3)
    static let statusRedGlow = rgba(239, 68, 68, 0.3)
    static let statusAmberGlow = rgba(251, 191, 36, 0.3)
    static let statusBlueGlow = rgba(37, 99, 235, 0.3)
    static let statusNeutralGlow = rgba(107, 114, 128, 0.3)

    // MARK: Helpers

    private static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: 1.0)
    }

    private static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> UIColor {
        UIColor(red: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
    }
}
