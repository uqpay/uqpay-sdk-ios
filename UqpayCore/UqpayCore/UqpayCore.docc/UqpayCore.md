# ``UqpayCore``

Networking, configuration, and credentials for the UQPAY iOS SDK.

## Overview

`UqpayCore` carries everything the payment UI is built on: the process-wide
``UqpayConfiguration`` singleton, the ``ApiClient`` that talks to the UQPAY
API, typed intent and attempt models, and structured errors.

Most merchants never call this module directly beyond initial setup:

```swift
UqpayConfiguration.shared.environment = .production
UqpayConfiguration.shared.headerToken = tokenFromYourBackend
UqpayConfiguration.shared.paymentIntentId = intent.id
```

Credentials are short-lived tokens minted by your backend — the SDK never
embeds or stores a long-lived API key.

## Topics

### Configuration

- ``UqpayConfiguration``
- ``UqpayEnvironment``
- ``UqpayConfigurationError``

### Talking to the API

- ``ApiClient``
- ``UqpayHTTPClient``
- ``UqpayRequest``
- ``UqpayIdempotencyKey``

### Payment intent models

- ``UqpayPaymentIntentStatus``
- ``UqpayPaymentAttemptStatus``

### Credentials

- ``UqpayCredentialProvider``
- ``UqpayStaticTokenProvider``
- ``KeychainHelper``

### Errors and logging

- ``UqpayAPIError``
- ``UqpayAPIErrorBody``
- ``UqpayLogger``
- ``UqpayLogLevel``
