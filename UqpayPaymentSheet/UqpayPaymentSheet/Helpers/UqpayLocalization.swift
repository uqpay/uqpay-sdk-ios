//
//  UqpayLocalization.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 13/08/2026.
//

import Foundation

/// Looks up user-facing copy in this module's `Localizable.strings`.
///
/// Keys are the English copy itself, so a locale (or key) with no entry
/// renders exactly what the SDK shipped before localization existed —
/// extraction can never change what an English user sees.
func UqpayLocalized(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: UqpayResourceManager.bundle, comment: "")
}
