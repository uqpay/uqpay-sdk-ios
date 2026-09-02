//
//  ViewController.swift
//  UIKitExample
//
//  Created by UQPAY on 18/09/2025.
//

import UIKit
import UqpayCore
import UqpayPayments
import UqpayPaymentSheet
import Combine

class ViewController: UIViewController {

    // MARK: - Properties
    private var viewModel = ContentViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var paymentSheet: PaymentSheet?

    // MARK: - UI Components
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        return scrollView
    }()

    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .fill
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let environmentSegmentedControl: UISegmentedControl = {
        // The SDK exposes exactly the two merchant environments.
        let items = ["Sandbox", "Production"]
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0 // Sandbox — the environment the docs' test cards live in
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private var selectedEnvironment: UqpayEnvironment {
        return environmentSegmentedControl.selectedSegmentIndex == 1 ? .productionMode : .sandboxMode
    }

    private let environmentLabel: UILabel = {
        let label = UILabel()
        label.text = "Environment"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = UIColor(red: 115/255.0, green: 115/255.0, blue: 115/255.0, alpha: 1.0) // Gray text
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let buyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Buy", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let buyCardOnlyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Buy - Card Only", for: .normal)
        button.backgroundColor = .systemGreen
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let paymentListV2Button: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Open Cart", for: .normal)
        button.backgroundColor = .systemPurple
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let resultLabel: UILabel = {
        let label = UILabel()
        label.text = ""
        label.font = .systemFont(ofSize: 14)
        label.textColor = UIColor(red: 10/255.0, green: 10/255.0, blue: 10/255.0, alpha: 1.0) // Dark text
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        // Force light mode for consistent appearance across all iOS versions
        overrideUserInterfaceStyle = .light
        setupUI()
        setupActions()
        bindViewModel()
        initializeSDK()
    }

    // MARK: - Setup Methods
    private func setupUI() {
        view.backgroundColor = .white
        title = "UQPAY iOS SDK Example"

        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentStackView)
        view.addSubview(loadingIndicator)

        // Environment section
        let environmentContainer = UIView()
        environmentContainer.addSubview(environmentLabel)
        environmentContainer.addSubview(environmentSegmentedControl)

        // Add views to stack
        contentStackView.addArrangedSubview(environmentContainer)
        contentStackView.addArrangedSubview(buyButton)
        contentStackView.addArrangedSubview(buyCardOnlyButton)
        contentStackView.addArrangedSubview(paymentListV2Button)
        contentStackView.addArrangedSubview(resultLabel)

        // Add spacing
        contentStackView.setCustomSpacing(40, after: environmentContainer)
        contentStackView.setCustomSpacing(30, after: paymentListV2Button)

        // Setup constraints
        NSLayoutConstraint.activate([
            // ScrollView
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            // Content Stack
            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),

            // Environment Label and Control
            environmentLabel.topAnchor.constraint(equalTo: environmentContainer.topAnchor),
            environmentLabel.leadingAnchor.constraint(equalTo: environmentContainer.leadingAnchor),
            environmentLabel.trailingAnchor.constraint(equalTo: environmentContainer.trailingAnchor),

            environmentSegmentedControl.topAnchor.constraint(equalTo: environmentLabel.bottomAnchor, constant: 8),
            environmentSegmentedControl.leadingAnchor.constraint(equalTo: environmentContainer.leadingAnchor),
            environmentSegmentedControl.trailingAnchor.constraint(equalTo: environmentContainer.trailingAnchor),
            environmentSegmentedControl.bottomAnchor.constraint(equalTo: environmentContainer.bottomAnchor),
            environmentSegmentedControl.heightAnchor.constraint(equalToConstant: 32),

            // Button Heights
            buyButton.heightAnchor.constraint(equalToConstant: 50),
            buyCardOnlyButton.heightAnchor.constraint(equalToConstant: 50),
            paymentListV2Button.heightAnchor.constraint(equalToConstant: 50),

            // Loading Indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupActions() {
        environmentSegmentedControl.addTarget(self, action: #selector(environmentChanged), for: .valueChanged)
        buyButton.addTarget(self, action: #selector(buyButtonTapped), for: .touchUpInside)
        buyCardOnlyButton.addTarget(self, action: #selector(buyCardOnlyButtonTapped), for: .touchUpInside)
        paymentListV2Button.addTarget(self, action: #selector(paymentListV2ButtonTapped), for: .touchUpInside)
    }

    private func bindViewModel() {
        // Observe loading state
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.updateLoadingState(isLoading)
            }
            .store(in: &cancellables)

        // Observe result text
        viewModel.$resultText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.resultLabel.text = text
            }
            .store(in: &cancellables)
    }

    private func updateLoadingState(_ isLoading: Bool) {
        if isLoading {
            loadingIndicator.startAnimating()
            buyButton.isEnabled = false
            buyCardOnlyButton.isEnabled = false
            paymentListV2Button.isEnabled = false
            buyButton.alpha = 0.6
            buyCardOnlyButton.alpha = 0.6
            paymentListV2Button.alpha = 0.6
        } else {
            loadingIndicator.stopAnimating()
            buyButton.isEnabled = true
            buyCardOnlyButton.isEnabled = true
            paymentListV2Button.isEnabled = true
            buyButton.alpha = 1.0
            buyCardOnlyButton.alpha = 1.0
            paymentListV2Button.alpha = 1.0
        }
    }

    private func initializeSDK() {
        viewModel.initializeSDK(environment: selectedEnvironment)
    }

    // MARK: - Actions
    @objc private func environmentChanged() {
        initializeSDK()
    }

    @objc private func buyButtonTapped() {
        startCheckout(allowedMethods: nil)
    }

    @objc private func buyCardOnlyButtonTapped() {
        let card = PaymentMethod(id: "card", type: .card, name: "Card", icon: "creditcard")
        startCheckout(allowedMethods: [card])
    }

    /// Creates an intent, then presents the sheet for it.
    ///
    /// A fresh intent is created per attempt. Reusing one that has already been
    /// paid returns a status other than `REQUIRES_PAYMENT_METHOD`.
    private func startCheckout(allowedMethods: [PaymentMethod]?) {
        // No credentials for the selected environment → say so up front
        // instead of quietly running against a different backend.
        guard viewModel.isConfigured else {
            showAlert(
                title: "Configure \(selectedEnvironment.displayName) first",
                message: DemoConfiguration.setupInstructions(for: selectedEnvironment)
            )
            return
        }

        // Production charges real cards. Make starting it a decision, not a slip.
        if selectedEnvironment == .productionMode {
            let alert = UIAlertController(
                title: "Production payment",
                message: "This runs against the live API and moves real money. Continue?",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Continue", style: .destructive) { [weak self] _ in
                self?.runCheckout(allowedMethods: allowedMethods)
            })
            present(alert, animated: true)
            return
        }

        runCheckout(allowedMethods: allowedMethods)
    }

    private func runCheckout(allowedMethods: [PaymentMethod]?) {
        Task { @MainActor in
            do {
                let intent = try await viewModel.prepareCheckout(
                    amount: DemoConfiguration.demoAmount,
                    description: "Demo order"
                )
                guard let clientSecret = intent.clientSecret else {
                    viewModel.resultText = "The intent came back without a client secret."
                    return
                }
                presentPaymentSheet(clientSecret: clientSecret, paymentMethods: allowedMethods)
            } catch {
                viewModel.resultText = error.localizedDescription
            }
        }
    }

    @objc private func paymentListV2ButtonTapped() {
        showCartViewController()
    }

    private func showCartViewController() {
        let cartVC = CartViewController()
        // Pass the viewModel so cart can use the same environment
        cartVC.viewModel = self.viewModel
        let navController = UINavigationController(rootViewController: cartVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }

    private func presentPaymentSheet(clientSecret: String, paymentMethods: [PaymentMethod]?) {
        // No environment override: the sheet follows UqpayConfiguration.shared,
        // which initializeSDK points at the selected environment. One source of
        // truth — the sheet can never disagree with the intent it pays.
        let configuration = PaymentSheet.Configuration(
            merchantDisplayName: "UQPAY Demo Store"
        )

        // `primaryColor` drives the pay button, selection highlights, and the
        // loading indicator. The SDK default is violet (#7C4DFF).
        let appearance = PaymentSheet.Appearance(primaryColor: .systemBlue)

        paymentSheet = PaymentSheet(configuration: configuration, appearance: appearance)

        // Receives every payment outcome — success, failure, cancellation.
        // This is the only delegate the SDK calls.
        paymentSheet?.paymentDelegate = self

        Task { @MainActor in
            paymentSheet?.loadViewController { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let viewController):
                    self.present(viewController, animated: true)
                case .failure(let error):
                    self.showAlert(title: "Error", message: error.localizedDescription)
                }
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - PaymentDelegate Implementation
extension ViewController: PaymentDelegate {
    func paymentSheet(_ paymentSheet: PaymentSheet, didCompleteWithResult result: PaymentResult) {
        // `amountDecimal` is the API's amount parsed exactly; nil only if the
        // API value could not be parsed, which the SDK logs.
        let amount = result.amountDecimal.map { "\($0)" } ?? "unknown"
        print("Payment succeeded: \(result.paymentIntentId) (\(result.paymentMethodType)) \(amount) \(result.currency)")

        DispatchQueue.main.async { [weak self] in
            self?.viewModel.resultText = "✅ Payment Success! (\(result.paymentMethodType))"
            self?.showAlert(
                title: "Payment Successful",
                message: "Payment ID: \(result.paymentIntentId)\n" +
                        "Method: \(result.paymentMethodType)\n" +
                        "Amount: \(amount) \(result.currency)"
            )
        }
    }

    func paymentSheet(_ paymentSheet: PaymentSheet, didFailWithError error: PaymentError) {
        print("Payment failed: \(error.code.rawValue) - \(error.message)")

        DispatchQueue.main.async { [weak self] in
            self?.viewModel.resultText = "❌ Payment Failed: \(error.message)"

            var message = error.message
            if let suggestion = error.recoverySuggestion {
                message += "\n\nSuggestion: \(suggestion)"
            }

            self?.showAlert(title: "Payment Failed", message: message)
        }
    }

    /// Fires once when the customer leaves without paying, and never alongside
    /// a success or failure for the same payment. Release any cart hold here.
    func paymentSheetDidCancel(_ paymentSheet: PaymentSheet) {
        print("Payment cancelled by user")

        DispatchQueue.main.async { [weak self] in
            self?.viewModel.resultText = "Payment Cancelled"
            self?.paymentSheet = nil
        }
    }

    func paymentSheet(_ paymentSheet: PaymentSheet, requiresAction action: RequiredAction) {
        switch action {
        case .authenticate3DS(let url):
            // In production, you would handle 3DS authentication here
            print("Action required: 3DS authentication at \(url)")

        case .scanQRCode(let qrCodeUrl):
            // In production, you would display the QR code here
            print("Action required: scan QR code at \(qrCodeUrl)")

        case .displayBankDetails(let details):
            // In production, you would display bank details here
            print("Action required: bank transfer of \(details.amount) \(details.currency)")

        case .verifyOTP:
            // In production, you would show OTP input here
            print("Action required: OTP verification")

        case .custom(let type, _):
            print("Action required: custom action \(type)")
        }
    }

}
