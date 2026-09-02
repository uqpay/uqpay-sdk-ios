import Foundation
import UIKit
import UqpayCore
import UqpayPayments

final class PaymentCardRawQRViewController: UIViewController {

    private let qrImage: UIImage
    public weak var paymentDelegate: PaymentDelegate?
    public weak var paymentSheet: PaymentSheet?

    private var qrOutcomeTask: Task<Void, Never>?

    private let containerView = UIView()
    private let qrImageView = UIImageView()
    private let instructionLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    init(qrImage: UIImage) {
        self.qrImage = qrImage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        qrOutcomeTask?.cancel()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            qrOutcomeTask?.cancel()
        }
    }

    private func setupUI() {
        view.backgroundColor = UqpayColors.background
        navigationItem.hidesBackButton = true

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(containerView)

        let titleLabel = UILabel()
        titleLabel.text = UqpayLocalized("Scan QR Code")
        titleLabel.font = UqpayFonts.scaled(size: 24, weight: .semibold, textStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = UqpayColors.textPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        let card = UIView()
        // Deliberately white in BOTH appearance modes: the card hosts the QR
        // code, and scanners need dark modules on a light tile. Its border
        // stays a light-mode value to match.
        card.backgroundColor = .white
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(red: 229/255.0, green: 229/255.0, blue: 229/255.0, alpha: 1.0).cgColor
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(card)

        qrImageView.image = qrImage
        qrImageView.contentMode = .scaleAspectFit
        qrImageView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(qrImageView)

        instructionLabel.text = UqpayLocalized("Use your wallet app to scan the QR code")
        instructionLabel.font = UqpayFonts.scaled(size: 14, textStyle: .footnote)
        instructionLabel.adjustsFontForContentSizeCategory = true
        instructionLabel.textColor = UqpayColors.textInstructionRawQR
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(instructionLabel)

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        // `.systemBlue` is #007AFF in light mode — the exact literal this was.
        loadingIndicator.color = .systemBlue
        containerView.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            containerView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            containerView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            containerView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            card.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            card.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            card.heightAnchor.constraint(equalToConstant: 280),

            qrImageView.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            qrImageView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            qrImageView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            qrImageView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),

            instructionLabel.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 16),
            instructionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            instructionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            loadingIndicator.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 16),
            loadingIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            loadingIndicator.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        loadingIndicator.startAnimating()
    }

    func startPollingForOutcome(paymentIntentId: String, amount: String?, currency: String?) {
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
                await MainActor.run { self?.presentOutcome(intent, amount: amount, currency: currency) }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.presentPollTimeout(paymentIntentId: paymentIntentId, amount: amount, currency: currency)
                }
            }
        }
    }

    /// The poll window closed without an observable outcome. The payment may
    /// still be live — this used to build an explanation, throw it away, and
    /// silently pop back to the card form after ten minutes of waiting.
    private func presentPollTimeout(paymentIntentId: String, amount: String?, currency: String?) {
        reportPendingOutcome(paymentIntentId: paymentIntentId, amount: amount, currency: currency)

        let displayAmount = [amount, currency].compactMap { $0 }.joined(separator: " ")
        let pendingVC = PaymentCardStatusViewController.pending(
            amount: displayAmount.isEmpty ? nil : displayAmount,
            transactionId: paymentIntentId,
            message: UqpayLocalized("We couldn't confirm your payment in time. Your payment may still be processing. Refresh to check the status.")
        )
        pendingVC.enableRefresh(paymentIntentId: paymentIntentId) { [weak self] response in
            self?.handleRefreshOutcome(response, amount: amount, currency: currency)
        }
        navigationController?.pushViewController(pendingVC, animated: true)
    }

    /// A terminal status the pending screen's own Refresh discovered.
    private func handleRefreshOutcome(_ response: PaymentIntentCreateResponse, amount: String?, currency: String?) {
        guard reportedRefreshIntentIds.insert(response.paymentIntentId).inserted else { return }

        switch response.intentStatus.uppercased() {
        case "SUCCEEDED":
            reportSuccess(
                paymentIntentId: response.paymentIntentId,
                amount: amount ?? response.amount,
                currency: currency ?? response.currency,
                merchantOrderId: response.merchantOrderId
            )
        case "FAILED", "CANCELLED", "REQUIRES_PAYMENT_METHOD":
            let failureCode = (response.latestPaymentAttempt?.failureCode?.isEmpty == false)
                ? response.latestPaymentAttempt?.failureCode : nil
            reportFailure(
                code: response.intentStatus.uppercased() == "CANCELLED"
                    ? .cancelled
                    : PaymentCardViewController.errorCode(
                        forFailureCode: failureCode,
                        intentStatus: UqpayPaymentIntentStatus(rawValue: response.intentStatus.uppercased())),
                message: UqpayLocalized("The payment could not be completed. Please try again."),
                declineCode: failureCode
            )
        default:
            break
        }
    }

    private func presentOutcome(_ intent: UqpayPaymentIntent, amount: String?, currency: String?) {
        guard !Task.isCancelled else { return }

        switch intent.intentStatus {
        case .succeeded, .requiresCapture:
            let displayAmount = [amount, currency].compactMap { $0 }.joined(separator: " ")
            reportSuccess(
                paymentIntentId: intent.paymentIntentId,
                amount: amount ?? intent.amount,
                currency: currency ?? intent.currency,
                merchantOrderId: intent.merchantOrderId
            )

            let successVC = PaymentCardStatusViewController.success(
                amount: displayAmount.isEmpty ? "" : displayAmount,
                transactionId: intent.paymentIntentId
            ) { [weak self] in
                self?.navigationController?.popToRootViewController(animated: true)
            }
            navigationController?.pushViewController(successVC, animated: true)

        case .requiresPaymentMethod:
            let attempt = intent.latestPaymentAttempt
            let failureCode = (attempt?.failureCode?.isEmpty == false) ? attempt?.failureCode : nil
            let reason = (attempt?.failureMessage?.isEmpty == false)
                ? attempt!.failureMessage! : "The payment could not be completed. Please try again."

            reportFailure(
                code: PaymentCardViewController.errorCode(forFailureCode: failureCode, intentStatus: intent.intentStatus),
                message: reason,
                declineCode: failureCode
            )
            presentFailureScreen(errorCode: failureCode ?? "PAYMENT_FAILED", message: reason)

        case .pending, .requiresCustomerAction:
            // Not terminal — the scan may have registered with settlement
            // still in flight. Calling this a failure was a lie; park it as
            // pending exactly like a timeout.
            presentPollTimeout(paymentIntentId: intent.paymentIntentId, amount: amount, currency: currency)

        default:
            let attempt = intent.latestPaymentAttempt
            let failureCode = (attempt?.failureCode?.isEmpty == false) ? attempt?.failureCode : nil
            let reason = (attempt?.failureMessage?.isEmpty == false)
                ? attempt!.failureMessage! : "The payment could not be completed. Please try again."

            reportFailure(
                code: intent.intentStatus == .cancelled
                    ? .cancelled
                    : PaymentCardViewController.errorCode(forFailureCode: failureCode, intentStatus: intent.intentStatus),
                message: reason,
                declineCode: failureCode
            )
            presentFailureScreen(errorCode: failureCode ?? "PAYMENT_FAILED", message: reason)
        }
    }

    // MARK: - Merchant reporting

    /// Refresh can be tapped repeatedly; one report per intent.
    private var reportedRefreshIntentIds = Set<String>()

    private func reportSuccess(paymentIntentId: String, amount: String?, currency: String?, merchantOrderId: String?) {
        guard let delegate = paymentDelegate else { return }
        let wireAmount = WireAmount.parse(amount, paymentIntentId: paymentIntentId)
        let result = PaymentResult(
            paymentIntentId: paymentIntentId,
            paymentMethodType: PaymentMethodType.card.rawValue,
            status: .succeeded,
            amount: wireAmount.double,
            currency: currency ?? "",
            merchantOrderId: merchantOrderId,
            completedAt: Date(),
            transactionId: paymentIntentId,
            amountDecimal: wireAmount.decimal
        )
        delegate.paymentSheet(reportingSheet, didCompleteWithResult: result)
    }

    private func reportFailure(code: PaymentError.ErrorCode, message: String, declineCode: String?) {
        guard let delegate = paymentDelegate else { return }
        delegate.paymentSheet(
            reportingSheet,
            didFailWithError: PaymentError(
                code: code,
                message: message,
                declineCode: declineCode,
                paymentMethodType: PaymentMethodType.card.rawValue
            )
        )
    }

    private func reportPendingOutcome(paymentIntentId: String, amount: String?, currency: String?) {
        guard let delegate = paymentDelegate else { return }
        let wireAmount = WireAmount.parse(amount, paymentIntentId: paymentIntentId)
        let result = PaymentResult(
            paymentIntentId: paymentIntentId,
            paymentMethodType: PaymentMethodType.card.rawValue,
            status: .pending,
            amount: wireAmount.double,
            currency: currency ?? "",
            transactionId: paymentIntentId,
            amountDecimal: wireAmount.decimal
        )
        delegate.paymentSheet(reportingSheet, paymentDidBecomePending: result)
    }

    private func presentFailureScreen(errorCode: String, message: String) {
        let failureVC = PaymentCardStatusViewController.failed(
            errorCode: errorCode,
            message: message,
            onRetry: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onCancel: { [weak self] in
                self?.navigationController?.popToRootViewController(animated: true)
            }
        )
        navigationController?.pushViewController(failureVC, animated: true)
    }

    private var reportingSheet: PaymentSheet {
        let sheet = paymentSheet ?? PaymentSheet()
        sheet.hasReportedOutcome = true
        return sheet
    }
}
