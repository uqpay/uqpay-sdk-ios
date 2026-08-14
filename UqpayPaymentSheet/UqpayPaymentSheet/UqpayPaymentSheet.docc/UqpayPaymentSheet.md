# ``UqpayPaymentSheet``

A drop-in payment UI for UQPAY: present one sheet, receive one callback per
payment outcome.

## Overview

`UqpayPaymentSheet` hosts the complete customer-facing flow — payment-method
selection, card entry with 3D Secure, and merchant-presented wallet QR codes —
inside a bottom sheet you present from UIKit or SwiftUI.

The integration is three steps:

1. Configure ``PaymentSheet`` with a ``PaymentSheet/Configuration`` and an
   optional ``PaymentSheet/Appearance``.
2. Set ``PaymentSheet/paymentDelegate`` and present the controller from
   ``PaymentSheet/loadViewController(completion:)`` (UIKit) or the
   `uqpayPaymentSheet(isPresented:sheet:sheetType:)` view modifier (SwiftUI).
3. Receive exactly one outcome per payment through ``PaymentDelegate``.

The sheet follows the device's light/dark appearance and the user's Dynamic
Type setting; pin a specific style with
``PaymentSheet/Appearance/userInterfaceStyle``.

### Where it runs

iOS 15.0 and later, on iPhone and iPad, in portrait and landscape. The sheet
never forces an orientation on your app — it adapts to whatever your app
declares, and every screen scrolls rather than clipping when the content
outgrows the viewport (a small phone in landscape, or an accessibility text
size). Multiple windows are supported: dismissal resolves the window the sheet
is actually in rather than an arbitrary connected scene, so Split View and
Stage Manager behave.

Treat delegate callbacks as UI signals: confirm every payment server-side from
the `acquiring.payment_intent.succeeded` webhook before shipping goods.

## Topics

### Presenting the sheet

- ``PaymentSheet``
- ``PaymentSheetType``
- ``UqpayPaymentSheetPresenter``

### Configuration and theming

- ``PaymentSheet/Configuration``
- ``PaymentSheet/Appearance``

### Receiving the outcome

- ``PaymentDelegate``
- ``PaymentResult``
- ``PaymentStatus``
- ``PaymentError``
- ``PaymentSheetError``

### Returning from external apps

- ``PaymentSheet/paymentReturnedFromBank``
