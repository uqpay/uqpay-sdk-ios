import Foundation
import UqpayCore

/// Every value you need to change to run this example.
///
/// Get sandbox credentials from https://app-sandbox.uqpaytech.com and
/// production credentials from https://app.uqpaytech.com, both under
/// Developer → API Keys. The API key is shown only once when you create it.
enum DemoConfiguration {

    /// Credentials load from `Demo/DemoSecrets.plist`, which is git-ignored so
    /// real keys can never enter version control. To set yours up, copy
    /// `DemoSecrets.example.plist` to `DemoSecrets.plist` next to it and fill
    /// in the pair for each environment you want to exercise:
    ///
    /// | Environment | Keys                                      |
    /// |-------------|-------------------------------------------|
    /// | Sandbox     | `ClientID` / `APIKey`                     |
    /// | Production  | `ProductionClientID` / `ProductionAPIKey` |
    ///
    /// Environments with no pair stay unconfigured and the app tells you so
    /// instead of quietly running against a different backend.
    private static let secrets: [String: String] = {
        guard let url = Bundle.main.url(forResource: "DemoSecrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return [:] }
        return plist
    }()

    private static func secretKeyPrefix(for environment: UqpayEnvironment) -> String {
        switch environment {
        case .sandboxMode: return ""            // Sandbox keeps the original key names.
        case .productionMode: return "Production"
        }
    }

    /// Your `x-client-id` for the environment.
    static func clientID(for environment: UqpayEnvironment) -> String {
        secrets["\(secretKeyPrefix(for: environment))ClientID"] ?? "PASTE_YOUR_CLIENT_ID_HERE"
    }

    /// Your `x-api-key` for the environment.
    ///
    /// - Warning: Present only so this example runs without a server. A real app
    ///   must never contain this key — see ``DemoMerchantBackend``.
    static func apiKey(for environment: UqpayEnvironment) -> String {
        secrets["\(secretKeyPrefix(for: environment))APIKey"] ?? "PASTE_YOUR_API_KEY_HERE"
    }

    /// True once both credentials for the environment have been filled in.
    static func isConfigured(for environment: UqpayEnvironment) -> Bool {
        !clientID(for: environment).hasPrefix("PASTE_") && !apiKey(for: environment).hasPrefix("PASTE_")
    }

    /// The `UqpayHTTPClient` environment matching the selected SDK environment.
    static func apiEnvironment(for environment: UqpayEnvironment) -> UqpayAPIEnvironment {
        switch environment {
        case .sandboxMode: return .sandbox
        case .productionMode: return .production
        }
    }

    /// Shown when the selected environment has no credentials yet.
    static func setupInstructions(for environment: UqpayEnvironment) -> String {
        let prefix = secretKeyPrefix(for: environment)
        let dashboard = environment == .productionMode
            ? "app.uqpaytech.com" : "app-sandbox.uqpaytech.com"
        let warning = environment == .productionMode
            ? " Production moves real money." : ""
        return """
            \(environment.displayName) is not configured. Add \(prefix)ClientID and \
            \(prefix)APIKey to Demo/DemoSecrets.plist with credentials from \
            \(dashboard) → Developer → API Keys.\(warning)
            """
    }

    /// Must match a scheme in CFBundleURLTypes in Info.plist, or iOS will never
    /// deliver the 3DS callback and the payment will appear to hang.
    static let returnURLScheme = "uqpayexample://payment"

    /// Currency for demo payments.
    static let currency = "SGD"

    /// Amount used by the demo buttons. In a real app this comes from the cart,
    /// and your backend recalculates it rather than trusting the app.
    static let demoAmount: Decimal = 8.98
}
