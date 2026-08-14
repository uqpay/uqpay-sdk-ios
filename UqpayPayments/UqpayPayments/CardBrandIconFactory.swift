//
//  CardBrandIconFactory.swift
//  UqpayPayments
//
//  Created by UQPAY on 14/08/2025.
//

import UIKit

public final class CardBrandIconFactory {
    
    // MARK: - Types
    
    public struct IconStyle {
        public let activeAlpha: CGFloat
        public let inactiveAlpha: CGFloat
        public let iconSize: CGSize
        
        public init(activeAlpha: CGFloat = 1.0, 
                   inactiveAlpha: CGFloat = 0.3,
                   iconSize: CGSize = CGSize(width: 32, height: 20)) {
            self.activeAlpha = activeAlpha
            self.inactiveAlpha = inactiveAlpha
            self.iconSize = iconSize
        }
    }
    
    public enum IconType {
        case simple  // Text-based icons
        case symbol  // SF Symbol-based icons
    }
    
    // MARK: - Public Methods
    
    /// Creates a card brand icon based on the specified type
    /// - Parameters:
    ///   - brand: The card brand
    ///   - type: The icon style (simple or symbol)
    ///   - style: Visual styling options
    /// - Returns: UIImage representing the card brand
    public static func createIcon(for brand: CardBrand, type: IconType = .simple, style: IconStyle = IconStyle()) -> UIImage? {
        switch type {
        case .simple:
            return createSimpleIcon(for: brand, style: style)
        case .symbol:
            return createSymbolIcon(for: brand, style: style)
        }
    }
    
    /// Creates a configured UIImageView for a card brand
    /// - Parameters:
    ///   - brand: The card brand
    ///   - type: The icon style
    ///   - style: Visual styling options
    ///   - isActive: Whether the icon should be in active state
    /// - Returns: Configured UIImageView
    public static func createImageView(for brand: CardBrand, 
                                     type: IconType = .simple,
                                     style: IconStyle = IconStyle(), 
                                     isActive: Bool = false) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.alpha = isActive ? style.activeAlpha : style.inactiveAlpha
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = createIcon(for: brand, type: type, style: style)
        
        // Set size constraints
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: style.iconSize.width),
            imageView.heightAnchor.constraint(equalToConstant: style.iconSize.height)
        ])
        
        return imageView
    }
    
    /// Updates the visual state of multiple card brand icons
    /// - Parameters:
    ///   - icons: Dictionary mapping card brands to their image views
    ///   - activeBrand: The currently active card brand
    ///   - style: Visual styling options
    public static func updateIconStates(_ icons: [CardBrand: UIImageView], 
                                      activeBrand: CardBrand,
                                      style: IconStyle = IconStyle()) {
        icons.forEach { brand, imageView in
            let isActive = brand == activeBrand
            
            UIView.animate(withDuration: 0.2) {
                imageView.alpha = isActive ? style.activeAlpha : style.inactiveAlpha
            }
        }
    }
    
    /// Creates a standard set of card brand icons (Visa, MasterCard, Amex)
    /// - Parameters:
    ///   - type: The icon style
    ///   - style: Visual styling options
    /// - Returns: Dictionary mapping brands to configured image views
    public static func createStandardIconSet(type: IconType = .simple, 
                                           style: IconStyle = IconStyle()) -> [CardBrand: UIImageView] {
        let brands: [CardBrand] = [.visa, .masterCard, .amex]
        var icons: [CardBrand: UIImageView] = [:]
        
        brands.forEach { brand in
            icons[brand] = createImageView(for: brand, type: type, style: style)
        }
        
        return icons
    }
    
    // MARK: - Private Methods
    
    private static func createSimpleIcon(for brand: CardBrand, style: IconStyle) -> UIImage? {
        let (text, color) = getSimpleBrandInfo(for: brand)
        return createTextBasedIcon(text: text, color: color, size: style.iconSize)
    }
    
    private static func createSymbolIcon(for brand: CardBrand, style: IconStyle) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: min(style.iconSize.width, style.iconSize.height) * 0.6, weight: .medium)
        let (systemName, color) = getSymbolBrandInfo(for: brand)
        
        return UIImage(systemName: systemName, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
    }
    
    private static func getSimpleBrandInfo(for brand: CardBrand) -> (text: String, color: UIColor) {
        switch brand {
        case .visa:
            return ("VISA", .systemBlue)
        case .masterCard:
            return ("MC", .systemOrange)
        case .amex:
            return ("AMEX", .systemGreen)
        case .discover:
            return ("DISC", .systemPurple)
        case .jcb:
            return ("JCB", .systemRed)
        case .dinersClub:
            return ("DINE", .systemIndigo)
        case .unionPay:
            return ("UNI", .systemTeal)
        case .unknown:
            return ("???", .systemGray)
        @unknown default:
            return ("???", .systemGray)
        }
    }
    
    private static func getSymbolBrandInfo(for brand: CardBrand) -> (systemName: String, color: UIColor) {
        switch brand {
        case .visa:
            return ("v.circle.fill", .systemBlue)
        case .masterCard:
            return ("circle.circle.fill", .systemOrange)
        case .amex:
            return ("square.fill", .systemGreen)
        case .discover:
            return ("d.circle.fill", .systemPurple)
        case .jcb:
            return ("j.circle.fill", .systemRed)
        case .dinersClub:
            return ("circle.hexagongrid.fill", .systemIndigo)
        case .unionPay:
            return ("u.circle.fill", .systemTeal)
        case .unknown:
            return ("creditcard.fill", .systemGray)
        @unknown default:
            return ("creditcard.fill", .systemGray)
        }
    }
    
    private static func createTextBasedIcon(text: String, color: UIColor, size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Background
            color.withAlphaComponent(0.1).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4).fill()
            
            // Border
            color.setStroke()
            let borderPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4)
            borderPath.lineWidth = 1
            borderPath.stroke()
            
            // Text
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: min(size.width, size.height) * 0.25, weight: .bold),
                .foregroundColor: color
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

// MARK: - CardBrandIconManager

public final class CardBrandIconManager {
    
    // MARK: - Properties
    
    private let iconType: CardBrandIconFactory.IconType
    private let iconStyle: CardBrandIconFactory.IconStyle
    private var icons: [CardBrand: UIImageView] = [:]
    private var currentBrand: CardBrand = .unknown
    
    // MARK: - Initialization
    
    public init(iconType: CardBrandIconFactory.IconType = .simple, 
               iconStyle: CardBrandIconFactory.IconStyle = CardBrandIconFactory.IconStyle()) {
        self.iconType = iconType
        self.iconStyle = iconStyle
    }
    
    // MARK: - Public Methods
    
    /// Sets up icon management for the provided brands
    /// - Parameter brands: Array of card brands to manage
    public func setupIcons(for brands: [CardBrand] = [.visa, .masterCard, .amex]) {
        icons.removeAll()
        
        brands.forEach { brand in
            icons[brand] = CardBrandIconFactory.createImageView(
                for: brand, 
                type: iconType, 
                style: iconStyle
            )
        }
        
        updateBrandState(.unknown)
    }
    
    /// Updates the active brand and refreshes icon states
    /// - Parameter brand: The currently detected card brand
    public func updateBrandState(_ brand: CardBrand) {
        guard brand != currentBrand else { return }
        
        currentBrand = brand
        CardBrandIconFactory.updateIconStates(icons, activeBrand: brand, style: iconStyle)
    }
    
    /// Returns the configured icon image views for layout
    /// - Returns: Array of UIImageView objects in standard order
    public func getIconViews() -> [UIImageView] {
        let standardOrder: [CardBrand] = [.visa, .masterCard, .amex]
        return standardOrder.compactMap { icons[$0] }
    }
    
    /// Returns a specific icon view for a brand
    /// - Parameter brand: The card brand
    /// - Returns: UIImageView for the specified brand, if available
    public func getIconView(for brand: CardBrand) -> UIImageView? {
        return icons[brand]
    }
}