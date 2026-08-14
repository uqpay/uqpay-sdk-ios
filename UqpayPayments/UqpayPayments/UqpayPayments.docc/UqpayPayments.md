# ``UqpayPayments``

Payment models and card validation for the UQPAY iOS SDK.

## Overview

`UqpayPayments` defines the payment-method domain — card brands, payment
method types, and billing models — plus client-side card validation: Luhn
checking, brand detection from the number, expiry parsing, and brand-aware
CVC length rules.

```swift
let result = PaymentValidationHelper.validateCard(
    cardNumber: "4242 4242 4242 4242",
    expiry: "12/29",
    cvc: "123"
)
// result.isValid, result.brand (.visa), result.errors
```

Validation failures are stable identifiers: switch on
`CardValidationResult.ValidationError` for logic, and show its localized
`errorDescription` to users.

## Topics

### Card validation

- ``PaymentValidationHelper``
- ``CardValidator``
- ``CardBrand``

### Payment models

- ``PaymentMethodType``
- ``CardDetails``
- ``BillingAddress``
- ``Customer``
- ``PaymentIntent``
- ``PaymentMethodOptions``
- ``Token``

### Card artwork

- ``CardBrandIconFactory``
- ``CardBrandIconManager``
