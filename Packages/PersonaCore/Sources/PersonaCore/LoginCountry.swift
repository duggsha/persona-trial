import Foundation

/// A country dialling option for phone entry (login + WhatsApp connect).
/// Pure model + matching/search logic lives here (PersonaCore) so it is unit
/// tested without SwiftUI; the picker UI stays in PersonaUI.
public struct LoginCountry: Identifiable, Hashable, Sendable {
    /// Canonical English name (the list's stable ordering key).
    public let name: String
    /// ISO 3166-1 alpha-2 (drives the flag and region matching).
    public let iso: String
    /// Dial code without the leading "+".
    public let dial: String

    public init(name: String, iso: String, dial: String) {
        self.name = name
        self.iso = iso
        self.dial = dial
    }

    public var id: String { iso }

    /// 🇩🇪 from "DE" via regional-indicator symbols.
    public var flag: String {
        iso.unicodeScalars.reduce(into: "") { result, scalar in
            if let flagScalar = Unicode.Scalar(127_397 + scalar.value) { result.unicodeScalars.append(flagScalar) }
        }
    }

    /// The name in the device language ("Alemania" on an es device). Falls back
    /// to the canonical English name.
    public var localizedName: String {
        Locale.current.localizedString(forRegionCode: iso) ?? name
    }

    public static let deviceDefault: LoginCountry = defaultCountry(forRegion: Locale.current.region?.identifier)

    /// The picker default for a device region: the region's own entry, else US.
    public static func defaultCountry(forRegion region: String?) -> LoginCountry {
        let iso = region?.uppercased() ?? "US"
        return all.first { $0.iso == iso } ?? all.first { $0.iso == "US" } ?? all[0]
    }

    /// The full default ladder, strongest prior first: the suggested/last-linked
    /// number's country, then the user's own ACCOUNT number's country (the
    /// WhatsApp flow binds the user's own line, so their account number is the
    /// best prior the client has), then the device region, then US. Each number
    /// resolves through `bestMatch`, so the device region still breaks shared
    /// dial-code ties inside every rung.
    public static func defaultCountry(
        suggestedNumber: String?,
        accountNumber: String?,
        deviceRegion: String?
    ) -> LoginCountry {
        if let suggested = suggestedNumber, let match = bestMatch(forNumber: suggested, deviceRegion: deviceRegion) {
            return match
        }
        if let account = accountNumber, let match = bestMatch(forNumber: account, deviceRegion: deviceRegion) {
            return match
        }
        return defaultCountry(forRegion: deviceRegion)
    }

    /// Best country for a raw/E.164 number: the LONGEST dial-code prefix wins,
    /// and when several countries share that dial code (+1 is US, Canada, and
    /// half the Caribbean) the DEVICE REGION breaks the tie — never list order,
    /// which is how a US tester once got Canada. Falls back US-first, then list
    /// order, so the result is deterministic.
    public static func bestMatch(
        forNumber number: String,
        deviceRegion: String? = Locale.current.region?.identifier
    ) -> LoginCountry? {
        let digits = number.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        let candidates = all.filter { digits.hasPrefix($0.dial) }
        guard let longest = candidates.map(\.dial.count).max() else { return nil }
        let tied = candidates.filter { $0.dial.count == longest }
        if let region = deviceRegion?.uppercased(), let regional = tied.first(where: { $0.iso == region }) {
            return regional
        }
        return tied.first { $0.iso == "US" } ?? tied.first
    }

    /// Picker search: matches the LOCALIZED name and the canonical English name
    /// (case- and diacritic-insensitive — "turkiye" finds Türkiye), the ISO code
    /// ("us", "DE"), and the dial code with or without the leading "+" ("49",
    /// "+ 1"). Dial matching runs BOTH directions: a partial query prefixes the
    /// dial ("4" finds +43/+44/+49…) and a pasted full number is prefixed BY the
    /// dial ("+4917 180…" finds Germany). Whitespace runs are collapsed, so
    /// " united states " still finds the US. An empty query returns the full
    /// list.
    public static func search(_ query: String, locale: Locale = .current) -> [LoginCountry] {
        let collapsed = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return all }

        let foldOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let folded = collapsed.folding(options: foldOptions, locale: locale)
        let digits = collapsed.filter(\.isNumber)
        let isDialQuery = !digits.isEmpty && collapsed.allSatisfy { $0.isNumber || $0 == "+" || $0 == " " }
        let isoQuery = collapsed.count == 2 && collapsed.allSatisfy(\.isLetter) ? collapsed.uppercased() : nil

        return all.filter { country in
            if isDialQuery, country.dial.hasPrefix(digits) || digits.hasPrefix(country.dial) { return true }
            if let isoQuery, country.iso == isoQuery { return true }
            let localized = locale.localizedString(forRegionCode: country.iso) ?? country.name
            if localized.folding(options: foldOptions, locale: locale).contains(folded) { return true }
            return country.name.folding(options: foldOptions, locale: locale).contains(folded)
        }
    }

    /// Common dialling codes (alpha-2 + dial). Covers essentially every user; the
    /// picker is searchable for the long tail.
    public static let all: [LoginCountry] = [
        .init(name: "Afghanistan", iso: "AF", dial: "93"),
        .init(name: "Albania", iso: "AL", dial: "355"),
        .init(name: "Algeria", iso: "DZ", dial: "213"),
        .init(name: "Argentina", iso: "AR", dial: "54"),
        .init(name: "Armenia", iso: "AM", dial: "374"),
        .init(name: "Australia", iso: "AU", dial: "61"),
        .init(name: "Austria", iso: "AT", dial: "43"),
        .init(name: "Azerbaijan", iso: "AZ", dial: "994"),
        .init(name: "Bahrain", iso: "BH", dial: "973"),
        .init(name: "Bangladesh", iso: "BD", dial: "880"),
        .init(name: "Belarus", iso: "BY", dial: "375"),
        .init(name: "Belgium", iso: "BE", dial: "32"),
        .init(name: "Bolivia", iso: "BO", dial: "591"),
        .init(name: "Bosnia & Herzegovina", iso: "BA", dial: "387"),
        .init(name: "Brazil", iso: "BR", dial: "55"),
        .init(name: "Bulgaria", iso: "BG", dial: "359"),
        .init(name: "Cambodia", iso: "KH", dial: "855"),
        .init(name: "Cameroon", iso: "CM", dial: "237"),
        .init(name: "Canada", iso: "CA", dial: "1"),
        .init(name: "Chile", iso: "CL", dial: "56"),
        .init(name: "China", iso: "CN", dial: "86"),
        .init(name: "Colombia", iso: "CO", dial: "57"),
        .init(name: "Costa Rica", iso: "CR", dial: "506"),
        .init(name: "Croatia", iso: "HR", dial: "385"),
        .init(name: "Cyprus", iso: "CY", dial: "357"),
        .init(name: "Czechia", iso: "CZ", dial: "420"),
        .init(name: "Denmark", iso: "DK", dial: "45"),
        .init(name: "Dominican Republic", iso: "DO", dial: "1"),
        .init(name: "Ecuador", iso: "EC", dial: "593"),
        .init(name: "Egypt", iso: "EG", dial: "20"),
        .init(name: "Estonia", iso: "EE", dial: "372"),
        .init(name: "Ethiopia", iso: "ET", dial: "251"),
        .init(name: "Finland", iso: "FI", dial: "358"),
        .init(name: "France", iso: "FR", dial: "33"),
        .init(name: "Georgia", iso: "GE", dial: "995"),
        .init(name: "Germany", iso: "DE", dial: "49"),
        .init(name: "Ghana", iso: "GH", dial: "233"),
        .init(name: "Greece", iso: "GR", dial: "30"),
        .init(name: "Guatemala", iso: "GT", dial: "502"),
        .init(name: "Hong Kong", iso: "HK", dial: "852"),
        .init(name: "Hungary", iso: "HU", dial: "36"),
        .init(name: "Iceland", iso: "IS", dial: "354"),
        .init(name: "India", iso: "IN", dial: "91"),
        .init(name: "Indonesia", iso: "ID", dial: "62"),
        .init(name: "Iran", iso: "IR", dial: "98"),
        .init(name: "Iraq", iso: "IQ", dial: "964"),
        .init(name: "Ireland", iso: "IE", dial: "353"),
        .init(name: "Israel", iso: "IL", dial: "972"),
        .init(name: "Italy", iso: "IT", dial: "39"),
        .init(name: "Jamaica", iso: "JM", dial: "1"),
        .init(name: "Japan", iso: "JP", dial: "81"),
        .init(name: "Jordan", iso: "JO", dial: "962"),
        .init(name: "Kazakhstan", iso: "KZ", dial: "7"),
        .init(name: "Kenya", iso: "KE", dial: "254"),
        .init(name: "Kuwait", iso: "KW", dial: "965"),
        .init(name: "Latvia", iso: "LV", dial: "371"),
        .init(name: "Lebanon", iso: "LB", dial: "961"),
        .init(name: "Lithuania", iso: "LT", dial: "370"),
        .init(name: "Luxembourg", iso: "LU", dial: "352"),
        .init(name: "Malaysia", iso: "MY", dial: "60"),
        .init(name: "Malta", iso: "MT", dial: "356"),
        .init(name: "Mexico", iso: "MX", dial: "52"),
        .init(name: "Moldova", iso: "MD", dial: "373"),
        .init(name: "Morocco", iso: "MA", dial: "212"),
        .init(name: "Nepal", iso: "NP", dial: "977"),
        .init(name: "Netherlands", iso: "NL", dial: "31"),
        .init(name: "New Zealand", iso: "NZ", dial: "64"),
        .init(name: "Nigeria", iso: "NG", dial: "234"),
        .init(name: "North Macedonia", iso: "MK", dial: "389"),
        .init(name: "Norway", iso: "NO", dial: "47"),
        .init(name: "Oman", iso: "OM", dial: "968"),
        .init(name: "Pakistan", iso: "PK", dial: "92"),
        .init(name: "Panama", iso: "PA", dial: "507"),
        .init(name: "Paraguay", iso: "PY", dial: "595"),
        .init(name: "Peru", iso: "PE", dial: "51"),
        .init(name: "Philippines", iso: "PH", dial: "63"),
        .init(name: "Poland", iso: "PL", dial: "48"),
        .init(name: "Portugal", iso: "PT", dial: "351"),
        .init(name: "Qatar", iso: "QA", dial: "974"),
        .init(name: "Romania", iso: "RO", dial: "40"),
        .init(name: "Russia", iso: "RU", dial: "7"),
        .init(name: "Saudi Arabia", iso: "SA", dial: "966"),
        .init(name: "Serbia", iso: "RS", dial: "381"),
        .init(name: "Singapore", iso: "SG", dial: "65"),
        .init(name: "Slovakia", iso: "SK", dial: "421"),
        .init(name: "Slovenia", iso: "SI", dial: "386"),
        .init(name: "South Africa", iso: "ZA", dial: "27"),
        .init(name: "South Korea", iso: "KR", dial: "82"),
        .init(name: "Spain", iso: "ES", dial: "34"),
        .init(name: "Sri Lanka", iso: "LK", dial: "94"),
        .init(name: "Sweden", iso: "SE", dial: "46"),
        .init(name: "Switzerland", iso: "CH", dial: "41"),
        .init(name: "Taiwan", iso: "TW", dial: "886"),
        .init(name: "Tanzania", iso: "TZ", dial: "255"),
        .init(name: "Thailand", iso: "TH", dial: "66"),
        .init(name: "Tunisia", iso: "TN", dial: "216"),
        .init(name: "Türkiye", iso: "TR", dial: "90"),
        .init(name: "Uganda", iso: "UG", dial: "256"),
        .init(name: "Ukraine", iso: "UA", dial: "380"),
        .init(name: "United Arab Emirates", iso: "AE", dial: "971"),
        .init(name: "United Kingdom", iso: "GB", dial: "44"),
        .init(name: "United States", iso: "US", dial: "1"),
        .init(name: "Uruguay", iso: "UY", dial: "598"),
        .init(name: "Uzbekistan", iso: "UZ", dial: "998"),
        .init(name: "Venezuela", iso: "VE", dial: "58"),
        .init(name: "Vietnam", iso: "VN", dial: "84")
    ]
}
