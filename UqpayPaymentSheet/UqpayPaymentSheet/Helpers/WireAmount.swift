//
//  WireAmount.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 02/09/2026.
//

import Foundation
import UqpayCore

/// An amount as the API sent it — a decimal string in major units, `"8.98"` —
/// in the two forms a ``PaymentResult`` carries.
///
/// Every result the prebuilt sheet reports is built through
/// ``parse(_:fallback:paymentIntentId:)``, so ``PaymentResult/amount`` and
/// ``PaymentResult/amountDecimal`` always describe the same wire value, and a
/// value that cannot be parsed is logged instead of reported as a silent zero.
struct WireAmount {
    /// The floating-point value merchants on 1.0.x have always received:
    /// `Double(raw) ?? 0`. Computed exactly as before so nothing a merchant
    /// already relies on moves.
    let double: Double

    /// The exact value, or `nil` when the wire value was absent or not a plain
    /// decimal string. Never derived from ``double``: that would reintroduce
    /// the floating-point error under a name that promises exactness.
    let decimal: Decimal?

    /// Parses an amount string from the API.
    ///
    /// - Parameters:
    ///   - raw: The amount string from the API, if any.
    ///   - fallback: A second wire string, tried when `raw` is absent or
    ///     unparseable. Mirrors the one site that always had a fallback.
    ///   - paymentIntentId: Names the payment in the log line written when the
    ///     value could not be parsed exactly.
    static func parse(_ raw: String?, fallback: String? = nil, paymentIntentId: String) -> WireAmount {
        let double = raw.flatMap(Double.init) ?? fallback.flatMap(Double.init) ?? 0
        let decimal = raw.flatMap(exactDecimal) ?? fallback.flatMap(exactDecimal)

        if decimal == nil {
            // Only the amount string and the intent id: the response object
            // carries card and billing details on some paths.
            let shown = raw.map { "\"\($0)\"" } ?? "nil"
            UqpayLogger.shared.error(
                "Amount \(shown) for intent \(paymentIntentId) is not a plain decimal string; "
                    + "reporting amountDecimal nil and amount \(double)"
            )
        }

        return WireAmount(double: double, decimal: decimal)
    }

    /// `Decimal(string:)` is lenient — it reads `"8,98"` as 8 and `"8.98abc"`
    /// as 8.98 — so the string is checked to be `-?digits[.digits]` first.
    /// Anything else is `nil`, never a plausible-looking wrong number.
    private static func exactDecimal(_ string: String) -> Decimal? {
        var body = Substring(string)
        if body.hasPrefix("-") { body = body.dropFirst() }

        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }

        return Decimal(string: string)
    }
}
