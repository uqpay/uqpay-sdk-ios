import SwiftUI
import UqpayCore
import UqpayPaymentSheet

@main
struct SwiftUIExampleApp: App {

    init() {
        // The issuer's 3DS page redirects here when authentication finishes.
        // This scheme must also be registered under CFBundleURLTypes in Info.plist,
        // otherwise iOS never delivers the callback and the payment appears to hang.
        UqpayConfiguration.shared.appReturnScheme = DemoConfiguration.returnURLScheme
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    NotificationCenter.default.post(
                        name: PaymentSheet.paymentReturnedFromBank,
                        object: url
                    )
                }
        }
    }
}
