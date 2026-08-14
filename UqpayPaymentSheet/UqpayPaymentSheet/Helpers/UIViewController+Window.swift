//
//  UIViewController+Window.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 13/08/2026.
//

import UIKit

extension UIViewController {

    /// The window this controller is actually presented in.
    ///
    /// The dismissal fallbacks used to start from
    /// `UIApplication.shared.connectedScenes.first`. `connectedScenes` is a
    /// `Set` — unordered — so `.first` returns an arbitrary element. With more
    /// than one window of the same app on screen (iPad Split View, Stage
    /// Manager, or any app that opts into multiple scenes) that can be a
    /// different window from the one the customer is paying in, and the walk up
    /// the presentation stack then dismisses the wrong hierarchy.
    ///
    /// The controller's own window is unambiguous, so it is tried first. The
    /// scene scan remains only as a last resort for a controller that is no
    /// longer in a hierarchy, and is at least restricted to scenes that are
    /// actually on screen.
    var uqpayResolvedWindow: UIWindow? {
        if let window = viewIfLoaded?.window {
            return window
        }
        if let window = presentingViewController?.viewIfLoaded?.window {
            return window
        }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
