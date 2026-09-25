Pod::Spec.new do |s|
  s.name                  = "UqpayCore"
  s.version               = "1.1.1"
  s.summary               = "Configuration, typed networking and credentials for the UQPAY iOS SDK."
  s.description           = <<-DESC
                            UqpayCore holds the pieces every other UQPAY module builds on:
                            environment and credential configuration, the typed HTTP client,
                            Keychain storage, the error taxonomy and logging.

                            Most integrations should depend on `UqpaySDKiOS` instead, which pulls
                            this in along with the payment models and the prebuilt payment sheet.
                            DESC
  s.homepage              = "https://docs.uqpay.com"
  s.license               = { :type => "MIT", :file => "LICENSE" }
  s.authors               = { "UQPAY" => "developer@uqpay.com" }
  s.source                = { :git => "https://github.com/uqpay/uqpay-sdk-ios.git", :tag => "#{s.version}" }
  s.documentation_url     = "https://docs.uqpay.com"

  s.platform              = :ios
  s.ios.deployment_target = "15.0"
  s.swift_versions        = ["5.9"]
  s.static_framework      = true

  s.source_files          = "UqpayCore/UqpayCore/**/*.swift"
  s.exclude_files         = "UqpayCore/UqpayCore/**/*.docc/**/*"
  # `UqpayCoreResources.bundle` looks for a nested `UqpayCore.bundle` on the
  # CocoaPods path, so that bundle name is load-bearing.
  s.resource_bundles      = {
    "UqpayCore"         => "UqpayCore/UqpayCore/Localizations/*.lproj",
    "UqpayCore_Privacy" => "UqpayCore/UqpayCore/PrivacyInfo.xcprivacy"
  }
end
