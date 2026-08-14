//
//  SceneDelegate.swift
//  UIKitExample
//
//  Created by UQPAY on 30/09/2025.
//

import UIKit
import UqpayCore
import UqpayPayments
import UqpayPaymentSheet

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Force light mode for consistent appearance
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // Configure UQPAY SDK return URL scheme for 3DS callbacks
        configureUqpayReturnScheme()

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = .light

        let viewController = ViewController()
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.overrideUserInterfaceStyle = .light

        window.rootViewController = navigationController
        self.window = window
        window.makeKeyAndVisible()
    }

    /// Configure the UQPAY SDK with the app's custom URL scheme for payment callbacks
    private func configureUqpayReturnScheme() {
        // Set the app's URL scheme for 3DS and payment callbacks
        // Format: yourapp://payment - the SDK will append /success, /failure, /cancel
        UqpayConfiguration.shared.appReturnScheme = "uqpayexample://payment"
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }

        print("Received payment return URL: \(url.absoluteString)")

        // Tell the payment screen to re-read the intent immediately. The typed
        // constant cannot be mistyped the way the old raw string could.
        NotificationCenter.default.post(
            name: PaymentSheet.paymentReturnedFromBank,
            object: url
        )
    }
}
