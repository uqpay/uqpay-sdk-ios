//
//  UqpayResourceManager.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on $(DATE).
//

import UIKit
import UqpayCore
import UqpayPayments

internal class UqpayResourceManager {
    
    // MARK: - Bundle Management
    
    static let shared = UqpayResourceManager()
    
    private init() {}
    
    /// The bundle that carries the compiled asset catalog.
    ///
    /// Each distribution channel puts it somewhere different:
    /// - SwiftPM synthesizes a resource bundle whose name is derived from the
    ///   package manifest's `name`, so it can only be reached reliably through
    ///   `Bundle.module` — probing by name breaks whenever the manifest is
    ///   renamed, and `Bundle(for:)` points at the host app under static
    ///   linking.
    /// - CocoaPods (`resource_bundle`) nests `UqpayPaymentSheet.bundle` inside
    ///   whichever bundle contains this class (the framework, or the app for a
    ///   static pod).
    /// - The Xcode framework targets compile the catalog straight into the
    ///   framework bundle.
    static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        let containingBundle = Bundle(for: UqpayResourceManager.self)
        if let nestedURL = containingBundle.url(forResource: "UqpayPaymentSheet", withExtension: "bundle"),
           let nestedBundle = Bundle(url: nestedURL) {
            return nestedBundle
        }
        return containingBundle
        #endif
    }()
    
    // MARK: - Image Loading
    
    /// Load image from the framework's asset catalog
    static func image(named name: String) -> UIImage? {
        if let image = UIImage(named: name, in: bundle, compatibleWith: nil) {
            return image
        }

        // The main bundle fallback lets a host app supply artwork the SDK
        // does not ship.
        if let mainImage = UIImage(named: name) {
            return mainImage
        }

        UqpayLogger.shared.debug("Image '\(name)' not found in \(bundle.bundlePath) or the main bundle")
        return nil
    }
    
    /// Load payment method icon with fallback to SF Symbol
    static func paymentMethodIcon(for type: PaymentMethodType) -> UIImage? {
        let iconName: String
        let fallbackSymbol: String
        
        switch type {
        case .card:
            iconName = "card"
            fallbackSymbol = "creditcard"
        case .wechat:
            iconName = "wechat"
            fallbackSymbol = "message.circle"
        case .paypal:
            iconName = "paypal"
            fallbackSymbol = "dollarsign.circle"
        case .alipayHK:
            iconName = "alipay"
            fallbackSymbol = "creditcard.circle"
        default:
            iconName = ""
            fallbackSymbol = "creditcard.circle"
        }
        
        // Try to load custom icon first
        if let customIcon = image(named: iconName) {
            return customIcon
        }
        
        // Fallback to SF Symbol
        return UIImage(systemName: fallbackSymbol)
    }
    
    /// Load card brand icon with enhanced styling
    static func cardBrandIcon(for brand: CardBrand, appearance: PaymentSheet.Appearance) -> UIImage? {
        let iconName: String
        let fallbackSymbol: String
        let color: UIColor
        
        switch brand {
        case .visa:
            iconName = "visa"
            fallbackSymbol = "creditcard"
            color = appearance.cardBrand.visa
        case .masterCard:
            iconName = "mastercard"
            fallbackSymbol = "creditcard"
            color = appearance.cardBrand.masterCard
        case .amex:
            iconName = "amex"
            fallbackSymbol = "creditcard"
            color = appearance.cardBrand.amex
        case .discover, .jcb, .dinersClub, .unionPay, .unknown:
            iconName = "unknown_card"
            fallbackSymbol = "creditcard"
            color = appearance.cardBrand.unknown
        @unknown default:
            iconName = ""
            fallbackSymbol = "creditcard"
            color = appearance.cardBrand.unknown
        }
        
        UqpayLogger.shared.debug("Card brand: \(brand), iconName: \(iconName)")

        // Try custom icon first
        if let customIcon = image(named: iconName) {
            UqpayLogger.shared.debug("Using custom icon for \(brand)")
            return customIcon
        }

        UqpayLogger.shared.debug("Fallback to SF Symbol: \(fallbackSymbol) for \(brand)")
        // Fallback to SF Symbol with color
        return UIImage(systemName: fallbackSymbol)?.withTintColor(color, renderingMode: .alwaysTemplate)
    }
    
    // MARK: - Dynamic Card Icon Creation
    
    /// Create a simple text-based card icon (fallback method)
    static func createTextBasedCardIcon(text: String, color: UIColor, size: CGSize = CGSize(width: 32, height: 20)) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Background
            color.withAlphaComponent(0.1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Border
            color.setStroke()
            let cgContext = context.cgContext
            cgContext.setLineWidth(1.0)
            cgContext.stroke(CGRect(origin: .zero, size: size))
            
            // Text
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: UIFont.systemFont(ofSize: 8, weight: .medium)
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
}

// MARK: - UIImage Extensions

extension UIImage {
    /// Load image from UqpayPaymentSheet bundle
    static func uqpayImage(named name: String) -> UIImage? {
        return UqpayResourceManager.image(named: name)
    }
    
    /// Load payment method icon
    static func uqpayPaymentMethodIcon(for type: PaymentMethodType) -> UIImage? {
        return UqpayResourceManager.paymentMethodIcon(for: type)
    }
}
