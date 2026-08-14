import Foundation

/// The UQPAY API environment a client targets.
public enum UqpayAPIEnvironment: Equatable {

    /// Sandbox: test credentials, test cards, no real money.
    case sandbox

    /// Production: live credentials and real money.
    case production

    /// An explicit host, for internal environments not covered above.
    case custom(URL)

    /// Root URL for the environment, without a trailing slash.
    public var baseURL: URL {
        switch self {
        case .sandbox:
            return URL(string: "https://api-sandbox.uqpaytech.com")!
        case .production:
            return URL(string: "https://api.uqpay.com")!
        case .custom(let url):
            return url
        }
    }

    /// Whether this environment moves real money.
    public var isLive: Bool {
        if case .production = self { return true }
        return false
    }
}
