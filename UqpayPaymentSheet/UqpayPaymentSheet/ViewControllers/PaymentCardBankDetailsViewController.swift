//
//  PaymentCardBankDetailsViewController.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 08/10/2025.
//

import Foundation
import UIKit

final class PaymentCardBankDetailsViewController: UIViewController {

    // MARK: - Properties
    private let bankName: String
    private let accountNumber: String
    private let routingNumber: String
    public var confirmHandler: (() -> Void)?

    // MARK: - UI Components
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        return scrollView
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Bank Transfer Details")
        label.font = UqpayFonts.scaled(size: 24, weight: .bold, textStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.statusTextPrimary
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Please transfer the payment amount to the following bank account.")
        label.font = UqpayFonts.scaled(size: 16, weight: .regular, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.statusTextSecondary
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let detailsContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = UqpayColors.surface
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = UqpayColors.border.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let bankNameTitleLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Bank Name")
        label.font = UqpayFonts.scaled(size: 14, weight: .medium, textStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.statusTextSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let bankNameValueLabel: UILabel = {
        let label = UILabel()
        label.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.statusTextPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let accountNumberTitleLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Account Number")
        label.font = UqpayFonts.scaled(size: 14, weight: .medium, textStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.statusTextSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let accountNumberValueLabel: UILabel = {
        let label = UILabel()
        label.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.statusTextPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let routingNumberTitleLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Routing Number")
        label.font = UqpayFonts.scaled(size: 14, weight: .medium, textStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.statusTextSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let routingNumberValueLabel: UILabel = {
        let label = UILabel()
        label.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.statusTextPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let divider1: UIView = {
        let view = UIView()
        view.backgroundColor = UqpayColors.border
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let divider2: UIView = {
        let view = UIView()
        view.backgroundColor = UqpayColors.border
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let confirmButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(UqpayLocalized("Confirm"), for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UqpayColors.statusBlue
        button.layer.cornerRadius = 12
        button.titleLabel?.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Initialization
    public init(bankName: String, accountNumber: String, routingNumber: String) {
        self.bankName = bankName
        self.accountNumber = accountNumber
        self.routingNumber = routingNumber
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        setupActions()
        populateData()
    }

    // MARK: - Trait Changes

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // Layer colors are plain `CGColor` and do not re-resolve on their own.
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            view.traitCollection.performAsCurrent {
                detailsContainerView.layer.borderColor = UqpayColors.border.cgColor
            }
        }
    }

    // MARK: - Setup Methods
    private func setupUI() {
        view.backgroundColor = UqpayColors.background

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(titleLabel)
        contentView.addSubview(instructionLabel)
        contentView.addSubview(detailsContainerView)
        contentView.addSubview(confirmButton)

        detailsContainerView.addSubview(bankNameTitleLabel)
        detailsContainerView.addSubview(bankNameValueLabel)
        detailsContainerView.addSubview(divider1)
        detailsContainerView.addSubview(accountNumberTitleLabel)
        detailsContainerView.addSubview(accountNumberValueLabel)
        detailsContainerView.addSubview(divider2)
        detailsContainerView.addSubview(routingNumberTitleLabel)
        detailsContainerView.addSubview(routingNumberValueLabel)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            instructionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            instructionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            instructionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            detailsContainerView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 32),
            detailsContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            detailsContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Bank Name
            bankNameTitleLabel.topAnchor.constraint(equalTo: detailsContainerView.topAnchor, constant: 20),
            bankNameTitleLabel.leadingAnchor.constraint(equalTo: detailsContainerView.leadingAnchor, constant: 20),
            bankNameTitleLabel.trailingAnchor.constraint(equalTo: detailsContainerView.trailingAnchor, constant: -20),

            bankNameValueLabel.topAnchor.constraint(equalTo: bankNameTitleLabel.bottomAnchor, constant: 8),
            bankNameValueLabel.leadingAnchor.constraint(equalTo: detailsContainerView.leadingAnchor, constant: 20),
            bankNameValueLabel.trailingAnchor.constraint(equalTo: detailsContainerView.trailingAnchor, constant: -20),

            divider1.topAnchor.constraint(equalTo: bankNameValueLabel.bottomAnchor, constant: 20),
            divider1.leadingAnchor.constraint(equalTo: detailsContainerView.leadingAnchor, constant: 20),
            divider1.trailingAnchor.constraint(equalTo: detailsContainerView.trailingAnchor, constant: -20),
            divider1.heightAnchor.constraint(equalToConstant: 1),

            // Account Number
            accountNumberTitleLabel.topAnchor.constraint(equalTo: divider1.bottomAnchor, constant: 20),
            accountNumberTitleLabel.leadingAnchor.constraint(equalTo: detailsContainerView.leadingAnchor, constant: 20),
            accountNumberTitleLabel.trailingAnchor.constraint(equalTo: detailsContainerView.trailingAnchor, constant: -20),

            accountNumberValueLabel.topAnchor.constraint(equalTo: accountNumberTitleLabel.bottomAnchor, constant: 8),
            accountNumberValueLabel.leadingAnchor.constraint(equalTo: detailsContainerView.leadingAnchor, constant: 20),
            accountNumberValueLabel.trailingAnchor.constraint(equalTo: detailsContainerView.trailingAnchor, constant: -20),

            divider2.topAnchor.constraint(equalTo: accountNumberValueLabel.bottomAnchor, constant: 20),
            divider2.leadingAnchor.constraint(equalTo: detailsContainerView.leadingAnchor, constant: 20),
            divider2.trailingAnchor.constraint(equalTo: detailsContainerView.trailingAnchor, constant: -20),
            divider2.heightAnchor.constraint(equalToConstant: 1),

            // Routing Number
            routingNumberTitleLabel.topAnchor.constraint(equalTo: divider2.bottomAnchor, constant: 20),
            routingNumberTitleLabel.leadingAnchor.constraint(equalTo: detailsContainerView.leadingAnchor, constant: 20),
            routingNumberTitleLabel.trailingAnchor.constraint(equalTo: detailsContainerView.trailingAnchor, constant: -20),

            routingNumberValueLabel.topAnchor.constraint(equalTo: routingNumberTitleLabel.bottomAnchor, constant: 8),
            routingNumberValueLabel.leadingAnchor.constraint(equalTo: detailsContainerView.leadingAnchor, constant: 20),
            routingNumberValueLabel.trailingAnchor.constraint(equalTo: detailsContainerView.trailingAnchor, constant: -20),

            detailsContainerView.bottomAnchor.constraint(equalTo: routingNumberValueLabel.bottomAnchor, constant: 20),

            // Confirm Button
            confirmButton.topAnchor.constraint(equalTo: detailsContainerView.bottomAnchor, constant: 32),
            confirmButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            confirmButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            confirmButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            confirmButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    private func setupActions() {
        confirmButton.addTarget(self, action: #selector(confirmButtonTapped), for: .touchUpInside)
    }

    private func populateData() {
        bankNameValueLabel.text = bankName
        accountNumberValueLabel.text = accountNumber
        routingNumberValueLabel.text = routingNumber
    }

    // MARK: - Actions
    @objc private func confirmButtonTapped() {
        if let handler = confirmHandler {
            handler()
        } else {
            // This screen has no payment context of its own, so it cannot
            // verify anything. Without a handler the only honest outcome is
            // "pending" — never a fabricated receipt.
            showPendingStatus()
        }
    }

    // MARK: - Helper Methods
    private func showPendingStatus() {
        let pendingViewController = PaymentCardStatusViewController.pending(
            message: UqpayLocalized("We're waiting for your transfer to arrive. You'll be notified once it clears.")
        )

        pendingViewController.primaryActionHandler = { [weak self] in
            // Dismiss the entire payment sheet
            self?.dismissEntirePaymentSheet()
        }

        navigationController?.pushViewController(pendingViewController, animated: true)
    }

    private func dismissEntirePaymentSheet() {
        if let navController = self.navigationController {
            if navController is AppNavigationViewController {
                navController.dismiss(animated: true)
            } else if let presentingVC = navController.presentingViewController {
                presentingVC.dismiss(animated: true)
            }
        }
    }
}
