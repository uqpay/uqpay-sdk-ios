# UIKitExample Setup Instructions

## Framework Dependencies

To use this UIKitExample, you need to add the following framework dependencies to your Xcode project:

1. **Open UIKitExample.xcodeproj**
2. **Select the UIKitExample target**
3. **Go to "General" tab**
4. **Under "Frameworks, Libraries, and Embedded Content", add:**
   - UqpayCore.framework
   - UqpayPayments.framework
   - UqpayPaymentSheet.framework

## Alternative: Using the Workspace

1. **Open uqpay_ios_sdk.xcworkspace** (not the .xcodeproj)
2. The workspace should automatically link the dependencies

## Features Implemented

The UIKitExample demonstrates:

1. **Environment Selection** - Switch between Demo, Staging, and Production environments
2. **Payment Methods:**
   - Buy - Shows all available payment methods
   - Buy Card Only - Restricts to card payment only
   - Payment List V2 - Custom payment list UI
3. **Delegate Implementations** - PaymentSheetDelegate
4. **Loading States** - Activity indicator with button state management
5. **Error Handling** - UIAlertController for error display

## Code Structure

- **ViewController.swift** - Main UIKit implementation with all UI components
- **ContentViewModel.swift** - Business logic and SDK configuration
- All UI is built programmatically using Auto Layout
- Uses Combine for state management between View and ViewModel

## Testing Without SDK Dependencies

If you want to test the UI without the SDK dependencies, you can:
1. Comment out the SDK imports
2. Create mock types for the SDK classes
3. Focus on the UI layout and interactions