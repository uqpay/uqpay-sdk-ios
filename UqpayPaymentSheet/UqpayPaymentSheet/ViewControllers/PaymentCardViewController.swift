//
//  PaymentCardViewController.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 14/08/2025.
//

import Foundation
import UIKit
import UqpayPayments
import UqpayCore
import Combine

final class PaymentCardViewController: UIViewController {

    // MARK: - Properties
    private var currentCardBrand: CardBrand = .unknown
    private var cancellables = Set<AnyCancellable>()

    /// Countries offered in the billing picker, and the customer's choice.
    /// `selectedCountry` is the only source of the ISO code sent to the API —
    /// there is no text-to-code guessing anywhere in this screen.
    private let countries = CountryRegion.all
    private var selectedCountry: CountryRegion?

    private lazy var countryPicker: UIPickerView = {
        let picker = UIPickerView()
        picker.dataSource = self
        picker.delegate = self
        return picker
    }()

    /// The guard of the 3DS step currently in flight, if any. The
    /// return-from-bank notification defers to it: the step's own poll
    /// resolves the payment, and resolving twice would double-report to
    /// the merchant.
    private var activeThreeDSGuard: ResolutionGuard?

    /// Intents whose success has already been reported to the merchant.
    /// A late or repeated return-from-bank notification for one of these is
    /// noise — re-polling it would report the same payment twice.
    private var resolvedPaymentIntentIds = Set<String>()

    /// Keeps the idempotency key of a confirm that died in transit, so
    /// tapping Pay again with the same details cannot charge twice.
    private let confirmIdempotency = ConfirmIdempotency()

    /// The bounded follow-up poll running after an indeterminate outcome,
    /// so a payment that settles late is still observed and reported.
    private var reconcileWatchTask: Task<Void, Never>?

    /// The in-flight confirm. Owned so that cancelling the payment — or
    /// starting a new attempt — actually stops the old task instead of
    /// leaving it replaying in the background and reporting stale outcomes.
    /// Internal rather than private so tests can stand up the one state that
    /// cannot otherwise be simulated: a confirm still in the air at the moment
    /// the customer dismisses the sheet.
    var confirmTask: Task<Void, Never>?

    // MARK: - Delegate
    public weak var paymentDelegate: PaymentDelegate?

    /// The sheet this controller reports for; delegate callbacks carry it so
    /// the merchant receives the instance they configured.
    public weak var paymentSheet: PaymentSheet?

    /// The sheet a success or failure is reported against.
    ///
    /// Reading it marks the payment as having reached a reported outcome, so
    /// the same payment can never also be reported as cancelled when the
    /// screens are torn down. Every delegate call in this file goes through
    /// here for exactly that reason.
    private var reportingSheet: PaymentSheet {
        let sheet = paymentSheet ?? PaymentSheet()
        sheet.hasReportedOutcome = true
        return sheet
    }

    /// Reports a cancellation, unless this payment already reported an outcome
    /// or another screen already reported the cancellation.
    private func reportCancellationIfUnreported() {
        guard let sheet = paymentSheet, !sheet.hasReportedOutcome else { return }
        sheet.hasReportedOutcome = true
        paymentDelegate?.paymentSheetDidCancel(sheet)
    }

    /// Tells the merchant the customer has been handed to an external step.
    private func reportRequiredAction(_ action: RequiredAction) {
        guard let sheet = paymentSheet else { return }
        paymentDelegate?.paymentSheet(sheet, requiresAction: action)
    }

    /// Tells the merchant the payment is resting unresolved — the API said
    /// `PENDING`/`PROCESSING`, or a confirm's outcome could not be observed.
    ///
    /// Goes through `reportingSheet` deliberately: an unresolved payment is
    /// not an abandoned one, so tearing the screens down afterwards must not
    /// also report a cancellation. Success and failure reporting is never
    /// gated on this — a settlement observed later is still delivered.
    private func reportPendingToMerchant(
        paymentIntentId: String,
        amount: Double,
        amountDecimal: Decimal? = nil,
        currency: String,
        merchantOrderId: String? = nil,
        status: PaymentStatus
    ) {
        guard let delegate = paymentDelegate else { return }
        delegate.paymentSheet(
            self.reportingSheet,
            paymentDidBecomePending: PaymentResult(
                paymentIntentId: paymentIntentId,
                paymentMethodType: "card",
                status: status,
                amount: amount,
                currency: currency,
                merchantOrderId: merchantOrderId,
                transactionId: paymentIntentId,
                amountDecimal: amountDecimal
            )
        )
    }

    private func reportPendingToMerchant(response: ConfirmPaymentIntentResponse, status: PaymentStatus) {
        let wireAmount = WireAmount.parse(response.amount, paymentIntentId: response.paymentIntentId)
        reportPendingToMerchant(
            paymentIntentId: response.paymentIntentId,
            amount: wireAmount.double,
            amountDecimal: wireAmount.decimal,
            currency: response.currency,
            merchantOrderId: response.merchantOrderId,
            status: status
        )
    }

    // MARK: - UI Components
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.accessibilityIdentifier = "uqpay.card.scroll"
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        return scrollView
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Payment methods")
        label.font = UqpayFonts.scaled(size: 24, weight: .semibold, textStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textPrimary // Tailwind Neutral-950
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let mainContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = UqpayColors.surface
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = UqpayColors.border.cgColor // Tailwind Neutral-200
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let cardIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(systemName: "creditcard")
        imageView.tintColor = UqpayColors.textPrimary // Dark icon
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let cardLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Card")
        label.font = UqpayFonts.scaled(size: 20, weight: .semibold, textStyle: .title3)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textPrimary // Tailwind Neutral-950
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Card Details Section
    private let cardDetailsLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Card details")
        label.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textLabel // Tailwind Neutral-900
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let cardNumberTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = UqpayLocalized("1234 1234 1234 1234")
        textField.keyboardType = .numberPad
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UqpayColors.border.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        textField.leftViewMode = .always
        textField.font = UqpayFonts.scaled(size: 15, weight: .medium, textStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    private let cardBrandContainerView: UIView = {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 52, height: 44))
        view.backgroundColor = .clear
        return view
    }()

    private let cardBrandImageView: UIImageView = {
        let imageView = UIImageView(frame: CGRect(x: 8, y: 11, width: 36, height: 22))
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 4
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UqpayColors.border.cgColor
        imageView.backgroundColor = .white
        imageView.clipsToBounds = true
        return imageView
    }()

    private let expiryTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = UqpayLocalized("MM/YY")
        textField.keyboardType = .numberPad
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UqpayColors.border.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        textField.leftViewMode = .always
        textField.font = UqpayFonts.scaled(size: 15, weight: .medium, textStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    private let cvvTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = UqpayLocalized("CVV")
        textField.keyboardType = .numberPad
        textField.isSecureTextEntry = true
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UqpayColors.border.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        textField.leftViewMode = .always
        textField.font = UqpayFonts.scaled(size: 15, weight: .medium, textStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    // Cardholder Name Section
    private let cardholderLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Cardholder name")
        label.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textLabel // Tailwind Neutral-900
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // First Name Label
    private let firstNameLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("First name")
        label.font = UqpayFonts.scaled(size: 14, weight: .medium, textStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let firstNameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = UqpayLocalized("John")
        textField.keyboardType = .default
        textField.autocapitalizationType = .words
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UqpayColors.border.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        textField.leftViewMode = .always
        textField.font = UqpayFonts.scaled(size: 15, weight: .medium, textStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    // Last Name Label
    private let lastNameLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Last name")
        label.font = UqpayFonts.scaled(size: 14, weight: .medium, textStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let lastNameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = UqpayLocalized("Doe")
        textField.keyboardType = .default
        textField.autocapitalizationType = .words
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UqpayColors.border.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        textField.leftViewMode = .always
        textField.font = UqpayFonts.scaled(size: 15, weight: .medium, textStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    // Email Label
    private let emailLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Email")
        label.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Email TextField
    private let emailTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = UqpayLocalized("john.doe@example.com")
        textField.keyboardType = .emailAddress
        textField.autocapitalizationType = .none
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UqpayColors.border.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        textField.leftViewMode = .always
        textField.font = UqpayFonts.scaled(size: 15, weight: .medium, textStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    // Phone Label
    private let phoneLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Phone")
        label.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Phone TextField
    private let phoneTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = UqpayLocalized("+1 234 567 8900")
        textField.keyboardType = .phonePad
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UqpayColors.border.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        textField.leftViewMode = .always
        textField.font = UqpayFonts.scaled(size: 15, weight: .medium, textStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    // Billing Address Section
    private let billingAddressLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Billing address")
        label.font = UqpayFonts.scaled(size: 18, weight: .semibold, textStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textPrimary // Tailwind Neutral-950
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Region Label
    private let regionLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Region")
        label.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Region TextField — driven by `countryPicker`, never typed into, so the
    // ISO code sent to the API is always one the customer actually chose.
    private let regionTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = UqpayLocalized("Select country or region")
        textField.keyboardType = .default
        textField.autocapitalizationType = .words
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UqpayColors.border.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        textField.leftViewMode = .always
        textField.font = UqpayFonts.scaled(size: 15, weight: .medium, textStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    // State Label
    private let stateLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("State")
        label.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // State TextField (replacing button)
    private let stateTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = UqpayLocalized("State or province")
        textField.keyboardType = .default
        textField.autocapitalizationType = .words
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UqpayColors.border.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        textField.leftViewMode = .always
        textField.font = UqpayFonts.scaled(size: 15, weight: .medium, textStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    // Address Line 1 Label
    private let addressLineLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Address line 1")
        label.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Address Line 1 TextField
    private let addressLineTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = UqpayLocalized("Street address")
        textField.keyboardType = .default
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UqpayColors.border.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        textField.leftViewMode = .always
        textField.font = UqpayFonts.scaled(size: 15, weight: .medium, textStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    // Address Line 2 Label
    private let addressLine2Label: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Address line 2 (optional)")
        label.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Address Line 2 TextField
    private let addressLine2TextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = UqpayLocalized("Apartment, suite, etc.")
        textField.keyboardType = .default
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UqpayColors.border.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        textField.leftViewMode = .always
        textField.font = UqpayFonts.scaled(size: 15, weight: .medium, textStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    // City Label
    private let cityLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("City")
        label.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // City TextField
    private let cityTextField: UITextField = {
        let textField = UITextField()
        textField.keyboardType = .default
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UqpayColors.border.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        textField.leftViewMode = .always
        textField.font = UqpayFonts.scaled(size: 15, weight: .medium, textStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    // Postal Code Label
    private let postalCodeLabel: UILabel = {
        let label = UILabel()
        label.text = UqpayLocalized("Postal code")
        label.font = UqpayFonts.scaled(size: 16, weight: .semibold, textStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UqpayColors.textLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Postal Code TextField
    private let postalCodeTextField: UITextField = {
        let textField = UITextField()
        textField.keyboardType = .default
        textField.layer.cornerRadius = 8
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UqpayColors.border.cgColor
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        textField.leftViewMode = .always
        textField.font = UqpayFonts.scaled(size: 15, weight: .medium, textStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    private let payButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(UqpayLocalized("Pay"), for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UqpayColors.uqpayBlue // UQPAY Blue — brand color, both modes
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UqpayFonts.scaled(size: 15, weight: .semibold, textStyle: .subheadline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Initialization
    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        // Property initialisers resolved their `cgColor`s against whatever
        // trait collection was current at init; re-resolve against this
        // view's actual traits.
        applyLayerColors()
        setupAccessibility()
        setupTextFieldDelegates()
        setupCountryPicker()
        setupActions()
        setupKeyboardHandling()
        setupCallbackObserver()

        #if DEBUG
        // Fill mock data for testing in debug builds only
        fillMockData()
        #endif
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Leaving the screen stops its tasks — their reports would have
        // nowhere to land. The idempotency pin survives on purpose: it is
        // static per payload, so re-entering and paying the same details
        // replays the pinned attempt instead of minting a key for a payment
        // that may already be processing. `isBeingDismissed` is false for a
        // child of a dismissed navigation controller, hence the parent check.
        if isMovingFromParent || isBeingDismissed
            || navigationController?.isBeingDismissed == true {
            handleFlowDismissal()
        }
    }

    /// The flow is going away for good.
    ///
    /// Internal rather than private so tests can drive it directly: the UIKit
    /// flags that trigger it (`isBeingDismissed` and friends) are read-only and
    /// cannot be simulated.
    func handleFlowDismissal() {
        // Read before anything is cancelled: a confirm that is still in the air
        // has already reached the server, and cancelling a Swift task does not
        // un-charge a card.
        let confirmWasInFlight = confirmTask != nil && paymentSheet?.hasReportedOutcome == false

        confirmTask?.cancel()
        reconcileWatchTask?.cancel()
        reconcileWatchTask = nil

        if confirmWasInFlight,
           let sheet = paymentSheet,
           let paymentIntentId = UqpayConfiguration.shared.paymentIntentId {
            // Not a cancellation. The customer left, but the payment did not —
            // it is mid-authorization, which is exactly the state
            // `paymentDidBecomePending` documents. Reporting `didCancel` here
            // told the merchant the customer walked away from a payment their
            // card was about to be charged for.
            reportDismissalDuringConfirm(sheet: sheet, paymentIntentId: paymentIntentId)
            return
        }

        // Leaving without ever reporting an outcome is the customer walking
        // away. Gated on the sheet, so a dismissal that tears down several
        // screens at once still reports exactly one cancellation — and a
        // completed or declined payment reports none.
        reportCancellationIfUnreported()
    }

    /// Reports the honest state for a sheet dismissed mid-confirm, and hands the
    /// watch to the sheet so a settlement arriving seconds later is still seen.
    ///
    /// Internal so tests can drive it without a live confirm in flight.
    @MainActor
    func reportDismissalDuringConfirm(sheet: PaymentSheet, paymentIntentId: String) {
        UqpayLogger.shared.info(
            "Sheet dismissed while a confirm was in flight; reporting pending and continuing to reconcile"
        )
        // Goes through `reportingSheet`, which marks the payment reported and so
        // suppresses a later cancellation — while still leaving success and
        // failure free to be delivered, per the delegate contract.
        reportPendingToMerchant(
            paymentIntentId: paymentIntentId,
            amount: 0,
            currency: "",
            status: .processing
        )
        sheet.beginDetachedReconciliation(paymentIntentId: paymentIntentId)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        reconcileWatchTask?.cancel()
        confirmTask?.cancel()
    }

    // MARK: - Trait Changes

    /// Layer colors are plain `CGColor` and do not re-resolve when the
    /// interface style changes; everything set on a `UIView` (text,
    /// backgrounds, tints) re-resolves on its own.
    private var borderedTextFields: [UITextField] {
        [cardNumberTextField, expiryTextField, cvvTextField,
         firstNameTextField, lastNameTextField, emailTextField,
         phoneTextField, regionTextField, stateTextField,
         addressLineTextField, addressLine2TextField,
         cityTextField, postalCodeTextField]
    }

    private func applyLayerColors() {
        view.traitCollection.performAsCurrent {
            mainContainerView.layer.borderColor = UqpayColors.border.cgColor
            cardBrandImageView.layer.borderColor = UqpayColors.border.cgColor
            // The focused field keeps its blue focus border — `focusBorder`
            // is the same in both modes, so skipping it is lossless.
            for field in borderedTextFields where !field.isFirstResponder {
                field.layer.borderColor = UqpayColors.border.cgColor
            }
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyLayerColors()
        }
    }

    // MARK: - Debug Helper

    #if DEBUG
    /// Fills all form fields with mock data for testing (DEBUG builds only)
    private func fillMockData() {
        // Cardholder name
        firstNameTextField.text = "John"
        lastNameTextField.text = "Doe"

        // Contact information
        emailTextField.text = "john.doe@example.com"
        phoneTextField.text = "+1 234 567 8900"

        // Billing address. The country goes through the picker so the ISO code
        // is set too — setting only the text would leave the payload's
        // country_code empty and fail validation.
        if let unitedStates = CountryRegion.first(matching: "US") {
            select(country: unitedStates)
        }
        stateTextField.text = "California"
        addressLineTextField.text = "123 Main Street"
        addressLine2TextField.text = "Apt 4B"
        cityTextField.text = "San Francisco"
        postalCodeTextField.text = "94102"
    }
    #endif

    // MARK: - Setup Methods
    private func setupUI() {
        view.backgroundColor = UqpayColors.background

        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(titleLabel)
        contentView.addSubview(mainContainerView)
        contentView.addSubview(payButton)

        // Container content
        mainContainerView.addSubview(cardIconImageView)
        mainContainerView.addSubview(cardLabel)
        mainContainerView.addSubview(cardDetailsLabel)
        mainContainerView.addSubview(cardNumberTextField)
        mainContainerView.addSubview(expiryTextField)
        mainContainerView.addSubview(cvvTextField)
        mainContainerView.addSubview(cardholderLabel)
        mainContainerView.addSubview(firstNameLabel)
        mainContainerView.addSubview(firstNameTextField)
        mainContainerView.addSubview(lastNameLabel)
        mainContainerView.addSubview(lastNameTextField)
        mainContainerView.addSubview(emailLabel)
        mainContainerView.addSubview(emailTextField)
        mainContainerView.addSubview(phoneLabel)
        mainContainerView.addSubview(phoneTextField)
        mainContainerView.addSubview(billingAddressLabel)
        mainContainerView.addSubview(regionLabel)
        mainContainerView.addSubview(regionTextField)
        mainContainerView.addSubview(stateLabel)
        mainContainerView.addSubview(stateTextField)
        mainContainerView.addSubview(addressLineLabel)
        mainContainerView.addSubview(addressLineTextField)
        mainContainerView.addSubview(addressLine2Label)
        mainContainerView.addSubview(addressLine2TextField)
        mainContainerView.addSubview(cityLabel)
        mainContainerView.addSubview(cityTextField)
        mainContainerView.addSubview(postalCodeLabel)
        mainContainerView.addSubview(postalCodeTextField)

        // Setup card brand image in the text field's rightView
        cardBrandContainerView.addSubview(cardBrandImageView)
        cardNumberTextField.rightView = cardBrandContainerView
        cardNumberTextField.rightViewMode = .always

        // Initially hide the card brand image
        cardBrandImageView.isHidden = true

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // ScrollView
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // ContentView
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Title Label
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Main Container
            mainContainerView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            mainContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            mainContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            // Card Icon and Label
            cardIconImageView.topAnchor.constraint(equalTo: mainContainerView.topAnchor, constant: 24),
            cardIconImageView.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),
            cardIconImageView.widthAnchor.constraint(equalToConstant: 24),
            cardIconImageView.heightAnchor.constraint(equalToConstant: 24),

            cardLabel.centerYAnchor.constraint(equalTo: cardIconImageView.centerYAnchor),
            cardLabel.leadingAnchor.constraint(equalTo: cardIconImageView.trailingAnchor, constant: 8),

            // Card Details Label
            cardDetailsLabel.topAnchor.constraint(equalTo: cardIconImageView.bottomAnchor, constant: 32),
            cardDetailsLabel.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),

            // Card Number Field
            cardNumberTextField.topAnchor.constraint(equalTo: cardDetailsLabel.bottomAnchor, constant: 10),
            cardNumberTextField.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),
            cardNumberTextField.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor, constant: -24),
            cardNumberTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            // Expiry and CVV Fields
            expiryTextField.topAnchor.constraint(equalTo: cardNumberTextField.bottomAnchor, constant: 8),
            expiryTextField.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),
            expiryTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            cvvTextField.topAnchor.constraint(equalTo: cardNumberTextField.bottomAnchor, constant: 8),
            cvvTextField.leadingAnchor.constraint(equalTo: expiryTextField.trailingAnchor, constant: 8),
            cvvTextField.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor, constant: -24),
            cvvTextField.widthAnchor.constraint(equalTo: expiryTextField.widthAnchor),
            cvvTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            // Cardholder Name Section
            cardholderLabel.topAnchor.constraint(equalTo: expiryTextField.bottomAnchor, constant: 16),
            cardholderLabel.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),

            // First Name
            firstNameLabel.topAnchor.constraint(equalTo: cardholderLabel.bottomAnchor, constant: 10),
            firstNameLabel.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),

            firstNameTextField.topAnchor.constraint(equalTo: firstNameLabel.bottomAnchor, constant: 6),
            firstNameTextField.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),
            firstNameTextField.widthAnchor.constraint(equalTo: mainContainerView.widthAnchor, multiplier: 0.5, constant: -30),
            firstNameTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            // Last Name
            lastNameLabel.topAnchor.constraint(equalTo: cardholderLabel.bottomAnchor, constant: 10),
            lastNameLabel.leadingAnchor.constraint(equalTo: firstNameTextField.trailingAnchor, constant: 12),

            lastNameTextField.topAnchor.constraint(equalTo: lastNameLabel.bottomAnchor, constant: 6),
            lastNameTextField.leadingAnchor.constraint(equalTo: firstNameTextField.trailingAnchor, constant: 12),
            lastNameTextField.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor, constant: -24),
            lastNameTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            // Email Section
            emailLabel.topAnchor.constraint(equalTo: firstNameTextField.bottomAnchor, constant: 16),
            emailLabel.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),

            emailTextField.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: 10),
            emailTextField.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),
            emailTextField.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor, constant: -24),
            emailTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            // Phone Section
            phoneLabel.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 16),
            phoneLabel.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),

            phoneTextField.topAnchor.constraint(equalTo: phoneLabel.bottomAnchor, constant: 10),
            phoneTextField.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),
            phoneTextField.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor, constant: -24),
            phoneTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            // Billing Address Section
            billingAddressLabel.topAnchor.constraint(equalTo: phoneTextField.bottomAnchor, constant: 32),
            billingAddressLabel.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),

            // Region
            regionLabel.topAnchor.constraint(equalTo: billingAddressLabel.bottomAnchor, constant: 16),
            regionLabel.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),

            regionTextField.topAnchor.constraint(equalTo: regionLabel.bottomAnchor, constant: 10),
            regionTextField.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),
            regionTextField.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor, constant: -24),
            regionTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            // State
            stateLabel.topAnchor.constraint(equalTo: regionTextField.bottomAnchor, constant: 16),
            stateLabel.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),

            stateTextField.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 10),
            stateTextField.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),
            stateTextField.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor, constant: -24),
            stateTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            // Address Line 1
            addressLineLabel.topAnchor.constraint(equalTo: stateTextField.bottomAnchor, constant: 16),
            addressLineLabel.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),

            addressLineTextField.topAnchor.constraint(equalTo: addressLineLabel.bottomAnchor, constant: 10),
            addressLineTextField.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),
            addressLineTextField.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor, constant: -24),
            addressLineTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            // Address Line 2
            addressLine2Label.topAnchor.constraint(equalTo: addressLineTextField.bottomAnchor, constant: 16),
            addressLine2Label.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),

            addressLine2TextField.topAnchor.constraint(equalTo: addressLine2Label.bottomAnchor, constant: 10),
            addressLine2TextField.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),
            addressLine2TextField.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor, constant: -24),
            addressLine2TextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            // City
            cityLabel.topAnchor.constraint(equalTo: addressLine2TextField.bottomAnchor, constant: 16),
            cityLabel.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),

            cityTextField.topAnchor.constraint(equalTo: cityLabel.bottomAnchor, constant: 10),
            cityTextField.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),
            cityTextField.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor, constant: -24),
            cityTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            // Postal Code
            postalCodeLabel.topAnchor.constraint(equalTo: cityTextField.bottomAnchor, constant: 16),
            postalCodeLabel.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),

            postalCodeTextField.topAnchor.constraint(equalTo: postalCodeLabel.bottomAnchor, constant: 10),
            postalCodeTextField.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: 24),
            postalCodeTextField.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor, constant: -24),
            postalCodeTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            mainContainerView.bottomAnchor.constraint(equalTo: postalCodeTextField.bottomAnchor, constant: 24),

            // Pay Button
            payButton.topAnchor.constraint(equalTo: mainContainerView.bottomAnchor, constant: 24),
            payButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            payButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            payButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            payButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    /// Turns the region field into a picker, so the billing country is chosen
    /// from the ISO list rather than typed and then guessed at.
    private func setupCountryPicker() {
        regionTextField.inputView = countryPicker

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissCountryPicker))
        ]
        regionTextField.inputAccessoryView = toolbar
        regionTextField.accessibilityIdentifier = "uqpay.card.country"

        // Start on the device's own region when it is a country we can send,
        // which is right far more often than not — but the customer can change
        // it, and nothing is guessed if they do.
        if let deviceDefault = CountryRegion.deviceDefault {
            select(country: deviceDefault)
        }
    }

    private func select(country: CountryRegion) {
        selectedCountry = country
        regionTextField.text = country.name
        if let index = countries.firstIndex(of: country) {
            countryPicker.selectRow(index, inComponent: 0, animated: false)
        }
    }

    @objc private func dismissCountryPicker() {
        // Opening the picker and tapping Done without scrolling must still
        // commit a country, so take whatever row is showing.
        if selectedCountry == nil {
            let row = countryPicker.selectedRow(inComponent: 0)
            if countries.indices.contains(row) {
                select(country: countries[row])
            }
        }
        regionTextField.resignFirstResponder()
    }

    /// VoiceOver support. The visible caption labels are separate views, so
    /// without these every field announces as a bare "text field".
    private func setupAccessibility() {
        cardNumberTextField.accessibilityLabel = UqpayLocalized("Card number")
        expiryTextField.accessibilityLabel = UqpayLocalized("Expiry date")
        cvvTextField.accessibilityLabel = UqpayLocalized("Security code")
        firstNameTextField.accessibilityLabel = UqpayLocalized("First name")
        lastNameTextField.accessibilityLabel = UqpayLocalized("Last name")
        emailTextField.accessibilityLabel = UqpayLocalized("Email")
        phoneTextField.accessibilityLabel = UqpayLocalized("Phone number")
        regionTextField.accessibilityLabel = UqpayLocalized("Country or region")
        stateTextField.accessibilityLabel = UqpayLocalized("State")
        addressLineTextField.accessibilityLabel = UqpayLocalized("Address line 1")
        addressLine2TextField.accessibilityLabel = UqpayLocalized("Address line 2")
        cityTextField.accessibilityLabel = UqpayLocalized("City")
        postalCodeTextField.accessibilityLabel = UqpayLocalized("Postal code")

        // Decorative imagery; the fields above carry the information.
        cardBrandImageView.isAccessibilityElement = false
        cardIconImageView.isAccessibilityElement = false

        titleLabel.accessibilityTraits.insert(.header)
        cardholderLabel.accessibilityTraits.insert(.header)
        billingAddressLabel.accessibilityTraits.insert(.header)
    }

    private func setupTextFieldDelegates() {
        cardNumberTextField.delegate = self
        expiryTextField.delegate = self
        cvvTextField.delegate = self
        firstNameTextField.delegate = self
        lastNameTextField.delegate = self
        emailTextField.delegate = self
        phoneTextField.delegate = self
        regionTextField.delegate = self
        stateTextField.delegate = self
        addressLineTextField.delegate = self
        addressLine2TextField.delegate = self
        cityTextField.delegate = self
        postalCodeTextField.delegate = self
    }

    private func setupActions() {
        payButton.addTarget(self, action: #selector(payButtonTapped), for: .touchUpInside)
    }

    private func setupKeyboardHandling() {
        // The form scrolls, but nothing used to inset it for the keyboard, so a
        // focused field could sit underneath one. Landscape is the worst case:
        // the keyboard takes roughly half the height, and the field the customer
        // just tapped is the one they cannot see.
        //
        // `keyboardWillChangeFrame` rather than `keyboardWillShow`, so switching
        // between a number pad and a text keyboard, an undocked or floating iPad
        // keyboard, and a hardware keyboard appearing mid-form are all the same
        // event.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    /// How far above the keyboard the focused field is parked, so the field is
    /// not flush against it. Merchant-tunable via
    /// `Configuration.Payment.keyboardScrollOffset`, which until now was a
    /// documented setting that did nothing.
    private var keyboardScrollOffset: CGFloat {
        paymentSheet?.configuration.payment.keyboardScrollOffset ?? 50
    }

    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }
        // Converted through the window: on iPad the keyboard can be split,
        // floating or off to one side, and only the part that actually overlaps
        // this view should inset it.
        let keyboardInView = view.convert(endFrame.cgRectValue, from: view.window)
        let overlap = view.bounds.maxY - keyboardInView.minY
        applyKeyboardInset(max(0, overlap - view.safeAreaInsets.bottom))
        scrollFocusedFieldIntoView()
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        applyKeyboardInset(0)
    }

    private func applyKeyboardInset(_ inset: CGFloat) {
        guard scrollView.contentInset.bottom != inset else { return }
        scrollView.contentInset.bottom = inset
        scrollView.verticalScrollIndicatorInsets.bottom = inset
    }

    private func scrollFocusedFieldIntoView() {
        guard let focused = focusedField() else { return }
        let target = focused.convert(focused.bounds, to: scrollView)
            .insetBy(dx: 0, dy: -keyboardScrollOffset)
        scrollView.scrollRectToVisible(target, animated: true)
    }

    private func focusedField() -> UIView? {
        func search(_ view: UIView) -> UIView? {
            if view.isFirstResponder { return view }
            for subview in view.subviews {
                if let match = search(subview) { return match }
            }
            return nil
        }
        return search(view)
    }

    private func setupCallbackObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePaymentCallback(_:)),
            name: PaymentSheet.paymentReturnedFromBank,
            object: nil
        )
    }

    @objc private func handlePaymentCallback(_ notification: Notification) {
        // Returning to the app proves only that the customer came back. The
        // URL's query parameters (status=success and friends) are writable by
        // anyone who can craft the return URL, so they are never read — the
        // outcome always comes from the API.
        if let guardBox = activeThreeDSGuard, !guardBox.isResolved {
            // The 3DS step in flight already polls the intent and will resolve
            // this payment; resolving here too would report it twice.
            UqpayLogger.shared.debug("Returned from bank; the active 3DS poll will settle the outcome")
            return
        }

        guard let paymentIntentId = UqpayConfiguration.shared.paymentIntentId else {
            UqpayLogger.shared.error("Returned from bank but no payment intent is configured")
            return
        }

        guard !resolvedPaymentIntentIds.contains(paymentIntentId) else {
            UqpayLogger.shared.debug("Returned from bank for an already-reported payment; ignoring")
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }

            let pendingVC = self.navigationController?.viewControllers.last(where: { $0 is PaymentCardStatusViewController }) as? PaymentCardStatusViewController
            pendingVC?.updateConfiguration(
                PaymentStatusConfiguration(status: .processing, message: UqpayLocalized("Confirming your payment…")),
                animated: true
            )

            do {
                let apiClient = try ApiClient.forConfiguredEnvironment()
                let intent = try await apiClient.awaitThreeDSOutcome(
                    paymentIntentId: paymentIntentId,
                    excludingActionType: "redirect_to_url"
                )
                self.presentThreeDSResult(intent, amount: intent.amount ?? "", pendingVC: pendingVC)
            } catch {
                let timedOut = (error as? PaymentSheetError) == .authenticationTimedOut
                self.presentThreeDSFailure(
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                    code: timedOut ? .timeout : .networkError,
                    pendingVC: pendingVC
                )
            }
            self.resetPayButton()
        }
    }

    // MARK: - Actions
    @objc private func payButtonTapped() {
        // Clear any old pending payment context from Keychain
        KeychainHelper.shared.delete(forKey: "pending_payment_context")

        guard validateCardInputs() else {
            return
        }

        // Only once a new attempt is actually starting: it supersedes the
        // previous confirm task (which may still be replaying) and any
        // watcher polling the previous indeterminate outcome — two
        // observers of one intent would race to report. A tap that fails
        // validation must not kill the only observer of a possibly-settled
        // payment.
        confirmTask?.cancel()
        reconcileWatchTask?.cancel()
        reconcileWatchTask = nil

        let cardNumber = cardNumberTextField.text?.replacingOccurrences(of: " ", with: "") ?? ""
        let expiry = expiryTextField.text?.replacingOccurrences(of: "/", with: "") ?? ""
        let cvc = cvvTextField.text ?? ""
        let firstName = firstNameTextField.text ?? ""
        let lastName = lastNameTextField.text ?? ""
        let cardholderName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)

        let expiryMonth = String(expiry.prefix(2))
        let twoDigitYear = String(expiry.suffix(2))

        // Convert 2-digit year to 4-digit year
        // Years 00-99 are interpreted as 2000-2099
        let expiryYear = convertToFourDigitYear(twoDigitYear)

        let email = emailTextField.text ?? ""
        let phone = phoneTextField.text ?? ""
        let street1 = addressLineTextField.text ?? ""
        let street2 = addressLine2TextField.text ?? ""
        let city = cityTextField.text ?? ""
        let state = stateTextField.text ?? ""
        // Validation above guarantees a selection, so this cannot fall back to
        // a guessed country.
        let country = billingCountryCode ?? ""
        let postalCode = postalCodeTextField.text ?? ""

        // Combine street addresses if line2 is provided
        let fullStreet = street2.isEmpty ? street1 : "\(street1), \(street2)"

        let address = Address(
            countryCode: country,
            state: state,
            city: city,
            street: fullStreet,
            postcode: postalCode
        )

        let billingDetails = BillingDetails(
            firstName: firstName,
            lastName: lastName,
            email: email,
            phoneNumber: phone,
            address: address
        )

        let cardDetails = ConfirmCardDetails(
            cardName: cardholderName,
            cardNumber: cardNumber,
            expiryMonth: expiryMonth,
            expiryYear: expiryYear,
            cvc: cvc,
            network: currentCardBrand.rawValue.lowercased(),
            billing: billingDetails,
            autoCapture: true,
            authorizationType: "authorization",
            threeDsAction: "enforce_3ds",
            threeDs: nil
        )

        guard let paymentIntentId = UqpayConfiguration.shared.paymentIntentId else {
            UqpayLogger.shared.error("Payment intent ID not found in configuration")
            navigateToFailure(errorCode: "NO_PAYMENT_INTENT", message: UqpayLocalized("Payment intent not found. Please try again."))
            return
        }

        payButton.isEnabled = false
        payButton.setTitle(UqpayLocalized("Processing..."), for: .normal)

        let pendingViewController = PaymentCardStatusViewController.processing(
            message: UqpayLocalized("Processing your payment...\nThis may take a few moments."),
            onCancel: { [weak self] in
                // Cancelling stops the replaying task — leaving it running
                // would let a stale outcome land on whatever attempt comes
                // next. The idempotency pin survives, so if the customer
                // pays again with the same details the send is a replay.
                self?.confirmTask?.cancel()
                self?.navigationController?.popViewController(animated: true)
                self?.resetPayButton()
            }
        )

        // Keep the cancel handler as is, but prepare for success transition
        // The primaryActionHandler is already set for cancel in the factory method
        navigationController?.pushViewController(pendingViewController, animated: true)

        // One attempt per distinct payment. The identity must cover
        // everything the customer can edit — card AND billing — so a
        // correction is sent as a new payment rather than silently replaced
        // by the previous attempt. The card number is reduced to
        // BIN-plus-last-4 and the CVC excluded: the digest outlives the
        // process, and nothing PAN- or CVC-derived may be stored at rest
        // (see ``ConfirmPayloadIdentity`` for why that trade is safe).
        // Field order is part of the identity — do not reorder.
        let payloadDigest = ConfirmPayloadIdentity.digest(of: [
            paymentIntentId,
            "card",
            ConfirmPayloadIdentity.cardNumberIdentity(cardNumber),
            expiryMonth,
            expiryYear,
            cardholderName,
            firstName,
            lastName,
            email,
            phone,
            country,
            state,
            city,
            fullStreet,
            postalCode
        ])

        confirmTask = Task {
            // The intent may have settled while no screen was watching — paid
            // a moment before the app was killed, or cancelled from the
            // merchant dashboard. Confirming it again is at best a server
            // rejection and at worst a second attempt; the settled outcome is
            // reported instead. Runs before the attempt is pinned, so an
            // already-finished payment never mints a pin.
            if await interceptTerminalIntent(paymentIntentId: paymentIntentId) {
                return
            }

            // Key plus the device values frozen with it. A retry of an
            // unresolved attempt gets the same ones back, so the body
            // re-encodes byte-identically (with the sorted-keys encoder) —
            // without this object ever holding the card number.
            let attempt = confirmIdempotency.attempt(
                forPayloadDigest: payloadDigest,
                paymentIntentId: paymentIntentId
            )

            do {
                let apiClient = try ApiClient.forConfiguredEnvironment()

                let requestBody = ConfirmPaymentIntentRequest(
                    paymentMethod: ConfirmPaymentMethod(type: "card", card: cardDetails),
                    browserInfo: attempt.browserInfo,
                    ipAddress: attempt.ipAddress
                )

                // Replay-on-unknown: if the outcome of a send is uncertain,
                // the identical request (same key, same bytes) is resent.
                // The server's answer to this key IS this attempt's outcome —
                // the only attribution that cannot confuse attempts.
                let response = try await withBackgroundTaskAssertion(named: "com.uqpay.confirm.card") {
                    try await Self.sendConfirmReplayingWhileUnknown(
                        apiClient: apiClient,
                        paymentIntentId: paymentIntentId,
                        encodedBody: try ConfirmBodyEncoder.make().encode(requestBody),
                        idempotencyKey: attempt.key
                    )
                }
                confirmIdempotency.resolve(attempt)

                await MainActor.run {
                    self.handleConfirmResponse(response)
                }

            } catch let error as PaymentSheetError {
                UqpayLogger.shared.error("Payment confirmation failed: \(error.localizedDescription)")
                // A PaymentSheetError from the confirm transport means the
                // request never left the device — a configuration problem,
                // not a decline. The attempt never started, so nothing
                // stays pinned.
                confirmIdempotency.resolve(attempt)

                await MainActor.run {
                    if let delegate = self.paymentDelegate {
                        let paymentError = PaymentError(
                            code: .invalidConfiguration,
                            message: error.localizedDescription,
                            underlyingError: error,
                            paymentMethodType: "card"
                        )
                        delegate.paymentSheet(self.reportingSheet, didFailWithError: paymentError)
                    }

                    let pendingVC = navigationController?.viewControllers.last(where: { $0 is PaymentCardStatusViewController }) as? PaymentCardStatusViewController

                    if let pendingVC = pendingVC {
                        pendingVC.transitionFromPending(
                            to: .failed,
                            errorCode: "PAYMENT_ERROR",
                            message: error.localizedDescription
                        )
                    } else {
                        navigateToFailure(
                            errorCode: "PAYMENT_ERROR",
                            message: error.localizedDescription
                        )
                    }
                    resetPayButton()
                }
            } catch {
                // A cancelled send reports nothing: the cancelling flow owns
                // the screen, and the pin stays so a same-details retry is a
                // replay of this very attempt.
                if Task.isCancelled || error is CancellationError
                    || (error as? URLError)?.code == .cancelled {
                    return
                }

                UqpayLogger.shared.error("Payment confirmation failed: \(error.localizedDescription)")
                // Keeps the attempt when the outcome is unknown — a transport
                // failure, an unreadable 2xx, a 5xx — and resolves it when the
                // server definitively answered.
                confirmIdempotency.handle(error, for: attempt)

                // A payment we could not observe is not a payment we may call
                // failed: the charge may well have gone through. Show the
                // honest state and keep watching for a settlement.
                if ConfirmIdempotency.isOutcomeUnknown(error) {
                    await reconcileUnobservedConfirm(paymentIntentId: paymentIntentId, error: error)
                    return
                }

                await MainActor.run {
                    // The server rejected this outright. Its own status and
                    // code describe why far better than a generic label —
                    // but the code goes in the code fields, never in the
                    // sentence the customer reads.
                    let apiError = error as? UqpayAPIError
                    let errorCode = apiError?.apiCode
                        ?? apiError.map { "HTTP_\($0.httpStatus ?? 0)" }
                        ?? (error as NSError).domain
                    let message = Self.customerMessage(for: apiError)

                    // The merchant hears about definitively failed attempts —
                    // they may need to unlock the order or offer another
                    // payment method.
                    if let delegate = self.paymentDelegate {
                        let paymentError = PaymentError(
                            code: Self.errorCode(for: apiError),
                            message: message,
                            underlyingError: error,
                            declineCode: apiError?.apiCode,
                            paymentMethodType: "card"
                        )
                        delegate.paymentSheet(self.reportingSheet, didFailWithError: paymentError)
                    }

                    let pendingVC = navigationController?.viewControllers.last(where: { $0 is PaymentCardStatusViewController }) as? PaymentCardStatusViewController

                    if let pendingVC = pendingVC {
                        pendingVC.transitionFromPending(
                            to: .failed,
                            errorCode: errorCode,
                            message: message
                        )
                    } else {
                        navigateToFailure(
                            errorCode: errorCode,
                            message: message
                        )
                    }
                    resetPayButton()
                }
            }
        }
    }

    /// Routes one confirm response through the status switch. Every branch
    /// must end with the customer seeing the truth and the merchant hearing
    /// it — reporting is part of the branch, not an afterthought.
    ///
    /// Internal rather than private so tests can drive each branch with a
    /// constructed response; UIKit reaches it only from the confirm task.
    @MainActor
    func handleConfirmResponse(_ response: ConfirmPaymentIntentResponse) {
        let pendingVC = navigationController?.viewControllers.last(where: { $0 is PaymentCardStatusViewController }) as? PaymentCardStatusViewController

        switch response.intentStatus.uppercased() {

        // MARK: - REQUIRES_PAYMENT_METHOD
        case "REQUIRES_PAYMENT_METHOD":
            // Two very different situations share this status: a
            // decline (the attempt exists and failed) and a confirm
            // that never attached a payment method. A failed
            // attempt row is a decline and the merchant must hear
            // about it — telling the customer to "fill in your
            // card details" for a declined card is a lie.
            if let failedAttempt = response.latestPaymentAttempt,
               failedAttempt.attemptStatus.uppercased() == "FAILED"
                   || (failedAttempt.failureCode?.isEmpty == false) {
                let failureCode = (failedAttempt.failureCode?.isEmpty == false)
                    ? failedAttempt.failureCode : nil
                // The confirm response's attempt carries only the
                // code; the human-readable reason lives on the
                // intent read, so a generic sentence is honest.
                let message = "The payment could not be completed. Please try again."

                if let delegate = self.paymentDelegate {
                    delegate.paymentSheet(
                        self.reportingSheet,
                        didFailWithError: PaymentError(
                            code: Self.errorCode(forFailureCode: failureCode,
                                                 intentStatus: .requiresPaymentMethod),
                            message: message,
                            declineCode: failureCode,
                            paymentMethodType: "card"
                        )
                    )
                }

                if let pendingVC = pendingVC {
                    pendingVC.transitionFromPending(
                        to: .failed,
                        errorCode: failureCode ?? "REQUIRES_PAYMENT_METHOD",
                        message: message
                    )
                } else {
                    navigateToFailure(
                        errorCode: failureCode ?? "REQUIRES_PAYMENT_METHOD",
                        message: message
                    )
                }
                resetPayButton()
                return
            }

            // No attempt: the confirm genuinely did not attach a
            // payment method. Pop back to card entry and say so.
            if pendingVC != nil {
                navigationController?.popViewController(animated: true)
            }

            resetPayButton()

            let alert = UIAlertController(
                title: UqpayLocalized("Payment Method Required"),
                message: UqpayLocalized("Payment method not attached. Please fill in your card details."),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: UqpayLocalized("OK"), style: .default))
            self.present(alert, animated: true)

        // MARK: - REQUIRES_CUSTOMER_ACTION
        case "REQUIRES_CUSTOMER_ACTION":
            guard let nextAction = response.nextAction else {
                UqpayLogger.shared.error("REQUIRES_CUSTOMER_ACTION with no next_action")
                self.handleUnexpectedStatus(response.intentStatus, pendingVC: pendingVC)
                return
            }

            switch nextAction.actionType.lowercased() {

            case "redirect_to_url":
                guard let redirectToUrl = nextAction.redirectToUrl else {
                    UqpayLogger.shared.error("redirect_to_url action missing redirect payload")
                    self.handleUnexpectedStatus("MISSING_REDIRECT", pendingVC: pendingVC)
                    return
                }

                // Save payment context to Keychain before redirect (in case app gets killed)
                let paymentContext = PaymentContext(
                    paymentIntentId: response.paymentIntentId,
                    clientSecret: response.clientSecret,
                    amount: Double(response.amount),
                    currency: response.currency,
                    paymentMethodType: "card"
                )
                KeychainHelper.shared.saveObject(paymentContext, forKey: "pending_payment_context")

                guard let url = URL(string: redirectToUrl.url) else {
                    self.handleUnexpectedStatus("INVALID_REDIRECT_URL", pendingVC: pendingVC)
                    return
                }

                self.beginThreeDS(
                    content: .url(url),
                    actionType: "redirect_to_url",
                    paymentIntentId: response.paymentIntentId,
                    amount: "\(response.amount)",
                    pendingVC: pendingVC,
                    apiReturnURL: redirectToUrl.returnUrl
                )

            case "display_qr_code":
                // The docs document this action for e-wallets, not
                // for cards, and no card confirm has been seen to
                // return it. It is handled rather than dropped
                // because next_action is one shared enum across
                // every method, so an acquirer could.
                //
                // It runs through the same browser step as 3DS,
                // which matters: that step polls the intent and
                // reports the real outcome. The dedicated screen
                // this replaced showed the QR, never polled, never
                // told the merchant anything, and closed with an
                // unconditional "your payment has been received".
                guard let displayQrCode = nextAction.displayQrCode else {
                    UqpayLogger.shared.error("display_qr_code action missing QR payload")
                    self.handleUnexpectedStatus("MISSING_QR_CODE", pendingVC: pendingVC)
                    return
                }

                // Check for raw EMVCo payload first (qr_code field)
                if let rawQrCode = displayQrCode.qrCode,
                   !rawQrCode.contains("://"),
                   let qrImage = QRCodeGenerator.generateQRImage(from: rawQrCode) {
                    // Raw EMVCo QR payload — render it as an image
                    self.displayRawQRCode(
                        image: qrImage,
                        paymentIntentId: response.paymentIntentId,
                        amount: response.amount,
                        currency: response.currency
                    )
                    return
                }

                // Try URL-based QR (qrCodeUrl or qr_code with URL scheme)
                let qrCandidates = [displayQrCode.qrCodeUrl, displayQrCode.qrCode]
                    .compactMap { $0 }
                    .compactMap { URL(string: $0) }
                guard let qrURL = qrCandidates.first(where: {
                    $0.scheme == "https"
                }) else {
                    UqpayLogger.shared.error("display_qr_code carried no loadable QR URL or EMVCo payload")
                    self.handleUnexpectedStatus("MISSING_QR_CODE", pendingVC: pendingVC)
                    return
                }

                self.beginThreeDS(
                    content: .url(qrURL),
                    actionType: "display_qr_code",
                    paymentIntentId: response.paymentIntentId,
                    amount: "\(response.amount)",
                    pendingVC: pendingVC,
                    // Scanning with a second device takes longer
                    // than answering a challenge; matches the
                    // wallet screen's own QR poll.
                    timeout: 600
                )

            case "display_bank_details":
                guard let displayBankDetails = nextAction.displayBankDetails else {
                    UqpayLogger.shared.error("display_bank_details action missing bank details payload")
                    return
                }

                let bankDetailsVC = PaymentCardBankDetailsViewController(
                    bankName: displayBankDetails.bankName,
                    accountNumber: displayBankDetails.accountNumber,
                    routingNumber: displayBankDetails.routingNumber
                )

                // Tapping Confirm proves nothing about the money —
                // bank transfers settle asynchronously. Read the
                // intent and show the customer what is actually true.
                bankDetailsVC.confirmHandler = { [weak self] in
                    guard let self else { return }

                    let statusVC = PaymentCardStatusViewController.processing(
                        message: UqpayLocalized("Checking your transfer…")
                    )
                    self.navigationController?.pushViewController(statusVC, animated: true)

                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        do {
                            let apiClient = try ApiClient.forConfiguredEnvironment()
                            let intent = try await apiClient.retrievePaymentIntent(response.paymentIntentId)

                            switch intent.intentStatus {
                            case .succeeded:
                                // Exactly-once: another resolution
                                // path may already have reported.
                                if self.resolvedPaymentIntentIds.insert(intent.paymentIntentId).inserted,
                                   let delegate = self.paymentDelegate {
                                    let wireAmount = WireAmount.parse(intent.amount, paymentIntentId: intent.paymentIntentId)
                                    let result = PaymentResult(
                                        paymentIntentId: intent.paymentIntentId,
                                        paymentMethodType: "card",
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
                                statusVC.primaryActionHandler = { [weak self] in
                                    self?.dismissEntirePaymentSheet()
                                }
                                statusVC.transitionFromPending(
                                    to: .succeeded,
                                    transactionId: intent.paymentIntentId,
                                    message: UqpayLocalized("Your payment has been received.")
                                )

                            case .failed, .cancelled:
                                let failureMessage = intent.latestPaymentAttempt?.failureMessage
                                    ?? "The payment could not be completed. Please try again."
                                if let delegate = self.paymentDelegate {
                                    delegate.paymentSheet(
                                        self.reportingSheet,
                                        didFailWithError: PaymentError(
                                            code: intent.intentStatus == .cancelled ? .cancelled : .unknown,
                                            message: failureMessage,
                                            paymentMethodType: "card"
                                        )
                                    )
                                }
                                statusVC.transitionFromPending(
                                    to: .failed,
                                    errorCode: intent.intentStatus.rawValue,
                                    message: failureMessage
                                )
                                self.resetPayButton()

                            default:
                                // The transfer has not reached us yet
                                // — an honest "pending", never a
                                // fabricated receipt.
                                let wireAmount = WireAmount.parse(intent.amount, paymentIntentId: intent.paymentIntentId)
                                self.reportPendingToMerchant(
                                    paymentIntentId: intent.paymentIntentId,
                                    amount: wireAmount.double,
                                    amountDecimal: wireAmount.decimal,
                                    currency: intent.currency ?? "",
                                    merchantOrderId: intent.merchantOrderId,
                                    status: .pending
                                )
                                statusVC.primaryActionHandler = { [weak self] in
                                    self?.dismissEntirePaymentSheet()
                                }
                                statusVC.transitionFromPending(
                                    to: .pending,
                                    transactionId: intent.paymentIntentId,
                                    message: UqpayLocalized("We haven't received your transfer yet. You'll be notified once it clears.")
                                )
                            }
                        } catch {
                            statusVC.transitionFromPending(
                                to: .failed,
                                errorCode: "STATUS_CHECK_FAILED",
                                message: UqpayLocalized("Could not verify the transfer status. Check the payment status before retrying.")
                            )
                            self.resetPayButton()
                        }
                    }
                }

                if pendingVC != nil {
                    navigationController?.popViewController(animated: false)
                }
                navigationController?.pushViewController(bankDetailsVC, animated: true)

            case "redirect_iframe":
                guard let redirectIframe = nextAction.redirectIframe else {
                    self.handleUnexpectedStatus("MISSING_IFRAME", pendingVC: pendingVC)
                    return
                }

                self.beginThreeDS(
                    content: .iframeHTML(redirectIframe.iframe),
                    actionType: "redirect_iframe",
                    paymentIntentId: response.paymentIntentId,
                    amount: "\(response.amount)",
                    pendingVC: pendingVC
                )

            default:
                UqpayLogger.shared.error("Unknown next_action type: \(nextAction.actionType)")
                self.handleUnexpectedStatus("UNKNOWN_ACTION", pendingVC: pendingVC)
            }

        // MARK: - REQUIRES_CAPTURE
        case "REQUIRES_CAPTURE":
            // Authorization is complete. If a further browser step is
            // attached, run it exactly like 3DS — the outcome is
            // always re-read from the API, never decided client-side.
            if let nextAction = response.nextAction,
               nextAction.actionType.lowercased() == "redirect_iframe",
               let redirectIframe = nextAction.redirectIframe {
                self.beginThreeDS(
                    content: .iframeHTML(redirectIframe.iframe),
                    actionType: "redirect_iframe",
                    paymentIntentId: response.paymentIntentId,
                    amount: "\(response.amount)",
                    pendingVC: pendingVC
                )
            } else {
                // Funds are authorized; with auto-capture the API
                // settles the payment. Report it as the 3DS path does.
                self.presentAuthorizedSuccess(response: response, pendingVC: pendingVC)
            }

        // MARK: - PENDING
        case "PENDING":
            // Show pending status (ignore next_action as per requirements)
            // API amounts are decimal strings in major units ("8.98"), shown as-is.
            let amount = "\(response.amount) \(response.currency)"

            if let pendingVC = pendingVC {
                pendingVC.primaryActionHandler = { [weak self] in
                    self?.dismissEntirePaymentSheet()
                }

                pendingVC.transitionFromPending(
                    to: .pending,
                    transactionId: response.paymentIntentId,
                    message: UqpayLocalized("Your payment is pending and you will be notified once it is cleared.")
                )
            } else {
                let pendingStatusVC = PaymentCardStatusViewController.pending(
                    amount: amount,
                    transactionId: response.paymentIntentId,
                    message: UqpayLocalized("Your payment is pending and you will be notified once it is cleared.")
                )

                pendingStatusVC.primaryActionHandler = { [weak self] in
                    self?.dismissEntirePaymentSheet()
                }

                navigationController?.pushViewController(pendingStatusVC, animated: true)
            }

            // The screen was honest; the merchant heard nothing — their app
            // sat waiting on a callback that never came. Tell them the
            // payment is resting in pending, and keep the bounded watcher on
            // it so a settlement inside the window is still reported.
            reportPendingToMerchant(response: response, status: .pending)
            watchUnsettledIntent(paymentIntentId: response.paymentIntentId, underlying: nil)
            resetPayButton()

        // MARK: - SUCCEEDED
        case "SUCCEEDED":
            self.presentAuthorizedSuccess(response: response, pendingVC: pendingVC)

        // MARK: - CANCELLED
        case "CANCELLED":
            // The intent is dead; the merchant may need to unlock the order.
            // The failure screen alone told only the customer.
            if let delegate = self.paymentDelegate {
                delegate.paymentSheet(
                    self.reportingSheet,
                    didFailWithError: PaymentError(
                        code: .cancelled,
                        message: UqpayLocalized("Your payment has been cancelled."),
                        paymentMethodType: "card"
                    )
                )
            }

            if let pendingVC = pendingVC {
                pendingVC.transitionFromPending(
                    to: .cancelled,
                    transactionId: response.paymentIntentId,
                    message: UqpayLocalized("Your payment has been cancelled.")
                )
            } else {
                let config = PaymentStatusConfiguration(
                    status: .cancelled,
                    message: UqpayLocalized("Your payment has been cancelled."),
                    transactionId: response.paymentIntentId
                )
                let cancelledVC = PaymentCardStatusViewController(configuration: config)
                navigationController?.pushViewController(cancelledVC, animated: true)
            }
            resetPayButton()

        // MARK: - FAILED
        case "FAILED":
            let failureCode = (response.latestPaymentAttempt?.failureCode?.isEmpty == false)
                ? response.latestPaymentAttempt?.failureCode : nil

            if let delegate = self.paymentDelegate {
                delegate.paymentSheet(
                    self.reportingSheet,
                    didFailWithError: PaymentError(
                        code: Self.errorCode(forFailureCode: failureCode,
                                             intentStatus: .failed),
                        message: UqpayLocalized("Payment could not be completed. Please try again."),
                        declineCode: failureCode,
                        paymentMethodType: "card"
                    )
                )
            }

            if let pendingVC = pendingVC {
                pendingVC.transitionFromPending(
                    to: .failed,
                    errorCode: failureCode ?? "FAILED",
                    message: UqpayLocalized("Payment could not be completed. Please try again.")
                )
            } else {
                navigateToFailure(
                    errorCode: failureCode ?? "FAILED",
                    message: UqpayLocalized("Payment could not be completed. Please try again.")
                )
            }
            resetPayButton()

        // MARK: - PROCESSING (legacy support)
        case "PROCESSING":
            let processingMessage = "Your payment is still being processed. This may take a few more moments."
            if let pendingVC = pendingVC {
                pendingVC.primaryActionHandler = { [weak self] in
                    self?.dismissEntirePaymentSheet()
                }
                pendingVC.updateConfiguration(PaymentStatusConfiguration(
                    status: .processing,
                    message: processingMessage
                ), animated: true)
            } else {
                // With no status screen up, this branch used to do nothing at
                // all — the Pay button stayed disabled on "Processing..."
                // forever and nobody heard anything.
                let processingVC = PaymentCardStatusViewController.processing(
                    message: processingMessage
                )
                processingVC.primaryActionHandler = { [weak self] in
                    self?.dismissEntirePaymentSheet()
                }
                navigationController?.pushViewController(processingVC, animated: true)
            }

            reportPendingToMerchant(response: response, status: .processing)
            watchUnsettledIntent(paymentIntentId: response.paymentIntentId, underlying: nil)
            resetPayButton()

        // MARK: - Unexpected Status
        default:
            UqpayLogger.shared.error("Unexpected payment intent status: \(response.intentStatus)")
            self.handleUnexpectedStatus(response.intentStatus, pendingVC: pendingVC)
        }
    }

    /// Sends a confirm, replaying the identical request while its outcome is
    /// unknown.
    ///
    /// Replay is the only attribution that cannot lie: the response the
    /// server gives for THIS idempotency key is THIS attempt's outcome. If
    /// the original send reached the server, the replay returns its recorded
    /// result; if it never arrived, the replay simply performs it. Either
    /// way the bytes are identical (the device snapshot is frozen in the
    /// attempt), so no replay can become a second charge.
    private static func sendConfirmReplayingWhileUnknown(
        apiClient: ApiClient,
        paymentIntentId: String,
        encodedBody: Data,
        idempotencyKey: UqpayIdempotencyKey
    ) async throws -> ConfirmPaymentIntentResponse {
        var lastError: Error
        do {
            return try await apiClient.confirmPaymentIntent(
                paymentIntentId: paymentIntentId,
                encodedBody: encodedBody,
                idempotencyKey: idempotencyKey
            )
        } catch {
            lastError = error
        }

        for delaySeconds in [3.0, 6.0, 10.0] {
            guard ConfirmIdempotency.isOutcomeUnknown(lastError) else { throw lastError }
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            if Task.isCancelled { throw lastError }
            do {
                return try await apiClient.confirmPaymentIntent(
                    paymentIntentId: paymentIntentId,
                    encodedBody: encodedBody,
                    idempotencyKey: idempotencyKey
                )
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Maps a definitive API rejection onto the merchant-facing error code.
    ///
    /// Reporting every rejection as `.cardDeclined` told merchants a card was
    /// refused when the request was merely malformed or unauthenticated.
    /// Internal so the error-code table test can assert every code is reachable.
    static func errorCode(for apiError: UqpayAPIError?) -> PaymentError.ErrorCode {
        guard let apiError else { return .unknown }

        switch apiError.apiCode {
        case "card_declined", "insufficient_funds", "do_not_honor":
            return apiError.apiCode == "insufficient_funds" ? .insufficientFunds : .cardDeclined
        case "invalid_payment_method":
            return .invalidPaymentMethod
        case "3ds_failed":
            return .threeDSFailed
        default:
            break
        }

        switch apiError.httpStatus {
        case 401, 403:
            return .authenticationFailed
        case 402:
            return .cardDeclined
        case 400, 404, 422:
            return .invalidPaymentMethod
        default:
            return .unknown
        }
    }

    /// Customer-facing text for a definitive API rejection.
    ///
    /// Only the API's human-readable message is ever shown. Its machine code
    /// ("invalid_payment_method") belongs in `PaymentError.declineCode` and
    /// the failure screen's error code, never in the sentence a customer
    /// reads — `UqpayAPIError.errorDescription` falls back to the code when
    /// the message is empty, so it cannot be used here.
    private static func customerMessage(for apiError: UqpayAPIError?) -> String {
        if let apiError, case .api(_, let body) = apiError, !body.message.isEmpty {
            return body.message
        }
        return "The payment could not be completed. Please try again."
    }

    /// Maps an attempt's `failure_code` onto the merchant-facing error code.
    /// Internal so the raw-QR screen reports through the same mapping.
    static func errorCode(
        forFailureCode failureCode: String?,
        intentStatus: UqpayPaymentIntentStatus
    ) -> PaymentError.ErrorCode {
        if intentStatus == .cancelled { return .cancelled }
        switch failureCode {
        case "3ds_failed":
            return .threeDSFailed
        case "insufficient_funds":
            return .insufficientFunds
        default:
            return .cardDeclined
        }
    }

    /// The status screen currently on the stack, if any. Looked up at the
    /// moment of use — never cached across an await, because the customer can
    /// dismiss it while a read is in flight.
    @MainActor
    private func currentStatusVC() -> PaymentCardStatusViewController? {
        navigationController?.viewControllers
            .last(where: { $0 is PaymentCardStatusViewController }) as? PaymentCardStatusViewController
    }

    /// A confirm whose outcome stayed unknown even after replays.
    ///
    /// Nothing is guessed at this point. The customer sees an honest
    /// "couldn't confirm" state, the idempotency key stays pinned (Pay
    /// replays the identical attempt), and a bounded watcher reports the
    /// payment if it settles — successes and intent-terminal failures only,
    /// because those are the only outcomes attributable without inference.
    @MainActor
    private func reconcileUnobservedConfirm(paymentIntentId: String, error: Error) async {
        reportIndeterminateOutcome(
            paymentIntentId: paymentIntentId,
            statusVC: currentStatusVC(),
            underlying: error,
            message: UqpayLocalized("We couldn't confirm whether your payment went through. ")
                + "Check your payment status, or go back and try again."
        )
        watchUnsettledIntent(paymentIntentId: paymentIntentId, underlying: error)
    }

    /// Polls an unsettled intent for a bounded window (about a minute) so a
    /// payment that settles late is still observed.
    ///
    /// Deliberately reports only what needs no attribution: a succeeded (or
    /// capture-pending) intent means the customer paid, and a failed or
    /// cancelled intent means the payment as a whole is dead. Statuses tied
    /// to a specific attempt — a failed attempt row, a pending 3DS challenge
    /// — are left alone; the Pay button's same-key replay is the correct way
    /// to learn those.
    @MainActor
    private func watchUnsettledIntent(paymentIntentId: String, underlying: Error?) {
        // Newest request wins: a watcher for a superseded confirm would race
        // this one to report.
        reconcileWatchTask?.cancel()
        reconcileWatchTask = Task { [weak self] in
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard let intent = try? await ApiClient.forConfiguredEnvironment()
                    .retrievePaymentIntent(paymentIntentId) else { continue }
                if Task.isCancelled { return }

                switch intent.intentStatus {
                case .succeeded, .requiresCapture:
                    self.reportReconciledSuccess(intent: intent, statusVC: self.currentStatusVC())
                    return
                case .failed, .cancelled:
                    self.reportReconciledFailure(intent: intent, statusVC: self.currentStatusVC(), underlying: underlying)
                    return
                default:
                    continue
                }
            }
            // The window closed without a settlement. The pending screen is
            // already honest about that; the webhook remains the merchant's
            // authoritative source.
        }
    }

    /// Pre-confirm safety net: reports an already-finished intent through
    /// the reconciled paths and answers whether the confirm must be
    /// abandoned. SUCCEEDED is reported as the success it is — this is the
    /// relaunch-recovery UX for a confirm that went through just before the
    /// app was killed — and CANCELLED/FAILED as the intent-level failure.
    ///
    /// Fails OPEN by design: when the status cannot be read, the confirm
    /// proceeds. Double-charge protection is the idempotency machinery's
    /// job, and a flaky status GET must not become a new way for payments
    /// to be refused. Internal so tests can drive it with fixtures.
    @MainActor
    func interceptTerminalIntent(paymentIntentId: String) async -> Bool {
        guard let intent = try? await ApiClient.forConfiguredEnvironment()
            .retrievePaymentIntent(paymentIntentId) else { return false }
        return interceptTerminalIntent(intent)
    }

    /// The decision half, network-free for tests.
    @MainActor
    func interceptTerminalIntent(_ intent: UqpayPaymentIntent) -> Bool {
        switch intent.intentStatus {
        case .succeeded:
            reportReconciledSuccess(intent: intent, statusVC: currentStatusVC())
            return true
        case .failed, .cancelled:
            reportReconciledFailure(intent: intent, statusVC: currentStatusVC(), underlying: nil)
            return true
        default:
            return false
        }
    }

    /// Success learned from the intent rather than from the confirm response.
    ///
    /// The idempotency pin is deliberately left alone: it belongs to the
    /// sending task, and clearing it here could un-pin a different attempt.
    /// If the customer pays again with the same details the pinned send
    /// replays and the server returns this same settled outcome — safe.
    @MainActor
    private func reportReconciledSuccess(intent: UqpayPaymentIntent, statusVC: PaymentCardStatusViewController?) {
        KeychainHelper.shared.delete(forKey: "pending_payment_context")

        // The set guards only the merchant notification — the 3DS and
        // return-from-bank paths report through it too, and a payment must
        // reach the merchant exactly once. The UI is never guarded: the
        // customer must see the outcome even when another path already
        // delivered the report.
        if resolvedPaymentIntentIds.insert(intent.paymentIntentId).inserted,
           let delegate = paymentDelegate {
            delegate.paymentSheet(
                reportingSheet,
                didCompleteWithResult: ReconciledOutcome.successResult(for: intent)
            )
        }

        if let statusVC {
            statusVC.primaryActionHandler = { [weak self] in self?.dismissEntirePaymentSheet() }
            statusVC.transitionFromPending(
                to: .succeeded,
                transactionId: intent.paymentIntentId,
                message: UqpayLocalized("Your payment was successful.")
            )
        } else {
            let successVC = PaymentCardStatusViewController.success(
                amount: intent.amount ?? "",
                transactionId: intent.paymentIntentId,
                completion: { [weak self] in self?.dismissEntirePaymentSheet() }
            )
            navigationController?.pushViewController(successVC, animated: true)
        }
    }

    /// A failure of the intent as a whole — FAILED or CANCELLED — which needs
    /// no attempt attribution: the payment is dead however it got there.
    ///
    /// Failures never enter `resolvedPaymentIntentIds`: an intent can host
    /// several attempts, and a recorded failure must not swallow a later
    /// reconciled success — or its UI — for the same intent.
    @MainActor
    private func reportReconciledFailure(
        intent: UqpayPaymentIntent,
        statusVC: PaymentCardStatusViewController?,
        underlying: Error?
    ) {
        // The idempotency pin is left alone here too: a same-details retry
        // replays the pinned send and observes this same dead intent, which
        // the observed path then reports — no path to a second charge.
        // The API commonly returns "" rather than omitting these fields, which
        // `ReconciledOutcome` normalises. Built there so the detached watcher
        // reports this same payment identically.
        let failureCode = ReconciledOutcome.failureCode(for: intent)
        let message = ReconciledOutcome.failureMessage(for: intent)

        if let delegate = paymentDelegate {
            delegate.paymentSheet(
                reportingSheet,
                didFailWithError: ReconciledOutcome.failureError(for: intent, underlying: underlying)
            )
        }

        if let statusVC {
            statusVC.transitionFromPending(
                to: .failed,
                errorCode: failureCode ?? intent.intentStatus.rawValue,
                message: message
            )
        } else {
            navigateToFailure(
                errorCode: failureCode ?? intent.intentStatus.rawValue,
                message: message
            )
        }
        resetPayButton()
    }

    /// The payment is not settled and the SDK will not pretend otherwise.
    ///
    /// No success or failure is reported to the merchant: the authoritative
    /// outcome reaches their backend by webhook. The idempotency key stays
    /// pinned so a retry cannot become a second charge.
    @MainActor
    private func reportIndeterminateOutcome(
        paymentIntentId: String,
        statusVC: PaymentCardStatusViewController?,
        underlying: Error,
        message: String
    ) {
        UqpayLogger.shared.info("Confirm outcome undetermined; reporting as pending.")

        // The merchant hears the same honest state the customer sees. The
        // amount is unknown here — the confirm never answered — so only the
        // intent id travels.
        reportPendingToMerchant(
            paymentIntentId: paymentIntentId,
            amount: 0,
            currency: "",
            status: .pending
        )

        if let statusVC {
            statusVC.primaryActionHandler = { [weak self] in self?.dismissEntirePaymentSheet() }
            statusVC.transitionFromPending(to: .pending,
                                           transactionId: paymentIntentId,
                                           message: message)
        } else {
            let pendingVC = PaymentCardStatusViewController.pending(
                transactionId: paymentIntentId,
                message: message,
                completion: { [weak self] in self?.dismissEntirePaymentSheet() }
            )
            navigationController?.pushViewController(pendingVC, animated: true)
        }
        resetPayButton()
    }

    /// Reports a completed authorization to the merchant and shows the success
    /// screen. Used for both `SUCCEEDED` and plain `REQUIRES_CAPTURE` — per the
    /// API contract, `REQUIRES_CAPTURE` means the authorization succeeded and
    /// only settlement remains.
    private func presentAuthorizedSuccess(response: ConfirmPaymentIntentResponse, pendingVC: PaymentCardStatusViewController?) {
        KeychainHelper.shared.delete(forKey: "pending_payment_context")

        // Exactly-once to the merchant, like every other success path; the
        // UI below is never gated.
        if resolvedPaymentIntentIds.insert(response.paymentIntentId).inserted,
           let delegate = self.paymentDelegate {
            // Built explicitly rather than via PaymentResult(from:) because
            // this screen knows more than the response does: the method is
            // "card" even when the response omits it, and the authorization
            // completed *now*, whether or not `complete_time` is set yet.
            let wireAmount = WireAmount.parse(response.amount, paymentIntentId: response.paymentIntentId)
            let paymentResult = PaymentResult(
                paymentIntentId: response.paymentIntentId,
                paymentMethodType: response.paymentMethod?.type ?? "card",
                status: .succeeded,
                amount: wireAmount.double,
                currency: response.currency,
                metadata: response.metadata,
                merchantOrderId: response.merchantOrderId,
                completedAt: Date(),
                transactionId: response.latestPaymentAttempt?.attemptId,
                amountDecimal: wireAmount.decimal
            )
            delegate.paymentSheet(self.reportingSheet, didCompleteWithResult: paymentResult)
        }

        // API amounts are decimal strings in major units ("8.98"), shown as-is.
        let amount = "\(response.amount) \(response.currency)"

        if let pendingVC = pendingVC {
            pendingVC.primaryActionHandler = { [weak self] in
                self?.dismissEntirePaymentSheet()
            }

            pendingVC.transitionFromPending(
                to: .succeeded,
                transactionId: response.paymentIntentId,
                message: "Your payment of \(amount) has been processed successfully."
            )
        } else {
            let successViewController = PaymentCardStatusViewController.success(
                amount: amount,
                transactionId: response.paymentIntentId
            )

            successViewController.primaryActionHandler = { [weak self] in
                self?.dismissEntirePaymentSheet()
            }

            navigationController?.pushViewController(successViewController, animated: true)
        }
    }

    private func displayRawQRCode(image: UIImage, paymentIntentId: String, amount: String?, currency: String?) {
        let qrVC = PaymentCardRawQRViewController(qrImage: image)
        qrVC.paymentDelegate = paymentDelegate
        qrVC.paymentSheet = paymentSheet
        navigationController?.pushViewController(qrVC, animated: true)

        qrVC.startPollingForOutcome(
            paymentIntentId: paymentIntentId,
            amount: amount,
            currency: currency
        )
    }

    private func handleUnexpectedStatus(_ status: String, pendingVC: PaymentCardStatusViewController?) {
        if let delegate = self.paymentDelegate {
            delegate.paymentSheet(
                self.reportingSheet,
                didFailWithError: PaymentError(
                    code: .unknown,
                    message: "Unexpected payment status: \(status). Please try again.",
                    declineCode: status,
                    paymentMethodType: "card"
                )
            )
        }

        if let pendingVC = pendingVC {
            pendingVC.transitionFromPending(
                to: .failed,
                errorCode: status,
                message: "Unexpected payment status: \(status). Please try again."
            )
        } else {
            navigateToFailure(
                errorCode: status,
                message: "Unexpected payment status: \(status). Please try again."
            )
        }
        resetPayButton()
    }

    /// Validates the form before a confirm is sent.
    ///
    /// This defers to ``PaymentValidationHelper``, which runs the Luhn check,
    /// rejects expiry dates in the past and sizes the CVC by brand. The screen
    /// previously counted digits and nothing more, so a mistyped digit and an
    /// expired card both travelled to the acquirer and came back as declines —
    /// a worse message, a slower one, and a needless authorisation attempt.
    private func validateCardInputs() -> Bool {
        let cardNumber = cardNumberTextField.text ?? ""
        let expiry = expiryTextField.text ?? ""
        let cvc = cvvTextField.text ?? ""

        let result = PaymentValidationHelper.validateCard(
            cardNumber: cardNumber,
            expiryText: expiry,
            cvc: cvc
        )

        if let firstError = result.errors.first {
            showValidationError(Self.message(for: firstError, brand: result.brand))
            return false
        }

        guard billingCountryCode != nil else {
            showValidationError("Please select your billing country or region.")
            regionTextField.becomeFirstResponder()
            return false
        }

        return true
    }

    /// Turns a validation failure into something a customer can act on.
    private static func message(
        for error: PaymentValidationHelper.CardValidationResult.ValidationError,
        brand: CardBrand
    ) -> String {
        switch error {
        case .emptyCardNumber:
            return "Please enter your card number."
        case .invalidCardNumber, .invalidLuhn:
            // Luhn catches single-digit typos and transpositions, which is
            // almost always what this is.
            return "That card number doesn't look right. Please check it and try again."
        case .emptyExpiry:
            return "Please enter your card's expiry date."
        case .invalidExpiry:
            return "That expiry date isn't valid. Check the month and year — the card may have expired."
        case .emptyCVC:
            return "Please enter your card's security code."
        case .invalidCVC:
            let digits = brand == .amex ? 4 : 3
            return "The security code should be \(digits) digits."
        case .emptyCardholderName:
            return "Please enter the cardholder's name."
        }
    }

    /// The ISO 3166-1 alpha-2 code for the chosen billing country.
    ///
    /// Only ever the customer's own selection. This replaced a nine-entry
    /// name-to-code table that fell back to `"US"`, which meant every customer
    /// outside those nine countries had the wrong country sent to the issuer.
    private var billingCountryCode: String? {
        selectedCountry?.code
    }

    // MARK: - Payment Sheet Dismissal

    /// Dismisses the entire payment sheet modal
    private func dismissEntirePaymentSheet() {
        // Try to find the AppNavigationViewController and dismiss it
        if let navController = self.navigationController {
            if navController is AppNavigationViewController {
                navController.dismiss(animated: true)
            } else if let presentingVC = navController.presentingViewController {
                presentingVC.dismiss(animated: true)
            }
        } else {
            // Fallback: Find and dismiss the topmost presented controller
            if let window = uqpayResolvedWindow,
               let rootVC = window.rootViewController {

                var currentVC = rootVC
                while let presented = currentVC.presentedViewController {
                    currentVC = presented
                }

                if currentVC != rootVC {
                    rootVC.dismiss(animated: true)
                }
            }
        }
    }

    private func navigateToFailure(errorCode: String? = nil, message: String) {
        let failedViewController = PaymentCardStatusViewController.failed(
            errorCode: errorCode,
            message: message,
            onRetry: { [weak self] in
                // Pop back to this card payment view
                self?.navigationController?.popViewController(animated: true)
                self?.resetPayButton()
            },
            onCancel: { [weak self] in
                // Dismiss the entire payment flow
                self?.dismissEntirePaymentSheet()
            }
        )

        // The handlers are already set correctly in the factory method:
        // - primaryActionHandler = onRetry (pops back to card view)
        // - secondaryActionHandler = onCancel (dismisses entire sheet)

        navigationController?.pushViewController(failedViewController, animated: true)
    }

    private func resetPayButton() {
        payButton.isEnabled = true
        payButton.setTitle(UqpayLocalized("Pay"), for: .normal)
    }

    private func showValidationError(_ message: String) {
        // For validation errors, we'll still use a simple alert as these are immediate input errors
        // that don't warrant a full-screen status view
        let alert = UIAlertController(title: UqpayLocalized("Validation Error"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: UqpayLocalized("OK"), style: .default))
        present(alert, animated: true)
    }


    // MARK: - Card Formatting & Validation
    private func formatCardNumber(_ text: String) -> String {
        let cleanedText = text.replacingOccurrences(of: " ", with: "")
        let groups = stride(from: 0, to: cleanedText.count, by: 4).map {
            let start = cleanedText.index(cleanedText.startIndex, offsetBy: $0)
            let end = cleanedText.index(start, offsetBy: min(4, cleanedText.count - $0))
            return String(cleanedText[start..<end])
        }
        return groups.joined(separator: " ")
    }

    private func formatExpiryDate(_ text: String) -> String {
        let cleanedText = text.replacingOccurrences(of: "/", with: "")
        guard !cleanedText.isEmpty else { return "" }

        if cleanedText.count <= 2 {
            return cleanedText
        } else {
            let month = String(cleanedText.prefix(2))
            let year = String(cleanedText.dropFirst(2).prefix(2))
            return "\(month)/\(year)"
        }
    }

    private func detectCardBrand(from cardNumber: String) -> CardBrand {
        let cleanedNumber = cardNumber.replacingOccurrences(of: " ", with: "")

        // Use existing card brand detection from UqpayPayments
        return CardValidator.brand(for: cleanedNumber)
    }

    private func updateCardBrandIcon(_ brand: CardBrand) {
        currentCardBrand = brand

        // Show or hide the card brand image based on detection
        if brand == .unknown {
            cardBrandImageView.isHidden = true
            return
        }

        cardBrandImageView.isHidden = false

        switch brand {
        case .visa:
            // Try to load from bundle first, then create a text-based image
            if let image = UIImage(named: "visa", in: UqpayResourceManager.bundle, compatibleWith: nil) {
                cardBrandImageView.image = image
            } else {
                // Create a text-based Visa logo
                cardBrandImageView.image = createCardBrandImage(text: "VISA", backgroundColor: .white, textColor: UIColor(red: 0/255.0, green: 57/255.0, blue: 166/255.0, alpha: 1.0))
            }
        case .masterCard:
            if let image = UIImage(named: "mastercard", in: UqpayResourceManager.bundle, compatibleWith: nil) {
                cardBrandImageView.image = image
            } else {
                // Create a text-based MasterCard logo
                cardBrandImageView.image = createCardBrandImage(text: "MC", backgroundColor: .white, textColor: UIColor(red: 235/255.0, green: 0/255.0, blue: 27/255.0, alpha: 1.0))
            }
        case .amex:
            if let image = UIImage(named: "amex", in: UqpayResourceManager.bundle, compatibleWith: nil) {
                cardBrandImageView.image = image
            } else {
                cardBrandImageView.image = createCardBrandImage(text: "AMEX", backgroundColor: UIColor(red: 0/255.0, green: 135/255.0, blue: 196/255.0, alpha: 1.0), textColor: .white)
            }
        case .discover:
            if let image = UIImage(named: "discover", in: UqpayResourceManager.bundle, compatibleWith: nil) {
                cardBrandImageView.image = image
            } else {
                cardBrandImageView.image = createCardBrandImage(text: "DISC", backgroundColor: .white, textColor: UIColor(red: 255/255.0, green: 102/255.0, blue: 0/255.0, alpha: 1.0))
            }
        case .jcb:
            if let image = UIImage(named: "jcb", in: UqpayResourceManager.bundle, compatibleWith: nil) {
                cardBrandImageView.image = image
            } else {
                cardBrandImageView.image = createCardBrandImage(text: "JCB", backgroundColor: .white, textColor: UIColor(red: 0/255.0, green: 94/255.0, blue: 184/255.0, alpha: 1.0))
            }
        case .dinersClub:
            if let image = UIImage(named: "diners", in: UqpayResourceManager.bundle, compatibleWith: nil) {
                cardBrandImageView.image = image
            } else {
                cardBrandImageView.image = createCardBrandImage(text: "DC", backgroundColor: .white, textColor: UIColor(red: 0/255.0, green: 72/255.0, blue: 153/255.0, alpha: 1.0))
            }
        case .unionPay:
            if let image = UIImage(named: "unionpay", in: UqpayResourceManager.bundle, compatibleWith: nil) {
                cardBrandImageView.image = image
            } else {
                cardBrandImageView.image = createCardBrandImage(text: "UP", backgroundColor: .white, textColor: UIColor(red: 226/255.0, green: 36/255.0, blue: 36/255.0, alpha: 1.0))
            }
        default:
            cardBrandImageView.image = nil
            cardBrandImageView.isHidden = true
        }

        // Update CVV field placeholder based on card brand
        updateCVVPlaceholder(for: brand)
    }

    private func createCardBrandImage(text: String, backgroundColor: UIColor, textColor: UIColor) -> UIImage? {
        let size = CGSize(width: 36, height: 22)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            // Draw background
            backgroundColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Draw text
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: textColor
            ]

            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )

            text.draw(in: textRect, withAttributes: attributes)
        }
    }

    private func updateCVVPlaceholder(for brand: CardBrand) {
        switch brand {
        case .amex:
            cvvTextField.placeholder = UqpayLocalized("CVVV")
        default:
            cvvTextField.placeholder = UqpayLocalized("CVV")
        }
    }

    private func getCVVLength(for brand: CardBrand) -> Int {
        switch brand {
        case .amex:
            return 4
        default:
            return 3
        }
    }

    private func convertToFourDigitYear(_ twoDigitYear: String) -> String {
        guard let yearInt = Int(twoDigitYear), twoDigitYear.count == 2 else {
            // If conversion fails, return the original string
            return twoDigitYear
        }

        // For credit card expiry dates:
        // - Years 00-99 map to 2000-2099 for simplicity
        // - This covers all valid credit card expiry dates
        let fourDigitYear = 2000 + yearInt

        return String(fourDigitYear)
    }
}

// MARK: - Country picker

extension PaymentCardViewController: UIPickerViewDataSource, UIPickerViewDelegate {

    public func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    public func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        countries.count
    }

    public func pickerView(
        _ pickerView: UIPickerView,
        titleForRow row: Int,
        forComponent component: Int
    ) -> String? {
        countries.indices.contains(row) ? countries[row].name : nil
    }

    public func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        guard countries.indices.contains(row) else { return }
        select(country: countries[row])
    }
}

// MARK: - UITextFieldDelegate
extension PaymentCardViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let currentText = textField.text,
              let textRange = Range(range, in: currentText) else {
            return true
        }

        let updatedText = currentText.replacingCharacters(in: textRange, with: string)

        if textField == cardNumberTextField {
            // Allow only numbers and limit to 19 characters (16 digits + 3 spaces)
            let cleanedText = updatedText.replacingOccurrences(of: " ", with: "")

            // Check if input is numeric
            if !string.isEmpty && !CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: string)) {
                return false
            }

            // UnionPay issues numbers up to 19 digits; a 16-digit cap made
            // those cards impossible to type. Luhn and brand rules decide
            // validity — this only bounds the field.
            if cleanedText.count > 19 {
                return false
            }

            // Format and update text
            let formattedText = formatCardNumber(cleanedText)
            textField.text = formattedText

            // Detect and update card brand
            let brand = detectCardBrand(from: cleanedText)
            updateCardBrandIcon(brand)

            // Move cursor to the end
            if let newPosition = textField.position(from: textField.beginningOfDocument, offset: formattedText.count) {
                textField.selectedTextRange = textField.textRange(from: newPosition, to: newPosition)
            }

            return false

        } else if textField == expiryTextField {
            // Allow only numbers and forward slash
            if !string.isEmpty && !CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: string)) {
                return false
            }

            let cleanedText = updatedText.replacingOccurrences(of: "/", with: "")

            // Limit to 4 digits (MMYY)
            if cleanedText.count > 4 {
                return false
            }

            // Format and update text
            let formattedText = formatExpiryDate(cleanedText)
            textField.text = formattedText

            // Auto-move to CVV field when complete
            if cleanedText.count == 4 {
                DispatchQueue.main.async {
                    self.cvvTextField.becomeFirstResponder()
                }
            }

            // Move cursor to the end
            if let newPosition = textField.position(from: textField.beginningOfDocument, offset: formattedText.count) {
                textField.selectedTextRange = textField.textRange(from: newPosition, to: newPosition)
            }

            return false

        } else if textField == cvvTextField {
            // Allow only numbers
            if !string.isEmpty && !CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: string)) {
                return false
            }

            // Limit based on card brand
            let maxLength = getCVVLength(for: currentCardBrand)
            if updatedText.count > maxLength {
                return false
            }

            return true

        } else if textField == firstNameTextField || textField == lastNameTextField {
            // Allow letters, spaces, and common name characters
            let allowedCharacters = CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "'-"))
            if !string.isEmpty && !allowedCharacters.isSuperset(of: CharacterSet(charactersIn: string)) {
                return false
            }

            // Limit to reasonable length
            if updatedText.count > 50 {
                return false
            }

            return true

        } else if textField == addressLineTextField {
            // Allow letters, numbers, spaces, and common address characters
            let allowedCharacters = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "#.,-/'"))
            if !string.isEmpty && !allowedCharacters.isSuperset(of: CharacterSet(charactersIn: string)) {
                return false
            }

            // Limit to reasonable length
            if updatedText.count > 100 {
                return false
            }

            return true

        } else if textField == cityTextField {
            // Allow letters, spaces, and common city name characters
            let allowedCharacters = CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "'-,."))
            if !string.isEmpty && !allowedCharacters.isSuperset(of: CharacterSet(charactersIn: string)) {
                return false
            }

            // Limit to reasonable length
            if updatedText.count > 50 {
                return false
            }

            return true

        } else if textField == postalCodeTextField {
            // Allow letters, numbers, spaces, and hyphens for international postal codes
            let allowedCharacters = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-"))
            if !string.isEmpty && !allowedCharacters.isSuperset(of: CharacterSet(charactersIn: string)) {
                return false
            }

            // Limit to reasonable length
            if updatedText.count > 10 {
                return false
            }

            return true
        }

        return true
    }

    public func textFieldDidBeginEditing(_ textField: UITextField) {
        // Add blue focus border
        textField.layer.borderColor = UqpayColors.focusBorder.cgColor
        textField.layer.borderWidth = 2

        // Add shadow for focus effect
        textField.layer.shadowColor = UqpayColors.focusGlow.cgColor
        textField.layer.shadowOpacity = 1
        textField.layer.shadowRadius = 4
        textField.layer.shadowOffset = CGSize(width: 0, height: 0)
    }

    public func textFieldDidEndEditing(_ textField: UITextField) {
        // Reset to default border
        textField.layer.borderColor = UqpayColors.border.cgColor
        textField.layer.borderWidth = 1

        // Remove shadow
        textField.layer.shadowOpacity = 0
    }
}

// MARK: - 3D Secure

extension PaymentCardViewController {

    /// Guards against the poll and the cancel handler both resolving the step.
    private final class ResolutionGuard {
        var isResolved = false
    }

    /// Presents the 3D Secure step and resolves it against the API.
    ///
    /// The browser step never reports an outcome — it only ends. The real result
    /// is delivered to the merchant's backend by webhook, so the intent is read
    /// back from the API before anything is shown to the customer. Showing
    /// success purely because the browser closed would tell people a declined or
    /// abandoned payment had gone through.
    func beginThreeDS(
        content: UqpayThreeDSViewController.Content,
        actionType: String,
        paymentIntentId: String,
        amount: String,
        pendingVC: PaymentCardStatusViewController?,
        apiReturnURL: String? = nil,
        // A 3DS challenge is answered in seconds; a QR has to be scanned with
        // a second device, so that caller asks for longer.
        timeout: TimeInterval = 300
    ) {
        let threeDSController = UqpayThreeDSViewController(
            content: content,
            returnURLPrefixes: [UqpayConfiguration.shared.appReturnScheme, apiReturnURL],
            appearance: PaymentSheet.Appearance(primaryColor: .systemBlue)
        )
        let host = UINavigationController(rootViewController: threeDSController)
        host.modalPresentationStyle = .formSheet
        host.isModalInPresentation = true

        let guardBox = ResolutionGuard()
        activeThreeDSGuard = guardBox

        // The customer is about to leave for the issuer (or a wallet app).
        switch content {
        case .url(let url):
            reportRequiredAction(
                actionType == "display_qr_code"
                    ? .scanQRCode(qrCodeUrl: url.absoluteString)
                    : .authenticate3DS(url: url.absoluteString)
            )
        case .iframeHTML:
            reportRequiredAction(.authenticate3DS(url: apiReturnURL ?? ""))
        }

        let pollTask = Task { [weak self] in
            do {
                let apiClient = try ApiClient.forConfiguredEnvironment()
                let intent = try await apiClient.awaitThreeDSOutcome(
                    paymentIntentId: paymentIntentId,
                    excludingActionType: actionType,
                    timeout: timeout
                )
                await MainActor.run {
                    self?.resolveThreeDS(.success(intent), guardBox: guardBox, host: host,
                                         amount: amount, pendingVC: pendingVC)
                }
            } catch {
                await MainActor.run {
                    self?.resolveThreeDS(.failure(error), guardBox: guardBox, host: host,
                                         amount: amount, pendingVC: pendingVC)
                }
            }
        }

        threeDSController.onCancel = { [weak self] in
            pollTask.cancel()
            // The customer may have authenticated and then closed the screen, so
            // read the real status instead of assuming they gave up.
            Task { [weak self] in
                let outcome: Result<UqpayPaymentIntent, Error>
                do {
                    let apiClient = try ApiClient.forConfiguredEnvironment()
                    outcome = .success(try await apiClient.retrievePaymentIntent(paymentIntentId))
                } catch {
                    outcome = .failure(error)
                }
                await MainActor.run {
                    self?.resolveThreeDS(outcome, guardBox: guardBox, host: host,
                                         amount: amount, pendingVC: pendingVC)
                }
            }
        }

        // Reaching the return URL only means the browser step ended. Close the
        // web view and let the poll settle what actually happened.
        threeDSController.onReachedReturnURL = { [weak host] in
            host?.dismiss(animated: true)
        }

        pendingVC?.updateConfiguration(
            PaymentStatusConfiguration(status: .processing, message: UqpayLocalized("Verifying with your bank…")),
            animated: true
        )

        // This controller is no longer on screen — pushing the pending status
        // screen removed its view from the window hierarchy, and presenting from
        // a detached controller silently does nothing. Present from the
        // navigation controller, then walk past anything already presented.
        var presenter: UIViewController = navigationController ?? self
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        UqpayLogger.shared.info(
            "Presenting 3DS step '\(actionType)' for \(paymentIntentId) from \(type(of: presenter))"
        )
        presenter.present(host, animated: true) {
            UqpayLogger.shared.debug("3DS step presented; polling for the outcome")
        }
    }

    private func resolveThreeDS(
        _ outcome: Result<UqpayPaymentIntent, Error>,
        guardBox: ResolutionGuard,
        host: UINavigationController,
        amount: String,
        pendingVC: PaymentCardStatusViewController?
    ) {
        guard !guardBox.isResolved else { return }
        guardBox.isResolved = true
        if activeThreeDSGuard === guardBox {
            activeThreeDSGuard = nil
        }

        switch outcome {
        case .success(let intent):
            UqpayLogger.shared.info(
                "3DS resolved: \(intent.intentStatus.rawValue), next_action \(intent.nextAction?.type ?? "none")"
            )
        case .failure(let error):
            // The description only. Logging the Error itself puts a URLError
            // userInfo — which carries the failing URL, and with it the
            // intent id — into the unified log.
            UqpayLogger.shared.error(
                "3DS could not be resolved: \((error as? LocalizedError)?.errorDescription ?? "request failed")"
            )
        }

        let proceed = { [weak self] in
            guard let self else { return }
            switch outcome {
            case .success(let intent):
                self.presentThreeDSResult(intent, amount: amount, pendingVC: pendingVC)
            case .failure(let error):
                // A timed-out poll is not a decline: the outcome was never
                // observed. Anything else here is a transport failure.
                let timedOut = (error as? PaymentSheetError) == .authenticationTimedOut
                self.presentThreeDSFailure(
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                    code: timedOut ? .timeout : .networkError,
                    pendingVC: pendingVC
                )
            }
        }

        if host.presentingViewController != nil {
            host.dismiss(animated: true, completion: proceed)
        } else {
            proceed()
        }
    }

    private func presentThreeDSResult(
        _ intent: UqpayPaymentIntent,
        amount: String,
        pendingVC: PaymentCardStatusViewController?
    ) {
        switch intent.intentStatus {
        case .succeeded, .requiresCapture:
            KeychainHelper.shared.delete(forKey: "pending_payment_context")

            // The merchant's app must hear about the outcome the moment it is
            // known, exactly as the non-3DS success path reports it — not when
            // the customer eventually taps Done. The insert result gates the
            // notification: the poll and the return-from-bank callback can
            // both land here, and the merchant must hear about the payment
            // exactly once.
            if resolvedPaymentIntentIds.insert(intent.paymentIntentId).inserted,
               let delegate = paymentDelegate {
                let wireAmount = WireAmount.parse(
                    intent.amount, fallback: amount, paymentIntentId: intent.paymentIntentId
                )
                let result = PaymentResult(
                    paymentIntentId: intent.paymentIntentId,
                    paymentMethodType: "card",
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
                amount: amount,
                transactionId: intent.paymentIntentId
            ) { [weak self] in
                self?.dismissEntirePaymentSheet()
            }
            navigationController?.pushViewController(successVC, animated: true)

        case .requiresCustomerAction:
            // A device fingerprint is commonly followed by a challenge screen.
            guard let next = intent.nextAction else {
                presentThreeDSFailure(message: UqpayLocalized("Authentication could not be completed."), code: .threeDSFailed, pendingVC: pendingVC)
                return
            }

            if let iframe = next.redirectIframe?.iframe, !iframe.isEmpty {
                beginThreeDS(content: .iframeHTML(iframe), actionType: "redirect_iframe",
                             paymentIntentId: intent.paymentIntentId, amount: amount, pendingVC: pendingVC)
            } else if let urlString = next.redirectToUrl?.url, let url = URL(string: urlString) {
                beginThreeDS(content: .url(url), actionType: "redirect_to_url",
                             paymentIntentId: intent.paymentIntentId, amount: amount, pendingVC: pendingVC,
                             apiReturnURL: next.redirectToUrl?.returnUrl)
            } else {
                presentThreeDSFailure(message: UqpayLocalized("Authentication could not be completed."), code: .threeDSFailed, pendingVC: pendingVC)
            }

        case .cancelled:
            presentThreeDSFailure(message: UqpayLocalized("The payment was cancelled."), code: .cancelled, pendingVC: pendingVC)

        case .requiresPaymentMethod:
            // The attempt failed and the intent is asking for a new payment
            // method. The API often leaves failure_message empty here with only
            // failure_code set (e.g. "3ds_failed"), so map the code ourselves.
            let attempt = intent.latestPaymentAttempt
            let failureCode = (attempt?.failureCode?.isEmpty == false) ? attempt?.failureCode : nil
            let message: String
            if let reason = attempt?.failureMessage, !reason.isEmpty {
                message = reason
            } else if failureCode == "3ds_failed" {
                message = "Card authentication failed. Try another card or contact your bank."
            } else {
                message = "The payment could not be completed. Please try again."
            }
            presentThreeDSFailure(
                message: message,
                code: Self.errorCode(forFailureCode: failureCode, intentStatus: intent.intentStatus),
                declineCode: failureCode,
                pendingVC: pendingVC
            )

        default:
            let attempt = intent.latestPaymentAttempt
            let failureCode = (attempt?.failureCode?.isEmpty == false) ? attempt?.failureCode : nil
            let reason = attempt?.failureMessage
            presentThreeDSFailure(
                message: (reason?.isEmpty == false ? reason : nil) ?? "Authentication failed. Please try again.",
                code: Self.errorCode(forFailureCode: failureCode, intentStatus: intent.intentStatus),
                declineCode: failureCode,
                pendingVC: pendingVC
            )
        }
    }

    /// Every 3DS failure used to be reported as `.cardDeclined` — timeouts
    /// and customer cancellations included — so merchants routing on
    /// `error.code` mis-bucketed them. The caller names what actually
    /// happened.
    private func presentThreeDSFailure(
        message: String,
        code: PaymentError.ErrorCode,
        declineCode: String? = nil,
        pendingVC: PaymentCardStatusViewController?
    ) {
        if let delegate = paymentDelegate {
            delegate.paymentSheet(
                self.reportingSheet,
                didFailWithError: PaymentError(
                    code: code,
                    message: message,
                    declineCode: declineCode,
                    paymentMethodType: "card"
                )
            )
        }

        let failedVC = PaymentCardStatusViewController.failed(
            message: message,
            onCancel: { [weak self] in self?.dismissEntirePaymentSheet() }
        )
        navigationController?.pushViewController(failedVC, animated: true)
        resetPayButton()
    }
}


