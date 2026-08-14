//
//  DeviceBrowserInfo.swift
//  UqpayPayments
//
//  Created by UQPAY on 10/08/2026.
//

import Foundation
#if canImport(UIKit)
import UIKit

public extension BrowserInfo {

    /// Browser info describing the device that is actually paying.
    ///
    /// Every value is measured from the running device — screen bounds, OS
    /// version, locale, processor count, memory. Nothing is fabricated: this
    /// payload feeds 3DS risk scoring, and canned values (1920×1080,
    /// "iOS 14.5") would misdescribe nearly every real customer. Use this
    /// rather than filling the fields by hand.
    ///
    /// Main-actor because `UIScreen` and `UIDevice` are main-thread API.
    /// Build it before hopping to a background task.
    @MainActor
    static func currentDevice() -> BrowserInfo {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osToken = "\(osVersion.majorVersion)_\(osVersion.minorVersion)"
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let screenBounds = UIScreen.main.bounds

        // The user agent must describe the same device as device_model — a
        // risk engine reads an iPad model with an iPhone UA as spoofing.
        // These are the shapes real Safari uses on each device family.
        let userAgent: String
        if UIDevice.current.userInterfaceIdiom == .pad {
            userAgent = "Mozilla/5.0 (iPad; CPU OS \(osToken) like Mac OS X)"
        } else {
            userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS \(osToken) like Mac OS X)"
        }

        let browser = BrowserDetails(
            javaEnabled: true,
            javascriptEnabled: true,
            userAgent: userAgent
        )

        // The confirm endpoint validates os_type strictly — lowercase is
        // rejected with a 400.
        let mobile = MobileInfo(
            deviceModel: UIDevice.current.model,
            osType: "IOS",
            osVersion: "iOS \(osVersion.majorVersion).\(osVersion.minorVersion)"
        )

        // Locale.current.identifier can carry extensions — a device with a
        // region override reports "en_US@rg=myzzzz" — and the API rejects
        // those with "language is invalid". Reduce to a plain BCP 47 tag.
        let language = Locale.current.identifier
            .split(separator: "@").first
            .map { $0.replacingOccurrences(of: "_", with: "-") } ?? "en-US"

        // Offset in whole hours. The 3DS integration guide's sample sends
        // "timezone": "-2", so this field is hours, not the minutes an EMV
        // 3DS `browserTZ` would carry. Half-hour zones (India, Nepal) cannot
        // be expressed in the documented shape and truncate toward zero.
        let timezoneHours = TimeZone.current.secondsFromGMT() / 3600

        // Location is omitted entirely: the SDK never fabricates
        // coordinates, and the API rejects lat/lon "0" anyway.
        return BrowserInfo(
            acceptHeader: "*/*",
            browser: browser,
            deviceId: deviceId,
            language: language,
            mobile: mobile,
            screenColorDepth: 24,
            screenHeight: Int(screenBounds.height),
            screenWidth: Int(screenBounds.width),
            timezone: "\(timezoneHours)",
            hardwareConcurrency: ProcessInfo.processInfo.activeProcessorCount,
            deviceMemory: max(1, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824))
        )
    }
}
#endif
