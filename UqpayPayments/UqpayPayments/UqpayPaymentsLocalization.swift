//
//  UqpayPaymentsLocalization.swift
//  UqpayPayments
//
//  Created by UQPAY on 13/08/2026.
//

import Foundation

/// Resolves the bundle carrying `UqpayPayments`' `Localizable.strings`.
///
/// - SwiftPM: `Bundle.module`.
/// - CocoaPods: the `UqpayPayments.bundle` resource bundle nested in whichever
///   bundle contains this class (the framework, or the app for a static pod).
/// - Xcode framework target: the framework bundle itself.
enum UqpayPaymentsResources {
    static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        final class Anchor {}
        let containing = Bundle(for: Anchor.self)
        if let nestedURL = containing.url(forResource: "UqpayPayments", withExtension: "bundle"),
           let nested = Bundle(url: nestedURL) {
            return nested
        }
        return containing
        #endif
    }()
}

/// Looks up user-facing copy in `UqpayPayments`' `Localizable.strings`.
/// Keys are the English copy, so a missing entry falls back to exactly the
/// pre-localization wording.
func uqpayPaymentsLocalized(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: UqpayPaymentsResources.bundle, comment: "")
}
