//
//  WalletQRPaymentViewController.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 11/08/2026.
//

import Foundation
import UIKit
import UqpayCore
import UqpayPayments

/// Any wallet that checks out through a merchant-presented QR code.
///
/// Confirms the intent with `flow: "qrcode"`, renders the returned
/// `display_qr_code`, and polls the intent until the scan resolves it. The
/// customer pays in another app, so that poll is the only way this SDK learns
/// the outcome.
///
/// The wallet is supplied as a ``WalletQRDescriptor``; this screen holds no
/// knowledge of any particular one. It replaced six copies of this file that
/// had begun to drift from each other.
final class WalletQRPaymentViewController: UIViewController {

    // MARK: - Properties

    /// The wallet being paid. Its `methodType` is the only copy of that
    /// constant on this screen — confirm, latch and delegate all read it here.
    private let descriptor: WalletQRDescriptor

    public weak var paymentDelegate: PaymentDelegate?

    /// The sheet this controller reports for; delegate callbacks carry it so
    /// the merchant receives the instance they configured.
    public weak var paymentSheet: PaymentSheet?

    /// The sheet a success or failure is reported against. Reading it marks
    /// the payment as reported, so it cannot also surface as a cancellation.
    private var reportingSheet: PaymentSheet {
        let sheet = paymentSheet ?? PaymentSheet()
        sheet.hasReportedOutcome = true
        return sheet
    }

    /// Reports a cancellation, unless an outcome was already reported.
    private func reportCancellationIfUnreported() {
        guard let sheet = paymentSheet, !sheet.hasReportedOutcome else { return }
        sheet.hasReportedOutcome = true
        paymentDelegate?.paymentSheetDidCancel(sheet)
    }

    /// Watches the intent while the QR code is on screen. The scan happens in
    /// the customer's wallet app, so this poll is the only way the SDK learns
    /// the outcome.
    private var qrOutcomeTask: Task<Void, Never>?

    /// Owns the one confirm this screen may make and the QR it produced.
    private let walletConfirm = WalletQRConfirm()

    /// Store the confirmed payment intent details for display on pending/failure.
    private var paymentIntentId: String?
    private var paymentIntentAmount: String?
    private var paymentIntentCurrency: String?

    /// Refresh can be tapped repeatedly; one report per intent.
    private var reportedRefreshIntentIds = Set<String>()

    deinit {
        qrOutcomeTask?.cancel()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        // Walking away from an unscanned QR is a cancellation. Gated on the
        // sheet, so one dismissal reports once however many screens it tears
        // down, and a paid or failed QR reports nothing here.
        if isMovingFromParent || isBeingDismissed
            || navigationController?.isBeingDismissed == true {
            handleFlowDismissal()
        }
    }

    /// The flow is going away for good. Internal so tests can drive it: the
    /// UIKit flags that trigger it are read-only.
    func handleFlowDismissal() {
        qrOutcomeTask?.cancel()
        reportCancellationIfUnreported()
    }

    // MARK: - UI Components
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = descriptor.displayName
        label.font = UqpayFonts.scaled(size: 24, weight: .semibold, textStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// The QR tile plus its button is ~490pt tall. An iPhone in landscape gives
    /// the sheet roughly 325pt and `.large` is all the room there will ever be,
    /// so without this the code the customer is asked to scan — and the button
    /// that reveals it — sit off-screen with no way to reach them.
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.accessibilityIdentifier = "uqpay.wallet.scroll"
        scrollView.contentInsetAdjustmentBehavior = .always
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let containerView: UIView = {
        let view = UIView()
        // Deliberately white in BOTH appearance modes: this card hosts the
        // QR code, and scanners need dark modules on a light tile. The border
        // and the instruction text inside stay light-mode values to match.
        view.backgroundColor = .white
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor(red: 229/255.0, green: 229/255.0, blue: 229/255.0, alpha: 1.0).cgColor
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var walletIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.image = descriptor.iconAssetName.flatMap {
            UIImage(named: $0, in: UqpayResourceManager.bundle, compatibleWith: nil)
        }
        if imageView.image == nil {
            // Either the wallet has no brand mark yet, or its asset set is
            // missing — a nil image would render an empty box either way.
            imageView.image = UIImage(systemName: descriptor.fallbackSymbolName)
            imageView.tintColor = descriptor.accentColor
        }
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var instructionLabel: UILabel = {
        let label = UILabel()
        label.text = descriptor.scanInstruction
        label.font = UqpayFonts.scaled(size: 14, weight: .regular, textStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(red: 115/255.0, green: 115/255.0, blue: 115/255.0, alpha: 1.0)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var showQRButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(UqpayLocalized("Show QR Code"), for: .normal)
        button.setTitleColor(descriptor.buttonTitleColor, for: .normal)
        button.backgroundColor = descriptor.accentColor
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UqpayFonts.scaled(size: 15, weight: .semibold, textStyle: .subheadline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityIdentifier = "uqpay.wallet.showQR"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let qrCodeImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        imageView.accessibilityIdentifier = "uqpay.wallet.qrCode"
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let qrLoadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let qrErrorLabel: UILabel = {
        let label = UILabel()
        label.textColor = .systemRed
        label.font = UqpayFonts.scaled(size: 14, weight: .regular, textStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Initialization
    public init(descriptor: WalletQRDescriptor) {
        self.descriptor = descriptor
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
    }

    // MARK: - Setup Methods
    private func setupUI() {
        view.backgroundColor = UqpayColors.background
        title = descriptor.displayName

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(containerView)
        contentView.addSubview(showQRButton)

        // Container content lives in a stack so hidden entries collapse and
        // the card resizes around whichever of icon / QR / error is showing.
        let contentStack = UIStackView(arrangedSubviews: [
            walletIconImageView, qrCodeImageView, instructionLabel, qrErrorLabel
        ])
        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(contentStack)
        containerView.addSubview(qrLoadingIndicator)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Pinned to `contentLayoutGuide` for the scrollable extent and to
            // `frameLayoutGuide` for width — mixing the two is what leaves a
            // scroll view with an ambiguous content height that scrolls nowhere.
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            containerView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            contentStack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 32),
            contentStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -32),

            walletIconImageView.widthAnchor.constraint(equalToConstant: 80),
            walletIconImageView.heightAnchor.constraint(equalToConstant: 80),
            qrCodeImageView.widthAnchor.constraint(equalToConstant: 220),
            qrCodeImageView.heightAnchor.constraint(equalToConstant: 220),

            qrLoadingIndicator.centerXAnchor.constraint(equalTo: qrCodeImageView.centerXAnchor),
            qrLoadingIndicator.centerYAnchor.constraint(equalTo: qrCodeImageView.centerYAnchor),

            showQRButton.topAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 24),
            showQRButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            showQRButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            showQRButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            // Closes the top-to-bottom chain: without this the content view has
            // no defined height and the scroll view reports a zero content size.
            showQRButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
        ])
    }

    private func setupActions() {
        showQRButton.addTarget(self, action: #selector(showQRButtonTapped), for: .touchUpInside)
    }

    // MARK: - Actions
    @objc private func showQRButtonTapped() {
        qrErrorLabel.isHidden = true
        qrErrorLabel.text = ""

        guard let paymentIntentId = UqpayConfiguration.shared.paymentIntentId else {
            showQRError(message: UqpayLocalized("Payment intent not found. Please try again."))
            return
        }

        if walletConfirm.hasConfirmed(intentId: paymentIntentId, methodType: descriptor.methodType) {
            // The intent already has a live payment attempt; never confirm
            // again. Re-downloading the issued QR is safe — and the outcome
            // watcher must be running again, or a payment made against the
            // reloaded QR is never observed.
            if let url = walletConfirm.issuedQRCodeURL(intentId: paymentIntentId, methodType: descriptor.methodType) {
                walletIconImageView.isHidden = true
                qrCodeImageView.isHidden = false
                loadQRCodeImage(from: url)
                startWatchingOutcome(paymentIntentId: paymentIntentId)
            }
            return
        }

        showQRButton.isEnabled = false
        showQRButton.setTitle(UqpayLocalized("Loading..."), for: .normal)

        // Swap the wallet icon for the QR area inside the card.
        walletIconImageView.isHidden = true
        qrCodeImageView.isHidden = false
        qrCodeImageView.image = nil
        instructionLabel.text = descriptor.scanInstruction
        qrLoadingIndicator.startAnimating()

        Task {
            do {
                let apiClient = try ApiClient.forConfiguredEnvironment()

                // Pre-confirm re-check (fail-open: an unreadable status must
                // not block payments — the confirm's own idempotency is the
                // double-charge protection). Two recoveries live here:
                // an intent that settled while nobody watched is reported as
                // the outcome it reached, and an intent still waiting on a
                // QR issued before the app was killed gets THAT QR re-served
                // rather than a second confirm — the in-memory latch died
                // with the process, but the server still holds the QR.
                if let current = try? await apiClient.retrievePaymentIntent(paymentIntentId) {
                    if current.intentStatus.isTerminal {
                        await MainActor.run {
                            self.qrLoadingIndicator.stopAnimating()
                            self.resetShowQRButton()
                            self.presentQROutcome(current)
                        }
                        return
                    }
                    if current.intentStatus == .requiresCustomerAction,
                       current.nextAction?.type == "display_qr_code",
                       let qrCodeUrl = current.nextAction?.displayQrCode?.qrCodeUrl {
                        await MainActor.run {
                            self.resetShowQRButton()
                            if let sheet = self.paymentSheet {
                                self.paymentDelegate?.paymentSheet(sheet, requiresAction: .scanQRCode(qrCodeUrl: qrCodeUrl))
                            }
                            self.loadQRCodeImage(from: qrCodeUrl)
                            self.startWatchingOutcome(paymentIntentId: paymentIntentId)
                        }
                        return
                    }
                }

                let response = try await walletConfirm.confirm(
                    apiClient: apiClient,
                    paymentIntentId: paymentIntentId,
                    paymentMethod: descriptor.confirmMethod()
                )

                await MainActor.run {
                    self.handleQRCodeResponse(response)
                }
            } catch {
                // The error text only. Logging the Error itself puts a URLError
                // userInfo — which carries the failing URL, and with it the
                // intent id — into the unified log.
                UqpayLogger.shared.error(
                    "\(descriptor.displayName) QR confirm failed: \((error as? LocalizedError)?.errorDescription ?? "request failed")"
                )
                await MainActor.run {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.showQRError(message: message)
                    self.resetShowQRButton()
                }
            }
        }
    }

    // MARK: - Helper Methods
    private func handleQRCodeResponse(_ response: ConfirmPaymentIntentResponse) {
        qrLoadingIndicator.stopAnimating()
        resetShowQRButton()

        paymentIntentId = response.paymentIntentId
        paymentIntentAmount = response.amount
        paymentIntentCurrency = response.currency

        guard let nextAction = response.nextAction,
              nextAction.actionType == "display_qr_code",
              let displayQrCode = nextAction.displayQrCode else {
            UqpayLogger.shared.error(
                "\(descriptor.displayName) QR: unexpected next_action \(response.nextAction?.actionType ?? "none")"
            )
            // No QR ever reached us — let the customer start a fresh confirm.
            walletConfirm.attemptFinished(intentId: response.paymentIntentId, methodType: descriptor.methodType)
            resetShowQRButton()
            showQRError(message: UqpayLocalized("Unexpected response from server. Please try again."))
            return
        }

        // The outcome watcher starts only where a QR image load was actually
        // initiated — never after a branch that declared the attempt dead.
        if let qrCodeUrl = displayQrCode.qrCodeUrl {
            if let sheet = paymentSheet {
                paymentDelegate?.paymentSheet(sheet, requiresAction: .scanQRCode(qrCodeUrl: qrCodeUrl))
            }
            loadQRCodeImage(from: qrCodeUrl)
            startWatchingOutcome(paymentIntentId: response.paymentIntentId)
        } else if let qrCode = displayQrCode.qrCode,
                  !qrCode.contains("://"),
                  let qrImage = QRCodeGenerator.generateQRImage(from: qrCode) {
            // Raw EMVCo payload (PayNow and friends): there is nothing to
            // download — the string IS the QR content. Feeding it to the
            // image downloader "succeeded" as a schemeless relative URL and
            // then failed with "unsupported URL"; the card path has rendered
            // these locally all along.
            if let sheet = paymentSheet {
                paymentDelegate?.paymentSheet(sheet, requiresAction: .scanQRCode(qrCodeUrl: qrCode))
            }
            qrLoadingIndicator.stopAnimating()
            qrCodeImageView.image = qrImage
            qrCodeImageView.isAccessibilityElement = true
            qrCodeImageView.accessibilityIdentifier = "uqpay.qr.image"
            qrCodeImageView.accessibilityLabel = String(format: UqpayLocalized("Payment QR code. Scan it with your %@ app."), descriptor.displayName)
            startWatchingOutcome(paymentIntentId: response.paymentIntentId)
        } else if let qrCode = displayQrCode.qrCode {
            loadQRCodeImage(from: qrCode)
            startWatchingOutcome(paymentIntentId: response.paymentIntentId)
        } else {
            // No QR ever reached us — let the customer start a fresh confirm.
            walletConfirm.attemptFinished(intentId: response.paymentIntentId, methodType: descriptor.methodType)
            resetShowQRButton()
            showQRError(message: UqpayLocalized("QR code URL not found in response"))
        }
    }

    private func loadQRCodeImage(from urlString: String) {
        guard let url = URL(string: urlString) else {
            showQRError(message: UqpayLocalized("Invalid QR code URL"))
            return
        }

        qrLoadingIndicator.startAnimating()

        Task {
            do {
                let (data, _) = try await PaymentImageSession.shared.data(from: url)
                await MainActor.run {
                    if let image = UIImage(data: data) {
                        self.qrCodeImageView.image = image
                        self.qrCodeImageView.isAccessibilityElement = true
                        self.qrCodeImageView.accessibilityIdentifier = "uqpay.qr.image"
                        self.qrCodeImageView.accessibilityLabel = String(format: UqpayLocalized("Payment QR code. Scan it with your %@ app."), self.descriptor.displayName)
                    } else {
                        self.showQRError(message: UqpayLocalized("Failed to load QR code image"))
                    }
                    self.qrLoadingIndicator.stopAnimating()
                }
            } catch {
                await MainActor.run {
                    self.showQRError(message: "Failed to download QR code: \(error.localizedDescription)")
                    self.qrLoadingIndicator.stopAnimating()
                }
            }
        }
    }

    /// Polls the intent until the scan resolves it one way or the other.
    private func startWatchingOutcome(paymentIntentId: String) {
        qrOutcomeTask?.cancel()

        qrOutcomeTask = Task { [weak self] in
            do {
                let apiClient = try ApiClient.forConfiguredEnvironment()
                let intent = try await apiClient.awaitThreeDSOutcome(
                    paymentIntentId: paymentIntentId,
                    excludingActionType: "display_qr_code",
                    timeout: 600
                )
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.presentQROutcome(intent) }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    // The poll ended without observing an outcome. The
                    // attempt — and its QR — may still be live. Report as
                    // pending (not failed) so the merchant knows to wait.
                    // User can refresh to resume polling.
                    self.navigateToPending(
                        message: UqpayLocalized("We couldn't confirm your payment in time. ")
                            + "Your payment may still be processing. "
                            + "Refresh to check the status."
                    )
                }
            }
        }
    }

    private func presentQROutcome(_ intent: UqpayPaymentIntent) {
        UqpayLogger.shared.info(
            "\(descriptor.displayName) QR resolved: \(intent.intentStatus.rawValue), attempt \(intent.latestPaymentAttempt?.attemptStatus?.rawValue ?? "-")"
        )

        switch intent.intentStatus {
        case .succeeded, .requiresCapture:
            // Paid: free the latch — the registry must not grow for finished payments.
            walletConfirm.attemptFinished(intentId: intent.paymentIntentId, methodType: descriptor.methodType)
            let displayAmount = [intent.amount, intent.currency].compactMap { $0 }.joined(separator: " ")

            if let delegate = paymentDelegate {
                let wireAmount = WireAmount.parse(intent.amount, paymentIntentId: intent.paymentIntentId)
                let result = PaymentResult(
                    paymentIntentId: intent.paymentIntentId,
                    paymentMethodType: descriptor.methodType,
                    status: .succeeded,
                    amount: wireAmount.double,
                    currency: intent.currency ?? "",
                    merchantOrderId: intent.merchantOrderId,
                    completedAt: Date(),
                    transactionId: intent.paymentIntentId,
                    amountDecimal: wireAmount.decimal
                )
                delegate.paymentSheet(self.reportingSheet, didCompleteWithResult: result)
            }

            let successVC = PaymentCardStatusViewController.success(
                amount: displayAmount.isEmpty ? "" : displayAmount,
                transactionId: intent.paymentIntentId
            ) { [weak self] in
                self?.dismiss(animated: true)
            }
            navigationController?.pushViewController(successVC, animated: true)

        case .requiresPaymentMethod:
            let reason = intent.latestPaymentAttempt?.failureMessage
            let failureCode = (intent.latestPaymentAttempt?.failureCode?.isEmpty == false)
                ? intent.latestPaymentAttempt?.failureCode : nil
            walletConfirm.attemptFinished(intentId: intent.paymentIntentId, methodType: descriptor.methodType)
            navigateToFailure(
                errorCode: failureCode ?? "PAYMENT_FAILED",
                message: (reason?.isEmpty == false ? reason! : "The payment could not be completed. Please try again."),
                // The card and raw-QR screens map through the same table, so
                // one server response yields one merchant-facing code.
                code: PaymentCardViewController.errorCode(
                    forFailureCode: failureCode, intentStatus: intent.intentStatus
                )
            )

        case .cancelled:
            walletConfirm.attemptFinished(intentId: intent.paymentIntentId, methodType: descriptor.methodType)
            navigateToFailure(errorCode: "CANCELLED", message: UqpayLocalized("The payment was cancelled."), code: .cancelled)

        case .pending, .requiresCustomerAction:
            // Not terminal: the wallet registered the scan and settlement —
            // or a further step — is still in flight. Reporting this as a
            // failure told the merchant a live payment was dead. The attempt
            // latch stays: confirming again against a live attempt is exactly
            // what the latch exists to prevent.
            navigateToPending(
                message: UqpayLocalized("Your payment is still being processed. Refresh to check the status.")
            )

        default:
            let reason = intent.latestPaymentAttempt?.failureMessage
            let failureCode = (intent.latestPaymentAttempt?.failureCode?.isEmpty == false)
                ? intent.latestPaymentAttempt?.failureCode : nil
            walletConfirm.attemptFinished(intentId: intent.paymentIntentId, methodType: descriptor.methodType)
            navigateToFailure(
                errorCode: failureCode ?? "PAYMENT_FAILED",
                message: (reason?.isEmpty == false ? reason! : "The payment failed. Please try again."),
                code: PaymentCardViewController.errorCode(
                    forFailureCode: failureCode, intentStatus: intent.intentStatus
                )
            )
        }
    }

    private func showQRError(message: String) {
        qrErrorLabel.text = message
        qrErrorLabel.isHidden = false
        qrCodeImageView.isHidden = true
        walletIconImageView.isHidden = false
        instructionLabel.text = descriptor.scanInstruction
        qrLoadingIndicator.stopAnimating()
    }

    private func resetShowQRButton() {
        let intentId = UqpayConfiguration.shared.paymentIntentId
        let confirmed = intentId.map { walletConfirm.hasConfirmed(intentId: $0, methodType: descriptor.methodType) } ?? false
        if confirmed {
            // The intent has a live attempt. The button can only re-download
            // the already-issued QR; without one there is nothing it can do.
            let canReload = intentId.flatMap { walletConfirm.issuedQRCodeURL(intentId: $0, methodType: descriptor.methodType) } != nil
            showQRButton.isEnabled = canReload
            showQRButton.setTitle(canReload ? "Reload QR Code" : "QR code requested", for: .normal)
        } else {
            showQRButton.isEnabled = true
            showQRButton.setTitle(UqpayLocalized("Show QR Code"), for: .normal)
        }
    }

    private func navigateToFailure(errorCode: String, message: String, code: PaymentError.ErrorCode = .unknown) {
        if let delegate = self.paymentDelegate {
            let paymentError = PaymentError(
                code: code,
                message: message,
                underlyingError: nil,
                declineCode: errorCode,
                recoverySuggestion: UqpayLocalized("Please try again or use a different payment method"),
                paymentMethodType: descriptor.methodType
            )
            delegate.paymentSheet(self.reportingSheet, didFailWithError: paymentError)
        }

        let failureViewController = PaymentCardStatusViewController.failed(
            errorCode: errorCode,
            message: message,
            onRetry: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onCancel: { [weak self] in
                self?.dismiss(animated: true)
            }
        )

        navigationController?.pushViewController(failureViewController, animated: true)
    }

    private func navigateToPending(message: String) {
        // QR timeout or a still-settling scan: the payment may be live, so a
        // failure report would be a lie — but silence left the merchant's app
        // waiting forever. Report pending, and arm the Refresh button the
        // message promises (it used to point at a button that never appeared).
        let displayAmount = [paymentIntentAmount, paymentIntentCurrency].compactMap { $0 }.joined(separator: " ")
        let pendingViewController = PaymentCardStatusViewController.pending(
            amount: displayAmount.isEmpty ? nil : displayAmount,
            transactionId: paymentIntentId,
            message: message
        )

        pendingViewController.dismissPaymentSheetCompletion = { [weak self] in
            self?.dismiss(animated: true)
        }

        if let intentId = paymentIntentId {
            reportPendingOutcome(intentId: intentId)
            pendingViewController.enableRefresh(paymentIntentId: intentId) { [weak self] response in
                self?.handleRefreshOutcome(response)
            }
        }

        navigationController?.pushViewController(pendingViewController, animated: true)
    }

    private func reportPendingOutcome(intentId: String) {
        guard let delegate = paymentDelegate else { return }
        let wireAmount = WireAmount.parse(paymentIntentAmount, paymentIntentId: intentId)
        let result = PaymentResult(
            paymentIntentId: intentId,
            paymentMethodType: descriptor.methodType,
            status: .pending,
            amount: wireAmount.double,
            currency: paymentIntentCurrency ?? "",
            transactionId: intentId,
            amountDecimal: wireAmount.decimal
        )
        delegate.paymentSheet(reportingSheet, paymentDidBecomePending: result)
    }

    /// A terminal status the pending screen's own Refresh discovered. The
    /// watcher is gone by then, so this is the only path left that can tell
    /// the merchant.
    private func handleRefreshOutcome(_ response: PaymentIntentCreateResponse) {
        guard reportedRefreshIntentIds.insert(response.paymentIntentId).inserted else { return }

        switch response.intentStatus.uppercased() {
        case "SUCCEEDED":
            walletConfirm.attemptFinished(intentId: response.paymentIntentId, methodType: descriptor.methodType)
            if let delegate = paymentDelegate {
                let wireAmount = WireAmount.parse(response.amount, paymentIntentId: response.paymentIntentId)
                let result = PaymentResult(
                    paymentIntentId: response.paymentIntentId,
                    paymentMethodType: descriptor.methodType,
                    status: .succeeded,
                    amount: wireAmount.double,
                    currency: response.currency,
                    merchantOrderId: response.merchantOrderId,
                    completedAt: Date(),
                    transactionId: response.paymentIntentId,
                    amountDecimal: wireAmount.decimal
                )
                delegate.paymentSheet(reportingSheet, didCompleteWithResult: result)
            }

        case "FAILED", "CANCELLED", "REQUIRES_PAYMENT_METHOD":
            walletConfirm.attemptFinished(intentId: response.paymentIntentId, methodType: descriptor.methodType)
            if let delegate = paymentDelegate {
                let failureCode = (response.latestPaymentAttempt?.failureCode?.isEmpty == false)
                    ? response.latestPaymentAttempt?.failureCode : nil
                delegate.paymentSheet(
                    reportingSheet,
                    didFailWithError: PaymentError(
                        // Same mapping as the card and raw-QR paths — one
                        // server response, one merchant-facing code.
                        code: PaymentCardViewController.errorCode(
                            forFailureCode: failureCode,
                            intentStatus: UqpayPaymentIntentStatus(rawValue: response.intentStatus.uppercased())
                        ),
                        message: UqpayLocalized("The payment could not be completed. Please try again."),
                        declineCode: failureCode,
                        paymentMethodType: descriptor.methodType
                    )
                )
            }

        default:
            break
        }
    }
}
