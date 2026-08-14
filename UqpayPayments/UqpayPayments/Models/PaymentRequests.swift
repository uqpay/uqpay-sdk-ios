//
//  PaymentRequests.swift
//  UqpayPayments
//
//  Created by UQPAY on 14/08/2025.
//

import Foundation

// MARK: - Payment Request Models

public struct CardPaymentRequest: Codable {
    public let cardNumber: String
    public let expiryMonth: Int
    public let expiryYear: Int
    public let cvc: String
    public let amount: Int
    public let currency: String
    public let billingDetails: BillingDetails?
    
    public init(cardNumber: String, expiryMonth: Int, expiryYear: Int, cvc: String, 
                amount: Int, currency: String, billingDetails: BillingDetails? = nil) {
        self.cardNumber = cardNumber
        self.expiryMonth = expiryMonth
        self.expiryYear = expiryYear
        self.cvc = cvc
        self.amount = amount
        self.currency = currency
        self.billingDetails = billingDetails
    }
}

public struct PaymentIntentRequest: Codable {
    public let amount: Int
    public let currency: String
    public let paymentMethodTypes: [String]
    
    public init(amount: Int, currency: String, paymentMethodTypes: [String]) {
        self.amount = amount
        self.currency = currency
        self.paymentMethodTypes = paymentMethodTypes
    }
}

// MARK: - Payment Response Models

public struct PaymentResponse: Codable {
    public let success: Bool
    public let paymentId: String?
    public let message: String?
    public let redirectUrl: String?
    
    public init(success: Bool, paymentId: String? = nil, message: String? = nil, redirectUrl: String? = nil) {
        self.success = success
        self.paymentId = paymentId
        self.message = message
        self.redirectUrl = redirectUrl
    }
}

public struct PaymentIntentResponse: Codable {
    public let success: Bool
    public let clientSecret: String?
    public let message: String?
    
    public init(success: Bool, clientSecret: String? = nil, message: String? = nil) {
        self.success = success
        self.clientSecret = clientSecret
        self.message = message
    }
}

// MARK: - Supporting Models

public struct PaymentMethod: Codable {
    public let id: String
    public let type: PaymentMethodType
    public let name: String
    public let icon: String

    public init(id: String, type: PaymentMethodType, name: String, icon: String) {
        self.id = id
        self.type = type
        self.name = name
        self.icon = icon
    }

    /// Builds a method from an `available_payment_method_types` entry on the
    /// payment intent.
    ///
    /// The API decides *which* methods a payment offers; this only knows how
    /// to render each documented type string. A type this SDK version cannot
    /// render yet (e.g. `tng`) returns nil, so a new server-side method
    /// degrades to being hidden instead of breaking the sheet.
    /// Icon strings name image sets in the sheet's asset catalog — they must
    /// match exactly, or the cell silently falls back to a generic glyph.
    public init?(apiType: String) {
        switch apiType {
        case "card":      self.init(id: apiType, type: .card,     name: "Card",      icon: "card")
        case "wechatpay": self.init(id: apiType, type: .wechat,   name: "WeChat",    icon: "wechat")
        case "alipaycn":  self.init(id: apiType, type: .alipay,   name: "Alipay",    icon: "alipay")
        case "alipayhk":  self.init(id: apiType, type: .alipayHK, name: "Alipay HK", icon: "alipay_hk")
        case "grabpay":   self.init(id: apiType, type: .grabPay,  name: "GrabPay",   icon: "grab_pay")
        case "paynow":    self.init(id: apiType, type: .payNow,   name: "PayNow",    icon: "pay_now")
        case "unionpay":  self.init(id: apiType, type: .unionPay, name: "UnionPay",  icon: "unionpay")
        // Regional QR wallets. No brand marks have been drawn for these yet,
        // so they name the "qrcode" SF Symbol rather than an asset set that
        // does not exist — a missing set falls back to a generic card glyph,
        // which reads as a card payment and is worse than an honest QR mark.
        // Swap each to its asset set name once design supplies one.
        case "truemoney": self.init(id: apiType, type: .trueMoney, name: "TrueMoney", icon: "qrcode")
        case "tng":       self.init(id: apiType, type: .touchNGo,  name: "Touch 'n Go", icon: "qrcode")
        case "gcash":     self.init(id: apiType, type: .gcash,     name: "GCash",     icon: "qrcode")
        case "dana":      self.init(id: apiType, type: .dana,      name: "DANA",      icon: "qrcode")
        case "kakaopay":  self.init(id: apiType, type: .kakaoPay,  name: "KakaoPay",  icon: "qrcode")
        case "tosspay":   self.init(id: apiType, type: .toss,      name: "Toss",      icon: "qrcode")
        case "naverpay":  self.init(id: apiType, type: .naverPay,  name: "Naver Pay", icon: "qrcode")
        default: return nil
        }
    }
}

public struct BillingDetails: Codable {
    public let firstName: String?
    public let lastName: String?
    public let email: String?
    public let phoneNumber: String?
    public let address: Address?

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case phoneNumber = "phone_number"
        case address
    }

    public init(firstName: String? = nil, lastName: String? = nil, email: String? = nil, phoneNumber: String? = nil, address: Address? = nil) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phoneNumber = phoneNumber
        self.address = address
    }
}

public struct Address: Codable {
    public let countryCode: String?
    public let state: String?
    public let city: String?
    public let street: String?
    public let postcode: String?

    enum CodingKeys: String, CodingKey {
        case countryCode = "country_code"
        case state
        case city
        case street
        case postcode
    }

    public init(countryCode: String? = nil, state: String? = nil, city: String? = nil,
                street: String? = nil, postcode: String? = nil) {
        self.countryCode = countryCode
        self.state = state
        self.city = city
        self.street = street
        self.postcode = postcode
    }
}

// MARK: - Auth Token Response

public struct AuthTokenResponse: Codable {
    public let authToken: String
    public let expiredAt: Int
    
    enum CodingKeys: String, CodingKey {
        case authToken = "auth_token"
        case expiredAt = "expired_at"
    }
    
    public init(authToken: String, expiredAt: Int) {
        self.authToken = authToken
        self.expiredAt = expiredAt
    }
}

// MARK: - Payment Intent Create Response

public struct PaymentIntentCreateResponse: Codable {
    public let paymentIntentId: String
    public let amount: String
    public let currency: String
    public let capturedAmount: String?
    public let paymentMethod: PaymentMethodDetails?
    public let customer: CustomerDetails?
    public let customerId: String?
    public let cancelTime: String?
    public let cancellationReason: String?
    public let clientSecret: String
    public let merchantOrderId: String?
    public let description: String?
    public let metadata: [String: String]?
    public var nextAction: NextAction?
    public let returnUrl: String?
    public let createTime: String
    public let updateTime: String
    public let completeTime: String?
    public let latestPaymentAttempt: PaymentAttempt?
    public var intentStatus: String

    public init(
        paymentIntentId: String,
        amount: String,
        currency: String,
        capturedAmount: String? = nil,
        paymentMethod: PaymentMethodDetails? = nil,
        customer: CustomerDetails? = nil,
        customerId: String? = nil,
        cancelTime: String? = nil,
        cancellationReason: String? = nil,
        clientSecret: String,
        merchantOrderId: String? = nil,
        description: String? = nil,
        metadata: [String: String]? = nil,
        nextAction: NextAction? = nil,
        returnUrl: String? = nil,
        createTime: String = "",
        updateTime: String = "",
        completeTime: String? = nil,
        latestPaymentAttempt: PaymentAttempt? = nil,
        intentStatus: String
    ) {
        self.paymentIntentId = paymentIntentId
        self.amount = amount
        self.currency = currency
        self.capturedAmount = capturedAmount
        self.paymentMethod = paymentMethod
        self.customer = customer
        self.customerId = customerId
        self.cancelTime = cancelTime
        self.cancellationReason = cancellationReason
        self.clientSecret = clientSecret
        self.merchantOrderId = merchantOrderId
        self.description = description
        self.metadata = metadata
        self.nextAction = nextAction
        self.returnUrl = returnUrl
        self.createTime = createTime
        self.updateTime = updateTime
        self.completeTime = completeTime
        self.latestPaymentAttempt = latestPaymentAttempt
        self.intentStatus = intentStatus
    }

    enum CodingKeys: String, CodingKey {
        case paymentIntentId = "payment_intent_id"
        case amount, currency
        case capturedAmount = "captured_amount"
        case paymentMethod = "payment_method"
        case customer
        case customerId = "customer_id"
        case cancelTime = "cancel_time"
        case cancellationReason = "cancellation_reason"
        case clientSecret = "client_secret"
        case merchantOrderId = "merchant_order_id"
        case description
        case metadata
        case nextAction = "next_action"
        case returnUrl = "return_url"
        case createTime = "create_time"
        case updateTime = "update_time"
        case completeTime = "complete_time"
        case latestPaymentAttempt = "latest_payment_attempt"
        case intentStatus = "intent_status"
    }
}

public struct PaymentMethodDetails: Codable {
    public let type: String
    public let card: CardPaymentDetails?
    
    public init(type: String, card: CardPaymentDetails?) {
        self.type = type
        self.card = card
    }
}

public struct CardPaymentDetails: Codable {
    public let cardName: String?
    public let cardNumber: String?
    public let network: String?
    public let billing: BillingDetails?
    public let autoCapture: Bool?
    public let authorizationType: String?
    public let threeDsAction: String?
    public let threeDs: ThreeDsDetails?
    
    enum CodingKeys: String, CodingKey {
        case cardName = "card_name"
        case cardNumber = "card_number"
        case network, billing
        case autoCapture = "auto_capture"
        case authorizationType = "authorization_type"
        case threeDsAction = "three_ds_action"
        case threeDs = "three_ds"
    }
}

public struct ThreeDsDetails: Codable {
    public let returnUrl: String?
    public let acsResponse: String?
    public let deviceDataCollectionRes: String?
    public let dsTransactionId: String?
    
    enum CodingKeys: String, CodingKey {
        case returnUrl = "return_url"
        case acsResponse = "acs_response"
        case deviceDataCollectionRes = "device_data_collection_res"
        case dsTransactionId = "ds_transaction_id"
    }
}

public struct CustomerDetails: Codable {
    public let firstName: String?
    public let lastName: String?
    public let email: String?
    public let phoneNumber: String?
    public let description: String?
    public let address: Address?
    public let metadata: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case phoneNumber = "phone_number"
        case description, address, metadata
    }
}

public struct NextAction: Codable {
    public var type: String?
    public var redirectToUrl: RedirectToUrl?
    public var displayQrCode: DisplayQrCode?
    public var displayBankDetails: DisplayBankDetails?
    public var redirectIframe: RedirectIframe?

    enum CodingKeys: String, CodingKey {
        case type
        case redirectToUrl = "redirect_to_url"
        case displayQrCode = "display_qr_code"
        case displayBankDetails = "display_bank_details"
        case redirectIframe = "redirect_iframe"
    }

    public init(type: String? = nil, redirectToUrl: RedirectToUrl? = nil, displayQrCode: DisplayQrCode? = nil, displayBankDetails: DisplayBankDetails? = nil, redirectIframe: RedirectIframe? = nil) {
        self.type = type
        self.redirectToUrl = redirectToUrl
        self.displayQrCode = displayQrCode
        self.displayBankDetails = displayBankDetails
        self.redirectIframe = redirectIframe
    }

    /// Infer the action type if not explicitly provided
    public var actionType: String {
        // If type is explicitly provided, use it
        if let explicitType = type {
            return explicitType
        }

        // Otherwise, infer from which field is present
        if redirectToUrl != nil {
            return "redirect_to_url"
        } else if displayQrCode != nil {
            return "display_qr_code"
        } else if displayBankDetails != nil {
            return "display_bank_details"
        } else if redirectIframe != nil {
            return "redirect_iframe"
        }

        return "unknown"
    }
}

public struct RedirectToUrl: Codable {
    public var url: String
    public var returnUrl: String

    enum CodingKeys: String, CodingKey {
        case url
        case returnUrl = "return_url"
    }

    public init(url: String, returnUrl: String) {
        self.url = url
        self.returnUrl = returnUrl
    }
}

public struct DisplayQrCode: Codable {
    public let qrCode: String?
    public let qrCodeUrl: String?
    public let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case qrCode = "qr_code"
        case qrCodeUrl = "qr_code_url"
        case expiresAt = "expires_at"
    }

    public init(qrCode: String? = nil, qrCodeUrl: String? = nil, expiresAt: String? = nil) {
        self.qrCode = qrCode
        self.qrCodeUrl = qrCodeUrl
        self.expiresAt = expiresAt
    }
}

public struct DisplayBankDetails: Codable {
    public let bankName: String
    public let accountNumber: String
    public let routingNumber: String

    enum CodingKeys: String, CodingKey {
        case bankName = "bank_name"
        case accountNumber = "account_number"
        case routingNumber = "routing_number"
    }

    public init(bankName: String, accountNumber: String, routingNumber: String) {
        self.bankName = bankName
        self.accountNumber = accountNumber
        self.routingNumber = routingNumber
    }
}

public struct RedirectIframe: Codable {
    public let iframe: String

    enum CodingKeys: String, CodingKey {
        case iframe
    }

    public init(iframe: String) {
        self.iframe = iframe
    }
}

public struct PaymentAttempt: Codable {
    public let attemptId: String
    public let amount: String
    public let currency: String
    public let capturedAmount: String
    public let refundedAmount: String
    public let createTime: String
    public let updateTime: String
    public let completeTime: String?
    public let cancelTime: String?
    public let cancellationReason: String?
    public let failureCode: String?
    public let attemptStatus: String

    enum CodingKeys: String, CodingKey {
        case attemptId = "attempt_id"
        case amount, currency
        case capturedAmount = "captured_amount"
        case refundedAmount = "refunded_amount"
        case createTime = "create_time"
        case updateTime = "update_time"
        case completeTime = "complete_time"
        case cancelTime = "cancel_time"
        case cancellationReason = "cancellation_reason"
        case failureCode = "failure_code"
        case attemptStatus = "attempt_status"
    }

    /// Lenient by design: this attempt rides inside the confirm response,
    /// and a missing bookkeeping field must not make the whole response
    /// undecodable — an unreadable 2xx reads as "outcome unknown" and would
    /// leave a genuinely-answered payment stuck in that state.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attemptId = (try? c.decode(String.self, forKey: .attemptId)) ?? ""
        amount = (try? c.decode(String.self, forKey: .amount)) ?? ""
        currency = (try? c.decode(String.self, forKey: .currency)) ?? ""
        capturedAmount = (try? c.decode(String.self, forKey: .capturedAmount)) ?? ""
        refundedAmount = (try? c.decode(String.self, forKey: .refundedAmount)) ?? ""
        createTime = (try? c.decode(String.self, forKey: .createTime)) ?? ""
        updateTime = (try? c.decode(String.self, forKey: .updateTime)) ?? ""
        completeTime = try? c.decode(String.self, forKey: .completeTime)
        cancelTime = try? c.decode(String.self, forKey: .cancelTime)
        cancellationReason = try? c.decode(String.self, forKey: .cancellationReason)
        failureCode = try? c.decode(String.self, forKey: .failureCode)
        attemptStatus = (try? c.decode(String.self, forKey: .attemptStatus)) ?? ""
    }
}

// MARK: - Confirm Payment Intent Request

public struct ConfirmPaymentIntentRequest: Codable {
    public let paymentMethod: ConfirmPaymentMethod
    public let browserInfo: BrowserInfo
    /// The customer's IP address. Required by the API for 3DS card
    /// confirmations; omitted when nil. Never send a fabricated address —
    /// it feeds risk and fraud scoring.
    public let ipAddress: String?
    enum CodingKeys: String, CodingKey {
        case paymentMethod = "payment_method"
        case browserInfo = "browser_info"
        case ipAddress = "ip_address"
    }

    public init(paymentMethod: ConfirmPaymentMethod, browserInfo: BrowserInfo, ipAddress: String? = nil) {
        self.paymentMethod = paymentMethod
        self.browserInfo = browserInfo
        self.ipAddress = ipAddress
    }
}

public struct ConfirmPaymentMethod: Codable {
    public let type: String
    public let card: ConfirmCardDetails?
    public let alipaycn: AlipayDetails?
    public let alipayhk: AlipayDetails?
    public let wechatpay: WeChatPayDetails?
    public let unionpay: UnionPayDetails?
    public let grabpay: GrabPayDetails?
    public let paynow: PayNowDetails?
    public let truemoney: WalletQRDetails?
    public let tng: WalletQRDetails?
    public let gcash: WalletQRDetails?
    public let dana: WalletQRDetails?
    public let kakaopay: WalletQRDetails?
    public let tosspay: WalletQRDetails?
    public let naverpay: WalletQRDetails?

    /// The one initialiser that names every field.
    ///
    /// Adding a payment method used to mean editing every initialiser to set
    /// the new field nil, and missing one silently changed that method's
    /// request body. Defaulting here makes a new method one line in one place.
    ///
    /// Synthesised `Codable` encodes optionals with `encodeIfPresent`, so the
    /// unset fields are absent from the JSON rather than null — which is what
    /// keeps an idempotent replay byte-identical to the original send.
    private init(
        methodType: String,
        card: ConfirmCardDetails? = nil,
        alipaycn: AlipayDetails? = nil,
        alipayhk: AlipayDetails? = nil,
        wechatpay: WeChatPayDetails? = nil,
        unionpay: UnionPayDetails? = nil,
        grabpay: GrabPayDetails? = nil,
        paynow: PayNowDetails? = nil,
        truemoney: WalletQRDetails? = nil,
        tng: WalletQRDetails? = nil,
        gcash: WalletQRDetails? = nil,
        dana: WalletQRDetails? = nil,
        kakaopay: WalletQRDetails? = nil,
        tosspay: WalletQRDetails? = nil,
        naverpay: WalletQRDetails? = nil
    ) {
        self.type = methodType
        self.card = card
        self.alipaycn = alipaycn
        self.alipayhk = alipayhk
        self.wechatpay = wechatpay
        self.unionpay = unionpay
        self.grabpay = grabpay
        self.paynow = paynow
        self.truemoney = truemoney
        self.tng = tng
        self.gcash = gcash
        self.dana = dana
        self.kakaopay = kakaopay
        self.tosspay = tosspay
        self.naverpay = naverpay
    }

    public init(type: String, card: ConfirmCardDetails) {
        self.init(methodType: type, card: card)
    }

    public init(type: String, alipay: AlipayDetails) {
        // One details shape, two method types — the type picks the field.
        if type == "alipaycn" {
            self.init(methodType: type, alipaycn: alipay)
        } else {
            self.init(methodType: type, alipayhk: alipay)
        }
    }

    public init(type: String, wechatpay: WeChatPayDetails) {
        self.init(methodType: type, wechatpay: wechatpay)
    }

    public init(type: String, unionpay: UnionPayDetails) {
        self.init(methodType: type, unionpay: unionpay)
    }

    public init(type: String, grabpay: GrabPayDetails) {
        self.init(methodType: type, grabpay: grabpay)
    }

    public init(type: String, paynow: PayNowDetails) {
        self.init(methodType: type, paynow: paynow)
    }

    /// The QR wallets whose details are the plain `WalletQRDetails` shape.
    ///
    /// Fails rather than guessing when the type has no field: sending
    /// `{"type": "…"}` with no details would be rejected by the server anyway,
    /// and failing here says why.
    public init?(type: String, walletQR details: WalletQRDetails) {
        switch type {
        case "truemoney": self.init(methodType: type, truemoney: details)
        case "tng":       self.init(methodType: type, tng: details)
        case "gcash":     self.init(methodType: type, gcash: details)
        case "dana":      self.init(methodType: type, dana: details)
        case "kakaopay":  self.init(methodType: type, kakaopay: details)
        case "tosspay":   self.init(methodType: type, tosspay: details)
        case "naverpay":  self.init(methodType: type, naverpay: details)
        default:          return nil
        }
    }
}

/// Details for the QR wallets that share one shape.
///
/// TrueMoney, Touch 'n Go, GCash, DANA, KakaoPay, Toss and Naver Pay are all
/// documented with the same three fields and a single `qrcode` checkout flow,
/// so they share a type instead of seven identical ones.
///
/// Caveat worth knowing: the confirm **request** reference lists these methods
/// as accepted `payment_method` variants but does not document their object
/// fields. This shape is taken from the **response** schema, where every one of
/// them carries `flow` (enum: qrcode), `os_type` (enum: ios, android) and
/// `is_present`. Treat it as inferred until a live confirm proves it.
public struct WalletQRDetails: Codable {
    public let flow: String
    public let osType: String?
    public let isPresent: Bool

    enum CodingKeys: String, CodingKey {
        case flow
        case osType = "os_type"
        case isPresent = "is_present"
    }

    public init(flow: String = "qrcode", osType: String? = nil, isPresent: Bool = false) {
        self.flow = flow
        self.osType = osType
        self.isPresent = isPresent
    }
}

/// PayNow method details for confirm requests.
///
/// PayNow is Singapore's national bank-transfer QR: the API documents a
/// single checkout flow, `qrcode` (merchant-presented SGQR the customer
/// scans with their banking app).
public struct PayNowDetails: Codable {
    public let flow: String
    public let isPresent: Bool

    enum CodingKeys: String, CodingKey {
        case flow
        case isPresent = "is_present"
    }

    public init(flow: String = "qrcode", isPresent: Bool = false) {
        self.flow = flow
        self.isPresent = isPresent
    }
}

/// GrabPay method details for confirm requests.
///
/// The API documents a single checkout flow, `qrcode` (merchant-presented QR).
/// `shopperName` is optional.
public struct GrabPayDetails: Codable {
    public let flow: String
    public let isPresent: Bool
    public let shopperName: String?

    enum CodingKeys: String, CodingKey {
        case flow
        case isPresent = "is_present"
        case shopperName = "shopper_name"
    }

    public init(flow: String = "qrcode", isPresent: Bool = false, shopperName: String? = nil) {
        self.flow = flow
        self.isPresent = isPresent
        self.shopperName = shopperName
    }
}

/// UnionPay method details for confirm requests.
///
/// `flow` selects the checkout mode: `qrcode` (merchant-presented EMVCo QR)
/// or `securepay`. `osType` is required for the `mobile_app` flow.
public struct UnionPayDetails: Codable {
    public let flow: String
    public let osType: String?
    public let isPresent: Bool

    enum CodingKeys: String, CodingKey {
        case flow
        case osType = "os_type"
        case isPresent = "is_present"
    }

    public init(flow: String = "qrcode", osType: String? = nil, isPresent: Bool = false) {
        self.flow = flow
        self.osType = osType
        self.isPresent = isPresent
    }
}

/// WeChat Pay method details for confirm requests.
///
/// `flow` selects the checkout mode: `qrcode` (merchant-presented QR),
/// `mobile_app`, `mobile_web`, `mini_program`, or `official_account`.
/// `osType` is required for the `mobile_app` and `mobile_web` flows, and
/// `openId` for `mini_program`, `mobile_app`, and `official_account`.
public struct WeChatPayDetails: Codable {
    public let flow: String
    public let osType: String?
    public let isPresent: Bool
    public let openId: String?

    enum CodingKeys: String, CodingKey {
        case flow
        case osType = "os_type"
        case isPresent = "is_present"
        case openId = "open_id"
    }

    public init(flow: String = "qrcode", osType: String? = nil, isPresent: Bool = false, openId: String? = nil) {
        self.flow = flow
        self.osType = osType
        self.isPresent = isPresent
        self.openId = openId
    }
}

public struct ConfirmCardDetails: Codable {
    public let cardName: String
    public let cardNumber: String
    public let expiryMonth: String
    public let expiryYear: String
    public let cvc: String
    public let network: String
    public let billing: BillingDetails
    public let autoCapture: Bool
    public let authorizationType: String
    public let threeDsAction: String
    public let threeDs: ThreeDsRequest?
    
    enum CodingKeys: String, CodingKey {
        case cardName = "card_name"
        case cardNumber = "card_number"
        case expiryMonth = "expiry_month"
        case expiryYear = "expiry_year"
        case cvc, network, billing
        case autoCapture = "auto_capture"
        case authorizationType = "authorization_type"
        case threeDsAction = "three_ds_action"
        case threeDs = "three_ds"
    }
    
    public init(cardName: String, cardNumber: String, expiryMonth: String, expiryYear: String, cvc: String, network: String, billing: BillingDetails, autoCapture: Bool = true, authorizationType: String = "authorization", threeDsAction: String = "enforce_3ds", threeDs: ThreeDsRequest?) {
        self.cardName = cardName
        self.cardNumber = cardNumber
        self.expiryMonth = expiryMonth
        self.expiryYear = expiryYear
        self.cvc = cvc
        self.network = network
        self.billing = billing
        self.autoCapture = autoCapture
        self.authorizationType = authorizationType
        self.threeDsAction = threeDsAction
        self.threeDs = threeDs
    }
}

public struct ThreeDsRequest: Codable {
    public let returnUrl: String
    public let acsResponse: String
    public let deviceDataCollectionRes: String
    public let dsTransactionId: String
    
    enum CodingKeys: String, CodingKey {
        case returnUrl = "return_url"
        case acsResponse = "acs_response"
        case deviceDataCollectionRes = "device_data_collection_res"
        case dsTransactionId = "ds_transaction_id"
    }
    
    public init(returnUrl: String, acsResponse: String = "", deviceDataCollectionRes: String = "", dsTransactionId: String = "") {
        self.returnUrl = returnUrl
        self.acsResponse = acsResponse
        self.deviceDataCollectionRes = deviceDataCollectionRes
        self.dsTransactionId = dsTransactionId
    }
}

public struct BrowserInfo: Codable {
    public let acceptHeader: String
    public let browser: BrowserDetails
    public let deviceId: String
    public let language: String
    /// Customer coordinates. Omitted when nil — never send fabricated
    /// coordinates, they feed risk scoring.
    public let location: LocationInfo?
    public let mobile: MobileInfo
    public let screenColorDepth: Int
    public let screenHeight: Int
    public let screenWidth: Int
    public let timezone: String
    public let touchSupport: Bool?
    public let fonts: [String]?
    public let webglVendor: String?
    public let webglRenderer: String?
    public let hardwareConcurrency: Int?
    public let deviceMemory: Int?

    enum CodingKeys: String, CodingKey {
        case acceptHeader = "accept_header"
        case browser
        case deviceId = "device_id"
        case language, location, mobile
        case screenColorDepth = "screen_color_depth"
        case screenHeight = "screen_height"
        case screenWidth = "screen_width"
        case timezone
        case touchSupport = "touch_support"
        case fonts
        case webglVendor = "webgl_vendor"
        case webglRenderer = "webgl_renderer"
        case hardwareConcurrency = "hardware_concurrency"
        case deviceMemory = "device_memory"
    }

    /// Fields describing the customer's device carry no defaults: this data
    /// feeds 3DS risk scoring, and a fabricated screen size, language, or
    /// timezone poisons it. Callers must pass the device's real values —
    /// optional fields the caller has not measured are omitted, never invented.
    public init(
        acceptHeader: String = "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8",
        browser: BrowserDetails,
        deviceId: String,
        language: String,
        location: LocationInfo? = nil,
        mobile: MobileInfo,
        screenColorDepth: Int = 24,
        screenHeight: Int,
        screenWidth: Int,
        timezone: String,
        touchSupport: Bool? = true,
        fonts: [String]? = nil,
        webglVendor: String? = nil,
        webglRenderer: String? = nil,
        hardwareConcurrency: Int? = nil,
        deviceMemory: Int? = nil
    ) {
        self.acceptHeader = acceptHeader
        self.browser = browser
        self.deviceId = deviceId
        self.language = language
        self.location = location
        self.mobile = mobile
        self.screenColorDepth = screenColorDepth
        self.screenHeight = screenHeight
        self.screenWidth = screenWidth
        self.timezone = timezone
        self.touchSupport = touchSupport
        self.fonts = fonts
        self.webglVendor = webglVendor
        self.webglRenderer = webglRenderer
        self.hardwareConcurrency = hardwareConcurrency
        self.deviceMemory = deviceMemory
    }
}

public struct BrowserDetails: Codable {
    public let javaEnabled: Bool
    public let javascriptEnabled: Bool
    public let userAgent: String
    public let cookieEnabled: Bool?
    public let plugins: [String]?
    public let doNotTrack: Bool?

    enum CodingKeys: String, CodingKey {
        case javaEnabled = "java_enabled"
        case javascriptEnabled = "javascript_enabled"
        case userAgent = "user_agent"
        case cookieEnabled = "cookie_enabled"
        case plugins
        case doNotTrack = "do_not_track"
    }

    /// `userAgent` has no default: it must describe the device actually
    /// paying, never a canned string for some other OS version.
    public init(
        javaEnabled: Bool = false,
        javascriptEnabled: Bool = true,
        userAgent: String,
        cookieEnabled: Bool? = true,
        plugins: [String]? = [],
        doNotTrack: Bool? = false
    ) {
        self.javaEnabled = javaEnabled
        self.javascriptEnabled = javascriptEnabled
        self.userAgent = userAgent
        self.cookieEnabled = cookieEnabled
        self.plugins = plugins
        self.doNotTrack = doNotTrack
    }
}

public struct LocationInfo: Codable {
    public let lat: String
    public let lon: String
    public let accuracy: Int?

    /// Coordinates have no defaults: only construct this from a real
    /// location fix. When there is none, omit `BrowserInfo.location`
    /// entirely — the API rejects lat/lon "0" and fabricated coordinates
    /// poison risk scoring.
    public init(lat: String, lon: String, accuracy: Int? = nil) {
        self.lat = lat
        self.lon = lon
        self.accuracy = accuracy
    }
}

public struct MobileInfo: Codable {
    public let deviceModel: String
    public let osType: String
    public let osVersion: String
    public let carrier: String?

    enum CodingKeys: String, CodingKey {
        case deviceModel = "device_model"
        case osType = "os_type"
        case osVersion = "os_version"
        case carrier
    }

    /// No defaults: the model and OS version must come from the running
    /// device. `osType` is spelled "IOS" — the confirm endpoint rejects
    /// lowercase with a 400. `carrier` is omitted when unknown, never
    /// filled with a placeholder.
    public init(deviceModel: String, osType: String, osVersion: String, carrier: String? = nil) {
        self.deviceModel = deviceModel
        self.osType = osType
        self.osVersion = osVersion
        self.carrier = carrier
    }
}

// MARK: - Alipay Payment Details

public struct AlipayDetails: Codable {
    public let flow: String
    public let osType: String
    public let isPresent: Bool

    enum CodingKeys: String, CodingKey {
        case flow
        case osType = "os_type"
        case isPresent = "is_present"
    }

    public init(flow: String = "app", osType: String = "ios", isPresent: Bool = true) {
        self.flow = flow
        self.osType = osType
        self.isPresent = isPresent
    }
}

// MARK: - Create Payment Intent Request Models

/// Request model for creating a payment intent
public struct CreatePaymentIntentRequest: Codable {
    public let amount: String
    public let currency: String
    public let paymentOrders: PaymentOrders
    public let merchantOrderId: String
    public let description: String
    public let metadata: [String: String]
    public let returnUrl: String

    public enum CodingKeys: String, CodingKey {
        case amount, currency, description, metadata
        case paymentOrders = "payment_orders"
        case merchantOrderId = "merchant_order_id"
        case returnUrl = "return_url"
    }

    /// Initialize a new payment intent request
    /// - Parameters:
    ///   - amount: The payment amount as a string
    ///   - currency: The currency code (e.g., "SGD", "USD")
    ///   - paymentOrders: The order details including products
    ///   - merchantOrderId: Unique merchant order identifier
    ///   - description: Description of the payment
    ///   - metadata: Additional metadata as key-value pairs
    ///   - returnUrl: URL to return to after payment completion
    public init(
        amount: String,
        currency: String,
        paymentOrders: PaymentOrders,
        merchantOrderId: String,
        description: String = "",
        metadata: [String: String] = [:],
        returnUrl: String = "https://checkout.uqpaytech.com/success"
    ) {
        self.amount = amount
        self.currency = currency
        self.paymentOrders = paymentOrders
        self.merchantOrderId = merchantOrderId
        self.description = description
        self.metadata = metadata
        self.returnUrl = returnUrl
    }

    /// Convenience initializer with products array
    /// - Parameters:
    ///   - amount: The payment amount as a string
    ///   - currency: The currency code (e.g., "SGD", "USD")
    ///   - products: Array of products in the order
    ///   - merchantOrderId: Unique merchant order identifier (auto-generated if nil)
    ///   - description: Description of the payment
    ///   - metadata: Additional metadata as key-value pairs
    ///   - returnUrl: URL to return to after payment completion
    public init(
        amount: String,
        currency: String = "SGD",
        products: [Product],
        merchantOrderId: String? = nil,
        description: String = "",
        metadata: [String: String] = [:],
        returnUrl: String = "https://checkout.uqpaytech.com/success"
    ) {
        self.amount = amount
        self.currency = currency
        self.paymentOrders = PaymentOrders(products: products)
        self.merchantOrderId = merchantOrderId ?? "ORDER_\(Int(Date().timeIntervalSince1970 * 1000))"
        self.description = description
        self.metadata = metadata
        self.returnUrl = returnUrl
    }
}

/// Payment order details containing products
public struct PaymentOrders: Codable {
    public let products: [Product]

    public init(products: [Product]) {
        self.products = products
    }
}

/// Product information for payment orders
public struct Product: Codable {
    public let url: String
    public let name: String
    public let price: String
    public let quantity: String

    /// Initialize a product
    /// - Parameters:
    ///   - url: Product image URL
    ///   - name: Product name
    ///   - price: Product price as string
    ///   - quantity: Product quantity as string
    public init(url: String = "", name: String, price: String, quantity: String = "1") {
        self.url = url
        self.name = name
        self.price = price
        self.quantity = quantity
    }
}

// MARK: - Confirm Payment Intent Response (same structure as PaymentIntentCreateResponse)
public typealias ConfirmPaymentIntentResponse = PaymentIntentCreateResponse
