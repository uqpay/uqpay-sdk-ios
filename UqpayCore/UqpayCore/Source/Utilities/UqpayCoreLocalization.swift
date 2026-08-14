//
//  UqpayCoreLocalization.swift
//  UqpayCore
//
//  Created by UQPAY on 13/08/2026.
//

import Foundation

/// Resolves the bundle carrying `UqpayCore`'s `Localizable.strings`.
///
/// - SwiftPM: `Bundle.module`.
/// - CocoaPods: the `UqpayCore.bundle` resource bundle nested in whichever
///   bundle contains this class (the framework, or the app for a static pod).
/// - Xcode framework target: the framework bundle itself.
enum UqpayCoreResources {
    static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        final class Anchor {}
        let containing = Bundle(for: Anchor.self)
        if let nestedURL = containing.url(forResource: "UqpayCore", withExtension: "bundle"),
           let nested = Bundle(url: nestedURL) {
            return nested
        }
        return containing
        #endif
    }()
}

/// Looks up user-facing copy in `UqpayCore`'s `Localizable.strings`.
/// Keys are the English copy, so a missing entry falls back to exactly the
/// pre-localization wording.
func uqpayCoreLocalized(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: UqpayCoreResources.bundle, comment: "")
}
