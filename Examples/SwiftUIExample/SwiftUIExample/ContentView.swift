import Combine
import SwiftUI
import UqpayCore
import UqpayPayments
import UqpayPaymentSheet

/// Demo storefront.
///
/// Sandbox only. A published example must never carry production credentials,
/// so there is no environment switch — change ``DemoConfiguration/environment``
/// if you need to point somewhere else.
struct ContentView: View {

    @StateObject private var viewModel = ContentViewModel()
    @StateObject private var paymentHandler = MerchantPaymentHandler()
    @State private var isShowingPaymentSheet = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !viewModel.isConfigured {
                    setupBanner
                }
                CartView(isShowingPaymentListV2: $isShowingPaymentSheet, contentViewModel: viewModel)
            }
            .navigationTitle("UQPAY Demo")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("SANDBOX")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                        .accessibilityLabel("Sandbox environment. No real money is charged.")
                }
            }
        }
        .navigationViewStyle(.stack)
        .uqpayPaymentSheet(
            isPresented: $isShowingPaymentSheet,
            sheet: paymentHandler.paymentSheet
        )
        .alert("Payment", isPresented: $paymentHandler.showAlert) {
            Button("OK") { viewModel.reset() }
        } message: {
            Text(paymentHandler.alertMessage)
        }
    }

    /// Shown until real credentials are pasted into ``DemoConfiguration``.
    private var setupBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Add your sandbox credentials")
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.setupInstructions)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - Payment outcome

/// Receives the outcome of the payment.
///
/// This is where your app records the order. Treat the delegate callback as a
/// UI signal only — confirm the payment server-side from the
/// `acquiring.payment_intent.succeeded` webhook before you ship goods, because
/// a device can be tampered with and may lose connectivity mid-flow.
@MainActor
final class MerchantPaymentHandler: ObservableObject {
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published private(set) var lastResult: PaymentResult?
    @Published private(set) var lastError: PaymentError?

    /// The configured sheet. The handler owns it because `paymentDelegate`
    /// is weak — someone must hold both while the payment UI is up.
    let paymentSheet: PaymentSheet = {
        let configuration = PaymentSheet.Configuration(
            merchantDisplayName: "UQPAY Demo Store",
            environment: .sandboxMode
        )
        // `primaryColor` drives the pay button, selection highlights, and the
        // loading indicator. The SDK default is violet (#7C4DFF); this matches
        // the blue Checkout button in the cart.
        let appearance = PaymentSheet.Appearance(primaryColor: .systemBlue)
        return PaymentSheet(configuration: configuration, appearance: appearance)
    }()

    init() {
        paymentSheet.paymentDelegate = self
    }

    fileprivate func report(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}

extension MerchantPaymentHandler: PaymentDelegate {

    nonisolated func paymentSheet(_ paymentSheet: PaymentSheet, didCompleteWithResult result: PaymentResult) {
        Task { @MainActor in
            lastResult = result
            lastError = nil
            report("""
                Payment successful.

                Amount: \(String(format: "%.2f", result.amount)) \(result.currency)
                Method: \(result.paymentMethodType)
                Intent: \(result.paymentIntentId)
                """)
        }
    }

    nonisolated func paymentSheet(_ paymentSheet: PaymentSheet, didFailWithError error: PaymentError) {
        Task { @MainActor in
            lastError = error
            var message = error.message
            if let suggestion = error.recoverySuggestion {
                message += "\n\n\(suggestion)"
            }
            if let decline = error.declineCode {
                message += "\n\nDecline code: \(decline)"
            }
            report(message)
        }
    }

    /// The customer closed the sheet without paying. Release the cart hold
    /// here — this fires once, and never for a payment that succeeded or was
    /// declined.
    nonisolated func paymentSheetDidCancel(_ paymentSheet: PaymentSheet) {
        Task { @MainActor in
            report("Payment cancelled.")
        }
    }

    /// The customer must do something before the payment can complete.
    ///
    /// The payment sheet performs these itself. The intent stays in
    /// `REQUIRES_CUSTOMER_ACTION` until it finishes — which is not a failure,
    /// so do not mark the order failed here.
    nonisolated func paymentSheet(_ paymentSheet: PaymentSheet, requiresAction action: RequiredAction) {}

}

#Preview {
    ContentView()
}
