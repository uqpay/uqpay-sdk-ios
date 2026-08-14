//
//  UqpayFonts.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 13/08/2026.
//

import UIKit

/// Dynamic Type support for the sheet's fixed-size fonts.
///
/// Every screen used to hardcode `systemFont(ofSize:)`, which never scales.
/// `scaled(size:weight:textStyle:)` wraps the exact same fixed font in
/// `UIFontMetrics`, so at the default content size it renders identically —
/// and grows/shrinks with the user's text-size setting. Pair it with
/// `adjustsFontForContentSizeCategory = true` so live setting changes apply
/// without recreating the view.
enum UqpayFonts {

    /// A Dynamic Type–scaling version of `systemFont(ofSize:weight:)`.
    ///
    /// - Parameter textStyle: The style whose scaling curve to borrow. Pick
    ///   the style whose default size is closest to `size` so the growth rate
    ///   matches what the system would do.
    static func scaled(
        size: CGFloat,
        weight: UIFont.Weight = .regular,
        textStyle: UIFont.TextStyle = .body
    ) -> UIFont {
        UIFontMetrics(forTextStyle: textStyle)
            .scaledFont(for: .systemFont(ofSize: size, weight: weight))
    }
}
