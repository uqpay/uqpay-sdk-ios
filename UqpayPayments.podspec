Pod::Spec.new do |s|
  s.name                  = "UqpayPayments"
  s.version               = "1.1.0"
  s.summary               = "Payment models, card validation and device info for the UQPAY iOS SDK."
  s.description           = <<-DESC
                            UqpayPayments carries the payment domain: intent and confirm
                            request/response types, card number and CVC validation with brand
                            detection, and the device/browser information 3D Secure risk
                            scoring needs.

                            Most integrations should depend on `UqpaySDKiOS` instead, which pulls
                            this in along with the prebuilt payment sheet.
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

  s.source_files          = "UqpayPayments/UqpayPayments/**/*.swift"
  s.exclude_files         = "UqpayPayments/UqpayPayments/**/*.docc/**/*"
  # `UqpayPaymentsResources.bundle` looks for a nested `UqpayPayments.bundle`
  # on the CocoaPods path, so that bundle name is load-bearing.
  s.resource_bundles      = {
    "UqpayPayments"         => "UqpayPayments/UqpayPayments/Localizations/*.lproj",
    "UqpayPayments_Privacy" => "UqpayPayments/UqpayPayments/PrivacyInfo.xcprivacy"
  }

  s.dependency "UqpayCore", "#{s.version}"
end
