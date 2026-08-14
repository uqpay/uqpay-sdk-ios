//
//  CustomAlertViewController.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 19/08/2025.
//

import UIKit

class CustomAlertViewController: UIViewController {
    
    // MARK: - Properties
    private let alertTitle: String
    private let alertMessage: String
    private let buttonTitle: String
    private let onDismiss: (() -> Void)?
    private let appearance: PaymentSheet.Appearance
    private let tapDelegate = BackgroundTapDelegate()

    // MARK: - UI Components
    private lazy var backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    /// At accessibility text sizes the card grows past the height of a small
    /// phone — and past any phone in landscape — pushing the only dismiss
    /// button off-screen. Scrolling keeps it reachable; the card still sits
    /// centred whenever it fits, which is every default-text-size case.
    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.accessibilityIdentifier = "uqpay.alert.scroll"
        scrollView.backgroundColor = .clear
        // `.never`, unlike every other scroll view in the SDK. This one overlays
        // the whole screen rather than sitting under a nav bar, and the card is
        // centred on its content: adjusting for the safe area would offset that
        // centre by the inset and leave the card visibly low on a notched phone.
        // The 24pt breathing room the card needs when it does scroll comes from
        // its own padding constraints instead.
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private lazy var scrollContentView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var alertContainer: UIView = {
        let view = UIView()
        view.accessibilityIdentifier = "uqpay.alert.card"
        view.backgroundColor = appearance.alertBackgroundColor
        view.layer.cornerRadius = 28
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.layer.shadowRadius = 24
        view.layer.shadowOpacity = 0.15
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = alertTitle
        label.font = UqpayFonts.scaled(size: 20, weight: .semibold, textStyle: .title3)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = appearance.alertTitleColor
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.text = alertMessage
        label.font = UqpayFonts.scaled(size: 16, weight: .regular, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = appearance.alertMessageColor
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(buttonTitle, for: .normal)
        button.setTitleColor(appearance.payButtonTextColor, for: .normal)
        button.titleLabel?.font = UqpayFonts.scaled(size: 18, weight: .semibold, textStyle: .headline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.backgroundColor = appearance.payButtonColor
        button.layer.cornerRadius = 25
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Initialization
    public init(title: String, message: String = "", buttonTitle: String = "OK", appearance: PaymentSheet.Appearance = PaymentSheet.Appearance(), onDismiss: (() -> Void)? = nil) {
        self.alertTitle = title
        self.alertMessage = message
        self.buttonTitle = buttonTitle
        self.appearance = appearance
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        
        // Setup modal presentation
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        // Presented modally, so the nav controller's style is not inherited:
        // apply the merchant's choice directly.
        overrideUserInterfaceStyle = appearance.userInterfaceStyle
        setupUI()
        setupGestures()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        animateIn()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .clear
        
        // Add subviews
        view.addSubview(backgroundView)
        view.addSubview(scrollView)
        scrollView.addSubview(scrollContentView)
        scrollContentView.addSubview(alertContainer)
        alertContainer.addSubview(titleLabel)
        
        // Only add message label if message is not empty
        if !alertMessage.isEmpty {
            alertContainer.addSubview(messageLabel)
        }
        
        alertContainer.addSubview(actionButton)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        // Keeps the content exactly one screen tall while the card fits, so the
        // card reads as centred; `defaultLow` lets the required minimum-height
        // and padding constraints below win once the card outgrows the screen.
        let collapseToScreenHeight = scrollContentView.heightAnchor.constraint(
            equalTo: scrollView.frameLayoutGuide.heightAnchor
        )
        collapseToScreenHeight.priority = .defaultLow

        NSLayoutConstraint.activate([
            // Background view
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Scroll view over the dimming layer
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Content guide drives the scrollable extent; frame guide drives width.
            scrollContentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            scrollContentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            scrollContentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            scrollContentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            scrollContentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            scrollContentView.heightAnchor.constraint(
                greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor
            ),
            collapseToScreenHeight,

            // Alert container
            alertContainer.centerXAnchor.constraint(equalTo: scrollContentView.centerXAnchor),
            alertContainer.centerYAnchor.constraint(equalTo: scrollContentView.centerYAnchor),
            alertContainer.topAnchor.constraint(greaterThanOrEqualTo: scrollContentView.topAnchor, constant: 24),
            alertContainer.bottomAnchor.constraint(lessThanOrEqualTo: scrollContentView.bottomAnchor, constant: -24),
            alertContainer.leadingAnchor.constraint(greaterThanOrEqualTo: scrollContentView.leadingAnchor, constant: 32),
            alertContainer.trailingAnchor.constraint(lessThanOrEqualTo: scrollContentView.trailingAnchor, constant: -32),
            alertContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 320),

            // Title label
            titleLabel.topAnchor.constraint(equalTo: alertContainer.topAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: alertContainer.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: alertContainer.trailingAnchor, constant: -24)
        ])
        
        // Conditional constraints based on whether message exists
        if !alertMessage.isEmpty {
            NSLayoutConstraint.activate([
                // Message label
                messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
                messageLabel.leadingAnchor.constraint(equalTo: alertContainer.leadingAnchor, constant: 24),
                messageLabel.trailingAnchor.constraint(equalTo: alertContainer.trailingAnchor, constant: -24),
                
                // Action button
                actionButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 32),
                actionButton.leadingAnchor.constraint(equalTo: alertContainer.leadingAnchor, constant: 24),
                actionButton.trailingAnchor.constraint(equalTo: alertContainer.trailingAnchor, constant: -24),
                actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
                actionButton.bottomAnchor.constraint(equalTo: alertContainer.bottomAnchor, constant: -24)
            ])
        } else {
            NSLayoutConstraint.activate([
                // Action button (directly below title when no message)
                actionButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 32),
                actionButton.leadingAnchor.constraint(equalTo: alertContainer.leadingAnchor, constant: 24),
                actionButton.trailingAnchor.constraint(equalTo: alertContainer.trailingAnchor, constant: -24),
                actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
                actionButton.bottomAnchor.constraint(equalTo: alertContainer.bottomAnchor, constant: -24)
            ])
        }
    }
    
    private func setupGestures() {
        // The scroll view now covers the dimming layer, so a tap outside the
        // card lands on the scroll view rather than on `backgroundView`. The
        // recogniser goes there instead, and `tapDelegate` keeps taps that hit
        // the card itself (the dismiss button) away from it.
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.delegate = tapDelegate
        tapDelegate.alertContainer = alertContainer
        scrollView.addGestureRecognizer(tapGesture)
    }

    /// Kept off the view controller itself so the internal class does not grow
    /// a `UIGestureRecognizerDelegate` conformance that callers could see.
    private final class BackgroundTapDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var alertContainer: UIView?

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
        ) -> Bool {
            guard let alertContainer else { return true }
            return !alertContainer.bounds.contains(touch.location(in: alertContainer))
        }
    }
    
    // MARK: - Animations
    private func animateIn() {
        // Initial state
        alertContainer.alpha = 0
        alertContainer.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        backgroundView.alpha = 0
        
        // Animate in
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            self.alertContainer.alpha = 1
            self.alertContainer.transform = .identity
            self.backgroundView.alpha = 1
        }
    }
    
    private func animateOut(completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
            self.alertContainer.alpha = 0
            self.alertContainer.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            self.backgroundView.alpha = 0
        } completion: { _ in
            completion()
        }
    }
    
    // MARK: - Actions
    @objc private func actionButtonTapped() {
        dismiss()
    }
    
    @objc private func backgroundTapped() {
        dismiss()
    }
    
    private func dismiss() {
        animateOut { [weak self] in
            self?.dismiss(animated: false) {
                self?.onDismiss?()
            }
        }
    }
    
    // MARK: - Public Methods
    public static func show(in viewController: UIViewController, 
                          title: String, 
                          message: String = "", 
                          buttonTitle: String = "OK", 
                          appearance: PaymentSheet.Appearance = PaymentSheet.Appearance(), 
                          onDismiss: (() -> Void)? = nil) {
        let alert = CustomAlertViewController(title: title, message: message, buttonTitle: buttonTitle, appearance: appearance, onDismiss: onDismiss)
        viewController.present(alert, animated: true)
    }
    
    // Convenience method for success messages
    public static func showSuccess(in viewController: UIViewController,
                                 title: String,
                                 message: String = "",
                                 appearance: PaymentSheet.Appearance = PaymentSheet.Appearance(),
                                 onDismiss: (() -> Void)? = nil) {
        show(in: viewController, title: title, message: message, buttonTitle: "OK", appearance: appearance, onDismiss: onDismiss)
    }
    
    // Convenience method for error messages  
    public static func showError(in viewController: UIViewController,
                               title: String,
                               message: String = "",
                               appearance: PaymentSheet.Appearance = PaymentSheet.Appearance(),
                               onDismiss: (() -> Void)? = nil) {
        show(in: viewController, title: title, message: message, buttonTitle: "OK", appearance: appearance, onDismiss: onDismiss)
    }
}

// MARK: - UIViewController Extension
public extension UIViewController {
    func showCustomAlert(title: String, 
                        message: String = "", 
                        buttonTitle: String = "OK", 
                        appearance: PaymentSheet.Appearance = PaymentSheet.Appearance(), 
                        onDismiss: (() -> Void)? = nil) {
        CustomAlertViewController.show(in: self, title: title, message: message, buttonTitle: buttonTitle, appearance: appearance, onDismiss: onDismiss)
    }
    
    func showSuccessAlert(title: String, 
                         message: String = "", 
                         appearance: PaymentSheet.Appearance = PaymentSheet.Appearance(), 
                         onDismiss: (() -> Void)? = nil) {
        CustomAlertViewController.showSuccess(in: self, title: title, message: message, appearance: appearance, onDismiss: onDismiss)
    }
    
    func showErrorAlert(title: String, 
                       message: String = "", 
                       appearance: PaymentSheet.Appearance = PaymentSheet.Appearance(), 
                       onDismiss: (() -> Void)? = nil) {
        CustomAlertViewController.showError(in: self, title: title, message: message, appearance: appearance, onDismiss: onDismiss)
    }
}
