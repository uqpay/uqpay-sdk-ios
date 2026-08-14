//
//  PaymentCardStatusViewController.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 26/09/2025.
//

import Foundation
import UIKit
import UqpayCore
import UqpayPayments

// MARK: - Payment Status Types
// Note: Using PaymentStatus from PaymentDelegate.swift which provides:
// .succeeded, .failed, .cancelled, .requiresAction, .processing

// MARK: - Status Configuration

public struct PaymentStatusConfiguration {
    let status: PaymentStatus
    let title: String
    let message: String
    let amount: String?
    let transactionId: String?
    let errorCode: String?
    let primaryActionTitle: String
    let secondaryActionTitle: String?
    let additionalInfo: [String: Any]?

    public init(
        status: PaymentStatus,
        title: String? = nil,
        message: String? = nil,
        amount: String? = nil,
        transactionId: String? = nil,
        errorCode: String? = nil,
        primaryActionTitle: String? = nil,
        secondaryActionTitle: String? = nil,
        additionalInfo: [String: Any]? = nil
    ) {
        self.status = status

        // Default titles based on status
        if let title = title {
            self.title = title
        } else {
            switch status {
            case .succeeded:
                self.title = UqpayLocalized("Payment Successful!")
            case .failed:
                self.title = UqpayLocalized("Payment Failed")
            case .processing, .requiresAction:
                self.title = UqpayLocalized("Payment Processing")
            case .cancelled:
                self.title = UqpayLocalized("Payment Cancelled")
            case .pending:
                self.title = UqpayLocalized("Payment Pending")
            }
        }

        // Default messages based on status
        if let message = message {
            self.message = message
        } else {
            switch status {
            case .succeeded:
                self.message = UqpayLocalized("Your payment has been processed successfully.")
            case .failed:
                self.message = UqpayLocalized("We were unable to process your payment. Please try again or use a different payment method.")
            case .processing, .requiresAction:
                self.message = UqpayLocalized("Your payment is being processed. Please wait...")
            case .cancelled:
                self.message = UqpayLocalized("Your payment has been cancelled.")
            case .pending:
                self.message = UqpayLocalized("Your payment is pending and you will be notified once it is cleared.")
            }
        }

        // Default primary action titles
        if let primaryActionTitle = primaryActionTitle {
            self.primaryActionTitle = primaryActionTitle
        } else {
            switch status {
            case .succeeded:
                self.primaryActionTitle = UqpayLocalized("Done")
            case .failed:
                self.primaryActionTitle = UqpayLocalized("Try Again")
            case .processing, .requiresAction:
                self.primaryActionTitle = UqpayLocalized("Cancel")
            case .cancelled:
                self.primaryActionTitle = UqpayLocalized("OK")
            case .pending:
                self.primaryActionTitle = UqpayLocalized("Close")
            }
        }

        // Default secondary action for failed status
        if let secondaryActionTitle = secondaryActionTitle {
            self.secondaryActionTitle = secondaryActionTitle
        } else {
            switch status {
            case .failed:
                self.secondaryActionTitle = UqpayLocalized("Cancel Payment")
            default:
                self.secondaryActionTitle = nil
            }
        }

        self.amount = amount
        self.transactionId = transactionId
        self.errorCode = errorCode
        self.additionalInfo = additionalInfo
    }

    // Convenience initializers for common scenarios
    public static func success(amount: String, transactionId: String) -> PaymentStatusConfiguration {
        return PaymentStatusConfiguration(
            status: .succeeded,
            amount: amount,
            transactionId: transactionId
        )
    }

    public static func failed(errorCode: String? = nil, message: String? = nil) -> PaymentStatusConfiguration {
        return PaymentStatusConfiguration(
            status: .failed,
            message: message,
            errorCode: errorCode
        )
    }

    public static func pending(amount: String? = nil, transactionId: String? = nil, message: String? = nil) -> PaymentStatusConfiguration {
        return PaymentStatusConfiguration(
            status: .pending,
            message: message,
            amount: amount,
            transactionId: transactionId
        )
    }
}

// MARK: - View Controller

final class PaymentCardStatusViewController: UIViewController {

    // MARK: - Properties

    /// Read access is internal so tests can assert what the customer is shown.
    private(set) var configuration: PaymentStatusConfiguration
    public var primaryActionHandler: (() -> Void)?
    public var secondaryActionHandler: (() -> Void)?

    // Completion callback for dismissing the entire payment flow
    public var dismissPaymentSheetCompletion: (() -> Void)?

    // Payment verification properties
    private var paymentIntentId: String?
    private var pollingAttempts: Int = 0
    /// Owns EVERY poll and retry task, including the 30-second retry sleeps —
    /// a retry that lived in an unowned Task once outran viewWillDisappear's
    /// cancel. Read access is internal so tests can assert cancellation.
    private(set) var pollingTask: Task<Void, Never>?

    // MARK: - UI Components

    private let statusImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let statusIconBackgroundView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 60
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UqpayFonts.scaled(size: 24, weight: .bold, textStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.statusTextPrimary // Gray-900
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.font = UqpayFonts.scaled(size: 32, weight: .bold, textStyle: .largeTitle)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.statusTextPrimary // Gray-900
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = UqpayFonts.scaled(size: 16, weight: .regular, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.statusTextSecondary // Gray-500
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = UqpayFonts.scaled(size: 14, weight: .medium, textStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let primaryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UqpayColors.statusBlue // Blue-600
        button.layer.cornerRadius = 12
        button.titleLabel?.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowOpacity = 0.1
        button.layer.shadowRadius = 4
        return button
    }()

    private let secondaryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitleColor(UqpayColors.statusTextSecondary, for: .normal)
        button.backgroundColor = UqpayColors.surface
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 1
        button.layer.borderColor = UqpayColors.statusButtonBorder.cgColor
        button.titleLabel?.font = UqpayFonts.scaled(size: 16, weight: .medium, textStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = UqpayColors.statusTextSecondary
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let refreshButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(UqpayLocalized("Refresh Status"), for: .normal)
        button.setTitleColor(UqpayColors.statusBlue, for: .normal)
        button.backgroundColor = UqpayColors.surface
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 1.5
        button.layer.borderColor = UqpayColors.statusBlue.cgColor
        button.titleLabel?.font = UqpayFonts.scaled(size: 14, weight: .semibold, textStyle: .footnote)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()

    // MARK: - Initialization

    public init(configuration: PaymentStatusConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Trait Changes

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        // The secondary button's default border is the only dynamic layer
        // color on this screen — layer colors are plain `CGColor` and do not
        // re-resolve on their own. The failed state replaces this border with
        // a static red, which must not be clobbered.
        if configuration.status != .failed {
            view.traitCollection.performAsCurrent {
                secondaryButton.layer.borderColor = UqpayColors.statusButtonBorder.cgColor
            }
        }
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        setupActions()
        configureForStatus()

        // A customer waiting on this screen routinely leaves for their
        // banking or wallet app. The 30-second retry sleeps do not fire
        // while suspended, so without this nudge their return stares at a
        // stale spinner for up to half a minute.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        pollingTask?.cancel()
    }

    /// Re-polls immediately on return to foreground — replacing whatever
    /// sleep or in-flight poll was pending, without consuming an attempt.
    /// Internal so tests can drive it; screens that never started a poll
    /// (Refresh-button-only parking) are deliberately left alone.
    @objc func applicationDidBecomeActive() {
        guard configuration.status == .processing
                || configuration.status == .requiresAction
                || configuration.status == .pending,
              pollingTask != nil,
              let paymentIntentId else { return }
        pollingTask?.cancel()
        startPolling(paymentIntentId: paymentIntentId)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)

        // Start animation for pending status
        if configuration.status == .processing || configuration.status == .requiresAction {
            activityIndicator.startAnimating()
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        activityIndicator.stopAnimating()
        pollingTask?.cancel()
    }

    // MARK: - Setup Methods

    private func setupUI() {
        view.backgroundColor = UqpayColors.background

        // Always add all views to maintain consistent layout
        view.addSubview(statusIconBackgroundView)
        statusIconBackgroundView.addSubview(statusImageView)
        view.addSubview(activityIndicator)
        view.addSubview(titleLabel)
        view.addSubview(descriptionLabel)
        view.addSubview(detailLabel)
        view.addSubview(primaryButton)
        view.addSubview(secondaryButton)
        view.addSubview(refreshButton)

        // Only add amount label if amount is provided
        if configuration.amount != nil {
            view.addSubview(amountLabel)
        }
    }

    private func setupConstraints() {
        var constraints: [NSLayoutConstraint] = []

        // Create a container view concept by using consistent positioning
        // Status Icon Background (always positioned, just hidden when needed)
        constraints.append(contentsOf: [
            statusIconBackgroundView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusIconBackgroundView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -120),
            statusIconBackgroundView.widthAnchor.constraint(equalToConstant: 120),
            statusIconBackgroundView.heightAnchor.constraint(equalToConstant: 120),

            statusImageView.centerXAnchor.constraint(equalTo: statusIconBackgroundView.centerXAnchor),
            statusImageView.centerYAnchor.constraint(equalTo: statusIconBackgroundView.centerYAnchor),
            statusImageView.widthAnchor.constraint(equalToConstant: 60),
            statusImageView.heightAnchor.constraint(equalToConstant: 60)
        ])

        // Activity Indicator (same position as icon)
        constraints.append(contentsOf: [
            activityIndicator.centerXAnchor.constraint(equalTo: statusIconBackgroundView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: statusIconBackgroundView.centerYAnchor),
            activityIndicator.widthAnchor.constraint(equalToConstant: 60),
            activityIndicator.heightAnchor.constraint(equalToConstant: 60)
        ])

        // Title - Always anchored to the same position
        constraints.append(contentsOf: [
            titleLabel.topAnchor.constraint(equalTo: statusIconBackgroundView.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])

        // Amount (if present)
        var lastAnchor = titleLabel.bottomAnchor
        if let amount = configuration.amount {
            amountLabel.text = amount
            constraints.append(contentsOf: [
                amountLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
                amountLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                amountLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
            ])
            lastAnchor = amountLabel.bottomAnchor
        }

        // Description
        constraints.append(contentsOf: [
            descriptionLabel.topAnchor.constraint(equalTo: lastAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])

        // Detail Label (Transaction ID or Error Code)
        constraints.append(contentsOf: [
            detailLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 12),
            detailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            detailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])

        // Buttons
        if configuration.secondaryActionTitle != nil {
            // Two button layout
            constraints.append(contentsOf: [
                primaryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                primaryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
                primaryButton.bottomAnchor.constraint(equalTo: secondaryButton.topAnchor, constant: -12),
                primaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),

                secondaryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                secondaryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
                secondaryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
                secondaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
            ])
        } else {
            // Single button layout
            constraints.append(contentsOf: [
                primaryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                primaryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
                primaryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
                primaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
            ])
            secondaryButton.isHidden = true
        }

        // Refresh button (shown only for pending status)
        constraints.append(contentsOf: [
            refreshButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 24),
            refreshButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            refreshButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            refreshButton.widthAnchor.constraint(equalToConstant: 160)
        ])

        NSLayoutConstraint.activate(constraints)
    }

    private func configureForStatus() {
        titleLabel.text = configuration.title
        descriptionLabel.text = configuration.message
        primaryButton.setTitle(configuration.primaryActionTitle, for: .normal)

        if let secondaryTitle = configuration.secondaryActionTitle {
            secondaryButton.setTitle(secondaryTitle, for: .normal)
            secondaryButton.isHidden = false
        } else {
            secondaryButton.isHidden = true
        }

        // Hide refresh button by default (only shown when explicitly needed)
        refreshButton.isHidden = true

        // Configure status-specific UI with production-quality styling
        switch configuration.status {
        case .succeeded:
            // Success state with green theme
            statusIconBackgroundView.backgroundColor = UqpayColors.statusGreenBadge // Green-100
            statusImageView.image = UIImage(systemName: "checkmark")
            statusImageView.tintColor = UqpayColors.statusGreen // Green-500
            statusImageView.isHidden = false
            statusIconBackgroundView.isHidden = false
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true

            // Success button color - Green
            primaryButton.backgroundColor = UqpayColors.statusGreen // Green-500
            primaryButton.layer.shadowColor = UqpayColors.statusGreenGlow.cgColor

            if let transactionId = configuration.transactionId {
                detailLabel.text = String(format: UqpayLocalized("Transaction ID: %@"), transactionId)
                detailLabel.textColor = UqpayColors.statusTextTertiary // Gray-600
                detailLabel.isHidden = false
            } else {
                detailLabel.isHidden = true
            }

        case .failed:
            // Failed state with red theme
            statusIconBackgroundView.backgroundColor = UqpayColors.statusRedBadge // Red-100
            statusImageView.image = UIImage(systemName: "xmark")
            statusImageView.tintColor = UqpayColors.statusRed // Red-500
            statusImageView.isHidden = false
            statusIconBackgroundView.isHidden = false
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true

            // Failed primary button color - Red for "Try Again"
            primaryButton.backgroundColor = UqpayColors.statusRed // Red-500
            primaryButton.layer.shadowColor = UqpayColors.statusRedGlow.cgColor

            // Secondary button styling
            secondaryButton.layer.borderColor = UqpayColors.statusRedGlow.cgColor
            secondaryButton.setTitleColor(UqpayColors.statusRed, for: .normal)

            if let errorCode = configuration.errorCode {
                detailLabel.text = String(format: UqpayLocalized("Error Code: %@"), errorCode)
                detailLabel.textColor = UqpayColors.statusRed // Red-500
                detailLabel.isHidden = false
            } else {
                detailLabel.isHidden = true
            }

        case .processing, .requiresAction:
            // Processing state with gray theme
            statusIconBackgroundView.isHidden = true
            statusImageView.isHidden = true
            detailLabel.isHidden = true
            activityIndicator.isHidden = false
            activityIndicator.startAnimating()

            // Processing button color - Gray
            primaryButton.backgroundColor = UqpayColors.statusNeutral // Gray-500
            primaryButton.layer.shadowColor = UqpayColors.statusNeutralGlow.cgColor

        case .cancelled:
            // Cancelled state with amber theme
            statusIconBackgroundView.backgroundColor = UqpayColors.statusAmberBadge // Amber-100
            statusImageView.image = UIImage(systemName: "exclamationmark")
            statusImageView.tintColor = UqpayColors.statusAmber // Amber-500
            statusImageView.isHidden = false
            statusIconBackgroundView.isHidden = false
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true

            // Cancelled button color - Amber
            primaryButton.backgroundColor = UqpayColors.statusAmber // Amber-500
            primaryButton.layer.shadowColor = UqpayColors.statusAmberGlow.cgColor

            detailLabel.isHidden = true

        case .pending:
            // Pending state with blue theme
            statusIconBackgroundView.backgroundColor = UqpayColors.statusBlueBadge // Blue-100
            statusImageView.image = UIImage(systemName: "hourglass")
            statusImageView.tintColor = UqpayColors.statusBlue // Blue-600
            statusImageView.isHidden = false
            statusIconBackgroundView.isHidden = false
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true

            // Pending button color - Blue
            primaryButton.backgroundColor = UqpayColors.statusBlue // Blue-600
            primaryButton.layer.shadowColor = UqpayColors.statusBlueGlow.cgColor

            if let transactionId = configuration.transactionId {
                detailLabel.text = String(format: UqpayLocalized("Transaction ID: %@"), transactionId)
                detailLabel.textColor = UqpayColors.statusTextTertiary // Gray-600
                detailLabel.isHidden = false
            } else {
                detailLabel.isHidden = true
            }
        }

        // The icon is decorative — the title and message carry the outcome.
        statusImageView.isAccessibilityElement = false
        statusIconBackgroundView.isAccessibilityElement = false
        titleLabel.accessibilityTraits.insert(.header)

        // Announce the outcome so VoiceOver users hear success or failure
        // without having to explore the screen.
        UIAccessibility.post(
            notification: .screenChanged,
            argument: [configuration.title, configuration.message]
                .filter { !$0.isEmpty }
                .joined(separator: ". ")
        )

        // Add subtle animation to icon appearance
        if !statusImageView.isHidden && !statusIconBackgroundView.isHidden {
            statusIconBackgroundView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            statusIconBackgroundView.alpha = 0

            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [], animations: {
                self.statusIconBackgroundView.transform = .identity
                self.statusIconBackgroundView.alpha = 1
            }, completion: nil)
        }
    }

    private func setupActions() {
        primaryButton.addTarget(self, action: #selector(primaryButtonTapped), for: .touchUpInside)
        secondaryButton.addTarget(self, action: #selector(secondaryButtonTapped), for: .touchUpInside)
        refreshButton.addTarget(self, action: #selector(refreshButtonTapped), for: .touchUpInside)

        // Add touch feedback
        primaryButton.addTarget(self, action: #selector(buttonTouchDown), for: .touchDown)
        primaryButton.addTarget(self, action: #selector(buttonTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        secondaryButton.addTarget(self, action: #selector(buttonTouchDown), for: .touchDown)
        secondaryButton.addTarget(self, action: #selector(buttonTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        refreshButton.addTarget(self, action: #selector(buttonTouchDown), for: .touchDown)
        refreshButton.addTarget(self, action: #selector(buttonTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    @objc private func buttonTouchDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }
    }

    @objc private func buttonTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = .identity
        }
    }

    // MARK: - Actions

    @objc private func primaryButtonTapped() {
        if let handler = primaryActionHandler {
            handler()
        } else {
            handleDefaultPrimaryAction()
        }
    }

    @objc private func secondaryButtonTapped() {
        if let handler = secondaryActionHandler {
            handler()
        } else {
            handleDefaultSecondaryAction()
        }
    }

    @objc private func refreshButtonTapped() {
        guard let paymentIntentId = paymentIntentId else {
            UqpayLogger.shared.error("No payment intent ID available for status refresh")
            return
        }
        verifyPaymentStatus(paymentIntentId: paymentIntentId, showLoading: true)
    }

    private func handleDefaultPrimaryAction() {
        switch configuration.status {
        case .succeeded:
            // Done action - use the callback if provided, otherwise try to dismiss
            if let dismissCallback = dismissPaymentSheetCompletion {
                // Use the provided callback to dismiss properly
                dismissCallback()
            } else {
                // Fallback to our dismissal logic
                dismissPaymentSheet(completion: {
                    NotificationCenter.default.post(
                        name: Notification.Name("PaymentSheetDidComplete"),
                        object: nil,
                        userInfo: ["status": "succeeded", "transactionId": self.configuration.transactionId ?? ""]
                    )
                })
            }

        case .pending:
            // Close action - use the callback if provided, otherwise try to dismiss
            if let dismissCallback = dismissPaymentSheetCompletion {
                dismissCallback()
            } else {
                // Fallback to our dismissal logic
                dismissPaymentSheet(completion: {
                    NotificationCenter.default.post(
                        name: Notification.Name("PaymentSheetDidComplete"),
                        object: nil,
                        userInfo: ["status": "pending", "transactionId": self.configuration.transactionId ?? ""]
                    )
                })
            }

        case .cancelled:
            // OK action - use callback or dismiss
            if let dismissCallback = dismissPaymentSheetCompletion {
                dismissCallback()
            } else {
                dismissPaymentSheet(completion: nil)
            }

        case .failed:
            // Try Again - pop back to payment card view to retry
            if let navController = navigationController {
                // Find the PaymentCardViewController in the navigation stack
                let cardVCExists = navController.viewControllers.contains { $0 is PaymentCardViewController }

                if cardVCExists {
                    // Pop back to the card entry screen
                    for viewController in navController.viewControllers {
                        if viewController is PaymentCardViewController {
                            navController.popToViewController(viewController, animated: true)
                            return
                        }
                    }
                } else {
                    // If PaymentCardViewController doesn't exist, go back to payment list
                    navController.popToRootViewController(animated: true)
                }
            }

        case .processing, .requiresAction:
            // Cancel pending payment - use callback or dismiss
            if let dismissCallback = dismissPaymentSheetCompletion {
                dismissCallback()
            } else {
                dismissPaymentSheet(completion: nil)
            }
        }
    }

    /// Helper method to properly dismiss the payment sheet modal
    private func dismissPaymentSheet(completion: (() -> Void)?) {
        // Method 1: Check if we're in AppNavigationViewController
        if let navController = self.navigationController {
            // The navigation controller or its presenting VC should dismiss the modal
            if navController is AppNavigationViewController {
                // We're in the payment sheet navigation controller
                navController.dismiss(animated: true, completion: completion)
                return
            }
        }

        // Method 2: Find the presented AppNavigationViewController and dismiss it
        if let window = uqpayResolvedWindow,
           let rootVC = window.rootViewController {

            // Find the top presented view controller
            var currentVC = rootVC
            while let presented = currentVC.presentedViewController {
                if presented is AppNavigationViewController {
                    // Found the payment sheet - dismiss it
                    currentVC.dismiss(animated: true, completion: completion)
                    return
                }
                currentVC = presented
            }

            // If AppNavigationViewController not found, dismiss whatever is on top
            if rootVC.presentedViewController != nil {
                rootVC.dismiss(animated: true, completion: completion)
            }
        }
    }

    private func handleDefaultSecondaryAction() {
        // Cancel Payment / Cancel action - dismiss the entire payment sheet
        if let dismissCallback = dismissPaymentSheetCompletion {
            dismissCallback()
        } else {
            dismissPaymentSheet(completion: {
                // Notify about cancellation if needed
                NotificationCenter.default.post(
                    name: Notification.Name("PaymentSheetDidCancel"),
                    object: nil
                )
            })
        }
    }

    // MARK: - Public Methods

    /// Update the configuration and refresh the UI
    public func updateConfiguration(_ newConfiguration: PaymentStatusConfiguration, animated: Bool = true) {
        self.configuration = newConfiguration

        if animated {
            UIView.animate(withDuration: 0.3) {
                self.configureForStatus()
            }
        } else {
            configureForStatus()
        }
    }

    /// Convenience method to transition from pending to success/failed
    public func transitionFromPending(to newStatus: PaymentStatus,
                                       transactionId: String? = nil,
                                       errorCode: String? = nil,
                                       message: String? = nil) {
        guard configuration.status == .processing || configuration.status == .requiresAction || configuration.status == .pending else { return }

        // Stop the activity indicator with a fade animation
        UIView.animate(withDuration: 0.3, animations: {
            self.activityIndicator.alpha = 0
        }) { _ in
            self.activityIndicator.stopAnimating()
            self.activityIndicator.isHidden = true
        }

        let newConfig: PaymentStatusConfiguration
        switch newStatus {
        case .succeeded:
            newConfig = PaymentStatusConfiguration(
                status: .succeeded,
                message: message,
                amount: configuration.amount,
                transactionId: transactionId
            )
        case .failed:
            newConfig = PaymentStatusConfiguration(
                status: .failed,
                message: message,
                errorCode: errorCode
            )
        default:
            // Pending and cancelled keep the reference data. Dropping it here
            // left "your payment is pending" screens with no transaction id
            // for the customer to quote.
            newConfig = PaymentStatusConfiguration(
                status: newStatus,
                message: message,
                amount: configuration.amount,
                transactionId: transactionId ?? configuration.transactionId
            )
        }

        updateConfiguration(newConfig, animated: true)
    }

    // MARK: - Payment Verification

    /// Fired when this screen's own refresh poll observes a terminal status.
    ///
    /// This screen is deliberately dumb about delegates — the owning flow
    /// (card or wallet) holds the exactly-once guards, so it supplies the
    /// handler and reports through them. Without this hook, a customer
    /// tapping Refresh could watch the payment succeed while the merchant's
    /// app never heard about it.
    var refreshOutcomeHandler: ((PaymentIntentCreateResponse) -> Void)?

    /// Arms the Refresh button for a parked payment without starting a poll.
    ///
    /// `verifyPaymentStatus` polls immediately; a timeout screen that says
    /// "Refresh to check the status" wants the button live but the polling
    /// left to the customer.
    func enableRefresh(paymentIntentId: String,
                       onOutcome: ((PaymentIntentCreateResponse) -> Void)? = nil) {
        self.paymentIntentId = paymentIntentId
        if let onOutcome {
            self.refreshOutcomeHandler = onOutcome
        }
        showRefreshButton()
    }

    /// Verifies payment status by calling API and updates UI accordingly
    /// - Parameters:
    ///   - paymentIntentId: The payment intent ID to verify
    ///   - showLoading: Whether to show loading state during verification
    public func verifyPaymentStatus(paymentIntentId: String, showLoading: Bool = false) {
        // Store payment intent ID for future refresh
        self.paymentIntentId = paymentIntentId

        // Cancel any existing polling task
        pollingTask?.cancel()
        pollingAttempts = 0

        // Show loading state if requested
        if showLoading {
            updateConfiguration(PaymentStatusConfiguration(
                status: .processing,
                message: UqpayLocalized("Checking payment status...")
            ), animated: true)
        }

        // Start polling
        startPolling(paymentIntentId: paymentIntentId)
    }

    /// Starts polling for payment status
    private func startPolling(paymentIntentId: String) {
        pollingTask = Task { @MainActor in
            do {
                let apiClient = try ApiClient.forConfiguredEnvironment()
                let response = try await apiClient.getPaymentIntentById(paymentIntentId)

                handlePaymentStatusResponse(response)

            } catch {
                // A cancelled poll reports nothing: its screen is going away,
                // or a foreground nudge already started a replacement — either
                // way, consuming an attempt or parking the UI on "pending"
                // would be acting on an outcome nobody observed.
                if Task.isCancelled { return }

                UqpayLogger.shared.error("Failed to fetch payment status: \(error.localizedDescription)")

                pollingAttempts += 1

                if pollingAttempts < 2 {
                    // Retry after 30 seconds
                    try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds

                    // Check if task was cancelled
                    if !Task.isCancelled {
                        startPolling(paymentIntentId: paymentIntentId)
                    }
                } else {
                    // Max attempts reached, show pending status with refresh button
                    showPendingWithRefresh()
                }
            }
        }
    }

    /// Handles the payment status response from API
    /// Statuses: REQUIRES_PAYMENT_METHOD, REQUIRES_CUSTOMER_ACTION, REQUIRES_CAPTURE, PENDING, SUCCEEDED, CANCELLED, FAILED
    /// Internal rather than private so tests can drive the refresh-outcome hook.
    func handlePaymentStatusResponse(_ response: PaymentIntentCreateResponse) {
        let status = response.intentStatus.uppercased()

        // Terminal statuses reach the owning flow before the UI moves — the
        // merchant hears about an outcome this screen discovered.
        switch status {
        case "SUCCEEDED", "FAILED", "CANCELLED", "REQUIRES_PAYMENT_METHOD":
            refreshOutcomeHandler?(response)
        default:
            break
        }

        switch status {
        case "SUCCEEDED":
            let newConfig = PaymentStatusConfiguration(
                status: .succeeded,
                message: UqpayLocalized("Your payment has been processed successfully."),
                amount: configuration.amount,
                transactionId: response.paymentIntentId
            )
            updateConfiguration(newConfig, animated: true)

        case "FAILED":
            let newConfig = PaymentStatusConfiguration(
                status: .failed,
                message: UqpayLocalized("Payment failed. Please try again with a different payment method."),
                errorCode: "PAYMENT_FAILED"
            )
            updateConfiguration(newConfig, animated: true)

        case "CANCELLED":
            let newConfig = PaymentStatusConfiguration(
                status: .failed,
                message: UqpayLocalized("Payment was cancelled."),
                errorCode: "PAYMENT_CANCELLED"
            )
            updateConfiguration(newConfig, animated: true)

        case "REQUIRES_PAYMENT_METHOD":
            // Payment requires a new payment method (previous one failed/declined)
            let newConfig = PaymentStatusConfiguration(
                status: .failed,
                message: UqpayLocalized("Payment method was declined. Please try again with a different card."),
                errorCode: "REQUIRES_PAYMENT_METHOD"
            )
            updateConfiguration(newConfig, animated: true)

        case "REQUIRES_CUSTOMER_ACTION":
            // Still waiting for customer action (3DS/authentication)
            pollingAttempts += 1

            if pollingAttempts < 2 {
                // Retry after 30 seconds to check if authentication completed
                pollingTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                    if !Task.isCancelled {
                        startPolling(paymentIntentId: self.paymentIntentId ?? "")
                    }
                }
            } else {
                // Max attempts reached, show pending with message about authentication
                let newConfig = PaymentStatusConfiguration(
                    status: .pending,
                    message: UqpayLocalized("Waiting for authentication to complete. Please complete the verification if prompted."),
                    amount: configuration.amount,
                    transactionId: paymentIntentId
                )
                updateConfiguration(newConfig, animated: true)
                showRefreshButton()
            }

        case "REQUIRES_CAPTURE":
            // Payment authorized but not yet captured
            let newConfig = PaymentStatusConfiguration(
                status: .pending,
                message: UqpayLocalized("Payment authorized. Awaiting confirmation from merchant."),
                amount: configuration.amount,
                transactionId: response.paymentIntentId
            )
            updateConfiguration(newConfig, animated: true)
            showRefreshButton()

        case "PENDING":
            pollingAttempts += 1

            if pollingAttempts < 2 {
                // Retry after 30 seconds
                pollingTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                    if !Task.isCancelled {
                        startPolling(paymentIntentId: self.paymentIntentId ?? "")
                    }
                }
            } else {
                // Max attempts reached, show pending with refresh button
                showPendingWithRefresh()
            }

        default:
            // Unknown status, show pending with refresh
            UqpayLogger.shared.error("Unknown payment intent status: \(status)")
            showPendingWithRefresh()
        }
    }

    /// Shows the refresh button
    private func showRefreshButton() {
        refreshButton.isHidden = false
        UIView.animate(withDuration: 0.3) {
            self.refreshButton.alpha = 1
        }
    }

    /// Shows pending status with refresh button
    private func showPendingWithRefresh() {
        let newConfig = PaymentStatusConfiguration(
            status: .pending,
            message: UqpayLocalized("Your payment is being processed. You will be notified once it is cleared."),
            amount: configuration.amount,
            transactionId: paymentIntentId
        )
        updateConfiguration(newConfig, animated: true)

        // Show refresh button
        refreshButton.isHidden = false
        UIView.animate(withDuration: 0.3) {
            self.refreshButton.alpha = 1
        }
    }
}

// MARK: - Convenience Factory Methods

extension PaymentCardStatusViewController {

    /// Create a success status view controller
    public static func success(amount: String, transactionId: String, completion: (() -> Void)? = nil) -> PaymentCardStatusViewController {
        let config = PaymentStatusConfiguration.success(amount: amount, transactionId: transactionId)
        let vc = PaymentCardStatusViewController(configuration: config)
        vc.primaryActionHandler = completion
        return vc
    }

    /// Create a failed status view controller
    public static func failed(errorCode: String? = nil,
                              message: String? = nil,
                              onRetry: (() -> Void)? = nil,
                              onCancel: (() -> Void)? = nil) -> PaymentCardStatusViewController {
        let config = PaymentStatusConfiguration.failed(errorCode: errorCode, message: message)
        let vc = PaymentCardStatusViewController(configuration: config)
        vc.primaryActionHandler = onRetry
        vc.secondaryActionHandler = onCancel
        return vc
    }

    /// Create a pending status view controller (processing state)
    public static func processing(message: String? = nil, onCancel: (() -> Void)? = nil) -> PaymentCardStatusViewController {
        let config = PaymentStatusConfiguration(status: .processing, message: message)
        let vc = PaymentCardStatusViewController(configuration: config)
        vc.primaryActionHandler = onCancel
        return vc
    }

    /// Create a pending clearance status view controller (final state, awaiting confirmation)
    public static func pending(amount: String? = nil,
                               transactionId: String? = nil,
                               message: String? = nil,
                               completion: (() -> Void)? = nil) -> PaymentCardStatusViewController {
        let config = PaymentStatusConfiguration(
            status: .pending,
            message: message,
            amount: amount,
            transactionId: transactionId
        )
        let vc = PaymentCardStatusViewController(configuration: config)
        vc.primaryActionHandler = completion
        return vc
    }
}
