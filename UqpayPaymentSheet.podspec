Pod::Spec.new do |s|
  s.name                  = "UqpayPaymentSheet"
  s.version               = "1.0.0"
  s.summary               = "The prebuilt UQPAY payment UI: method list, card form, 3D Secure and QR wallets."
  s.description           = <<-DESC
                            UqpayPaymentSheet is the drop-in payment flow: the payment method
                            list, the card form with 3D Secure, and the merchant-presented QR
                            screens for WeChat Pay, Alipay, GrabPay, PayNow, UnionPay and the
                            other regional wallets. It reports every outcome through one
                            `PaymentDelegate`.

                            Most integrations should depend on `UqpayiOSSDK`, which pulls this in
                            along with its two dependencies.
                            DESC
  s.homepage              = "https://developer.uqpay.com"
  s.license               = { :type => "MIT", :file => "LICENSE" }
  s.authors               = { "UQPAY" => "developer@uqpay.com" }
  s.source                = { :git => "https://github.com/uqpay/uqpay-ios-sdk.git", :tag => "#{s.version}" }
  s.documentation_url     = "https://developer.uqpay.com"

  s.platform              = :ios
  s.ios.deployment_target = "15.0"
  s.swift_versions        = ["5.9"]
  s.static_framework      = true

  s.source_files          = "UqpayPaymentSheet/UqpayPaymentSheet/**/*.swift"
  s.exclude_files         = "UqpayPaymentSheet/UqpayPaymentSheet/**/*.docc/**/*"

  # `UqpayResourceManager.bundle` looks for a nested `UqpayPaymentSheet.bundle`
  # on the CocoaPods path, so this bundle name is load-bearing — see
  # UqpayPaymentSheet/UqpayPaymentSheet/Resources/UqpayResourceManager.swift.
  s.resource_bundles      = {
    "UqpayPaymentSheet"         => [
      "UqpayPaymentSheet/UqpayPaymentSheet/Resources/UqpayPaymentSheet.xcassets",
      "UqpayPaymentSheet/UqpayPaymentSheet/Localizations/*.lproj"
    ],
    "UqpayPaymentSheet_Privacy" => "UqpayPaymentSheet/UqpayPaymentSheet/PrivacyInfo.xcprivacy"
  }

  # Both are declared explicitly even though UqpayPayments already pulls in
  # UqpayCore: 11 files in this pod `import UqpayCore` directly, so the
  # dependency is real and must not rest on UqpayPayments keeping its own.
  s.dependency "UqpayCore", "#{s.version}"
  s.dependency "UqpayPayments", "#{s.version}"
end
