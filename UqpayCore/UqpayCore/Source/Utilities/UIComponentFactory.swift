//
//  UIComponentFactory.swift
//  UqpayCore
//
//  Created by UQPAY on 14/08/2025.
//

import UIKit

final class UIComponentFactory {
    
    // MARK: - Appearance Configuration
    
    public struct FieldAppearance {
        public let backgroundColor: UIColor
        public let borderColor: UIColor
        public let cornerRadius: CGFloat
        public let borderWidth: CGFloat
        public let textColor: UIColor
        public let font: UIFont
        public let placeholderColor: UIColor
        public let height: CGFloat
        public let horizontalPadding: CGFloat
        
        public init(
            backgroundColor: UIColor = .systemBackground,
            borderColor: UIColor = .systemGray4,
            cornerRadius: CGFloat = 8,
            borderWidth: CGFloat = 1,
            textColor: UIColor = .label,
            font: UIFont = UIFont.systemFont(ofSize: 16),
            placeholderColor: UIColor = .placeholderText,
            height: CGFloat = 48,
            horizontalPadding: CGFloat = 12
        ) {
            self.backgroundColor = backgroundColor
            self.borderColor = borderColor
            self.cornerRadius = cornerRadius
            self.borderWidth = borderWidth
            self.textColor = textColor
            self.font = font
            self.placeholderColor = placeholderColor
            self.height = height
            self.horizontalPadding = horizontalPadding
        }
    }
    
    public struct ButtonAppearance {
        public let backgroundColor: UIColor
        public let titleColor: UIColor
        public let font: UIFont
        public let cornerRadius: CGFloat
        public let height: CGFloat
        public let borderWidth: CGFloat
        public let borderColor: UIColor
        
        public init(
            backgroundColor: UIColor = .systemBlue,
            titleColor: UIColor = .white,
            font: UIFont = UIFont.systemFont(ofSize: 18, weight: .semibold),
            cornerRadius: CGFloat = 8,
            height: CGFloat = 48,
            borderWidth: CGFloat = 0,
            borderColor: UIColor = .clear
        ) {
            self.backgroundColor = backgroundColor
            self.titleColor = titleColor
            self.font = font
            self.cornerRadius = cornerRadius
            self.height = height
            self.borderWidth = borderWidth
            self.borderColor = borderColor
        }
    }
    
    // MARK: - Text Field Creation
    
    /// Creates a styled text field with consistent appearance
    /// - Parameters:
    ///   - placeholder: Placeholder text
    ///   - appearance: Visual styling configuration
    ///   - keyboardType: Keyboard type for the field
    ///   - contentType: Text content type for autofill
    ///   - isSecure: Whether the field should be secure
    /// - Returns: Configured UITextField
    public static func createTextField(
        placeholder: String,
        appearance: FieldAppearance = FieldAppearance(),
        keyboardType: UIKeyboardType = .default,
        contentType: UITextContentType? = nil,
        isSecure: Bool = false
    ) -> UITextField {
        
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.font = appearance.font
        textField.textColor = appearance.textColor
        textField.backgroundColor = appearance.backgroundColor
        textField.keyboardType = keyboardType
        textField.isSecureTextEntry = isSecure
        textField.translatesAutoresizingMaskIntoConstraints = false
        
        if let contentType = contentType {
            textField.textContentType = contentType
        }
        
        // Styling
        textField.layer.cornerRadius = appearance.cornerRadius
        textField.layer.borderWidth = appearance.borderWidth
        textField.layer.borderColor = appearance.borderColor.cgColor
        
        // Add padding
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: appearance.horizontalPadding, height: 0))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: appearance.horizontalPadding, height: 0))
        textField.rightViewMode = .always
        
        // Height constraint
        textField.heightAnchor.constraint(equalToConstant: appearance.height).isActive = true
        
        return textField
    }
    
    /// Creates a card number text field with specific formatting
    /// - Parameter appearance: Visual styling configuration
    /// - Returns: Configured UITextField for card numbers
    public static func createCardNumberField(appearance: FieldAppearance = FieldAppearance()) -> UITextField {
        let textField = createTextField(
            placeholder: "1234 1234 1234 1234",
            appearance: appearance,
            keyboardType: .numberPad,
            contentType: .creditCardNumber
        )
        
        // Use monospaced font for card numbers
        textField.font = UIFont.monospacedDigitSystemFont(ofSize: appearance.font.pointSize, weight: .medium)
        
        return textField
    }
    
    /// Creates an expiry date text field
    /// - Parameter appearance: Visual styling configuration
    /// - Returns: Configured UITextField for expiry dates
    public static func createExpiryField(appearance: FieldAppearance = FieldAppearance()) -> UITextField {
        return createTextField(
            placeholder: "MM / YY",
            appearance: appearance,
            keyboardType: .numberPad
        )
    }
    
    /// Creates a CVC text field
    /// - Parameter appearance: Visual styling configuration
    /// - Returns: Configured UITextField for CVC codes
    public static func createCVCField(appearance: FieldAppearance = FieldAppearance()) -> UITextField {
        // `.creditCardSecurityCode` lets the system offer the stored security
        // code, but it only exists from iOS 17. Before that there is no
        // equivalent content type — autofill simply does not offer the CVC —
        // so the field is left untyped rather than mislabelled as another kind
        // of secure entry.
        let contentType: UITextContentType?
        if #available(iOS 17.0, *) {
            contentType = .creditCardSecurityCode
        } else {
            contentType = nil
        }

        return createTextField(
            placeholder: "CVC",
            appearance: appearance,
            keyboardType: .numberPad,
            contentType: contentType,
            isSecure: true
        )
    }
    
    /// Creates a cardholder name text field
    /// - Parameter appearance: Visual styling configuration
    /// - Returns: Configured UITextField for cardholder names
    public static func createCardholderNameField(appearance: FieldAppearance = FieldAppearance()) -> UITextField {
        let textField = createTextField(
            placeholder: "Cardholder Name",
            appearance: appearance,
            keyboardType: .default,
            contentType: .name
        )
        textField.autocapitalizationType = .words
        return textField
    }
    
    // MARK: - Button Creation
    
    /// Creates a styled button with consistent appearance
    /// - Parameters:
    ///   - title: Button title
    ///   - appearance: Visual styling configuration
    ///   - target: Target for button actions
    ///   - action: Selector for button tap
    /// - Returns: Configured UIButton
    public static func createButton(
        title: String,
        appearance: ButtonAppearance = ButtonAppearance(),
        target: Any? = nil,
        action: Selector? = nil
    ) -> UIButton {
        
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(appearance.titleColor, for: .normal)
        button.titleLabel?.font = appearance.font
        button.backgroundColor = appearance.backgroundColor
        button.layer.cornerRadius = appearance.cornerRadius
        button.translatesAutoresizingMaskIntoConstraints = false
        
        if appearance.borderWidth > 0 {
            button.layer.borderWidth = appearance.borderWidth
            button.layer.borderColor = appearance.borderColor.cgColor
        }
        
        if let target = target, let action = action {
            button.addTarget(target, action: action, for: .touchUpInside)
        }
        
        // Height constraint
        button.heightAnchor.constraint(equalToConstant: appearance.height).isActive = true
        
        return button
    }
    
    /// Creates a primary action button (e.g., Pay button)
    /// - Parameters:
    ///   - title: Button title
    ///   - color: Primary color for the button
    ///   - target: Target for button actions
    ///   - action: Selector for button tap
    /// - Returns: Configured primary button
    public static func createPrimaryButton(
        title: String,
        color: UIColor = .systemBlue,
        target: Any? = nil,
        action: Selector? = nil
    ) -> UIButton {
        
        let appearance = ButtonAppearance(
            backgroundColor: color,
            titleColor: .white,
            font: UIFont.systemFont(ofSize: 18, weight: .semibold)
        )
        
        return createButton(title: title, appearance: appearance, target: target, action: action)
    }
    
    /// Creates a secondary action button (e.g., Cancel button)
    /// - Parameters:
    ///   - title: Button title
    ///   - target: Target for button actions
    ///   - action: Selector for button tap
    /// - Returns: Configured secondary button
    public static func createSecondaryButton(
        title: String,
        target: Any? = nil,
        action: Selector? = nil
    ) -> UIButton {
        
        let appearance = ButtonAppearance(
            backgroundColor: .clear,
            titleColor: .systemBlue,
            font: UIFont.systemFont(ofSize: 16, weight: .medium),
            borderWidth: 1,
            borderColor: .systemBlue
        )
        
        return createButton(title: title, appearance: appearance, target: target, action: action)
    }
    
    // MARK: - Loading Indicator
    
    /// Creates a styled activity indicator
    /// - Parameters:
    ///   - style: Activity indicator style
    ///   - color: Indicator color
    /// - Returns: Configured UIActivityIndicatorView
    public static func createLoadingIndicator(
        style: UIActivityIndicatorView.Style = .medium,
        color: UIColor = .systemGray
    ) -> UIActivityIndicatorView {
        
        let indicator = UIActivityIndicatorView(style: style)
        indicator.color = color
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        
        return indicator
    }
    
    // MARK: - Label Creation
    
    /// Creates a styled label
    /// - Parameters:
    ///   - text: Label text
    ///   - font: Font for the label
    ///   - textColor: Text color
    ///   - textAlignment: Text alignment
    ///   - numberOfLines: Number of lines (0 for unlimited)
    /// - Returns: Configured UILabel
    public static func createLabel(
        text: String,
        font: UIFont = UIFont.systemFont(ofSize: 16),
        textColor: UIColor = .label,
        textAlignment: NSTextAlignment = .left,
        numberOfLines: Int = 1
    ) -> UILabel {
        
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = textColor
        label.textAlignment = textAlignment
        label.numberOfLines = numberOfLines
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }
    
    /// Creates a section header label
    /// - Parameter text: Header text
    /// - Returns: Configured header label
    public static func createSectionHeaderLabel(text: String) -> UILabel {
        return createLabel(
            text: text,
            font: UIFont.systemFont(ofSize: 20, weight: .semibold),
            textColor: .label
        )
    }
    
    /// Creates a field label
    /// - Parameter text: Label text
    /// - Returns: Configured field label
    public static func createFieldLabel(text: String) -> UILabel {
        return createLabel(
            text: text,
            font: UIFont.systemFont(ofSize: 14, weight: .medium),
            textColor: .label
        )
    }
    
    // MARK: - Container Views
    
    /// Creates a styled container view
    /// - Parameters:
    ///   - backgroundColor: Background color
    ///   - cornerRadius: Corner radius
    ///   - borderWidth: Border width
    ///   - borderColor: Border color
    /// - Returns: Configured UIView
    public static func createContainerView(
        backgroundColor: UIColor = .clear,
        cornerRadius: CGFloat = 0,
        borderWidth: CGFloat = 0,
        borderColor: UIColor = .clear
    ) -> UIView {
        
        let view = UIView()
        view.backgroundColor = backgroundColor
        view.layer.cornerRadius = cornerRadius
        view.translatesAutoresizingMaskIntoConstraints = false
        
        if borderWidth > 0 {
            view.layer.borderWidth = borderWidth
            view.layer.borderColor = borderColor.cgColor
        }
        
        return view
    }
    
    /// Creates a card-style container view
    /// - Parameter backgroundColor: Background color
    /// - Returns: Configured card view
    public static func createCardView(backgroundColor: UIColor = .systemBackground) -> UIView {
        let view = createContainerView(
            backgroundColor: backgroundColor,
            cornerRadius: 12,
            borderWidth: 1,
            borderColor: .systemGray5
        )
        
        // Add shadow
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.layer.shadowOpacity = 0.1
        
        return view
    }
}

// MARK: - Loading State Management

extension UIComponentFactory {
    
    /// Manages loading state for buttons
    /// - Parameters:
    ///   - button: Button to modify
    ///   - isLoading: Whether to show loading state
    ///   - loadingIndicator: Loading indicator to use
    ///   - originalTitle: Original button title to restore
    public static func setButtonLoadingState(
        _ button: UIButton,
        isLoading: Bool,
        loadingIndicator: UIActivityIndicatorView? = nil,
        originalTitle: String? = nil
    ) {
        
        if isLoading {
            button.isEnabled = false
            button.setTitle("", for: .normal)
            
            let indicator = loadingIndicator ?? createLoadingIndicator()
            button.addSubview(indicator)
            
            NSLayoutConstraint.activate([
                indicator.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                indicator.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
            
            indicator.startAnimating()
        } else {
            button.isEnabled = true
            
            // Remove loading indicator
            button.subviews.compactMap { $0 as? UIActivityIndicatorView }.forEach {
                $0.stopAnimating()
                $0.removeFromSuperview()
            }
            
            // Restore title
            if let title = originalTitle ?? button.titleLabel?.text {
                button.setTitle(title, for: .normal)
            }
        }
    }
}
