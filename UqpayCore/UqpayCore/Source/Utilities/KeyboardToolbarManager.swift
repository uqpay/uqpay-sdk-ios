//
//  KeyboardToolbarManager.swift
//  UqpayCore
//
//  Created by UQPAY on 14/08/2025.
//

import UIKit

final class KeyboardToolbarManager: NSObject {
    
    // MARK: - Properties
    
    private weak var parentViewController: UIViewController?
    private var textFields: [UITextField] = []
    private let appearance: KeyboardToolbarAppearance
    
    public struct KeyboardToolbarAppearance {
        public let backgroundColor: UIColor
        public let tintColor: UIColor
        public let doneButtonColor: UIColor
        
        public init(backgroundColor: UIColor = .systemBackground, 
                   tintColor: UIColor = .systemBlue,
                   doneButtonColor: UIColor = .systemBlue) {
            self.backgroundColor = backgroundColor
            self.tintColor = tintColor
            self.doneButtonColor = doneButtonColor
        }
    }
    
    // MARK: - UI Components
    
    private lazy var keyboardToolbar: UIToolbar = {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.backgroundColor = appearance.backgroundColor
        
        let previousButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.up"),
            style: .plain,
            target: self,
            action: #selector(previousFieldTapped)
        )
        previousButton.tintColor = appearance.tintColor
        
        let nextButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.down"),
            style: .plain,
            target: self,
            action: #selector(nextFieldTapped)
        )
        nextButton.tintColor = appearance.tintColor
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        let doneButton = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        doneButton.tintColor = appearance.doneButtonColor
        
        toolbar.items = [previousButton, nextButton, flexSpace, doneButton]
        return toolbar
    }()
    
    // MARK: - Initialization
    
    public init(parentViewController: UIViewController, appearance: KeyboardToolbarAppearance = KeyboardToolbarAppearance()) {
        self.parentViewController = parentViewController
        self.appearance = appearance
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Configures text fields with keyboard toolbar and navigation
    /// - Parameter textFields: Array of text fields to manage
    public func configureTextFields(_ textFields: [UITextField]) {
        self.textFields = textFields
        
        // Add toolbar to each text field
        textFields.forEach { textField in
            textField.inputAccessoryView = keyboardToolbar
        }
    }
    
    /// Updates the toolbar button states based on current text field
    /// - Parameter textField: The currently active text field
    public func updateToolbarButtonStates(for textField: UITextField) {
        guard let currentIndex = textFields.firstIndex(of: textField),
              let toolbar = textField.inputAccessoryView as? UIToolbar,
              let items = toolbar.items else { return }
        
        // Previous button (index 0)
        items[0].isEnabled = currentIndex > 0
        
        // Next button (index 1)
        items[1].isEnabled = currentIndex < textFields.count - 1
    }
    
    /// Moves focus to the next text field in the sequence
    /// - Returns: True if navigation occurred, false if at end
    @discardableResult
    public func navigateToNextField() -> Bool {
        guard let currentField = textFields.first(where: { $0.isFirstResponder }),
              let currentIndex = textFields.firstIndex(of: currentField),
              currentIndex < textFields.count - 1 else { return false }
        
        let nextField = textFields[currentIndex + 1]
        nextField.becomeFirstResponder()
        return true
    }
    
    /// Moves focus to the previous text field in the sequence
    /// - Returns: True if navigation occurred, false if at beginning
    @discardableResult
    public func navigateToPreviousField() -> Bool {
        guard let currentField = textFields.first(where: { $0.isFirstResponder }),
              let currentIndex = textFields.firstIndex(of: currentField),
              currentIndex > 0 else { return false }
        
        let previousField = textFields[currentIndex - 1]
        previousField.becomeFirstResponder()
        return true
    }
    
    /// Dismisses the keyboard
    public func dismissKeyboard() {
        parentViewController?.view.endEditing(true)
    }
    
    // MARK: - Private Actions
    
    @objc private func previousFieldTapped() {
        navigateToPreviousField()
    }
    
    @objc private func nextFieldTapped() {
        navigateToNextField()
    }
    
    @objc private func doneButtonTapped() {
        dismissKeyboard()
    }
}

// MARK: - UITextFieldDelegate Support

extension KeyboardToolbarManager {
    
    /// Call this from textFieldDidBeginEditing to update toolbar states
    /// - Parameter textField: The text field that began editing
    public func textFieldDidBeginEditing(_ textField: UITextField) {
        updateToolbarButtonStates(for: textField)
    }
}
