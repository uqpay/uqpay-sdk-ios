import Foundation
import UqpayCore

/// Every value you need to change to run this example.
///
/// Get credentials from the sandbox dashboard at https://app-sandbox.uqpaytech.com
/// under Developer → API Keys. The API key is shown only once when you create it.
enum DemoConfiguration {

    /// Sandbox uses test cards and moves no real money. Leave this as `.sandbox`.
    static let environment: UqpayAPIEnvironment = .sandbox

    /// Credentials load from `Demo/DemoSecrets.plist`, which is git-ignored so
    /// real keys can never enter version control. To set yours up, copy
    /// `DemoSecrets.example.plist` to `DemoSecrets.plist` next to it and fill
    /// in both values.
    private static let secrets: [String: String] = {
        guard let url = Bundle.main.url(forResource: "DemoSecrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return [:] }
        return plist
    }()

    /// Your `x-client-id`.
    static var clientID: String { secrets["ClientID"] ?? "PASTE_YOUR_SANDBOX_CLIENT_ID_HERE" }

    /// Your `x-api-key`.
    ///
    /// - Warning: Present only so this example runs without a server. A real app
    ///   must never contain this key — see ``DemoMerchantBackend``.
    static var apiKey: String { secrets["APIKey"] ?? "PASTE_YOUR_SANDBOX_API_KEY_HERE" }

    /// URL scheme the issuer's 3DS page returns to. Must match the scheme
    /// registered under CFBundleURLTypes in Info.plist.
    static let returnURLScheme = "uqpayswiftui://payment"

    /// Currency for demo payments.
    static let currency = "SGD"

    /// True once both credentials have been filled in.
    static var isConfigured: Bool {
        !clientID.hasPrefix("PASTE_") && !apiKey.hasPrefix("PASTE_")
    }

    /// Shown in the UI when credentials are still placeholders.
    static let setupInstructions = """
        Copy Demo/DemoSecrets.example.plist to Demo/DemoSecrets.plist and fill in \
        ClientID and APIKey with your sandbox credentials from \
        app-sandbox.uqpaytech.com → Developer → API Keys.
        """
}
