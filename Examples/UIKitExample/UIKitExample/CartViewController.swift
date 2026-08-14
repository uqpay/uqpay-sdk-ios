//
//  CartViewController.swift
//  UIKitExample
//
//  Created by UQPAY
//

import UIKit
import UqpayPaymentSheet
import UqpayCore
import UqpayPayments
import Combine

// Cart Item Model for UIKit
struct CartItemModel {
    let id = UUID()
    let name: String
    let size: String
    let price: Double
    let imageName: String
}

// Shipping Address Model
struct ShippingAddressModel {
    let name: String
    let phoneCode: String
    let phoneNumber: String
    let address: String

    var formattedPhone: String {
        "\(phoneCode) \(phoneNumber)"
    }
}

class CartViewController: UIViewController {

    // MARK: - Properties
    var viewModel: ContentViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var cartItems: [CartItemModel] = [
        CartItemModel(name: "T-Shirt", size: "XL", price: 10.00, imageName: "tshirt"),
        CartItemModel(name: "Jeans", size: "XL", price: 10.00, imageName: "rectangle.stack")
    ]

    private let deliveryFee: Double = 2.00
    private let discount: Double = 0.00

    private var subtotal: Double {
        cartItems.reduce(0) { $0 + $1.price }
    }

    private var total: Double {
        subtotal + deliveryFee - discount
    }

    private let shippingAddress = ShippingAddressModel(
        name: "John",
        phoneCode: "+65",
        phoneNumber: "520*102",
        address: "123 Orchard Road, Singapore 238888"
    )

    // MARK: - UI Components
    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .grouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .white
        table.separatorStyle = .singleLine
        table.contentInsetAdjustmentBehavior = .automatic
        return table
    }()

    private let checkoutButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Checkout", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let checkoutContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.05
        view.layer.shadowOffset = CGSize(width: 0, height: -2)
        view.layer.shadowRadius = 4
        return view
    }()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        // Force light mode for consistent appearance across all iOS versions
        overrideUserInterfaceStyle = .light
        setupUI()
        setupTableView()

        // The payment intent is created when the customer taps Checkout, not here.
        // Creating it on load would charge an amount the customer can still change,
        // and would waste an intent every time the cart is merely opened.
    }

    // MARK: - Setup Methods
    private func setupUI() {
        view.backgroundColor = .white
        title = "My Cart"

        // Setup navigation bar
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backButtonTapped)
        )

        // Add subviews
        view.addSubview(tableView)
        view.addSubview(checkoutContainer)
        checkoutContainer.addSubview(checkoutButton)

        // Setup constraints
        NSLayoutConstraint.activate([
            // Table View
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: checkoutContainer.topAnchor),

            // Checkout Container
            checkoutContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            checkoutContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            checkoutContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            checkoutContainer.heightAnchor.constraint(equalToConstant: 80),

            // Checkout Button
            checkoutButton.leadingAnchor.constraint(equalTo: checkoutContainer.leadingAnchor, constant: 16),
            checkoutButton.trailingAnchor.constraint(equalTo: checkoutContainer.trailingAnchor, constant: -16),
            checkoutButton.centerYAnchor.constraint(equalTo: checkoutContainer.centerYAnchor),
            checkoutButton.heightAnchor.constraint(equalToConstant: 50)
        ])

        // Setup button action
        checkoutButton.addTarget(self, action: #selector(checkoutButtonTapped), for: .touchUpInside)
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(CartItemTableViewCell.self, forCellReuseIdentifier: "CartItemCell")
        tableView.register(PriceSummaryCell.self, forCellReuseIdentifier: "PriceSummaryCell")
        tableView.register(ShippingAddressCell.self, forCellReuseIdentifier: "ShippingAddressCell")
    }

    // MARK: - Actions
    @objc private func backButtonTapped() {
        dismiss(animated: true)
    }

    @objc private func checkoutButtonTapped() {
        guard let viewModel = viewModel else {
            showErrorAlert("ViewModel not set")
            return
        }

        Task { @MainActor in
            do {
                try await viewModel.prepareCheckout(
                    amount: Self.decimal(from: total),
                    description: "Cart order"
                )
                dismissAndShowPaymentList()
            } catch {
                showErrorAlert(error.localizedDescription)
            }
        }
    }

    /// Converts through a fixed-scale string so binary floating point cannot
    /// introduce a rounding difference between the display and the charge.
    private static func decimal(from value: Double) -> Decimal {
        Decimal(string: String(format: "%.2f", value)) ?? 0
    }

    /// Holds the sheet while its UI is up: the SDK's screens keep only weak
    /// references back to it, so the merchant owns its lifetime.
    private static var activePaymentSheet: PaymentSheet?

    private func dismissAndShowPaymentList() {
        dismiss(animated: true) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else { return }
            // `primaryColor` drives the pay button, selection highlights, and
            // the loading indicator. The SDK default is violet (#7C4DFF).
            let appearance = PaymentSheet.Appearance(primaryColor: .systemBlue)
            let configuration = PaymentSheet.Configuration()
            let sheet = PaymentSheet(configuration: configuration, appearance: appearance)
            Self.activePaymentSheet = sheet
            sheet.loadViewController { result in
                switch result {
                case .success(let viewController):
                    rootVC.present(viewController, animated: true)
                case .failure(let error):
                    let alert = UIAlertController(
                        title: "Error",
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    rootVC.present(alert, animated: true)
                }
            }
        }
    }

    private func removeItem(at index: Int) {
        cartItems.remove(at: index)
        tableView.reloadData()
    }

    // MARK: - Loading & Error Handling
    private var loadingAlert: UIAlertController?

    private func showLoadingAlert() {
        let alert = UIAlertController(title: nil, message: "Processing payment...\n\n", preferredStyle: .alert)

        let loadingIndicator = UIActivityIndicatorView(style: .medium)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.startAnimating()

        alert.view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            loadingIndicator.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -20)
        ])

        loadingAlert = alert
        present(alert, animated: true)
    }

    private func dismissLoadingAlert() {
        loadingAlert?.dismiss(animated: true)
        loadingAlert = nil
    }

    private func showErrorAlert(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableView DataSource & Delegate
extension CartViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 3 // Items, Price Summary, Shipping
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return cartItems.count
        case 1: return 1 // Price summary
        case 2: return 1 // Shipping address
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Item"
        case 2: return "Shipping"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "CartItemCell", for: indexPath) as! CartItemTableViewCell
            let item = cartItems[indexPath.row]
            cell.configure(with: item) { [weak self] in
                self?.removeItem(at: indexPath.row)
            }
            return cell

        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "PriceSummaryCell", for: indexPath) as! PriceSummaryCell
            cell.configure(subtotal: subtotal, deliveryFee: deliveryFee, discount: discount, total: total)
            return cell

        case 2:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ShippingAddressCell", for: indexPath) as! ShippingAddressCell
            cell.configure(with: shippingAddress)
            return cell

        default:
            return UITableViewCell()
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case 0: return 80
        case 1: return 160
        case 2: return 80
        default: return 44
        }
    }
}

// MARK: - Custom Table View Cells

class CartItemTableViewCell: UITableViewCell {
    private let productImageView = UIImageView()
    private let nameLabel = UILabel()
    private let sizeLabel = UILabel()
    private let priceLabel = UILabel()
    private let removeButton = UIButton(type: .system)
    private var removeAction: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        selectionStyle = .none

        // Configure views
        productImageView.backgroundColor = UIColor.systemGray6
        productImageView.layer.cornerRadius = 8
        productImageView.contentMode = .center
        productImageView.tintColor = .systemGray

        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        sizeLabel.font = .systemFont(ofSize: 12)
        sizeLabel.textColor = .systemGray

        priceLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        removeButton.setTitle("Remove", for: .normal)
        removeButton.titleLabel?.font = .systemFont(ofSize: 12)
        removeButton.setTitleColor(.systemRed, for: .normal)

        // Add views
        [productImageView, nameLabel, sizeLabel, priceLabel, removeButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        // Constraints
        NSLayoutConstraint.activate([
            productImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            productImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            productImageView.widthAnchor.constraint(equalToConstant: 60),
            productImageView.heightAnchor.constraint(equalToConstant: 60),

            nameLabel.leadingAnchor.constraint(equalTo: productImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: productImageView.topAnchor, constant: 8),

            sizeLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            sizeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),

            priceLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            priceLabel.topAnchor.constraint(equalTo: productImageView.topAnchor, constant: 8),

            removeButton.trailingAnchor.constraint(equalTo: priceLabel.trailingAnchor),
            removeButton.topAnchor.constraint(equalTo: priceLabel.bottomAnchor, constant: 8)
        ])

        removeButton.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)
    }

    func configure(with item: CartItemModel, removeAction: @escaping () -> Void) {
        nameLabel.text = item.name
        sizeLabel.text = item.size
        priceLabel.text = "S$\(String(format: "%.2f", item.price))"
        self.removeAction = removeAction

        if let image = UIImage(systemName: item.imageName) {
            productImageView.image = image
        }
    }

    @objc private func removeButtonTapped() {
        removeAction?()
    }
}

class PriceSummaryCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(subtotal: Double, deliveryFee: Double, discount: Double, total: Double) {
        contentView.subviews.forEach { $0.removeFromSuperview() }

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        // Add price rows
        addPriceRow(to: stackView, title: "Subtotal", value: "S$\(String(format: "%.2f", subtotal))", isTotal: false)
        addPriceRow(to: stackView, title: "Delivery Fee", value: "S$\(String(format: "%.2f", deliveryFee))", isTotal: false)
        addPriceRow(to: stackView, title: "Discount", value: "\(String(format: "%.2f", discount))", isTotal: false)

        // Add separator
        let separator = UIView()
        separator.backgroundColor = .systemGray5
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        stackView.addArrangedSubview(separator)

        // Add total
        addPriceRow(to: stackView, title: "Total", value: "S$\(String(format: "%.2f", total))", isTotal: true)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    private func addPriceRow(to stackView: UIStackView, title: String, value: String, isTotal: Bool) {
        let rowView = UIView()
        let titleLabel = UILabel()
        let valueLabel = UILabel()

        titleLabel.text = title
        titleLabel.font = isTotal ? .systemFont(ofSize: 16, weight: .semibold) : .systemFont(ofSize: 14)
        titleLabel.textColor = isTotal ? .label : .systemGray

        valueLabel.text = value
        valueLabel.font = isTotal ? .systemFont(ofSize: 16, weight: .bold) : .systemFont(ofSize: 14, weight: .medium)

        [titleLabel, valueLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            rowView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            rowView.heightAnchor.constraint(equalToConstant: 20)
        ])

        stackView.addArrangedSubview(rowView)
    }
}

class ShippingAddressCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with address: ShippingAddressModel) {
        contentView.subviews.forEach { $0.removeFromSuperview() }

        let iconView = UIImageView(image: UIImage(systemName: "mappin.circle"))
        iconView.tintColor = .systemGray
        iconView.contentMode = .scaleAspectFit

        let namePhoneLabel = UILabel()
        namePhoneLabel.text = "\(address.name) | \(address.formattedPhone)"
        namePhoneLabel.font = .systemFont(ofSize: 14, weight: .medium)

        let addressLabel = UILabel()
        addressLabel.text = address.address
        addressLabel.font = .systemFont(ofSize: 13)
        addressLabel.textColor = .systemGray
        addressLabel.numberOfLines = 2

        [iconView, namePhoneLabel, addressLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            namePhoneLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            namePhoneLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            namePhoneLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            addressLabel.leadingAnchor.constraint(equalTo: namePhoneLabel.leadingAnchor),
            addressLabel.topAnchor.constraint(equalTo: namePhoneLabel.bottomAnchor, constant: 4),
            addressLabel.trailingAnchor.constraint(equalTo: namePhoneLabel.trailingAnchor)
        ])
    }
}