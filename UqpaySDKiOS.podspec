Pod::Spec.new do |s|
  s.name                  = "UqpaySDKiOS"
  s.version               = "1.0.3"
  s.summary               = "Accept card payments and regional QR wallets in your iOS app with UQPAY."
  s.description           = <<-DESC
                            The UQPAY iOS SDK provides a prebuilt payment sheet for card payments
                            (with 3D Secure) and merchant-presented QR wallets — WeChat Pay, Alipay,
                            GrabPay, PayNow, UnionPay and seven regional wallets — plus a typed API
                            client for integrations that supply their own UI.

                            This is an umbrella pod: it ships no source of its own and simply pulls
                            in `UqpayCore`, `UqpayPayments` and `UqpayPaymentSheet`. Depend on the
                            individual pods instead if you only need part of the SDK.
                            DESC
  s.homepage              = "https://developer.uqpay.com"
  s.license               = { :type => "MIT", :file => "LICENSE" }
  s.authors               = { "UQPAY" => "developer@uqpay.com" }
  s.source                = { :git => "https://github.com/uqpay/uqpay-sdk-ios.git", :tag => "#{s.version}" }
  s.documentation_url     = "https://developer.uqpay.com"

  s.platform              = :ios
  s.ios.deployment_target = "15.0"
  s.swift_versions        = ["5.9"]
  s.static_framework      = true

  # Each module is its own pod because each is its own Swift module: the sources
  # say `import UqpayCore` / `import UqpayPayments`, and CocoaPods compiles all
  # subspecs of a single pod into one module, where those imports cannot resolve.
  s.dependency "UqpayCore", "#{s.version}"
  s.dependency "UqpayPayments", "#{s.version}"
  s.dependency "UqpayPaymentSheet", "#{s.version}"
end
