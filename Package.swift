// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "uqpay_ios_sdk",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        // Core products
        .library(name: "UqpayCore", targets: ["UqpayCore"]),
        .library(name: "UqpayPayments", targets: ["UqpayPayments"]),
        .library(name: "UqpayPaymentSheet", targets: ["UqpayPaymentSheet"]),
        
        // Complete SDK bundle
        .library(name: "UqpaySDK", targets: [
            "UqpayCore",
            "UqpayPayments",
            "UqpayPaymentSheet"
        ])
    ],
    dependencies: [],
    targets: [
        // MARK: - Core Framework
        .target(
            name: "UqpayCore",
            path: "UqpayCore/UqpayCore",
            exclude: [
                "UqpayCore.docc",
                "Source/Utilities/README.md"
            ],
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
                .process("Localizations")
            ]
        ),

        // MARK: - Payments Framework
        .target(
            name: "UqpayPayments",
            dependencies: [
                .target(name: "UqpayCore")
            ],
            path: "UqpayPayments/UqpayPayments",
            exclude: [
                "UqpayPayments.docc"
            ],
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
                .process("Localizations")
            ]
        ),

        // MARK: - Payment Sheet Framework with Resources
        .target(
            name: "UqpayPaymentSheet",
            dependencies: [
                .target(name: "UqpayCore"),
                .target(name: "UqpayPayments")
            ],
            path: "UqpayPaymentSheet/UqpayPaymentSheet",
            exclude: [
                "UqpayPaymentSheet.docc"
            ],
            resources: [
                .process("Resources/UqpayPaymentSheet.xcassets"),
                .copy("PrivacyInfo.xcprivacy"),
                .process("Localizations")
            ]
        ),
        
        // MARK: - Test Targets
        .testTarget(
            name: "UqpayCoreTests",
            dependencies: ["UqpayCore"],
            path: "UqpayCore/UqpayCoreTests"
        ),
        .testTarget(
            name: "UqpayPaymentsTests",
            dependencies: ["UqpayPayments"],
            path: "UqpayPayments/UqpayPaymentsTests"
        ),
        .testTarget(
            name: "UqpayPaymentSheetTests",
            dependencies: ["UqpayPaymentSheet"],
            path: "UqpayPaymentSheet/UqpayPaymentSheetTests"
        )
    ]
)

