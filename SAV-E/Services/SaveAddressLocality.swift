import Foundation

/// One structural parse for Home locality labels and stable city IDs.
///
/// Rules:
/// 1. Identifiers always fold with `en_US_POSIX` — never `.current`.
/// 2. Country-aware admin handling is explicit for US / CA / AU, including
///    full state and province names. Bare two-letter tokens qualify only
///    when they are known codes for that country.
/// 3. CJK municipalities stop at prefecture / province suffixes (`県` `府`
///    `道` `省` …). The label stays the municipality; the stable ID keeps
///    the prefecture so 府中市 in Tokyo and Hiroshima stay apart.
/// 4. Metro aliases apply only when the parsed locality matches and the
///    recognized region or country does not contradict the alias.
struct SaveAddressLocality: Equatable {
    let label: String
    let cityID: String
    let metroKey: String?
    let region: String?
    let country: String?

    static let locale = Locale(identifier: "en_US_POSIX")

    struct Parsed: Equatable {
        let address: String
        let label: String
        let stableLocality: String
        let region: String?
        let country: String?
        let isCJK: Bool
    }

    static func resolve(_ address: String) -> SaveAddressLocality? {
        guard let parsed = parse(address) else { return nil }
        let metro = SaveHomeSearch.metroAlias(for: parsed)
        let cityID: String
        if let metro {
            cityID = metro
        } else if let qualifier = parsed.region ?? (parsed.isCJK ? nil : parsed.country) {
            cityID = "\(parsed.stableLocality),\(qualifier)"
        } else {
            cityID = parsed.stableLocality
        }
        return SaveAddressLocality(
            label: parsed.label,
            cityID: cityID,
            metroKey: metro,
            region: parsed.region,
            country: parsed.country
        )
    }

    static func parse(_ address: String) -> Parsed? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var parts = commaParts(trimmed)
        let country = parts.last.flatMap { Self.country(in: $0) }
        if country != nil { parts.removeLast() }

        if let cjk = cjkMunicipalityToken(in: trimmed) {
            return Parsed(
                address: trimmed,
                label: cjk,
                stableLocality: normalizeIdentifier(cjk),
                region: cjkAdminQualifier(in: trimmed, municipality: cjk),
                country: country,
                isCJK: true
            )
        }

        var region: String?
        if let last = parts.last, isTrailingAdmin(last, country: country) {
            region = qualifyingRegion(in: last, country: country)
            parts.removeLast()
        }

        guard let rawCity = parts.last, !rawCity.isEmpty else { return nil }
        let label = strippingPostalCode(from: rawCity)
        guard !label.isEmpty else { return nil }
        return Parsed(
            address: trimmed,
            label: label,
            stableLocality: normalizeIdentifier(label),
            region: region,
            country: country,
            isCJK: false
        )
    }

    static func country(in value: String) -> String? {
        let last = commaParts(value).last ?? value
        let token = normalizeToken(last)
        guard !token.isEmpty else { return nil }
        if let aliased = countryAliases[token] { return aliased }
        if explicitCountries.contains(token) { return countryAliases[token] ?? token }
        return localizedCountries[token]
    }

    static func canonicalCityID(_ id: String) -> String {
        guard let separator = id.lastIndex(of: ","),
              let country = Self.country(in: String(id[id.index(after: separator)...]))
        else { return id }
        return String(id[...separator]) + country
    }

    static func normalizeIdentifier(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            .lowercased(with: locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeToken(_ value: String) -> String {
        normalizeIdentifier(value)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func strippingPostalCode(from token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = trimmed.replacingOccurrences(of: #"^\d{4,6}\s+"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(
            of: #"\s+(?:\d{4,6}|[A-Za-z]{1,2}\d[A-Za-z\d]?\s*\d[A-Za-z]{2}|[A-Za-z]\d[A-Za-z]\s*\d[A-Za-z]\d)$"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? trimmed : name
    }

    static func countryForAdminRegion(_ code: String) -> String? {
        if usStateCodes.contains(code) { return "united states" }
        if canadianProvinceCodes.contains(code) { return "canada" }
        if australianStateCodes.contains(code) { return "australia" }
        return nil
    }

    static func signalsUnitedStates(_ parsed: Parsed) -> Bool {
        parsed.country == "united states" || (parsed.region != nil && usStateCodes.contains(parsed.region ?? ""))
    }
}

private extension SaveAddressLocality {
    static func commaParts(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func isTrailingAdmin(_ value: String, country: String?) -> Bool {
        qualifyingRegion(in: value, country: country) != nil
            || isStandalonePostcode(value)
            || isKnownNonQualifyingAdmin(value, country: country)
    }

    static func qualifyingRegion(in value: String, country: String?) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^[A-Za-z]{2}$"#, options: .regularExpression) != nil {
            return knownAdminCode(trimmed.lowercased(with: locale), country: country)
        }
        if let match = trimmed.range(of: #"^[A-Za-z]{2}(?=\s)"#, options: .regularExpression) {
            return knownAdminCode(String(trimmed[match]).lowercased(with: locale), country: country)
        }
        if let code = australianStatePostcodeCode(in: trimmed) {
            return code
        }
        let folded = normalizeIdentifier(trimmed)
        if australianStateCodes.contains(folded) { return folded }
        if let code = usStateNames[folded] { return code }
        if let code = canadianProvinceNames[folded] { return code }
        if country == "australia", let code = australianStateNames[folded] {
            return code
        }
        return nil
    }

    static func knownAdminCode(_ code: String, country: String?) -> String? {
        let us = usStateCodes.contains(code)
        let canadian = canadianProvinceCodes.contains(code)
        let australian = australianStateCodes.contains(code)
        switch country {
        case "united states":
            return us ? code : nil
        case "canada":
            return canadian ? code : nil
        case "australia":
            return australian ? code : nil
        case nil:
            return (us || canadian || australian) ? code : nil
        default:
            return nil
        }
    }

    /// `NSW 2000` / `VIC 3000` only — not `Los Ángeles` or `New South Wales`.
    static func australianStatePostcodeCode(in value: String) -> String? {
        let folded = normalizeIdentifier(value)
        guard let match = folded.range(
            of: #"^(nsw|vic|qld|tas|act|sa|wa|nt)\s+\d{4}$"#,
            options: .regularExpression
        ) else { return nil }
        return String(folded[match]).split(separator: " ").first.map(String.init)
    }

    static func isStandalonePostcode(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^\d{5}(?:-\d{4})?$"#,
            #"^[A-Za-z]\d[A-Za-z]\s*\d[A-Za-z]\d$"#,
            #"^[A-Za-z]{1,2}\d[A-Za-z\d]?\s*\d[A-Za-z]{2}$"#,
            #"^\d{4}$"#,
        ]
        return patterns.contains { trimmed.range(of: $0, options: .regularExpression) != nil }
    }

    static func isKnownNonQualifyingAdmin(_ value: String, country: String?) -> Bool {
        let regions: [String: Set<String>] = [
            "chile": ["biobio", "bio bio", "region del biobio"],
            "colombia": ["santander"],
        ]
        guard let country else { return false }
        return regions[country]?.contains(normalizeIdentifier(value)) == true
    }

    static let cjkCountryPrefixes = ["台灣", "臺灣", "台湾", "日本", "中國", "中国"]

    /// Last `市`/`縣`/`县` municipality only. Japanese prefecture suffixes
    /// (`県` `府` `道`) are locality boundaries so `神奈川県横浜市` stays `横浜市`.
    static func cjkMunicipalityToken(in token: String) -> String? {
        guard token.contains(where: {
            $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        }) else { return nil }
        let parts = commaParts(token)
        if let city = parts.reversed().compactMap({ cjkMunicipality(in: $0) }).first {
            return city
        }
        return cjkMunicipality(in: token)
    }

    static func cjkMunicipality(in token: String) -> String? {
        var text = token
        for country in cjkCountryPrefixes {
            text = text.replacingOccurrences(of: country, with: "")
        }
        text = String(text.drop { $0.isNumber || $0.isWhitespace || $0 == "," || $0 == "，" })
        guard let marker = text.rangeOfCharacter(
            from: CharacterSet(charactersIn: "市縣县"),
            options: .backwards
        ) else { return nil }
        let head = text[..<marker.upperBound]
        let boundaries = CharacterSet(charactersIn: "省區区鄉乡鎮镇國国県府道,，")
        var start = marker.lowerBound
        var taken = 0
        while start > head.startIndex {
            let previous = head.index(before: start)
            let character = head[previous]
            if character.unicodeScalars.contains(where: { boundaries.contains($0) })
                || character.isNumber
                || character.isWhitespace
                || character.isASCII {
                break
            }
            start = previous
            taken += 1
            if taken >= 4 { break }
        }
        let city = String(head[start...])
        return city.count >= 2 ? city : nil
    }

    /// Prefecture / province immediately before the municipality.
    /// `東京都府中市` and `広島県府中市` stay distinct; the label stays `府中市`.
    static func cjkAdminQualifier(in address: String, municipality: String) -> String? {
        let parts = commaParts(address)
        if let index = parts.lastIndex(where: { $0.contains(municipality) }) {
            for part in parts[..<index].reversed() {
                if country(in: part) != nil { continue }
                if let admin = cjkAdminToken(in: part) { return admin }
            }
        }
        guard let range = address.range(of: municipality) else { return nil }
        var prefix = String(address[..<range.lowerBound])
        for name in cjkCountryPrefixes where prefix.hasPrefix(name) {
            prefix.removeFirst(name.count)
        }
        prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",，"))
        return cjkAdminToken(in: prefix) ?? trailingCJKAdmin(in: prefix)
    }

    static func cjkAdminToken(in token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, "都府道県省".contains(last) else { return nil }
        if (2...5).contains(trimmed.count) { return trimmed }
        return trailingCJKAdmin(in: trimmed)
    }

    static func trailingCJKAdmin(in text: String) -> String? {
        guard let last = text.last, "都府道県省".contains(last), !text.isEmpty else { return nil }
        var start = text.index(before: text.endIndex)
        var taken = 0
        while start > text.startIndex {
            let previous = text.index(before: start)
            let character = text[previous]
            if "省區区鄉乡鎮镇國国県府道都市縣县,，".contains(character)
                || character.isNumber
                || character.isWhitespace
                || character.isASCII {
                break
            }
            start = previous
            taken += 1
            if taken >= 4 { break }
        }
        let admin = String(text[start...])
        return admin.count >= 2 && "都府道県省".contains(admin.last!) ? admin : nil
    }

    static let countryAliases: [String: String] = [
        "uk": "united kingdom", "u k": "united kingdom", "u.k.": "united kingdom",
        "england": "united kingdom", "britain": "united kingdom",
        "usa": "united states", "us": "united states",
        "united states of america": "united states",
        "korea": "south korea",
        "schweiz": "switzerland", "suisse": "switzerland", "svizzera": "switzerland",
        "österreich": "austria", "osterreich": "austria",
        "nederland": "netherlands", "holland": "netherlands",
        "belgie": "belgium", "belgië": "belgium", "belgique": "belgium",
        "turkiye": "turkey", "türkiye": "turkey",
    ]

    static let explicitCountries: Set<String> = [
        "usa", "us", "united states", "united states of america",
        "uk", "u.k.", "united kingdom", "england", "britain",
        "taiwan", "japan", "china", "canada", "australia", "france",
        "germany", "italy", "spain", "korea", "south korea", "thailand",
        "singapore", "hong kong",
        "turkey", "turkiye", "türkiye",
        "switzerland", "austria", "netherlands", "belgium",
        "india", "chile", "colombia", "mexico", "brazil",
    ]

    static let localizedCountries: [String: String] = {
        let english = locale
        let locales = [english, Locale(identifier: "zh_Hant"), Locale(identifier: "zh_Hans")]
        var tokens: [String: String] = [:]
        for region in Locale.Region.isoRegions {
            guard let name = english.localizedString(forRegionCode: region.identifier) else { continue }
            let canonical = region.identifier == "HK" ? "hong kong" : normalizeToken(name)
            for named in locales {
                if let localized = named.localizedString(forRegionCode: region.identifier) {
                    tokens[normalizeToken(localized)] = canonical
                }
            }
        }
        return tokens
    }()

    static let usStateCodes: Set<String> = [
        "al", "ak", "az", "ar", "ca", "co", "ct", "de", "fl", "ga", "hi",
        "id", "il", "in", "ia", "ks", "ky", "la", "me", "md", "ma", "mi",
        "mn", "ms", "mo", "mt", "ne", "nv", "nh", "nj", "nm", "ny", "nc",
        "nd", "oh", "ok", "or", "pa", "ri", "sc", "sd", "tn", "tx", "ut",
        "vt", "va", "wa", "wv", "wi", "wy", "dc",
    ]

    static let usStateNames: [String: String] = [
        "alabama": "al", "alaska": "ak", "arizona": "az", "arkansas": "ar",
        "california": "ca", "colorado": "co", "connecticut": "ct",
        "delaware": "de", "florida": "fl", "georgia": "ga", "hawaii": "hi",
        "idaho": "id", "illinois": "il", "indiana": "in", "iowa": "ia",
        "kansas": "ks", "kentucky": "ky", "louisiana": "la", "maine": "me",
        "maryland": "md", "massachusetts": "ma", "michigan": "mi",
        "minnesota": "mn", "mississippi": "ms", "missouri": "mo",
        "montana": "mt", "nebraska": "ne", "nevada": "nv",
        "new hampshire": "nh", "new jersey": "nj", "new mexico": "nm",
        "new york": "ny", "north carolina": "nc", "north dakota": "nd",
        "ohio": "oh", "oklahoma": "ok", "oregon": "or", "pennsylvania": "pa",
        "rhode island": "ri", "south carolina": "sc", "south dakota": "sd",
        "tennessee": "tn", "texas": "tx", "utah": "ut", "vermont": "vt",
        "virginia": "va", "washington": "wa", "west virginia": "wv",
        "wisconsin": "wi", "wyoming": "wy", "district of columbia": "dc",
    ]

    static let canadianProvinceCodes: Set<String> = [
        "ab", "bc", "mb", "nb", "nl", "ns", "nt", "nu", "on", "pe", "qc", "sk", "yt",
    ]

    static let canadianProvinceNames: [String: String] = [
        "alberta": "ab", "british columbia": "bc", "manitoba": "mb",
        "new brunswick": "nb", "newfoundland": "nl",
        "newfoundland and labrador": "nl", "nova scotia": "ns",
        "northwest territories": "nt", "nunavut": "nu", "ontario": "on",
        "prince edward island": "pe", "quebec": "qc", "saskatchewan": "sk",
        "yukon": "yt",
    ]

    static let australianStateCodes: Set<String> = [
        "nsw", "vic", "qld", "sa", "wa", "tas", "act", "nt",
    ]

    static let australianStateNames: [String: String] = [
        "new south wales": "nsw",
        "victoria": "vic",
        "queensland": "qld",
        "south australia": "sa",
        "western australia": "wa",
        "tasmania": "tas",
        "australian capital territory": "act",
        "northern territory": "nt",
    ]
}
