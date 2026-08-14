//
//  UqpayPaymentSheetTests.swift
//  UqpayPaymentSheetTests
//
//  Created by UQPAY on 14/08/2025.
//

import XCTest
import UIKit
@testable import UqpayCore
@testable import UqpayPayments
@testable import UqpayPaymentSheet

/// Locks down the rule that decides whether a failed confirm may be reported
/// as a failure and whether its idempotency key may be released.
///
/// Getting this wrong in either direction is a money bug. Treating an unknown
/// outcome as a failure releases the key, so the customer's retry is charged a
/// second time; treating a definitive decline as unknown pins a stale key onto
/// a genuinely new payment. Both have shipped here before, which is why every
/// branch is pinned.
@MainActor
final class ConfirmOutcomeClassificationTests: XCTestCase {

    // MARK: - Outcome unknown: the payment may have been processed

    func testTransportFailuresAreUnknown() {
        XCTAssertTrue(ConfirmIdempotency.isOutcomeUnknown(URLError(.timedOut)))
        XCTAssertTrue(ConfirmIdempotency.isOutcomeUnknown(URLError(.networkConnectionLost)))
        XCTAssertTrue(ConfirmIdempotency.isOutcomeUnknown(URLError(.notConnectedToInternet)))
        XCTAssertTrue(ConfirmIdempotency.isOutcomeUnknown(URLError(.badServerResponse)))
        XCTAssertTrue(ConfirmIdempotency.isOutcomeUnknown(UqpayAPIError.timedOut))
        XCTAssertTrue(ConfirmIdempotency.isOutcomeUnknown(
            UqpayAPIError.transport(underlying: URLError(.cannotConnectToHost))
        ))
    }

    /// A 2xx that cannot be decoded means the server DID process the payment.
    func testUndecodableSuccessIsUnknown() {
        let decodingError = DecodingError.keyNotFound(
            AnyKey(stringValue: "intent_status")!,
            DecodingError.Context(codingPath: [], debugDescription: "missing")
        )
        XCTAssertTrue(ConfirmIdempotency.isOutcomeUnknown(decodingError))
        XCTAssertTrue(ConfirmIdempotency.isOutcomeUnknown(
            UqpayAPIError.decoding(underlying: decodingError)
        ))
    }

    /// Regression: these once arrived as `PaymentSheetError` and released the
    /// key, so a 504 after the acquirer authorized led to a double charge.
    func testRetryableServerStatusesAreUnknown() {
        for status in [429, 500, 502, 503, 504] {
            XCTAssertTrue(
                ConfirmIdempotency.isOutcomeUnknown(
                    UqpayAPIError.unexpectedStatus(status: status, responseBody: nil)
                ),
                "status \(status) must be treated as an unknown outcome"
            )
            XCTAssertTrue(
                ConfirmIdempotency.isOutcomeUnknown(
                    UqpayAPIError.api(status: status, body: Self.errorBody)
                ),
                "status \(status) must be treated as an unknown outcome"
            )
        }
    }

    // MARK: - Outcome known: the server answered definitively

    func testClientErrorsAreDefinitive() {
        for status in [400, 401, 402, 403, 404, 422] {
            XCTAssertFalse(
                ConfirmIdempotency.isOutcomeUnknown(
                    UqpayAPIError.api(status: status, body: Self.errorBody)
                ),
                "status \(status) is a definitive rejection"
            )
        }
    }

    func testDefinitiveSheetErrorsAreKnown() {
        XCTAssertFalse(ConfirmIdempotency.isOutcomeUnknown(PaymentSheetError.failed("Card declined")))
        XCTAssertFalse(ConfirmIdempotency.isOutcomeUnknown(PaymentSheetError.canceled))
        XCTAssertFalse(ConfirmIdempotency.isOutcomeUnknown(PaymentSheetError.notReady))
        XCTAssertFalse(ConfirmIdempotency.isOutcomeUnknown(UqpayAPIError.notConfigured("no client id")))
    }

    /// The classifier must not treat an unrecognised error as unknown: pinning
    /// a key onto an error we do not understand risks replaying a stale
    /// payment. Definitive is the safe default here because the retry then
    /// carries a fresh key for what the SDK believes is a new attempt.
    func testUnrecognisedErrorsAreTreatedAsDefinitive() {
        struct SomeOtherError: Error {}
        XCTAssertFalse(ConfirmIdempotency.isOutcomeUnknown(SomeOtherError()))
    }

    /// Cancellation is neither outcome: the cancelled task reports nothing,
    /// and unknown-outcome handling must not run for it.
    func testCancellationIsNotAnUnknownOutcome() {
        XCTAssertFalse(ConfirmIdempotency.isOutcomeUnknown(CancellationError()))
        XCTAssertFalse(ConfirmIdempotency.isOutcomeUnknown(URLError(.cancelled)))
    }

    private static let errorBody = UqpayAPIErrorBody(
        code: "invalid_payment_method",
        type: "invalid_request_error",
        message: "language is invalid"
    )

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

/// The attempt bookkeeping around that rule: which failures keep an attempt
/// pinned for a same-key replay, and which end it.
@MainActor
final class ConfirmIdempotencyTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ConfirmIdempotency._removeAllForTesting()
    }

    func testSamePayloadReusesTheKeyWhileUnresolved() {
        let idempotency = ConfirmIdempotency(store: InMemoryConfirmAttemptStore())
        let first = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        let second = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        XCTAssertEqual(first.key.value, second.key.value)
    }

    /// The frozen device values must come back unchanged too: a retry whose
    /// body differs is rejected by an idempotent server.
    func testReusedAttemptKeepsItsDeviceSnapshot() {
        let idempotency = ConfirmIdempotency(store: InMemoryConfirmAttemptStore())
        let first = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        let second = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        XCTAssertEqual(first.browserInfo.deviceId, second.browserInfo.deviceId)
        XCTAssertEqual(first.browserInfo.screenWidth, second.browserInfo.screenWidth)
        XCTAssertEqual(first.browserInfo.screenHeight, second.browserInfo.screenHeight)
        XCTAssertEqual(first.ipAddress, second.ipAddress)
    }

    /// Regression: the pin used to live on the screen instance, so backing
    /// out and re-entering minted a fresh key for a payment that may already
    /// be processing. The pin belongs to the payment.
    func testPinSurvivesAcrossInstances() {
        let first = ConfirmIdempotency(store: InMemoryConfirmAttemptStore()).attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        let second = ConfirmIdempotency(store: InMemoryConfirmAttemptStore()).attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        XCTAssertEqual(first.key.value, second.key.value)
    }

    func testEditedPayloadGetsAFreshKey() {
        let idempotency = ConfirmIdempotency(store: InMemoryConfirmAttemptStore())
        let first = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        let second = idempotency.attempt(forPayloadDigest: "payload-b", paymentIntentId: "pi_test")
        XCTAssertNotEqual(first.key.value, second.key.value)
    }

    func testResolvedAttemptGetsAFreshKey() {
        let idempotency = ConfirmIdempotency(store: InMemoryConfirmAttemptStore())
        let first = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        idempotency.resolve(first)
        let second = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        XCTAssertNotEqual(first.key.value, second.key.value)
    }

    /// Regression: a stale task finishing late used to clear whatever pin was
    /// current. Resolution is now identity-checked — an old attempt cannot
    /// un-pin the newer attempt that superseded it.
    func testStaleResolveCannotUnpinANewerAttempt() {
        let idempotency = ConfirmIdempotency(store: InMemoryConfirmAttemptStore())
        let old = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        idempotency.resolve(old)
        let newer = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        idempotency.resolve(old) // stale task finishing late
        let retry = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        XCTAssertEqual(newer.key.value, retry.key.value,
                       "a stale resolve must not clear the newer attempt's pin")
    }

    func testUnknownOutcomeKeepsTheKeyForRetry() {
        for error: Error in [URLError(.timedOut),
                             UqpayAPIError.unexpectedStatus(status: 503, responseBody: nil)] {
            ConfirmIdempotency._removeAllForTesting()
            let idempotency = ConfirmIdempotency(store: InMemoryConfirmAttemptStore())
            let first = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
            idempotency.handle(error, for: first)
            let retry = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
            XCTAssertEqual(first.key.value, retry.key.value,
                           "an unknown outcome must retry under the same key")
        }
    }

    func testDefinitiveFailureEndsTheAttempt() {
        let idempotency = ConfirmIdempotency(store: InMemoryConfirmAttemptStore())
        let first = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        idempotency.handle(PaymentSheetError.failed("Card declined"), for: first)
        let next = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        XCTAssertNotEqual(first.key.value, next.key.value,
                          "a declined card is a finished attempt; retrying is a new payment")
    }

    /// A cancelled send reports nothing and must leave the pin exactly as it
    /// was — the outcome is unknown, and the next Pay replays it.
    func testCancellationLeavesThePinAlone() {
        let idempotency = ConfirmIdempotency(store: InMemoryConfirmAttemptStore())
        let first = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        idempotency.handle(CancellationError(), for: first)
        idempotency.handle(URLError(.cancelled), for: first)
        let retry = idempotency.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        XCTAssertEqual(first.key.value, retry.key.value)
    }
}

/// A `ConfirmAttemptStore` that lives in a test: "relaunch" is a new
/// registry over the same store instance, with the static in-memory
/// registry cleared in between.
private final class InMemoryConfirmAttemptStore: ConfirmAttemptStore {
    var records: [PersistedConfirmAttempt] = []
    func load() -> [PersistedConfirmAttempt] { records }
    func save(_ records: [PersistedConfirmAttempt]) { self.records = records }
}

/// A store whose writes never land and whose reads find nothing — what the
/// registry sees when the Keychain refuses to cooperate.
private final class BrokenConfirmAttemptStore: ConfirmAttemptStore {
    func load() -> [PersistedConfirmAttempt] { [] }
    func save(_ records: [PersistedConfirmAttempt]) {}
}

/// What the pins do across process death. Losing a pin to a kill is exactly
/// the double-charge window P1 closes: the relaunched app paying again with
/// the same details must replay the same key and the same frozen body.
@MainActor
final class ConfirmIdempotencyPersistenceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ConfirmIdempotency._removeAllForTesting()
    }

    private func expiredRecord(digest: String, age: TimeInterval) -> PersistedConfirmAttempt {
        PersistedConfirmAttempt(
            identityDigest: digest,
            keyValue: "11111111-1111-1111-1111-111111111111",
            paymentIntentId: "pi_old",
            browserInfo: .currentDevice(),
            ipAddress: "10.0.0.1",
            createdAt: Date().timeIntervalSince1970 - age
        )
    }

    /// The P1 acceptance test: kill the app mid-confirm, relaunch, pay again
    /// with the same details — same key, same frozen device values, so the
    /// send is a byte-identical replay the server can recognize.
    func testPinSurvivesRelaunch() {
        let store = InMemoryConfirmAttemptStore()
        let before = ConfirmIdempotency(store: store)
            .attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")

        ConfirmIdempotency._clearInMemoryForTesting() // process death

        let after = ConfirmIdempotency(store: store)
            .attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        XCTAssertEqual(before.key.value, after.key.value)
        XCTAssertEqual(before.browserInfo.deviceId, after.browserInfo.deviceId)
        XCTAssertEqual(before.browserInfo.screenWidth, after.browserInfo.screenWidth)
        XCTAssertEqual(before.ipAddress, after.ipAddress)
        XCTAssertEqual(after.paymentIntentId, "pi_test")
    }

    /// The server honors a replayed key for 24 hours. A pin older than that
    /// cannot protect anyone — restoring it would replay a key the server
    /// has forgotten, silently starting a SECOND payment under old details.
    func testExpiredPinIsNotRestored() {
        let store = InMemoryConfirmAttemptStore()
        store.records = [expiredRecord(digest: "payload-a", age: 25 * 60 * 60)]

        let attempt = ConfirmIdempotency(store: store)
            .attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        XCTAssertNotEqual(attempt.key.value, "11111111-1111-1111-1111-111111111111")
    }

    func testFreshPinWithinTheWindowIsRestored() {
        let store = InMemoryConfirmAttemptStore()
        store.records = [expiredRecord(digest: "payload-a", age: 60)]

        let attempt = ConfirmIdempotency(store: store)
            .attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        XCTAssertEqual(attempt.key.value, "11111111-1111-1111-1111-111111111111")
    }

    /// A resolved attempt is over everywhere — a relaunch must not resurrect
    /// its key for what is by then a NEW payment.
    func testResolvedPinIsRemovedFromTheStore() {
        let store = InMemoryConfirmAttemptStore()
        let registry = ConfirmIdempotency(store: store)
        let attempt = registry.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        registry.resolve(attempt)
        XCTAssertTrue(store.records.isEmpty)

        ConfirmIdempotency._clearInMemoryForTesting()
        let next = ConfirmIdempotency(store: store)
            .attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        XCTAssertNotEqual(attempt.key.value, next.key.value)
    }

    /// The TTL trusts the wall clock and the wall clock is user-settable, so
    /// the store is also capped outright, oldest first.
    func testStoreIsCappedWithOldestEvictedFirst() {
        let store = InMemoryConfirmAttemptStore()
        let registry = ConfirmIdempotency(store: store)
        for index in 0...ConfirmIdempotency.maxPersistedAttempts {
            _ = registry.attempt(forPayloadDigest: "payload-\(index)", paymentIntentId: "pi_test")
        }
        XCTAssertEqual(store.records.count, ConfirmIdempotency.maxPersistedAttempts)
        XCTAssertFalse(store.records.contains { $0.identityDigest == "payload-0" },
                       "the oldest pin is the one to give up")
        XCTAssertTrue(store.records.contains {
            $0.identityDigest == "payload-\(ConfirmIdempotency.maxPersistedAttempts)"
        })
    }

    /// A refused Keychain must never break the live session: the in-memory
    /// pin still guarantees same-key replay until the process dies.
    func testBrokenStoreStillPinsInMemory() {
        let registry = ConfirmIdempotency(store: BrokenConfirmAttemptStore())
        let first = registry.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        let retry = registry.attempt(forPayloadDigest: "payload-a", paymentIntentId: "pi_test")
        XCTAssertEqual(first.key.value, retry.key.value)
    }

    /// The restoring initializer must round-trip the persisted value
    /// byte-identically — the server matches keys as opaque strings.
    func testRestoredKeyRoundTripsVerbatim() {
        let minted = UqpayIdempotencyKey()
        XCTAssertEqual(UqpayIdempotencyKey(restoring: minted.value).value, minted.value)
    }
}

/// The payload identity that keys those pins. It must be stable across
/// process launches — a pin that cannot be re-derived after relaunch is a
/// pin lost, and a lost pin is the double-charge window — and it must never
/// be derivable back to a full card number or CVC, because it outlives the
/// process at rest.
final class ConfirmPayloadIdentityTests: XCTestCase {

    /// Pinned against an independently computed SHA-256 of "a\u{1F}b"
    /// (`printf 'a\x1fb' | shasum -a 256`). If this vector ever changes,
    /// every pin persisted by a previous SDK version becomes unreachable —
    /// treat the canonical form as a wire format.
    func testDigestMatchesTheIndependentlyComputedVector() {
        XCTAssertEqual(
            ConfirmPayloadIdentity.digest(of: ["a", "b"]),
            "f04cdced9736a69da6103f08a4daaf8c485dd481217d218a1b4993c8c3968e13"
        )
        XCTAssertEqual(
            ConfirmPayloadIdentity.digest(of: ["pi_123", "grabpay"]),
            "f54bf243bef884d9911df9fc3d7169731647ea074c43108dcbfe45686658f28e"
        )
    }

    /// Plain concatenation would let ["ab","c"] and ["a","bc"] share a key —
    /// two different payments replaying one attempt. The U+001F separator
    /// keeps field boundaries part of the identity.
    func testFieldBoundariesArePartOfTheIdentity() {
        XCTAssertNotEqual(
            ConfirmPayloadIdentity.digest(of: ["ab", "c"]),
            ConfirmPayloadIdentity.digest(of: ["a", "bc"])
        )
    }

    func testCardNumberIdentityKeepsOnlyBinAndLast4() {
        let identity = ConfirmPayloadIdentity.cardNumberIdentity("5521970079998012")
        XCTAssertEqual(identity, "552197:8012")
        XCTAssertFalse(identity.contains("0079"),
                       "the middle digits must never reach the digest input")
    }

    /// Two PANs sharing BIN and last 4 collapse to one identity — by design.
    /// The server rejects a replayed key whose body differs, so the worst
    /// case is one rejected round trip, never a silent replay.
    func testDistinctExpiryStillSeparatesReducedIdentities() {
        let a = ConfirmPayloadIdentity.digest(of: ["pi_1", "card", "552197:8012", "01", "2027"])
        let b = ConfirmPayloadIdentity.digest(of: ["pi_1", "card", "552197:8012", "02", "2027"])
        XCTAssertNotEqual(a, b)
    }
}

/// The 3DS/wallet outcome poll. It used to hold a wall-clock deadline,
/// which kept advancing while the app was suspended even though the polls
/// did not — a customer's trip into their banking app consumed the whole
/// timeout and their return was greeted with "timed out". The budget is
/// now attempts, spent only while the app actually runs.
@MainActor
final class OutcomePollingTests: XCTestCase {

    func testReturnsTheFirstOutcome() async throws {
        var polls = 0
        let outcome: String = try await ApiClient.pollForOutcome(attempts: 5, interval: 0.001) {
            polls += 1
            return polls == 3 ? "settled" : nil
        }
        XCTAssertEqual(outcome, "settled")
        XCTAssertEqual(polls, 3)
    }

    func testExhaustedAttemptsThrowTheTimeout() async {
        var polls = 0
        do {
            let _: String = try await ApiClient.pollForOutcome(attempts: 4, interval: 0.001) {
                polls += 1
                return nil
            }
            XCTFail("exhaustion must throw")
        } catch {
            XCTAssertEqual(error as? PaymentSheetError, .authenticationTimedOut)
        }
        XCTAssertEqual(polls, 4, "the budget is attempts, not elapsed time")
    }

    /// Deliberately preserved from the loop this replaced: an error still
    /// held when the budget runs out outranks the generic timeout.
    func testHeldErrorOutranksTheTimeoutOnExhaustion() async {
        do {
            let _: String = try await ApiClient.pollForOutcome(attempts: 2, interval: 0.001) {
                throw URLError(.timedOut)
            }
            XCTFail("exhaustion must throw")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
    }

    /// A poll that answers — even without an outcome — proves the connection
    /// works; an older transport error must not be the one reported.
    func testASuccessfulPollClearsTheHeldError() async {
        var polls = 0
        do {
            let _: String = try await ApiClient.pollForOutcome(attempts: 2, interval: 0.001) {
                polls += 1
                if polls == 1 { throw URLError(.timedOut) }
                return nil
            }
            XCTFail("exhaustion must throw")
        } catch {
            XCTAssertEqual(error as? PaymentSheetError, .authenticationTimedOut)
        }
    }

    func testAPathologicalBudgetStillPollsOnce() async throws {
        var polls = 0
        let outcome: String = try await ApiClient.pollForOutcome(attempts: 0, interval: 0.001) {
            polls += 1
            return "settled"
        }
        XCTAssertEqual(outcome, "settled")
        XCTAssertEqual(polls, 1)
    }
}

/// Ownership of the status screen's polls and retries across teardown and
/// the app lifecycle. The 30-second retry sleeps used to live in detached
/// tasks that viewWillDisappear's cancel could not reach; and a customer
/// returning from their banking app used to stare at a stale spinner until
/// whatever remained of a sleep elapsed.
@MainActor
final class StatusPollingLifecycleTests: XCTestCase {

    private func pendingResponse() -> PaymentIntentCreateResponse {
        PaymentIntentCreateResponse(
            paymentIntentId: "pi_test_123",
            amount: "8.98",
            currency: "SGD",
            clientSecret: "cs_test",
            intentStatus: "PENDING"
        )
    }

    /// A processing screen that has polled once and is parked in a 30s retry.
    private func parkedProcessingScreen() -> PaymentCardStatusViewController {
        let screen = PaymentCardStatusViewController.processing()
        screen.loadViewIfNeeded()
        screen.enableRefresh(paymentIntentId: "pi_test_123")
        screen.handlePaymentStatusResponse(pendingResponse())
        return screen
    }

    func testPendingRetryIsCancellableByTeardown() {
        let screen = parkedProcessingScreen()
        XCTAssertNotNil(screen.pollingTask, "the 30s retry must be owned, not detached")
        screen.viewWillDisappear(false)
        XCTAssertEqual(screen.pollingTask?.isCancelled, true)
    }

    func testForegroundNudgeReplacesThePendingRetry() {
        let screen = parkedProcessingScreen()
        let parkedRetry = screen.pollingTask
        screen.applicationDidBecomeActive()
        XCTAssertEqual(parkedRetry?.isCancelled, true,
                       "what remains of the 30s sleep must not outlive the nudge")
        XCTAssertEqual(screen.pollingTask?.isCancelled, false,
                       "the nudge polls immediately in the retry's place")
    }

    func testNudgeLeavesSettledScreensAlone() {
        let screen = PaymentCardStatusViewController.success(amount: "8.98", transactionId: "pi_1")
        screen.loadViewIfNeeded()
        screen.applicationDidBecomeActive()
        XCTAssertNil(screen.pollingTask)
    }

    /// Refresh-button-only parking leaves polling to the customer by design;
    /// coming back to the app must not start a poll nobody asked for.
    func testNudgeDoesNotStartAPollNobodyAskedFor() {
        let screen = PaymentCardStatusViewController.pending(amount: "8.98", transactionId: "pi_1")
        screen.loadViewIfNeeded()
        screen.enableRefresh(paymentIntentId: "pi_test_123")
        screen.applicationDidBecomeActive()
        XCTAssertNil(screen.pollingTask)
    }
}

/// The sheet-level half of the terminal-intent guard: presenting a payment
/// UI for an intent that already SUCCEEDED showed the customer a working
/// payment form for a payment they had made. `getPaymentMethods()` now
/// refuses, which covers every list-based entry path in one place.
@MainActor
final class TerminalIntentPresentationTests: XCTestCase {

    /// `UqpayPaymentIntent` only decodes, and the wire is snake_case.
    private func intent(status: String) -> UqpayPaymentIntent {
        let json = """
        {"payment_intent_id": "pi_test_123", "intent_status": "\(status)", "amount": "8.98", "currency": "SGD"}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(UqpayPaymentIntent.self, from: Data(json.utf8))
    }

    func testEveryFinalStatusRefusesPresentation() {
        for status in ["SUCCEEDED", "CANCELLED", "FAILED"] {
            let fixture = intent(status: status)
            XCTAssertEqual(
                ApiClient.presentationRefusal(for: fixture),
                .intentNotPayable(status: fixture.intentStatus),
                "\(status) is final; a payment form for it can only mislead"
            )
        }
    }

    /// Includes a status this SDK version does not know: a future status
    /// wrongly refused would block real payments, while a wrongly presented
    /// one is still caught by the pre-confirm intercept.
    func testEveryLiveStatusPresents() {
        for status in ["REQUIRES_PAYMENT_METHOD", "REQUIRES_CUSTOMER_ACTION",
                       "PENDING", "REQUIRES_CAPTURE", "SOMETHING_NEW"] {
            XCTAssertNil(ApiClient.presentationRefusal(for: intent(status: status)),
                         "\(status) must present")
        }
    }

    /// The message is merchant-facing: it must name the state and say what
    /// to do about it, not just declare an error.
    func testRefusalTellsTheMerchantWhatHappenedAndWhatToDo() {
        let refusal = PaymentSheetError.intentNotPayable(status: .succeeded)
        let description = refusal.errorDescription ?? ""
        XCTAssertTrue(description.contains("SUCCEEDED"))
        XCTAssertTrue(description.contains("new payment intent"))
    }
}

/// The device fingerprint must describe the real device — the whole point of
/// removing the fabricated defaults.
@MainActor
final class DeviceBrowserInfoTests: XCTestCase {

    /// The 3DS integration guide's sample sends `"timezone": "-2"`, so this
    /// field is whole hours. A minutes value here was rejected guesswork.
    func testTimezoneIsInHoursAsTheDocsSpecify() {
        let info = BrowserInfo.currentDevice()
        XCTAssertEqual(info.timezone, "\(TimeZone.current.secondsFromGMT() / 3600)")
    }

    func testScreenMatchesTheRealDevice() {
        let info = BrowserInfo.currentDevice()
        XCTAssertEqual(info.screenWidth, Int(UIScreen.main.bounds.width))
        XCTAssertEqual(info.screenHeight, Int(UIScreen.main.bounds.height))
        // Regression: these were hardcoded 1920x1080.
        XCTAssertFalse(info.screenWidth == 1920 && info.screenHeight == 1080)
    }

    func testUserAgentAgreesWithTheDeviceModel() {
        let info = BrowserInfo.currentDevice()
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(info.browser.userAgent.contains("iPad"))
        } else {
            XCTAssertTrue(info.browser.userAgent.contains("iPhone"))
        }
        // Regression: a canned "iPhone OS 14_5" shipped for every device.
        XCTAssertFalse(info.browser.userAgent.contains("14_5")
                       && ProcessInfo.processInfo.operatingSystemVersion.majorVersion != 14)
    }

    /// Coordinates are never invented; the field is omitted instead.
    func testLocationIsOmitted() {
        XCTAssertNil(BrowserInfo.currentDevice().location)
    }

    func testOsTypeIsUppercaseAsTheAPIRequires() {
        XCTAssertEqual(BrowserInfo.currentDevice().mobile.osType, "IOS")
    }
}

/// Locks the wallet registry that replaced six copied-and-edited QR screens.
///
/// Every defect pinned here was live in those copies. They are cheap to check
/// once and impossible to check by reading six files that look identical.
@MainActor
final class WalletQRDescriptorTests: XCTestCase {

    /// Types that legitimately have no QR wallet: card has its own form, and
    /// PayPal is not implemented.
    private let nonWalletTypes: Set<PaymentMethodType> = [.card, .paypal]

    private var allDescriptors: [(PaymentMethodType, WalletQRDescriptor)] {
        PaymentMethodType.allCases.compactMap { type in
            WalletQRDescriptor.descriptor(for: type).map { (type, $0) }
        }
    }

    /// Every method the sheet can show must be routable, or selecting it in the
    /// list dead-ends. PayNow answered "coming soon" for exactly this reason
    /// while the sandbox was already offering it.
    func testEveryImplementedMethodHasAWallet() {
        for type in PaymentMethodType.allCases where !nonWalletTypes.contains(type) {
            XCTAssertNotNil(
                WalletQRDescriptor.descriptor(for: type),
                "\(type) has no wallet descriptor, so the list cannot route to it"
            )
        }
        for type in nonWalletTypes {
            XCTAssertNil(WalletQRDescriptor.descriptor(for: type))
        }
    }

    /// The type confirmed, the type latched and the type reported to the
    /// merchant are one value.
    ///
    /// Regression: the Alipay screens confirmed as `alipaycn` but reported
    /// `alipay` to the delegate, so a merchant matching on the method type saw
    /// a payment method that had never been charged.
    func testEveryDescriptorConfirmsUnderItsOwnMethodType() {
        for (type, descriptor) in allDescriptors {
            XCTAssertEqual(
                descriptor.confirmMethod().type,
                descriptor.methodType,
                "\(type) confirms under a different type than it latches with"
            )
        }
    }

    /// Regression: `wechatpay` and `alipayhk` named asset sets that do not
    /// exist. `UIImage(named:)` returns nil silently, so both wallets showed a
    /// generic glyph in place of their brand mark and nobody noticed.
    ///
    /// A wallet with no artwork yet says so with nil; naming a set that is not
    /// there is the bug this catches.
    func testEveryNamedAssetExists() {
        // The exact bundle production code resolves — under SwiftPM,
        // `Bundle(for:)` would point at the test host instead.
        let bundle = UqpayResourceManager.bundle
        for (type, descriptor) in allDescriptors {
            guard let assetName = descriptor.iconAssetName else { continue }
            XCTAssertNotNil(
                UIImage(named: assetName, in: bundle, compatibleWith: nil),
                "\(type) names asset '\(assetName)', which is not in the catalog"
            )
        }
    }

    /// The wallets still waiting on a brand mark, written down so the list
    /// shrinks deliberately rather than drifting. Failing here means artwork
    /// landed (or was lost) without this being updated.
    func testOnlyTheRegionalWalletsAwaitArtwork() {
        let awaiting = allDescriptors
            .filter { $0.1.iconAssetName == nil }
            .map { $0.1.methodType }
            .sorted()
        XCTAssertEqual(
            awaiting,
            ["dana", "gcash", "kakaopay", "naverpay", "tng", "tosspay", "truemoney"],
            "the set of wallets without a brand mark changed"
        )
    }

    /// White on a bright accent is unreadable — KakaoPay's yellow is the case
    /// that forced this. The button must not print white on light.
    func testButtonTitleContrastsWithTheAccent() {
        for (type, descriptor) in allDescriptors {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            XCTAssertTrue(descriptor.accentColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

            var titleWhite: CGFloat = 0
            XCTAssertTrue(descriptor.buttonTitleColor.getWhite(&titleWhite, alpha: &alpha))

            if luminance > 0.6 {
                XCTAssertLessThan(titleWhite, 0.5, "\(type) prints a light title on a light button")
            } else {
                XCTAssertGreaterThan(titleWhite, 0.5, "\(type) prints a dark title on a dark button")
            }
        }
    }

    /// The fallback only helps if it resolves; a bad symbol name renders empty.
    func testEveryFallbackSymbolResolves() {
        for (type, descriptor) in allDescriptors {
            XCTAssertNotNil(
                UIImage(systemName: descriptor.fallbackSymbolName),
                "\(type) has an unresolvable fallback symbol"
            )
        }
    }

    /// The body carries the details under a key equal to the method type, with
    /// the merchant-presented QR flow. This is the shape the API documents for
    /// every one of these wallets — the screen renders `display_qr_code` and
    /// nothing else, so any other flow would strand the customer.
    func testEveryDescriptorRequestsTheQRCodeFlow() throws {
        for (type, descriptor) in allDescriptors {
            let data = try ConfirmBodyEncoder.make().encode(descriptor.confirmMethod())
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any],
                "\(type) did not encode to an object"
            )

            XCTAssertEqual(json["type"] as? String, descriptor.methodType)

            let details = try XCTUnwrap(
                json[descriptor.methodType] as? [String: Any],
                "\(type) put no details under the '\(descriptor.methodType)' key"
            )
            XCTAssertEqual(details["flow"] as? String, "qrcode")
            XCTAssertEqual(details["is_present"] as? Bool, false)

            // Nothing but the type and this wallet's details. Every other
            // method's field must be absent rather than null: the confirm body
            // is replayed byte-for-byte under the same idempotency key, and a
            // body carrying nulls for fourteen unused methods is both wasteful
            // and a shape the server was never shown.
            XCTAssertEqual(
                Set(json.keys),
                ["type", descriptor.methodType],
                "\(type) encoded unexpected keys: \(Set(json.keys).sorted())"
            )
        }
    }

    /// Two wallets must never share a method type: the one-confirm latch is
    /// keyed by it, so a duplicate would let one wallet serve another's QR.
    func testMethodTypesAreUnique() {
        let types = allDescriptors.map { $0.1.methodType }
        XCTAssertEqual(Set(types).count, types.count, "duplicate wallet method type in the registry")
    }
}
