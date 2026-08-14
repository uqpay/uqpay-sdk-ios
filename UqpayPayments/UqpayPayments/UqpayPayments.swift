//
//  UqpayPayments.swift
//  UqpayPayments
//
//  Created by UQPAY on 14/08/2025.
//

import Foundation

// MARK: - Core Models

public enum CardBrand: String, Codable, CaseIterable {
    case visa
    case masterCard
    case amex
    case discover
    case jcb
    case dinersClub
    case unionPay
    case unknown
}

public enum PaymentMethodType: String, Codable, CaseIterable {
    case card
    case wechat
    case alipay
    case alipayHK
    case payNow
    case grabPay
    case paypal
    case unionPay
    // Regional QR wallets. All check out through the same merchant-presented
    // QR flow as the wallets above.
    case trueMoney
    case touchNGo
    case gcash
    case dana
    case kakaoPay
    case toss
    case naverPay
}

public struct CardDetails: Codable, Hashable {
    public var name: String
    public var number: String
    public var expMonth: Int
    public var expYear: Int
    public var cvc: String

    public init(name: String, number: String, expMonth: Int, expYear: Int, cvc: String) {
        self.name = name
        self.number = number
        self.expMonth = expMonth
        self.expYear = expYear
        self.cvc = cvc
    }
}

public struct Customer: Codable, Hashable, Identifiable {
    public let id: String
    public var name: String?
    public var email: String?

    public init(id: String, name: String? = nil, email: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
    }
}

public struct Token: Codable, Hashable, Identifiable {
    public let id: String
    public let created: Date
}

public struct PaymentIntent: Codable, Hashable, Identifiable {
    public enum Status: String, Codable {
        case requiresPaymentMethod
        case requiresConfirmation
        case processing
        case succeeded
        case requiresAction
        case canceled
    }

    public let id: String
    public var amount: Int
    public var currency: String
    public var status: Status
}

public struct PaymentMethodOptions: Codable, Hashable {
    public var requestThreeDSecure: Bool?
    public init(requestThreeDSecure: Bool? = nil) { self.requestThreeDSecure = requestThreeDSecure }
}

// MARK: - Card Validator (minimal, based on Stripe API surface)


public struct BillingAddress: Codable, Hashable {
    public var sameAsShipping: Bool
    public var country: String
    public var district: String
    public var city: String
    public var state: String
    public var postalCode: String
    
    public init(sameAsShipping: Bool, country: String, district: String, city: String, state: String, postalCode: String) {
        self.sameAsShipping = sameAsShipping
        self.country = country
        self.district = district
        self.city = city
        self.state = state
        self.postalCode = postalCode
    }
}


public enum CardValidator {
    public static func brand(for cardNumber: String) -> CardBrand {
        let sanitized = cardNumber.filter { $0.isNumber }
        if sanitized.hasPrefix("4") { return .visa }
        // MasterCard is two BIN ranges: the classic 51–55 and the 2-series
        // 2221–2720 issued since 2017. A number in the 2-series needs four
        // digits before it can be told apart from other 2xxx ranges.
        if ["51","52","53","54","55"].contains(where: { sanitized.hasPrefix($0) }) { return .masterCard }
        if let four = numericPrefix(sanitized, 4), (2221...2720).contains(four) { return .masterCard }
        if ["34","37"].contains(where: { sanitized.hasPrefix($0) }) { return .amex }
        if sanitized.hasPrefix("6011") || sanitized.hasPrefix("65") { return .discover }
        if let three = numericPrefix(sanitized, 3), (644...649).contains(three) { return .discover }
        if let four = numericPrefix(sanitized, 4), (3528...3589).contains(four) { return .jcb }
        if ["300","301","302","303","304","305","36","38"].contains(where: { sanitized.hasPrefix($0) }) { return .dinersClub }
        if sanitized.hasPrefix("62") { return .unionPay }
        return .unknown
    }

    /// The first `length` digits as a number, or nil when fewer have been
    /// typed — a range can only be tested once enough digits exist.
    private static func numericPrefix(_ digits: String, _ length: Int) -> Int? {
        guard digits.count >= length else { return nil }
        return Int(digits.prefix(length))
    }

    public static func isValidLuhn(_ cardNumber: String) -> Bool {
        let digits = cardNumber.filter { $0.isNumber }.compactMap { Int(String($0)) }
        guard digits.count >= 8 else { return false }
        var sum = 0
        for (idx, digit) in digits.reversed().enumerated() {
            if idx % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    public static func isValidExpiry(month: Int, year: Int) -> Bool {
        guard (1...12).contains(month) else { return false }
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        guard let currentYear = comps.year, let currentMonth = comps.month else { return false }
        if year < currentYear { return false }
        if year == currentYear && month < currentMonth { return false }
        return true
    }

    public static func isValidCVC(_ cvc: String, brand: CardBrand) -> Bool {
        let count = cvc.filter { $0.isNumber }.count
        switch brand {
        case .amex: return count == 4
        default: return count == 3
        }
    }
}

