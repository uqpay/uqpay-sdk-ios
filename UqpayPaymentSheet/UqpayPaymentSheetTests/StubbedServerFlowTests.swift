//
//  StubbedServerFlowTests.swift
//  UqpayPaymentSheetTests
//
//  T3 coverage: the confirm → poll → outcome pipeline against a stubbed
//  transport. No packet leaves the process; every response is scripted, so
//  the full decode → status → mapping chain is exercised the way the live
//  sandbox exercises it — without charging real money.
//

import XCTest
@testable import UqpayPaymentSheet
import UqpayCore

// MARK: - Stubbed transport

/// Serves scripted responses by URL-path suffix, FIFO per suffix.
final class StubURLProtocol: URLProtocol {

    struct Scripted {
        let status: Int
        let body: String
    }

    private static let lock = NSLock()
    private static var script: [(suffix: String, responses: [Scripted])] = []
    private(set) static var requestLog: [URLRequest] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        script = []
        requestLog = []
    }

    /// Queue `responses` for requests whose path ends in `suffix`.
    static func serve(_ suffix: String, _ responses: Scripted...) {
        lock.lock(); defer { lock.unlock() }
        script.append((suffix, responses))
    }

    private static func nextResponse(for request: URLRequest) -> Scripted? {
        lock.lock(); defer { lock.unlock() }
        requestLog.append(request)
        guard let path = request.url?.path else { return nil }
        for index in script.indices where path.hasSuffix(script[index].suffix) {
            guard !script[index].responses.isEmpty else { continue }
            // Keep the last response replaying so long polls stay scripted.
            return script[index].responses.count == 1
                ? script[index].responses[0]
                : script[index].responses.removeFirst()
        }
        return nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let scripted = Self.nextResponse(for: request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: scripted.status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(scripted.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Tests

final class StubbedServerFlowTests: XCTestCase {

    private var apiClient: ApiClient!
    private var savedToken: String?
    private var savedClientId: String?
    private var savedIntentId: String?
    private var savedEnvironment: UqpayEnvironment?

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        apiClient = ApiClient(
            urlSession: URLSession(configuration: configuration),
            environment: .sandboxMode
        )

        let shared = UqpayConfiguration.shared
        savedToken = shared.headerToken
        savedClientId = shared.clientId
        savedIntentId = shared.paymentIntentId
        savedEnvironment = shared.environment
        shared.headerToken = "test-token"
        shared.clientId = "test-client"
        shared.paymentIntentId = "pi_stubbed"
        shared.environment = .sandboxMode
    }

    override func tearDown() {
        let shared = UqpayConfiguration.shared
        shared.headerToken = savedToken
        shared.clientId = savedClientId
        shared.paymentIntentId = savedIntentId
        shared.environment = savedEnvironment
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func intentJSON(
        status: String,
        methods: [String] = ["card", "grabpay"],
        nextActionType: String? = nil,
        failureCode: String? = nil
    ) -> String {
        var fields = [
            "\"payment_intent_id\": \"pi_stubbed\"",
            "\"intent_status\": \"\(status)\"",
            "\"amount\": \"8.98\"",
            "\"currency\": \"SGD\"",
            "\"available_payment_method_types\": [\(methods.map { "\"\($0)\"" }.joined(separator: ", "))]",
        ]
        if let nextActionType {
            fields.append("\"next_action\": {\"type\": \"\(nextActionType)\"}")
        }
        if let failureCode {
            fields.append("\"latest_payment_attempt\": {\"attempt_status\": \"FAILED\", \"failure_code\": \"\(failureCode)\"}")
        }
        return "{\(fields.joined(separator: ", "))}"
    }

    // MARK: getPaymentMethods

    func testPayableIntentYieldsItsMethodList() async throws {
        StubURLProtocol.serve(
            "/payment_intents/pi_stubbed",
            .init(status: 200, body: intentJSON(status: "REQUIRES_PAYMENT_METHOD"))
        )
        let methods = try await apiClient.getPaymentMethods()
        XCTAssertEqual(methods.map(\.id), ["card", "grabpay"],
                       "The API's list and ordering are preserved")
    }

    func testSettledIntentRefusesToPresent() async {
        StubURLProtocol.serve(
            "/payment_intents/pi_stubbed",
            .init(status: 200, body: intentJSON(status: "SUCCEEDED"))
        )
        do {
            _ = try await apiClient.getPaymentMethods()
            XCTFail("A SUCCEEDED intent must refuse presentation")
        } catch let error as PaymentSheetError {
            XCTAssertEqual(error, .intentNotPayable(status: .succeeded))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: Poll → outcome

    func testPollResolvesWhenTheIntentSettles() async throws {
        StubURLProtocol.serve(
            "/payment_intents/pi_stubbed",
            .init(status: 200, body: intentJSON(status: "PENDING")),
            .init(status: 200, body: intentJSON(status: "PENDING")),
            .init(status: 200, body: intentJSON(status: "SUCCEEDED"))
        )
        let intent = try await apiClient.awaitThreeDSOutcome(
            paymentIntentId: "pi_stubbed",
            excludingActionType: nil,
            timeout: 5,
            pollInterval: 0.01
        )
        XCTAssertEqual(intent.intentStatus, .succeeded)
        XCTAssertGreaterThanOrEqual(StubURLProtocol.requestLog.count, 3,
                                    "The first two PENDING reads must not end the poll")
    }

    func testFailedThreeDSReturnsImmediatelyWithTheFailureCode() async throws {
        StubURLProtocol.serve(
            "/payment_intents/pi_stubbed",
            .init(status: 200, body: intentJSON(status: "REQUIRES_PAYMENT_METHOD", failureCode: "3ds_failed"))
        )
        let intent = try await apiClient.awaitThreeDSOutcome(
            paymentIntentId: "pi_stubbed",
            excludingActionType: "redirect_to_url",
            timeout: 5,
            pollInterval: 0.01
        )
        XCTAssertEqual(intent.intentStatus, .requiresPaymentMethod)
        // The full merchant-facing chain: this response maps to .threeDSFailed
        // on every screen (card, wallet QR, raw QR route through one table).
        XCTAssertEqual(
            PaymentCardViewController.errorCode(
                forFailureCode: intent.latestPaymentAttempt?.failureCode,
                intentStatus: intent.intentStatus
            ),
            .threeDSFailed
        )
    }

    func testNewCustomerActionEndsThePollAsAFurtherStep() async throws {
        StubURLProtocol.serve(
            "/payment_intents/pi_stubbed",
            .init(status: 200, body: intentJSON(status: "REQUIRES_CUSTOMER_ACTION", nextActionType: "redirect_to_url"))
        )
        let intent = try await apiClient.awaitThreeDSOutcome(
            paymentIntentId: "pi_stubbed",
            excludingActionType: "device_fingerprint",
            timeout: 5,
            pollInterval: 0.01
        )
        XCTAssertEqual(intent.nextAction?.type, "redirect_to_url",
                       "A different action type is a new step, not the one already shown")
    }

    // MARK: Confirm rejections

    func testDefinitiveConfirmRejectionSurfacesTheAPICode() async {
        StubURLProtocol.serve(
            "/payment_intents/pi_stubbed/confirm",
            .init(status: 402, body: #"{"code": "insufficient_funds", "type": "card_error", "message": "Insufficient funds."}"#)
        )
        do {
            _ = try await apiClient.confirmPaymentIntent(
                paymentIntentId: "pi_stubbed",
                encodedBody: Data("{}".utf8),
                idempotencyKey: UqpayIdempotencyKey()
            )
            XCTFail("A 402 must throw")
        } catch let error as UqpayAPIError {
            XCTAssertEqual(error.apiCode, "insufficient_funds")
            XCTAssertEqual(PaymentCardViewController.errorCode(for: error), .insufficientFunds,
                           "The merchant sees .insufficientFunds for this server answer")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testConfirmSendsTheIdempotencyKeyHeader() async {
        StubURLProtocol.serve(
            "/payment_intents/pi_stubbed/confirm",
            .init(status: 400, body: #"{"code": "invalid_payment_method", "type": "invalid_request_error", "message": ""}"#)
        )
        let key = UqpayIdempotencyKey()
        _ = try? await apiClient.confirmPaymentIntent(
            paymentIntentId: "pi_stubbed",
            encodedBody: Data("{}".utf8),
            idempotencyKey: key
        )
        let sent = StubURLProtocol.requestLog.compactMap { $0.value(forHTTPHeaderField: "x-idempotency-key") }
        XCTAssertEqual(sent, [key.value],
                       "Exactly one confirm, carrying exactly the caller's key")
    }
}
