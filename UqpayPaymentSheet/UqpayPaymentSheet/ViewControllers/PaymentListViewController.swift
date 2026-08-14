//
//  PaymentListViewController.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 14/08/2025.
//

import Foundation
import UIKit
import UqpayPayments
import UqpayCore
import Combine

final class PaymentListViewController: UIViewController {

    // MARK: - Properties
    private let appearance: PaymentSheet.Appearance
    private let configuration: PaymentSheet.Configuration
    private var paymentMethods: [PaymentMethod] = []
    private var selectedPaymentMethod: PaymentMethod?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Delegate
    public weak var paymentDelegate: PaymentDelegate?

    /// The sheet that presented this list. Payment callbacks carry this
    /// instance, and its `paymentDelegate` is used when none is set here.
    public weak var paymentSheet: PaymentSheet?

    // MARK: - UI Components
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Payment methods")
        label.font = UqpayFonts.scaled(size: 20, weight: .semibold, textStyle: .title3)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textPrimary // Dark text #0A0A0A
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UqpayColors.surface
        view.layer.cornerRadius = 16
        view.layer.borderWidth = 1
        view.layer.borderColor = UqpayColors.border.cgColor
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = UqpayColors.surface
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        table.showsVerticalScrollIndicator = false
        table.isScrollEnabled = false
        table.alwaysBounceVertical = false
        return table
    }()

    private lazy var continueButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(UqpayLocalized("Continue"), for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = appearance.payButtonColor
        button.layer.cornerRadius = 12
        button.titleLabel?.font = UqpayFonts.scaled(size: 17, weight: .medium, textStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        button.alpha = 0.6
        return button
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    // MARK: - Initialization
    public init(appearance: PaymentSheet.Appearance, configuration: PaymentSheet.Configuration) {
        self.appearance = appearance
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Trait Changes

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // Layer colors are plain `CGColor` and do not re-resolve on their own.
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            view.traitCollection.performAsCurrent {
                containerView.layer.borderColor = UqpayColors.border.cgColor
            }
        }
    }

    // MARK: - Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        setupActions()
        fetchPaymentMethods()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        // The card and wallet screens each report their own dismissal, but this
        // is the sheet's root: a customer who opens the sheet, looks at the
        // method list and swipes it away never reaches either of them, and the
        // merchant was left waiting on a callback that never came.
        //
        // Pushing a method's screen on top does not set any of these flags, so
        // choosing a payment method is not mistaken for abandoning one.
        if isMovingFromParent || isBeingDismissed
            || navigationController?.isBeingDismissed == true {
            handleFlowDismissal()
        }
    }

    /// The flow is going away for good. Internal so tests can drive it: the
    /// UIKit flags that trigger it are read-only.
    func handleFlowDismissal() {
        reportCancellationIfUnreported()
    }

    /// Reports a cancellation unless this payment already reported an outcome,
    /// or a screen pushed on top of this one already reported the dismissal.
    /// The gate lives on the sheet, so tearing down several screens at once
    /// still produces exactly one callback.
    private func reportCancellationIfUnreported() {
        guard let sheet = paymentSheet, !sheet.hasReportedOutcome else { return }
        sheet.hasReportedOutcome = true
        (paymentDelegate ?? sheet.paymentDelegate)?.paymentSheetDidCancel(sheet)
    }

    // MARK: - Setup Methods
    private func setupUI() {
        view.backgroundColor = UqpayColors.background

        // Add subviews
        view.addSubview(titleLabel)
        view.addSubview(containerView)
        containerView.addSubview(tableView)
        view.addSubview(continueButton)
        view.addSubview(loadingIndicator)

        // Setup constraints
        NSLayoutConstraint.activate([
            // Title Label
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            // Container View
            containerView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            containerView.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -24),

            // Table View inside Container
            tableView.topAnchor.constraint(equalTo: containerView.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            // Continue Button
            continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            continueButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),

            // Loading Indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PaymentMethodCell.self, forCellReuseIdentifier: PaymentMethodCell.identifier)
    }

    private func setupActions() {
        continueButton.addTarget(self, action: #selector(continueButtonTapped), for: .touchUpInside)
    }

    // MARK: - Data Fetching
    private func fetchPaymentMethods() {
        loadingIndicator.startAnimating()
        containerView.alpha = 0

        Task { @MainActor in
            do {
                let apiClient = try ApiClient.forConfiguredEnvironment()
                // The list, its membership and its order come from the payment
                // intent's available_payment_method_types — nothing client-side.
                self.paymentMethods = try await apiClient.getPaymentMethods()

                if let firstMethod = self.paymentMethods.first {
                    self.selectedPaymentMethod = firstMethod
                    self.updateContinueButton()
                }

                self.tableView.reloadData()

                UIView.animate(withDuration: 0.3) {
                    self.loadingIndicator.stopAnimating()
                    self.containerView.alpha = 1
                }
            } catch {
                self.loadingIndicator.stopAnimating()
                self.showError(String(format: UqpayLocalized("Failed to load payment methods: %@"), error.localizedDescription))
            }
        }
    }

    // MARK: - Actions
    @objc private func continueButtonTapped() {
        guard let selectedMethod = selectedPaymentMethod else { return }

        // Resolved at tap time, so a delegate the merchant set on the sheet
        // after presenting still arrives.
        let delegate = paymentDelegate ?? paymentSheet?.paymentDelegate

        // Card has its own form. Every other implemented method is a
        // merchant-presented QR wallet, and they all run the same screen —
        // the registry supplies the branding and the confirm payload.
        if selectedMethod.type == .card {
            let cardViewController = PaymentCardViewController()
            cardViewController.paymentDelegate = delegate
            cardViewController.paymentSheet = paymentSheet
            navigationController?.pushViewController(cardViewController, animated: true)
            return
        }

        guard let descriptor = WalletQRDescriptor.descriptor(for: selectedMethod.type) else {
            showError(String(format: UqpayLocalized("%@ is not available yet"), selectedMethod.name))
            return
        }

        let walletViewController = WalletQRPaymentViewController(descriptor: descriptor)
        walletViewController.paymentDelegate = delegate
        walletViewController.paymentSheet = paymentSheet
        navigationController?.pushViewController(walletViewController, animated: true)
    }

    private func updateContinueButton() {
        let hasSelection = selectedPaymentMethod != nil
        continueButton.isEnabled = hasSelection
        continueButton.alpha = hasSelection ? 1.0 : 0.6
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: UqpayLocalized("Error"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: UqpayLocalized("OK"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension PaymentListViewController: UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return paymentMethods.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: PaymentMethodCell.identifier, for: indexPath) as? PaymentMethodCell else {
            return UITableViewCell()
        }

        let method = paymentMethods[indexPath.row]
        let isSelected = selectedPaymentMethod?.id == method.id
        let isLastRow = indexPath.row == paymentMethods.count - 1
        cell.configure(with: method, isSelected: isSelected, showSeparator: !isLastRow)

        return cell
    }
}

// MARK: - UITableViewDelegate
extension PaymentListViewController: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        selectedPaymentMethod = paymentMethods[indexPath.row]
        updateContinueButton()
        tableView.reloadData()
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // Scales with the user's text size so larger type is not clipped.
        return UIFontMetrics(forTextStyle: .body).scaledValue(for: 64)
    }
}

// MARK: - PaymentMethodCell
private class PaymentMethodCell: UITableViewCell {
    static let identifier = "PaymentMethodCell"

    private let radioButton: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 10
        view.layer.borderWidth = 2
        view.layer.borderColor = UIColor.systemGray3.cgColor
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let radioInnerCircle: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 5
        view.backgroundColor = UIColor.systemBlue
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UqpayFonts.scaled(size: 17, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textPrimary // Dark text #0A0A0A
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let separatorView: UIView = {
        let view = UIView()
        view.backgroundColor = UqpayColors.border
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // The radio ring is a `CGColor`; re-resolve it for the current mode.
        // `radioInnerCircle.isHidden` mirrors the selection state set in
        // `configure(with:isSelected:showSeparator:)`.
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            traitCollection.performAsCurrent {
                radioButton.layer.borderColor = radioInnerCircle.isHidden
                    ? UIColor.systemGray3.cgColor
                    : UIColor.systemBlue.cgColor
            }
        }
    }

    private func setupCell() {
        selectionStyle = .none
        backgroundColor = UqpayColors.surface

        contentView.addSubview(radioButton)
        radioButton.addSubview(radioInnerCircle)
        contentView.addSubview(iconImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(separatorView)

        NSLayoutConstraint.activate([
            // Radio Button
            radioButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            radioButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            radioButton.widthAnchor.constraint(equalToConstant: 20),
            radioButton.heightAnchor.constraint(equalToConstant: 20),

            // Radio Inner Circle
            radioInnerCircle.centerXAnchor.constraint(equalTo: radioButton.centerXAnchor),
            radioInnerCircle.centerYAnchor.constraint(equalTo: radioButton.centerYAnchor),
            radioInnerCircle.widthAnchor.constraint(equalToConstant: 10),
            radioInnerCircle.heightAnchor.constraint(equalToConstant: 10),

            // Icon
            iconImageView.leadingAnchor.constraint(equalTo: radioButton.trailingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 30),
            iconImageView.heightAnchor.constraint(equalToConstant: 30),

            // Name Label
            nameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Separator
            separatorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    func configure(with paymentMethod: PaymentMethod, isSelected: Bool, showSeparator: Bool) {
        nameLabel.text = paymentMethod.name

        // One VoiceOver element per row: name, button behaviour, selection.
        isAccessibilityElement = true
        accessibilityLabel = paymentMethod.name
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]

        // Set icon - first try to load from bundle, then use system image
        if let image = UIImage(named: paymentMethod.icon, in: UqpayResourceManager.bundle, compatibleWith: nil) {
            iconImageView.image = image
        } else if let systemImage = UIImage(systemName: paymentMethod.icon) {
            iconImageView.image = systemImage
            iconImageView.tintColor = .label
        } else {
            // Fallback to a generic payment icon
            iconImageView.image = UIImage(systemName: "creditcard.fill")
            iconImageView.tintColor = .label
        }

        // Update selection state
        if isSelected {
            radioButton.layer.borderColor = UIColor.systemBlue.cgColor
            radioInnerCircle.isHidden = false
        } else {
            radioButton.layer.borderColor = UIColor.systemGray3.cgColor
            radioInnerCircle.isHidden = true
        }

        // Show/hide separator
        separatorView.isHidden = !showSeparator
    }
}
