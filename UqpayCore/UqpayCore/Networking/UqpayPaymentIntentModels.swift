import Foundation

/// Lifecycle state of a payment intent.
///
/// Unrecognised values decode to ``unknown(_:)`` so a new server-side status
/// cannot break an already-shipped app.
public enum UqpayPaymentIntentStatus: RawRepresentable, Decodable, Equatable {

    case requiresPaymentMethod
    case requiresCustomerAction
    case requiresCapture
    case pending
    case succeeded
    case cancelled
    case failed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "REQUIRES_PAYMENT_METHOD": self = .requiresPaymentMethod
        case "REQUIRES_CUSTOMER_ACTION": self = .requiresCustomerAction
        case "REQUIRES_CAPTURE": self = .requiresCapture
        case "PENDING": self = .pending
        case "SUCCEEDED": self = .succeeded
        case "CANCELLED": self = .cancelled
        case "FAILED": self = .failed
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .requiresPaymentMethod: return "REQUIRES_PAYMENT_METHOD"
        case .requiresCustomerAction: return "REQUIRES_CUSTOMER_ACTION"
        case .requiresCapture: return "REQUIRES_CAPTURE"
        case .pending: return "PENDING"
        case .succeeded: return "SUCCEEDED"
        case .cancelled: return "CANCELLED"
        case .failed: return "FAILED"
        case .unknown(let raw): return raw
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    /// Whether the payment has reached a state that will not change on its own.
    public var isTerminal: Bool {
        switch self {
        case .succeeded, .cancelled, .failed: return true
        default: return false
        }
    }

    /// Whether the customer must do something, such as complete 3DS.
    public var needsCustomerAction: Bool {
        self == .requiresCustomerAction
    }
}

/// Lifecycle state of a single payment attempt against an intent.
public enum UqpayPaymentAttemptStatus: RawRepresentable, Decodable, Equatable {

    case initiated
    case authenticationRedirected
    case pendingAuthorization
    case authorized
    case captureRequested
    case settled
    case succeeded
    case cancelled
    case expired
    case failed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "INITIATED": self = .initiated
        case "AUTHENTICATION_REDIRECTED": self = .authenticationRedirected
        case "PENDING_AUTHORIZATION": self = .pendingAuthorization
        case "AUTHORIZED": self = .authorized
        case "CAPTURE_REQUESTED": self = .captureRequested
        case "SETTLED": self = .settled
        case "SUCCEEDED": self = .succeeded
        case "CANCELLED": self = .cancelled
        case "EXPIRED": self = .expired
        case "FAILED": self = .failed
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .initiated: return "INITIATED"
        case .authenticationRedirected: return "AUTHENTICATION_REDIRECTED"
        case .pendingAuthorization: return "PENDING_AUTHORIZATION"
        case .authorized: return "AUTHORIZED"
        case .captureRequested: return "CAPTURE_REQUESTED"
        case .settled: return "SETTLED"
        case .succeeded: return "SUCCEEDED"
        case .cancelled: return "CANCELLED"
        case .expired: return "EXPIRED"
        case .failed: return "FAILED"
        case .unknown(let raw): return raw
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
}

/// What the customer must do next, present when the intent requires action.
public struct UqpayNextAction: Decodable, Equatable {

    /// Redirect the customer to this URL, used by 3DS challenges and wallets.
    public struct RedirectToURL: Decodable, Equatable {
        public let url: String?
        public let returnUrl: String?
    }

    /// An HTML form that must be submitted, used by 3DS device fingerprinting.
    ///
    /// The markup contains a `method="POST"` form targeting the issuer's ACS.
    /// It must be loaded as HTML and allowed to submit itself — rewriting it as
    /// a `GET` navigation drops the POST body and the authentication fails.
    public struct RedirectIframe: Decodable, Equatable {
        public let iframe: String?
    }

    /// A QR code the customer scans in a wallet app.
    public struct DisplayQRCode: Decodable, Equatable {
        public let qrCodeUrl: String?
    }

    public let type: String?
    public let redirectToUrl: RedirectToURL?
    public let redirectIframe: RedirectIframe?
    public let displayQrCode: DisplayQRCode?
}

/// Result data attached to a payment attempt.
public struct UqpayAuthenticationData: Decodable, Equatable {

    public struct ThreeDS: Decodable, Equatable {
        public let threeDsVersion: String?
        public let cavv: String?
        public let eci: String?
        public let dsTransactionId: String?
        public let threeDsAuthenticationStatus: String?
        public let threeDsCancellationReason: String?
    }

    public let cvvResult: String?
    public let avsResult: String?
    public let threeDs: ThreeDS?
}

/// One attempt to pay a payment intent.
///
/// An intent may have several attempts; a single failed attempt does not mean
/// the intent has failed.
public struct UqpayPaymentAttempt: Decodable, Equatable {

    /// Attempt identifier.
    ///
    /// The API returns this as `attempt_id` when nested under a payment intent
    /// and as `payment_attempt_id` in webhook payloads. Both are accepted.
    public let attemptId: String?

    public let paymentIntentId: String?
    public let attemptStatus: UqpayPaymentAttemptStatus?
    public let amount: String?
    public let currency: String?
    public let capturedAmount: String?
    public let refundedAmount: String?
    public let authCode: String?
    public let arn: String?
    public let rrn: String?
    public let adviceCode: String?
    public let failureCode: String?
    public let failureMessage: String?
    public let authenticationData: UqpayAuthenticationData?
    public let createTime: String?
    public let updateTime: String?
    public let completeTime: String?

    private enum CodingKeys: String, CodingKey {
        case attemptId, paymentAttemptId, paymentIntentId, attemptStatus, amount, currency
        case capturedAmount, refundedAmount, authCode, arn, rrn, adviceCode
        case failureCode, failureMessage, authenticationData
        case createTime, updateTime, completeTime
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attemptId = try c.decodeIfPresent(String.self, forKey: .attemptId)
            ?? c.decodeIfPresent(String.self, forKey: .paymentAttemptId)
        paymentIntentId = try c.decodeIfPresent(String.self, forKey: .paymentIntentId)
        attemptStatus = try c.decodeIfPresent(UqpayPaymentAttemptStatus.self, forKey: .attemptStatus)
        amount = try c.decodeIfPresent(String.self, forKey: .amount)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        capturedAmount = try c.decodeIfPresent(String.self, forKey: .capturedAmount)
        refundedAmount = try c.decodeIfPresent(String.self, forKey: .refundedAmount)
        authCode = try c.decodeIfPresent(String.self, forKey: .authCode)
        arn = try c.decodeIfPresent(String.self, forKey: .arn)
        rrn = try c.decodeIfPresent(String.self, forKey: .rrn)
        adviceCode = try c.decodeIfPresent(String.self, forKey: .adviceCode)
        failureCode = try c.decodeIfPresent(String.self, forKey: .failureCode)
        failureMessage = try c.decodeIfPresent(String.self, forKey: .failureMessage)
        authenticationData = try c.decodeIfPresent(UqpayAuthenticationData.self, forKey: .authenticationData)
        createTime = try c.decodeIfPresent(String.self, forKey: .createTime)
        updateTime = try c.decodeIfPresent(String.self, forKey: .updateTime)
        completeTime = try c.decodeIfPresent(String.self, forKey: .completeTime)
    }
}

/// A payment intent: the record of an amount a customer intends to pay.
///
/// Amounts are decimal strings such as `"8.98"`, in major units. They are not
/// minor units — do not divide by 100.
public struct UqpayPaymentIntent: Decodable, Equatable {

    public let paymentIntentId: String
    public let intentStatus: UqpayPaymentIntentStatus
    public let amount: String?
    public let currency: String?
    public let capturedAmount: String?
    public let merchantOrderId: String?
    public let description: String?
    public let customerId: String?
    public let clientSecret: String?
    public let returnUrl: String?
    public let cancellationReason: String?
    public let availablePaymentMethodTypes: [String]?
    public let nextAction: UqpayNextAction?
    public let latestPaymentAttempt: UqpayPaymentAttempt?
    public let createTime: String?
    public let updateTime: String?
    public let completeTime: String?
    public let cancelTime: String?

    /// ``amount`` parsed for arithmetic. `nil` when absent or malformed.
    public var amountDecimal: Decimal? {
        guard let amount else { return nil }
        return Decimal(string: amount)
    }

    /// ``capturedAmount`` parsed for arithmetic.
    public var capturedAmountDecimal: Decimal? {
        guard let capturedAmount else { return nil }
        return Decimal(string: capturedAmount)
    }
}
