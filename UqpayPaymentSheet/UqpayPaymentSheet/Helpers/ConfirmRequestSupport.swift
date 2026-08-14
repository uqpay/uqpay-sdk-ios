//
//  ConfirmRequestSupport.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 10/08/2026.
//

import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
import UqpayCore
import UqpayPayments

/// Ephemeral session for fetching payment QR images. The image URLs identify
/// a specific payment, so they must never be written to the shared on-disk
/// URL cache — and a cached response could also serve a stale, expired QR.
enum PaymentImageSession {
    static let shared = URLSession(configuration: .ephemeral)
}

/// The encoder for every confirm body.
///
/// `sortedKeys` is load-bearing: a retry of an unresolved attempt re-encodes
/// the body from the same frozen values, and an idempotent server accepts a
/// replayed key only for byte-identical content. Foundation's JSONEncoder
/// does not otherwise guarantee key order between encodes.
enum ConfirmBodyEncoder {
    static func make() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}

/// Runs `body` under a UIKit background-task assertion.
///
/// A confirm POST plus its replay ladder can spend ~19 seconds in flight,
/// and the customer backgrounding the app mid-confirm would otherwise leave
/// the process suspendable at the exact moment a payment's outcome is
/// unknown. The assertion buys roughly 30 seconds of protected runtime —
/// enough for the ladder to reach an answer and resolve the idempotency pin
/// instead of leaving it to relaunch recovery.
///
/// If the system's patience expires first, the assertion is handed back and
/// the work simply takes its chances with suspension — same as today, never
/// worse.
@MainActor
func withBackgroundTaskAssertion<T>(
    named name: String,
    _ body: () async throws -> T
) async rethrows -> T {
    let application = UIApplication.shared
    var identifier = UIBackgroundTaskIdentifier.invalid
    identifier = application.beginBackgroundTask(withName: name) {
        if identifier != .invalid {
            application.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
    defer {
        if identifier != .invalid {
            application.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
    return try await body()
}

/// The stable identity of a confirm payload.
///
/// `Hasher` is seeded per process, so its values cannot outlive a launch —
/// and idempotency pins must (a pin lost to process death is exactly the
/// double-charge window). The digest is SHA-256 over the identity fields
/// joined with U+001F, a separator no form field can contain, so
/// ["ab","c"] and ["a","bc"] can never collide.
///
/// The card identity deliberately excludes the CVC and reduces the card
/// number to BIN-plus-last-4: these digests will be written at rest, and
/// nothing persisted may be derivable from a full PAN or CVC. The cost is
/// bounded — an edit that changes ONLY the excluded fields replays the
/// previous attempt's key, the server rejects the same key with a different
/// body, the pin resolves, and the next tap mints a fresh key. One extra
/// rejected round trip; never a double charge.
enum ConfirmPayloadIdentity {

    static func digest(of fields: [String]) -> String {
        let canonical = fields.joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// BIN (first 6) plus last 4 — enough to distinguish a corrected card
    /// number without the digest being brute-forceable back to a PAN.
    static func cardNumberIdentity(_ cardNumber: String) -> String {
        "\(cardNumber.prefix(6)):\(cardNumber.suffix(4))"
    }
}

/// One confirm attempt: its idempotency key, the payload identity it belongs
/// to, and the device values frozen with it.
///
/// The device values are frozen because they are the only parts of a confirm
/// body that change on their own between sends — the IP flips when the phone
/// leaves Wi-Fi, the screen dimensions swap on rotation. Freezing them (plus
/// the sorted-keys encoder) means a retry re-encodes byte-identical JSON,
/// which an idempotent server requires before it will replay a key rather
/// than reject it.
///
/// Only these values are held. The card number and CVC are re-read from the
/// form for each send and never retained here.
struct ConfirmAttempt {
    let key: UqpayIdempotencyKey
    let payloadDigest: String
    /// Carried by the attempt itself: the configuration singleton's intent
    /// id is mutable, and a pin restored after relaunch must know which
    /// payment it belongs to without trusting whatever is current then.
    let paymentIntentId: String
    let browserInfo: BrowserInfo
    let ipAddress: String?
    /// Seconds since 1970, set when the attempt was first pinned. The
    /// server's idempotency window is 24 hours; a pin older than that is
    /// dead weight and is dropped on read.
    let createdAt: TimeInterval
}

/// A pending attempt in its at-rest form — what survives process death.
///
/// Holds nothing card-derived: the digest excludes the CVC and reduces the
/// card number to BIN-plus-last-4 (see ``ConfirmPayloadIdentity``), and the
/// rest is the key, device metadata, and timestamps. Field names are a wire
/// format — persisted blobs from a previous SDK version must keep decoding.
struct PersistedConfirmAttempt: Codable {
    let identityDigest: String
    let keyValue: String
    let paymentIntentId: String
    let browserInfo: BrowserInfo
    let ipAddress: String?
    let createdAt: TimeInterval

    init(from attempt: ConfirmAttempt) {
        identityDigest = attempt.payloadDigest
        keyValue = attempt.key.value
        paymentIntentId = attempt.paymentIntentId
        browserInfo = attempt.browserInfo
        ipAddress = attempt.ipAddress
        createdAt = attempt.createdAt
    }

    init(
        identityDigest: String,
        keyValue: String,
        paymentIntentId: String,
        browserInfo: BrowserInfo,
        ipAddress: String?,
        createdAt: TimeInterval
    ) {
        self.identityDigest = identityDigest
        self.keyValue = keyValue
        self.paymentIntentId = paymentIntentId
        self.browserInfo = browserInfo
        self.ipAddress = ipAddress
        self.createdAt = createdAt
    }
}

/// Where pending attempts outlive the process. Records are stored in
/// insertion order — the registry relies on that for oldest-first eviction.
protocol ConfirmAttemptStore {
    func load() -> [PersistedConfirmAttempt]
    func save(_ records: [PersistedConfirmAttempt])
}

/// The production store: one JSON blob in the Keychain.
///
/// Keychain rather than a file because the blob pairs live idempotency keys
/// with a payment's identity, and because Keychain items survive app
/// reinstall — which is the point (a reinstall mid-confirm is still the
/// same possibly-processing payment) but also why the registry enforces the
/// 24-hour TTL on READ; there is no launch hook guaranteed to prune first.
struct KeychainConfirmAttemptStore: ConfirmAttemptStore {

    static let keychainKey = "com.uqpay.sdk.confirm-pins.v1"

    func load() -> [PersistedConfirmAttempt] {
        KeychainHelper.shared.retrieveObject(
            ofType: [PersistedConfirmAttempt].self,
            forKey: Self.keychainKey
        ) ?? []
    }

    func save(_ records: [PersistedConfirmAttempt]) {
        if records.isEmpty {
            KeychainHelper.shared.delete(forKey: Self.keychainKey)
            return
        }
        if !KeychainHelper.shared.saveObject(records, forKey: Self.keychainKey) {
            // Never fatal: the in-memory pin still protects this session;
            // only relaunch recovery is lost.
            UqpayLogger.shared.error("Could not persist confirm idempotency pins to Keychain")
        }
    }
}

/// Tracks confirm attempts whose outcome is unknown.
///
/// A confirm can end three ways. The server answers definitively — the
/// attempt is over. The server never answers, or answers unreadably — the
/// payment may well have been processed, so the next send must reuse the
/// same `x-idempotency-key` and body or the customer can be charged twice.
/// Or the customer edits their details — that is a different payment and
/// must get a fresh key.
///
/// Pending attempts are stored STATICALLY, keyed by payload digest: the
/// unresolved-attempt invariant belongs to the PAYMENT, not to whichever
/// screen instance happened to send it. Backing out of a screen and
/// re-entering must replay the pinned attempt, not mint a fresh key for a
/// payment that may already be processing. Entries hold no card data and are
/// removed the moment an outcome is known, so the registry stays small.
///
/// Pins also outlive the process, through a ``ConfirmAttemptStore``: the app
/// being killed mid-confirm is the same invariant on a longer timescale —
/// the relaunched app paying again with the same details must replay the
/// same key, or the customer can be charged twice. The in-memory dictionary
/// stays the session's source of truth; the store is consulted only on a
/// miss and written through on pin and resolve.
///
/// Resolution requires the attempt itself — a stale task finishing late can
/// only clear its own pin, never one belonging to a newer attempt.
@MainActor
final class ConfirmIdempotency {

    /// Matches the server's idempotency window: a replayed key is honored
    /// for 24 hours, so a pin older than that can no longer protect anyone.
    static let timeToLive: TimeInterval = 24 * 60 * 60

    /// Backstop against a user-settable wall clock defeating the TTL: the
    /// store never holds more than this many records, oldest evicted first.
    /// Sixteen distinct unresolved payments at once is already implausible.
    static let maxPersistedAttempts = 16

    private static var pending: [String: ConfirmAttempt] = [:]

    private let store: ConfirmAttemptStore

    init(store: ConfirmAttemptStore = KeychainConfirmAttemptStore()) {
        self.store = store
    }

    /// The attempt to send for a payload. While an attempt for this payload
    /// is unresolved, the same key and frozen device values come back — even
    /// across process death, via the store; a new payload gets a fresh key.
    func attempt(forPayloadDigest payloadDigest: String, paymentIntentId: String) -> ConfirmAttempt {
        if let existing = Self.pending[payloadDigest] {
            return existing
        }
        if let restored = restoredAttempt(forPayloadDigest: payloadDigest) {
            Self.pending[payloadDigest] = restored
            return restored
        }
        let attempt = ConfirmAttempt(
            key: UqpayIdempotencyKey(),
            payloadDigest: payloadDigest,
            paymentIntentId: paymentIntentId,
            browserInfo: .currentDevice(),
            ipAddress: UqpayDeviceIP.current(),
            createdAt: Date().timeIntervalSince1970
        )
        Self.pending[payloadDigest] = attempt
        persistPin(attempt)
        return attempt
    }

    /// Ends THIS attempt, if it is still the pinned one. A stale task
    /// resolving late cannot un-pin a newer attempt for the same payload.
    func resolve(_ attempt: ConfirmAttempt) {
        if Self.pending[attempt.payloadDigest]?.key.value == attempt.key.value {
            Self.pending.removeValue(forKey: attempt.payloadDigest)
            store.save(liveRecords().filter { $0.identityDigest != attempt.payloadDigest })
        }
    }

    // MARK: Persistence

    /// A previous launch's pin for this payload, if it is still inside the
    /// server's replay window. The frozen device values come back with it —
    /// the relaunched process's own values may differ, and a replayed key
    /// with a different body is rejected, not honored.
    private func restoredAttempt(forPayloadDigest payloadDigest: String) -> ConfirmAttempt? {
        guard let record = liveRecords().first(where: { $0.identityDigest == payloadDigest }) else {
            return nil
        }
        return ConfirmAttempt(
            key: UqpayIdempotencyKey(restoring: record.keyValue),
            payloadDigest: record.identityDigest,
            paymentIntentId: record.paymentIntentId,
            browserInfo: record.browserInfo,
            ipAddress: record.ipAddress,
            createdAt: record.createdAt
        )
    }

    private func persistPin(_ attempt: ConfirmAttempt) {
        var records = liveRecords().filter { $0.identityDigest != attempt.payloadDigest }
        records.append(PersistedConfirmAttempt(from: attempt))
        if records.count > Self.maxPersistedAttempts {
            records.removeFirst(records.count - Self.maxPersistedAttempts)
        }
        store.save(records)
    }

    /// The stored records still within the TTL. Expiry is enforced here, on
    /// read, because Keychain items outlive the app itself — no uninstall,
    /// reinstall, or launch hook can be trusted to prune them first.
    private func liveRecords() -> [PersistedConfirmAttempt] {
        let now = Date().timeIntervalSince1970
        return store.load().filter { now - $0.createdAt <= Self.timeToLive }
    }

    /// Call when a send of this attempt threw. Keeps the pin when the
    /// outcome is unknown; ends the attempt when the server definitively
    /// answered. Cancellation is a third category — the cancelled task
    /// reports nothing, and the pin stays exactly as it was.
    func handle(_ error: Error, for attempt: ConfirmAttempt) {
        if error is CancellationError { return }
        if (error as? URLError)?.code == .cancelled { return }
        guard !Self.isOutcomeUnknown(error) else { return }
        resolve(attempt)
    }

    /// Whether this error leaves the payment's fate undetermined.
    ///
    /// True means the request may have reached the server and been processed:
    /// retry only with the same key, and never tell the merchant the payment
    /// failed. This mirrors ``UqpayAPIError/isRetryable`` — a 429 or 5xx is
    /// the acquirer authorising while the edge gives up, which is precisely
    /// the double-charge case. Cancellation is NOT unknown-outcome handling's
    /// business: a cancelled task reports nothing and leaves the pin as-is.
    static func isOutcomeUnknown(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        // The response never arrived.
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        // A 2xx arrived — the payment WAS processed — but could not be read.
        if error is DecodingError { return true }
        if let apiError = error as? UqpayAPIError {
            switch apiError {
            case .timedOut, .transport, .decoding:
                return true
            case .api, .unexpectedStatus:
                return apiError.isRetryable
            default:
                return false
            }
        }
        return false
    }

    /// Test hook: clears the static registry AND the production Keychain
    /// store. Tests that drive real view controllers pin real attempts —
    /// without the purge they would leak into each other and into the
    /// developer's simulator keychain.
    static func _removeAllForTesting() {
        pending.removeAll()
        KeychainConfirmAttemptStore().save([])
    }

    /// Test hook: clears ONLY the in-memory registry, leaving stores
    /// untouched — this is what process death looks like to the registry.
    static func _clearInMemoryForTesting() {
        pending.removeAll()
    }
}

/// The one confirm a QR-wallet payment is allowed, plus the QR it produced.
///
/// Every QR wallet has the same shape: one confirm creates the payment
/// attempt and yields a QR; confirming again would create a second live
/// attempt, but *re-downloading* the already-issued QR image must stay
/// possible or a dropped image request strands the customer.
///
/// This type owned that distinction back when five hand-copied screens could
/// drift apart — and they did, which is why it exists. They are now one
/// screen (``WalletQRPaymentViewController``), so it has one caller.
@MainActor
final class WalletQRConfirm {

    private struct IssuedQR {
        /// nil when the server confirmed but delivered no usable QR.
        let url: String?
    }

    /// Keyed by intent id AND wallet method, and static deliberately: the
    /// one-confirm invariant belongs to the PAYMENT, not to a screen
    /// instance — backing out of a wallet screen and re-entering it must not
    /// confirm the same intent a second time. The method is part of the key
    /// because one intent can be tried through different wallets, and an
    /// Alipay screen must never serve the QR a GrabPay confirm issued.
    /// Entries are removed when their attempt finishes (success included),
    /// so the registry stays bounded.
    private static var issuedByAttempt: [String: IssuedQR] = [:]

    private static func registryKey(_ intentId: String, _ methodType: String) -> String {
        "\(intentId)|\(methodType)"
    }

    private static func payloadDigest(_ intentId: String, _ methodType: String) -> String {
        ConfirmPayloadIdentity.digest(of: [intentId, methodType])
    }

    private let idempotency = ConfirmIdempotency()

    /// True once a confirm for this intent and wallet succeeded — on any
    /// screen instance. The intent has a live payment attempt; another
    /// confirm would create a second one.
    func hasConfirmed(intentId: String, methodType: String) -> Bool {
        Self.issuedByAttempt[Self.registryKey(intentId, methodType)] != nil
    }

    /// The QR the server issued for this intent and wallet, if any.
    /// Re-fetching this URL is always safe.
    func issuedQRCodeURL(intentId: String, methodType: String) -> String? {
        Self.issuedByAttempt[Self.registryKey(intentId, methodType)]?.url
    }

    /// Confirms the intent for a wallet payment method.
    ///
    /// The idempotency pin is static: a confirm whose outcome stayed unknown
    /// is replayed under the same key even from a freshly-created screen, so
    /// re-entering a wallet cannot open a second attempt for a payment that
    /// may already be processing.
    func confirm(
        apiClient: ApiClient,
        paymentIntentId: String,
        paymentMethod: ConfirmPaymentMethod
    ) async throws -> ConfirmPaymentIntentResponse {
        let attempt = idempotency.attempt(
            forPayloadDigest: Self.payloadDigest(paymentIntentId, paymentMethod.type),
            paymentIntentId: paymentIntentId
        )

        let request = ConfirmPaymentIntentRequest(
            paymentMethod: paymentMethod,
            browserInfo: attempt.browserInfo,
            // The device's real address — the API produces no QR without it.
            ipAddress: attempt.ipAddress
        )

        do {
            let response = try await withBackgroundTaskAssertion(named: "com.uqpay.confirm.wallet") {
                try await apiClient.confirmPaymentIntent(
                    paymentIntentId: paymentIntentId,
                    encodedBody: try ConfirmBodyEncoder.make().encode(request),
                    idempotencyKey: attempt.key
                )
            }
            idempotency.resolve(attempt)
            let qr = response.nextAction?.displayQrCode
            Self.issuedByAttempt[Self.registryKey(paymentIntentId, paymentMethod.type)]
                = IssuedQR(url: qr?.qrCodeUrl ?? qr?.qrCode)
            return response
        } catch {
            idempotency.handle(error, for: attempt)
            throw error
        }
    }

    /// Call when the attempt this confirm created is over — paid, terminally
    /// failed, or QR-less. A finished attempt frees the latch (a fresh
    /// confirm on a dead attempt is legitimate; a re-confirm of a paid
    /// intent is refused server-side) and keeps the registry bounded.
    ///
    /// NEVER call this because a poll timed out or errored: an unobserved
    /// attempt is not a finished one, and its QR may still be paid.
    func attemptFinished(intentId: String, methodType: String) {
        Self.issuedByAttempt.removeValue(forKey: Self.registryKey(intentId, methodType))
    }

    /// Test hook: clears the static registry so cases cannot leak state.
    static func _removeAllForTesting() {
        issuedByAttempt.removeAll()
    }
}
#endif
