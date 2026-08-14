//
//  PaymentValidationHelper.swift
//  UqpayPayments
//
//  Created by UQPAY on 14/08/2025.
//

import Foundation


public final class PaymentValidationHelper {
    
    // MARK: - Validation Results
    
    public struct CardValidationResult {
        public let isValid: Bool
        public let brand: CardBrand
        public let errors: [ValidationError]
        
        /// The raw values are frozen: they are stable machine identifiers
        /// (and the localization keys), not display text. Show
        /// `errorDescription` to users — it resolves through the module's
        /// `Localizable.strings` and falls back to the raw value verbatim.
        public enum ValidationError: String, CaseIterable, LocalizedError {
            case invalidCardNumber = "Invalid card number"
            case invalidLuhn = "Card number failed Luhn validation"
            case invalidExpiry = "Invalid expiry date"
            case invalidCVC = "Invalid security code"
            case emptyCardNumber = "Card number is required"
            case emptyExpiry = "Expiry date is required"
            case emptyCVC = "Security code is required"
            case emptyCardholderName = "Cardholder name is required"

            public var errorDescription: String? {
                uqpayPaymentsLocalized(rawValue)
            }
        }
    }
    
    public struct FormValidationResult {
        public let isValid: Bool
        public let cardValidation: CardValidationResult
        public let isCardholderNameValid: Bool
        public let cardholderNameError: CardValidationResult.ValidationError?
    }
    
    // MARK: - Card Validation
    
    /// Validates a complete card form
    /// - Parameters:
    ///   - cardNumber: Raw card number string
    ///   - expiryText: Expiry date text (MM/YY or MM / YY format)
    ///   - cvc: CVC/CVV code
    ///   - cardholderName: Optional cardholder name
    ///   - requireCardholderName: Whether cardholder name is required
    /// - Returns: Complete validation result
    public static func validateCardForm(
        cardNumber: String,
        expiryText: String,
        cvc: String,
        cardholderName: String? = nil,
        requireCardholderName: Bool = false
    ) -> FormValidationResult {
        
        let cardValidation = validateCard(cardNumber: cardNumber, expiryText: expiryText, cvc: cvc)
        
        var isCardholderNameValid = true
        var cardholderNameError: CardValidationResult.ValidationError?
        
        if requireCardholderName {
            let nameValidation = validateCardholderName(cardholderName)
            isCardholderNameValid = nameValidation.isValid
            cardholderNameError = nameValidation.error
        }
        
        let isFormValid = cardValidation.isValid && isCardholderNameValid
        
        return FormValidationResult(
            isValid: isFormValid,
            cardValidation: cardValidation,
            isCardholderNameValid: isCardholderNameValid,
            cardholderNameError: cardholderNameError
        )
    }
    
    /// Validates card details (number, expiry, CVC)
    /// - Parameters:
    ///   - cardNumber: Raw card number string
    ///   - expiryText: Expiry date text
    ///   - cvc: CVC/CVV code
    /// - Returns: Card validation result
    public static func validateCard(cardNumber: String, expiryText: String, cvc: String) -> CardValidationResult {
        var errors: [CardValidationResult.ValidationError] = []
        
        // Clean and validate card number
        let cleanCardNumber = cardNumber.filter { $0.isNumber }
        let brand = CardValidator.brand(for: cleanCardNumber)
        
        if cleanCardNumber.isEmpty {
            errors.append(.emptyCardNumber)
        } else if cleanCardNumber.count < 13 {
            errors.append(.invalidCardNumber)
        } else if !CardValidator.isValidLuhn(cleanCardNumber) {
            errors.append(.invalidLuhn)
        }
        
        // Validate expiry
        if expiryText.isEmpty {
            errors.append(.emptyExpiry)
        } else {
            let expiryValidation = validateExpiryDate(expiryText)
            if !expiryValidation.isValid {
                errors.append(.invalidExpiry)
            }
        }
        
        // Validate CVC
        if cvc.isEmpty {
            errors.append(.emptyCVC)
        } else if !CardValidator.isValidCVC(cvc, brand: brand) {
            errors.append(.invalidCVC)
        }
        
        return CardValidationResult(isValid: errors.isEmpty, brand: brand, errors: errors)
    }
    
    /// Validates individual card number
    /// - Parameter cardNumber: Raw card number string
    /// - Returns: Tuple containing validation status and detected brand
    public static func validateCardNumber(_ cardNumber: String) -> (isValid: Bool, brand: CardBrand) {
        let cleanNumber = cardNumber.filter { $0.isNumber }
        let brand = CardValidator.brand(for: cleanNumber)
        
        guard !cleanNumber.isEmpty else { return (false, brand) }
        guard cleanNumber.count >= 13 else { return (false, brand) }
        
        let isValid = CardValidator.isValidLuhn(cleanNumber)
        return (isValid, brand)
    }
    
    /// Validates expiry date in various formats
    /// - Parameter expiryText: Expiry date text (MM/YY, MM / YY, MMYY)
    /// - Returns: Validation result with parsed month and year
    public static func validateExpiryDate(_ expiryText: String) -> (isValid: Bool, month: Int?, year: Int?) {
        let cleanExpiry = expiryText.replacingOccurrences(of: " ", with: "")
        
        // Handle MM/YY format
        if cleanExpiry.contains("/") {
            let components = cleanExpiry.split(separator: "/")
            guard components.count == 2 else { return (false, nil, nil) }
            
            guard let month = Int(components[0]),
                  let yearSuffix = Int(components[1]) else { return (false, nil, nil) }
            
            let year = yearSuffix < 100 ? yearSuffix + 2000 : yearSuffix
            
            return (CardValidator.isValidExpiry(month: month, year: year), month, year)
        }
        
        // Handle MMYY format
        else if cleanExpiry.count == 4, let _ = Int(cleanExpiry) {
            let monthString = String(cleanExpiry.prefix(2))
            let yearString = String(cleanExpiry.suffix(2))
            
            guard let month = Int(monthString),
                  let yearSuffix = Int(yearString) else { return (false, nil, nil) }
            
            let year = yearSuffix + 2000
            
            return (CardValidator.isValidExpiry(month: month, year: year), month, year)
        }
        
        return (false, nil, nil)
    }
    
    /// Validates CVC for a specific card brand
    /// - Parameters:
    ///   - cvc: CVC/CVV code
    ///   - brand: Card brand for length validation
    /// - Returns: Whether the CVC is valid
    public static func validateCVC(_ cvc: String, for brand: CardBrand) -> Bool {
        return CardValidator.isValidCVC(cvc, brand: brand)
    }
    
    /// Validates cardholder name
    /// - Parameter name: Cardholder name
    /// - Returns: Validation result
    public static func validateCardholderName(_ name: String?) -> (isValid: Bool, error: CardValidationResult.ValidationError?) {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return (false, .emptyCardholderName)
        }
        
        guard name.count >= 2 else {
            return (false, .emptyCardholderName)
        }
        
        return (true, nil)
    }
    
    // MARK: - Text Formatting Helpers
    
    /// Formats card number with spaces for display
    /// - Parameter cardNumber: Raw card number
    /// - Returns: Formatted card number (XXXX XXXX XXXX XXXX)
    public static func formatCardNumber(_ cardNumber: String) -> String {
        let digits = cardNumber.filter { $0.isNumber }
        var formatted = ""
        
        for (index, digit) in digits.enumerated() {
            if index > 0 && index % 4 == 0 {
                formatted += " "
            }
            formatted += String(digit)
        }
        
        return formatted
    }
    
    /// Formats expiry date for display
    /// - Parameter expiryText: Raw expiry text
    /// - Returns: Formatted expiry (MM / YY)
    public static func formatExpiryDate(_ expiryText: String) -> String {
        let digits = expiryText.filter { $0.isNumber }
        guard !digits.isEmpty else { return "" }
        
        if digits.count <= 2 {
            return digits
        } else {
            let month = String(digits.prefix(2))
            let year = String(digits.dropFirst(2).prefix(2))
            return "\(month) / \(year)"
        }
    }
    
    /// Cleans and limits card number input
    /// - Parameters:
    ///   - input: Raw input string
    ///   - brand: Current card brand for length limits
    /// - Returns: Cleaned and limited card number
    public static func cleanCardNumber(_ input: String, for brand: CardBrand = .unknown) -> String {
        let digits = input.filter { $0.isNumber }
        let maxLength = brand == .amex ? 15 : 16
        return String(digits.prefix(maxLength))
    }
    
    /// Cleans and limits CVC input
    /// - Parameters:
    ///   - input: Raw input string
    ///   - brand: Card brand for length limits
    /// - Returns: Cleaned and limited CVC
    public static func cleanCVC(_ input: String, for brand: CardBrand = .unknown) -> String {
        let digits = input.filter { $0.isNumber }
        let maxLength = brand == .amex ? 4 : 3
        return String(digits.prefix(maxLength))
    }
    
    /// Cleans and limits expiry input
    /// - Parameter input: Raw input string
    /// - Returns: Cleaned expiry (max 4 digits)
    public static func cleanExpiry(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        return String(digits.prefix(4))
    }
}

// MARK: - Real-time Validation

extension PaymentValidationHelper {
    
    /// Provides real-time validation feedback for card number input
    /// - Parameter cardNumber: Current card number input
    /// - Returns: Validation state and formatting suggestion
    public static func validateCardNumberRealTime(_ cardNumber: String) -> (isValidSoFar: Bool, shouldFormat: Bool, brand: CardBrand) {
        let cleanNumber = cardNumber.filter { $0.isNumber }
        let brand = CardValidator.brand(for: cleanNumber)
        
        // Allow partial input
        let isValidSoFar = cleanNumber.isEmpty || cleanNumber.count <= 16
        let shouldFormat = cleanNumber.count > 4
        
        return (isValidSoFar, shouldFormat, brand)
    }
    
    /// Provides real-time validation feedback for expiry input
    /// - Parameter expiry: Current expiry input
    /// - Returns: Validation state and formatting suggestion
    public static func validateExpiryRealTime(_ expiry: String) -> (isValidSoFar: Bool, shouldFormat: Bool) {
        let digits = expiry.filter { $0.isNumber }
        
        guard !digits.isEmpty else { return (true, false) }
        
        let isValidSoFar = digits.count <= 4
        let shouldFormat = digits.count > 2
        
        return (isValidSoFar, shouldFormat)
    }
}