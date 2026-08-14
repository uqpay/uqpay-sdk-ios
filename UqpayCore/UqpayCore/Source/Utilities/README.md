# UqpayCore Utilities

This directory contains shared utility classes designed to eliminate code duplication across the UQPAY iOS SDK modules and provide consistent behavior.

## Overview

These utilities extract common patterns from the SDK's view controllers and provide reusable, well-tested components.

## Utilities

### 1. KeyboardToolbarManager
**Purpose**: Manages keyboard navigation toolbar for text fields
**Replaces**: Duplicated keyboard toolbar code in `PaymentListViewController` and `PaymentCardDialogViewController`

**Features**:
- Automatic Previous/Next navigation between text fields
- Customizable appearance with themes
- Done button to dismiss keyboard
- Automatic button state management

**Usage**:
```swift
// Initialize
let keyboardManager = KeyboardToolbarManager(
    parentViewController: self,
    appearance: KeyboardToolbarManager.KeyboardToolbarAppearance(
        doneButtonColor: appearance.payButtonColor
    )
)

// Configure text fields
keyboardManager.configureTextFields([cardNumberField, expiryField, cvcField])

// In textFieldDidBeginEditing delegate method
keyboardManager.textFieldDidBeginEditing(textField)
```

### 2. APIResponseHandler
**Purpose**: Consistent API response processing and error handling
**Replaces**: Duplicated HTTP response handling across API calls

**Features**:
- Standardized error mapping
- HTTP status code handling
- Network error categorization
- Retry logic helpers
- Payment-specific response processing

**Usage**:
```swift
// Process generic API response
let result = APIResponseHandler.processHTTPResponse(
    data: data,
    response: response,
    error: error,
    responseType: PaymentResponse.self
)

if result.isSuccess {
    // Handle success
} else {
    // Handle error
    print(result.error?.errorDescription)
}

// Process payment response
let paymentResult = APIResponseHandler.processPaymentResponse(
    data: data,
    response: response,
    error: error
)
```

### 3. UIComponentFactory
**Purpose**: Creates consistent UI components with standardized styling
**Replaces**: Duplicated UI setup patterns

**Features**:
- Styled text fields for different input types
- Primary and secondary buttons
- Loading indicators
- Container views with consistent styling
- Loading state management

**Usage**:
```swift
// Create payment form fields
let cardNumberField = UIComponentFactory.createCardNumberField()
let expiryField = UIComponentFactory.createExpiryField()
let cvcField = UIComponentFactory.createCVCField()

// Create buttons
let payButton = UIComponentFactory.createPrimaryButton(
    title: "Pay",
    color: appearance.payButtonColor,
    target: self,
    action: #selector(payButtonTapped)
)

// Manage loading state
UIComponentFactory.setButtonLoadingState(payButton, isLoading: true)
```

## Migration Guide

### From PaymentListViewController
Replace the following patterns:

**Before** (Keyboard Toolbar):
```swift
private lazy var keyboardToolbar: UIToolbar = {
    // 30+ lines of setup code
}()
```

**After**:
```swift
private lazy var keyboardManager = KeyboardToolbarManager(parentViewController: self)
```

### From PaymentCardDialogViewController
Similar replacements apply for:
- Keyboard toolbar management
- API response handling

**Note**: Payment-specific utilities like `CardBrandIconFactory` and `PaymentValidationHelper` have been moved to the `UqpayPayments` module as part of proper architectural separation.

## Benefits

✅ **Reduced Code Duplication**: ~800-1000 lines of duplicated code eliminated
✅ **Consistent Behavior**: All components use the same validation and styling logic
✅ **Easier Maintenance**: Changes in one place affect all usage locations
✅ **Better Testing**: Shared utilities can have comprehensive unit tests
✅ **Type Safety**: Strongly typed APIs with clear error handling
✅ **Customization**: Configurable appearance and behavior

## Dependencies

These utilities depend on:
- `UIKit` (for UI components)
- `Foundation` (for basic functionality)

**Note**: Payment-specific utilities that previously depended on `UqpayPayments` have been moved to that module to maintain proper dependency hierarchy.

## Testing

Each utility is designed to be unit testable. Consider adding tests for:
- API response parsing in `APIResponseHandler`
- Text field navigation in `KeyboardToolbarManager`
- UI component creation in `UIComponentFactory`

**Note**: Payment-specific validation and icon utilities are now tested within the `UqpayPayments` module.

## Future Improvements

Consider these enhancements:
- Accessibility support for all UI components
- Localization support for error messages
- Analytics integration for user interactions
- Performance optimizations for icon rendering
- Additional validation rules for international cards
