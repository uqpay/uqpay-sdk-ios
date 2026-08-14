//
//  CountryRegion.swift
//  UqpayPaymentSheet
//
//  Created by UQPAY on 11/08/2026.
//

import Foundation

/// One selectable billing country, carrying the ISO 3166-1 alpha-2 code the
/// confirm API expects.
///
/// The card form used to take the country as free text and translate it through
/// a nine-entry lookup table that returned `"US"` for everything it did not
/// recognise. A customer in Indonesia had `country_code: "US"` sent to the
/// issuer, which is wrong AVS and wrong risk data on every payment outside
/// those nine markets. The code now comes from the customer's actual selection
/// and can never be silently substituted.
struct CountryRegion: Equatable {

    /// ISO 3166-1 alpha-2, e.g. `SG`.
    let code: String

    /// Localised display name, e.g. "Singapore".
    let name: String

    /// Every ISO country/territory the platform knows, sorted by display name
    /// in the current locale.
    static let all: [CountryRegion] = {
        isoCountryCodes()
            .compactMap { code in
                guard let name = Locale.current.localizedString(forRegionCode: code) else { return nil }
                return CountryRegion(code: code, name: name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    /// The device's own region, used as the initial selection.
    static var deviceDefault: CountryRegion? {
        guard let code = deviceRegionCode() else { return nil }
        return all.first { $0.code == code }
    }

    static func first(matching code: String) -> CountryRegion? {
        let wanted = code.uppercased()
        return all.first { $0.code == wanted }
    }

    // MARK: - Platform lookup

    private static func isoCountryCodes() -> [String] {
        let identifiers: [String]
        if #available(iOS 16.0, *) {
            identifiers = Locale.Region.isoRegions.map(\.identifier)
        } else {
            identifiers = Locale.isoRegionCodes
        }

        // `isoRegions` also contains groupings such as "001" (World) and "150"
        // (Europe). Only alpha-2 country codes are billing addresses.
        return identifiers.filter { identifier in
            identifier.count == 2 && identifier.allSatisfy { $0.isLetter && $0.isUppercase }
        }
    }

    private static func deviceRegionCode() -> String? {
        if #available(iOS 16.0, *) {
            return Locale.current.region?.identifier
        }
        return Locale.current.regionCode
    }
}
