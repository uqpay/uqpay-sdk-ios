//
//  AppDelegate.swift
//  UIKitExample
//
//  Created by UQPAY on 18/09/2025.
//

//TODO : we need an api to  : backend have an API endpoint to fetch payment intent status by ID? (e.g., GET /payment-intents/{id})


import UIKit
import UqpayPaymentSheet

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        print("🚀 [AppDelegate] Application launched")
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    // No URL callback handler: every payment method the SDK implements
    // completes inside the app. Alipay and AlipayHK check out through a
    // merchant-presented QR the customer scans from another device or app —
    // the outcome is read back from the payment intent, not from a return URL.
    // The app-to-app hand-off is parked on feature/alipay-app-handoff-v2.
}

