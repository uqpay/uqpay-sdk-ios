import SwiftUI
#if canImport(UIKit)
import UIKit
import UqpayCore
import UqpayPayments

// MARK: - Presenter

/// Presents the payment UI from SwiftUI.
///
/// Both sheet types run through here. The payment screens are UIKit and push
/// their own status screens — receipts, failures, pending — so whatever is shown
/// **must** sit inside a `UINavigationController`. Presenting a payment screen
/// bare makes every one of those pushes a no-op against a nil navigation
/// controller: the customer pays and then sees nothing at all.
public struct UqpayPaymentSheetPresenter: ViewModifier {

    @Binding var isPresented: Bool
    let sheet: PaymentSheet
    let sheetType: PaymentSheetType

    init(isPresented: Binding<Bool>, sheet: PaymentSheet, sheetType: PaymentSheetType) {
        self._isPresented = isPresented
        self.sheet = sheet
        self.sheetType = sheetType
    }

    public func body(content: Content) -> some View {
        content
            .background(EmptyView().sheet(isPresented: $isPresented) {
                sheetContent
            })
    }

    /// Presentation modifiers belong on the sheet's own content — applied to the
    /// presenting view they do nothing. `presentationDetents` and
    /// `presentationDragIndicator` are iOS 16; below that the sheet simply
    /// presents at its default full height.
    @ViewBuilder
    private var sheetContent: some View {
        let host = SheetHostView(isPresented: $isPresented, sheet: sheet, sheetType: sheetType)
            .ignoresSafeArea()

        if #available(iOS 16.0, *) {
            host
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            host
        }
    }

    // MARK: - UIKit bridge

    struct SheetHostView: UIViewControllerRepresentable {

        @Binding var isPresented: Bool

        let sheet: PaymentSheet
        let sheetType: PaymentSheetType

        func makeCoordinator() -> Coordinator {
            Coordinator(isPresented: $isPresented)
        }

        func makeUIViewController(context: Context) -> ContainerViewController {
            let host = makeContainer()

            // The SDK dismisses its own view controllers when the customer taps
            // Done. SwiftUI does not observe that, so without this the binding
            // stays `true`, SwiftUI still believes the sheet is up, and it can
            // never be presented again.
            host.onDismissed = { [weak coordinator = context.coordinator] in
                coordinator?.sheetWasDismissed()
            }

            return host
        }

        /// Builds the hosted payment stack.
        ///
        /// Split out of `makeUIViewController(context:)` because a SwiftUI
        /// `Context` cannot be constructed in a test, and the structure this
        /// produces — specifically that the payment screen sits inside a
        /// navigation controller — is the part worth pinning.
        func makeContainer() -> ContainerViewController {
            let host = ContainerViewController()

            switch sheetType {
            case .cardOnly:
                host.embed(child: Self.makeCardOnlyStack(sheet: sheet))

            case .paymentList:
                loadPaymentList(into: host)
            }

            return host
        }

        func updateUIViewController(_ uiViewController: ContainerViewController, context: Context) {
            // Re-resolve the merchant's delegate on every update, so one set
            // after presentation still reaches the payment screens.
            uiViewController.refreshPaymentDelegate(from: sheet)
        }

        /// The card form, wrapped so its status screens have somewhere to push.
        private static func makeCardOnlyStack(sheet: PaymentSheet) -> UINavigationController {
            let card = PaymentCardViewController()
            card.paymentSheet = sheet
            card.paymentDelegate = sheet.paymentDelegate

            let navigation = UINavigationController(rootViewController: card)
            navigation.navigationBar.tintColor = sheet.appearance.primaryColor
            return navigation
        }

        /// Loads the payment method list, which first fetches the methods the
        /// payment intent actually offers.
        private func loadPaymentList(into host: ContainerViewController) {
            sheet.loadViewController { result in
                switch result {
                case .success(let viewController):
                    // Embed rather than present, so the sheet does not stack a
                    // second modal with a layered background. The root is
                    // re-wrapped in a plain navigation controller because the
                    // SDK's own one is configured to be presented, not embedded.
                    if let navigation = viewController as? UINavigationController,
                       let root = navigation.viewControllers.first {
                        let embedded = UINavigationController(rootViewController: root)
                        embedded.navigationBar.tintColor = navigation.navigationBar.tintColor
                        host.embed(child: embedded)
                    } else {
                        host.embed(child: viewController)
                    }

                case .failure(let error):
                    host.embed(child: SheetLoadErrorViewController(
                        message: error.errorDescription ?? "The payment sheet could not be loaded."
                    ))
                }
            }
        }

        /// Keeps SwiftUI's presentation state in step with UIKit's.
        final class Coordinator: NSObject {

            @Binding private var isPresented: Bool

            init(isPresented: Binding<Bool>) {
                self._isPresented = isPresented
            }

            func sheetWasDismissed() {
                guard isPresented else { return }
                isPresented = false
            }
        }
    }

    // MARK: - Container

    /// Hosts the payment stack inside the SwiftUI sheet.
    final class ContainerViewController: UIViewController {

        /// Called when this controller genuinely leaves the screen — dismissed
        /// by the customer or by the SDK — rather than merely being covered by
        /// something presented over it, such as the 3D Secure step.
        var onDismissed: (() -> Void)?

        private var hasReportedDismissal = false

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)

            // The 3DS step is presented as a form sheet, which leaves this
            // controller on screen and does not trigger this callback at all.
            // A dismissal racing a presentation can still leave `window`
            // transiently nil, so the check waits a runloop turn and asks again.
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      !self.hasReportedDismissal,
                      self.view.window == nil else { return }

                self.hasReportedDismissal = true
                self.onDismissed?()
            }
        }

        func embed(child: UIViewController) {
            if let existing = children.first {
                existing.willMove(toParent: nil)
                existing.view.removeFromSuperview()
                existing.removeFromParent()
            }

            addChild(child)
            child.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child.view)
            NSLayoutConstraint.activate([
                child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                child.view.topAnchor.constraint(equalTo: view.topAnchor),
                child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            child.didMove(toParent: self)
        }

        /// Pushes the sheet's current delegate down to the embedded payment
        /// screens, so a delegate assigned after presentation still receives the
        /// outcome.
        func refreshPaymentDelegate(from sheet: PaymentSheet) {
            guard let delegate = sheet.paymentDelegate else { return }

            for case let navigation as UINavigationController in children {
                for viewController in navigation.viewControllers {
                    switch viewController {
                    case let card as PaymentCardViewController:
                        card.paymentDelegate = delegate
                    case let list as PaymentListViewController:
                        list.paymentDelegate = delegate
                    case let wallet as WalletQRPaymentViewController:
                        wallet.paymentDelegate = delegate
                    default:
                        break
                    }
                }
            }
        }
    }

    /// Shown in place of the payment UI when loading fails, so the customer
    /// sees why instead of an empty sheet.
    final class SheetLoadErrorViewController: UIViewController {

        private let message: String

        init(message: String) {
            self.message = message
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground

            let label = UILabel()
            label.text = message
            label.font = UqpayFonts.scaled(size: 16, textStyle: .body)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)

            NSLayoutConstraint.activate([
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
            ])
        }
    }
}

// MARK: - View modifiers

public extension View {

    /// Presents the UQPAY payment UI.
    ///
    /// Set `sheet.paymentDelegate` before presenting to receive the outcome.
    /// The binding is cleared automatically when the sheet closes, however it
    /// was closed.
    ///
    /// - Parameters:
    ///   - isPresented: Drives presentation, and is set back to `false` when the
    ///     sheet closes.
    ///   - sheet: The configured payment sheet. Hold a strong reference to it —
    ///     `paymentDelegate` is weak.
    ///   - sheetType: Which UI to show. Defaults to the type the `PaymentSheet`
    ///     was created with.
    func uqpayPaymentSheet(
        isPresented: Binding<Bool>,
        sheet: PaymentSheet,
        sheetType: PaymentSheetType? = nil
    ) -> some View {
        modifier(
            UqpayPaymentSheetPresenter(
                isPresented: isPresented,
                sheet: sheet,
                sheetType: sheetType ?? sheet.paymentsheetType
            )
        )
    }

}

// MARK: - Deprecated

@available(*, deprecated, renamed: "UqpayPaymentSheetPresenter", message: """
    Use uqpayPaymentSheet(isPresented:sheet:sheetType:) with sheetType: .cardOnly.
    """)
public struct UqpayPaymentCardDialogPresenter: ViewModifier {

    @Binding var isPresented: Bool
    let sheet: PaymentSheet

    public func body(content: Content) -> some View {
        content.modifier(
            UqpayPaymentSheetPresenter(
                isPresented: $isPresented,
                sheet: sheet,
                sheetType: .cardOnly
            )
        )
    }
}

#endif
