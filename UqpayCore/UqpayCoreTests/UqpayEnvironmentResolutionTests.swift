import XCTest
@testable import UqpayCore

/// Locks in the environment-resolution rules established when the silent
/// test-environment fallbacks were removed:
///
/// 1. The hosts match the developer docs (go-live checklist): sandbox is
///    `api-sandbox.uqpaytech.com`, production is `api.uqpay.com`.
/// 2. An unconfigured SDK fails loudly with `environmentNotSet` — it never
///    silently talks to a test server.
/// 3. Every client built from the global configuration resolves to exactly
///    the environment the merchant set.
final class UqpayEnvironmentResolutionTests: XCTestCase {

    private var savedEnvironment: UqpayEnvironment?
    private var savedClientSecret: String?
    private var savedClientId: String?

    override func setUp() {
        super.setUp()
        // The configuration is a process-wide singleton; snapshot it so these
        // tests cannot leak state into other suites.
        savedEnvironment = UqpayConfiguration.shared.environment
        savedClientSecret = UqpayConfiguration.shared.clientSecret
        savedClientId = UqpayConfiguration.shared.clientId
        UqpayConfiguration.shared.reset()
    }

    override func tearDown() {
        UqpayConfiguration.shared.reset()
        UqpayConfiguration.shared.environment = savedEnvironment
        UqpayConfiguration.shared.clientSecret = savedClientSecret
        UqpayConfiguration.shared.clientId = savedClientId
        super.tearDown()
    }

    // MARK: - Hosts match the documentation

    func testSandboxHostMatchesDocs() {
        XCTAssertEqual(UqpayEnvironment.sandboxMode.baseURL.host, "api-sandbox.uqpaytech.com")
        XCTAssertEqual(UqpayEnvironment.sandboxMode.authBaseURL.host, "api-sandbox.uqpaytech.com")
    }

    /// Regression: production once pointed at `api.uqpaytech.com`, which is not
    /// the documented production host and would have broken every live payment.
    func testProductionHostMatchesDocs() {
        XCTAssertEqual(UqpayEnvironment.productionMode.baseURL.host, "api.uqpay.com")
        XCTAssertEqual(UqpayEnvironment.productionMode.authBaseURL.host, "api.uqpay.com")
    }

    /// The SDK carries two environment types (`UqpayEnvironment` and the newer
    /// `UqpayAPIEnvironment`); they must never disagree about a host again.
    func testBothEnvironmentTypesAgreeOnHosts() {
        XCTAssertEqual(UqpayEnvironment.sandboxMode.baseURL.host,
                       UqpayAPIEnvironment.sandbox.baseURL.host)
        XCTAssertEqual(UqpayEnvironment.productionMode.baseURL.host,
                       UqpayAPIEnvironment.production.baseURL.host)
    }

    func testAuthTokenURLComposition() {
        XCTAssertEqual(UqpayEnvironment.sandboxMode.authTokenURL.absoluteString,
                       "https://api-sandbox.uqpaytech.com/api/v1/connect/token")
        XCTAssertEqual(UqpayEnvironment.productionMode.authTokenURL.absoluteString,
                       "https://api.uqpay.com/api/v1/connect/token")
    }

    func testOnlySandboxIsATestEnvironment() {
        XCTAssertTrue(UqpayEnvironment.sandboxMode.isTestEnvironment)
        XCTAssertFalse(UqpayEnvironment.productionMode.isTestEnvironment)
    }

    /// Regression: internal test/staging hosts once shipped in the enum, so
    /// every release binary carried them and they were runtime-selectable.
    /// The public SDK exposes exactly the two merchant environments.
    func testOnlyMerchantEnvironmentsExist() {
        XCTAssertEqual(Set(UqpayEnvironment.allCases.map(\.rawValue)),
                       ["sandbox", "production"])
    }

    // MARK: - Unconfigured SDK fails loudly

    /// Regression: the getter used to invent `.testingMode` when nothing was
    /// set, so a merchant who forgot one line silently hit a test server.
    func testUnsetEnvironmentIsNilNotATestDefault() {
        XCTAssertNil(UqpayConfiguration.shared.environment)
    }

    func testRequireEnvironmentThrowsWhenUnset() {
        XCTAssertThrowsError(try UqpayConfiguration.shared.requireEnvironment()) { error in
            XCTAssertEqual(error as? UqpayConfigurationError, .environmentNotSet)
        }
    }

    func testForConfiguredEnvironmentThrowsWhenUnset() {
        XCTAssertThrowsError(try ApiClient.forConfiguredEnvironment()) { error in
            XCTAssertEqual(error as? UqpayConfigurationError, .environmentNotSet)
        }
    }

    // MARK: - Configured SDK resolves to exactly what was set

    func testConfiguredEnvironmentResolves() throws {
        for environment in UqpayEnvironment.allCases {
            UqpayConfiguration.shared.environment = environment
            XCTAssertEqual(try UqpayConfiguration.shared.requireEnvironment(), environment)
            XCTAssertEqual(try ApiClient.forConfiguredEnvironment().currentEnvironment, environment)
        }
    }

    func testForEnvironmentClientCarriesItsEnvironment() {
        XCTAssertEqual(ApiClient.forEnvironment(.sandboxMode).currentEnvironment, .sandboxMode)
        XCTAssertEqual(ApiClient.forEnvironment(.productionMode).currentEnvironment, .productionMode)
    }

    func testConfigureSetsEnvironmentExplicitly() throws {
        try UqpayConfiguration.shared.configure(
            clientSecret: "sk_test_0123456789",
            environment: .sandboxMode
        )
        XCTAssertEqual(UqpayConfiguration.shared.environment, .sandboxMode)
    }
}
