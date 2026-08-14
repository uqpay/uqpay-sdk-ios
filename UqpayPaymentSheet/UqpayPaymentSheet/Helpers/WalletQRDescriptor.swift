//
//  WalletQRDescriptor.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 11/08/2026.
//

import Foundation
#if canImport(UIKit)
import UIKit
import UqpayPayments

/// Everything that distinguishes one merchant-presented QR wallet from another.
///
/// Every documented QR wallet checks out identically: confirm the intent with
/// `flow: "qrcode"`, render the `display_qr_code` the server returns, and poll
/// the intent until the scan resolves it. Only the branding, the customer-facing
/// copy and the shape of the method details differ — so those are data, and the
/// behaviour is one screen (`WalletQRPaymentViewController` — internal since
/// the 1.0 API lockdown, so a plain code reference rather than a symbol link).
///
/// This replaced six near-identical view controllers. They had already drifted
/// apart in ways that cost real money and real debugging: two asked for icon
/// assets that do not exist, and the Alipay pair reported a different method
/// type to the merchant than the one they confirmed with. A descriptor cannot
/// drift, because there is only one copy of the behaviour.
public struct WalletQRDescriptor {

    /// The API's method type string — `grabpay`, `alipaycn`, and so on.
    ///
    /// This is the single source of that constant. It keys the one-confirm
    /// latch, it is sent in the confirm body, and it is what the merchant
    /// delegate is told. Those three MUST agree: the Alipay screens once sent
    /// `alipaycn` and reported `alipay`, so a merchant matching on the type
    /// saw a payment method that had never been charged.
    public let methodType: String

    /// Shown as the screen title and heading.
    public let displayName: String

    /// Image set in the sheet's asset catalog, or nil for a wallet whose brand
    /// mark has not been drawn yet.
    ///
    /// When it is set it must name a real set: `UIImage(named:)` returns nil
    /// silently, and `wechatpay` and `alipayhk` were both wrong for exactly
    /// that reason without anyone noticing. A test enforces that. Wallets
    /// awaiting artwork say so with nil rather than naming a set that does not
    /// exist, so "no icon yet" stays distinguishable from "typo".
    public let iconAssetName: String?

    /// Drawn when there is no asset, tinted with `accentColor`.
    public let fallbackSymbolName: String

    /// The wallet's brand colour: the icon tint and the action button.
    public let accentColor: UIColor

    /// Tells the customer which app to scan with. Wrong copy here sends people
    /// to the wrong app, so it names the app rather than saying "your wallet".
    public let scanInstruction: String

    /// Builds the confirm method details. It is handed the method type rather
    /// than closing over a literal, so a descriptor cannot confirm under one
    /// type while latching under another.
    private let makeConfirmMethod: (String) -> ConfirmPaymentMethod

    /// Title colour for the action button, chosen so the label stays readable
    /// on `accentColor`. White-on-brand is right for most wallets and wrong
    /// for the bright ones — KakaoPay's yellow would render a white title
    /// almost invisible.
    var buttonTitleColor: UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard accentColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return .white }
        // Rec. 709 relative luminance, the same weighting WCAG contrast uses.
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.6 ? UIColor(white: 0.1, alpha: 1.0) : .white
    }

    public init(
        methodType: String,
        displayName: String,
        iconAssetName: String?,
        fallbackSymbolName: String = "creditcard.circle.fill",
        accentColor: UIColor,
        scanInstruction: String,
        makeConfirmMethod: @escaping (String) -> ConfirmPaymentMethod
    ) {
        self.methodType = methodType
        self.displayName = displayName
        self.iconAssetName = iconAssetName
        self.fallbackSymbolName = fallbackSymbolName
        self.accentColor = accentColor
        self.scanInstruction = scanInstruction
        self.makeConfirmMethod = makeConfirmMethod
    }

    /// The confirm payload for this wallet.
    ///
    /// The assertion is the structural guarantee that the type sent, the type
    /// latched and the type reported are one value. It fires in debug only; in
    /// release the sent body still wins, because that is what the server saw.
    func confirmMethod() -> ConfirmPaymentMethod {
        let method = makeConfirmMethod(methodType)
        assert(
            method.type == methodType,
            "Descriptor for \(methodType) built a ConfirmPaymentMethod typed \(method.type)"
        )
        return method
    }
}

// MARK: - Registry

extension WalletQRDescriptor {

    /// The QR wallet this payment method checks out through, or nil if the
    /// method is not a merchant-presented QR wallet (card has its own screen;
    /// PayPal is not implemented).
    ///
    /// Adding a wallet is a case here plus its details type — not a file.
    public static func descriptor(for type: PaymentMethodType) -> WalletQRDescriptor? {
        switch type {
        case .wechat:
            return WalletQRDescriptor(
                methodType: "wechatpay",
                displayName: "WeChat Pay",
                iconAssetName: "wechat",
                fallbackSymbolName: "message.circle.fill",
                accentColor: UIColor(red: 9/255.0, green: 187/255.0, blue: 7/255.0, alpha: 1.0),
                scanInstruction: "Scan the QR code with WeChat to pay",
                // The `mobile_app` flow (WeChat openSDK hand-off) needs an
                // open_id and SDK registration with WeChat; only `qrcode` is
                // implemented here.
                makeConfirmMethod: { type in
                    ConfirmPaymentMethod(type: type, wechatpay: WeChatPayDetails(flow: "qrcode", isPresent: false))
                }
            )

        case .alipay:
            return WalletQRDescriptor(
                methodType: "alipaycn",
                displayName: "Alipay",
                iconAssetName: "alipay",
                accentColor: UIColor(red: 0/255.0, green: 169/255.0, blue: 240/255.0, alpha: 1.0),
                scanInstruction: "Scan the QR code with the Alipay app to pay",
                makeConfirmMethod: { type in
                    ConfirmPaymentMethod(type: type, alipay: AlipayDetails(flow: "qrcode", osType: "ios", isPresent: false))
                }
            )

        case .alipayHK:
            return WalletQRDescriptor(
                methodType: "alipayhk",
                displayName: "Alipay HK",
                iconAssetName: "alipay_hk",
                accentColor: UIColor(red: 0/255.0, green: 169/255.0, blue: 240/255.0, alpha: 1.0),
                scanInstruction: "Scan the QR code with the AlipayHK app to pay",
                makeConfirmMethod: { type in
                    ConfirmPaymentMethod(type: type, alipay: AlipayDetails(flow: "qrcode", osType: "ios", isPresent: false))
                }
            )

        case .grabPay:
            return WalletQRDescriptor(
                methodType: "grabpay",
                displayName: "GrabPay",
                iconAssetName: "grab_pay",
                accentColor: UIColor(red: 0/255.0, green: 177/255.0, blue: 79/255.0, alpha: 1.0),
                scanInstruction: "Scan the QR code with the Grab app to pay",
                makeConfirmMethod: { type in
                    ConfirmPaymentMethod(type: type, grabpay: GrabPayDetails(flow: "qrcode", isPresent: false))
                }
            )

        case .payNow:
            return WalletQRDescriptor(
                methodType: "paynow",
                displayName: "PayNow",
                iconAssetName: "pay_now",
                accentColor: UIColor(red: 124/255.0, green: 26/255.0, blue: 120/255.0, alpha: 1.0),
                scanInstruction: "Scan the QR code with your banking app to pay",
                makeConfirmMethod: { type in
                    ConfirmPaymentMethod(type: type, paynow: PayNowDetails(flow: "qrcode", isPresent: false))
                }
            )

        case .unionPay:
            return WalletQRDescriptor(
                methodType: "unionpay",
                displayName: "UnionPay",
                iconAssetName: "unionpay",
                accentColor: UIColor(red: 0/255.0, green: 76/255.0, blue: 151/255.0, alpha: 1.0),
                scanInstruction: "Scan the QR code with your UnionPay app to pay",
                makeConfirmMethod: { type in
                    ConfirmPaymentMethod(type: type, unionpay: UnionPayDetails(flow: "qrcode", isPresent: false))
                }
            )

        // Regional QR wallets. No brand marks exist for these yet, so they
        // carry a nil asset name and render the QR symbol until design
        // supplies artwork. Accent colours are approximations of each brand
        // and should be confirmed before launch.
        case .trueMoney:
            return regionalWallet(
                methodType: "truemoney",
                displayName: "TrueMoney",
                appName: "TrueMoney Wallet",
                accentColor: UIColor(red: 238/255.0, green: 118/255.0, blue: 35/255.0, alpha: 1.0)
            )

        case .touchNGo:
            return regionalWallet(
                methodType: "tng",
                displayName: "Touch 'n Go",
                appName: "Touch 'n Go eWallet",
                accentColor: UIColor(red: 0/255.0, green: 86/255.0, blue: 160/255.0, alpha: 1.0)
            )

        case .gcash:
            return regionalWallet(
                methodType: "gcash",
                displayName: "GCash",
                appName: "GCash",
                accentColor: UIColor(red: 0/255.0, green: 125/255.0, blue: 254/255.0, alpha: 1.0)
            )

        case .dana:
            return regionalWallet(
                methodType: "dana",
                displayName: "DANA",
                appName: "DANA",
                accentColor: UIColor(red: 17/255.0, green: 142/255.0, blue: 234/255.0, alpha: 1.0)
            )

        case .kakaoPay:
            return regionalWallet(
                methodType: "kakaopay",
                displayName: "KakaoPay",
                appName: "KakaoTalk",
                accentColor: UIColor(red: 254/255.0, green: 229/255.0, blue: 0/255.0, alpha: 1.0)
            )

        case .toss:
            return regionalWallet(
                methodType: "tosspay",
                displayName: "Toss",
                appName: "Toss",
                accentColor: UIColor(red: 0/255.0, green: 100/255.0, blue: 255/255.0, alpha: 1.0)
            )

        case .naverPay:
            return regionalWallet(
                methodType: "naverpay",
                displayName: "Naver Pay",
                appName: "Naver",
                accentColor: UIColor(red: 3/255.0, green: 199/255.0, blue: 90/255.0, alpha: 1.0)
            )

        case .card, .paypal:
            return nil
        }
    }

    /// A wallet whose confirm details are the plain ``WalletQRDetails`` shape.
    ///
    /// `os_type` is sent as `ios`: the response schema documents the field for
    /// every one of these methods, and the device really is iOS. If a live
    /// confirm rejects it, drop it — the field is optional in every shape the
    /// docs do spell out.
    private static func regionalWallet(
        methodType: String,
        displayName: String,
        appName: String,
        accentColor: UIColor
    ) -> WalletQRDescriptor {
        WalletQRDescriptor(
            methodType: methodType,
            displayName: displayName,
            iconAssetName: nil,
            fallbackSymbolName: "qrcode",
            accentColor: accentColor,
            scanInstruction: "Scan the QR code with the \(appName) app to pay",
            makeConfirmMethod: { type in
                let details = WalletQRDetails(flow: "qrcode", osType: "ios", isPresent: false)
                guard let method = ConfirmPaymentMethod(type: type, walletQR: details) else {
                    // Unreachable: every caller above passes a type this
                    // initialiser handles, and a test walks the whole registry.
                    preconditionFailure("No confirm field for wallet type \(type)")
                }
                return method
            }
        )
    }
}
#endif
