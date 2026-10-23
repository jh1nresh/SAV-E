import CoreLocation
import MapKit
import UIKit
import XCTest
@testable import SAVE

@MainActor
final class SaveDoodleHomeTests: XCTestCase {
    func testVisitHistoryIsSharedAcrossSurfacesAndSurvivesUndoAndRelaunch() {
        let suite = "save.doodle.shared-visits.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var day = Date(timeIntervalSince1970: 1_760_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let map = SaveDoodleVisitStore(defaults: defaults, calendar: calendar, now: { day })
        let passport = SaveDoodleVisitStore(defaults: defaults, calendar: calendar, now: { day })
        let id = UUID()
        for expected in 1...5 {
            XCTAssertTrue(map.recordVisit(for: id))
            XCTAssertFalse(passport.recordVisit(for: id), "No duplicate same-day visit from another surface")
            XCTAssertEqual(passport.count(for: id), expected)
            if expected < 5 { day = day.addingTimeInterval(86_400) }
        }
        XCTAssertTrue(passport.undoToday(for: id))
        XCTAssertEqual(map.count(for: id), 4)
        XCTAssertFalse(map.hasVisitedToday(id))
        XCTAssertTrue(map.recordVisit(for: id))
        XCTAssertEqual(SaveDoodleVisitStore(defaults: defaults).count(for: id), 5)
    }

    func testVisitHistoryPreservesLegacyCountsWithoutDoubleCounting() {
        let suite = "save.doodle.legacy-visits.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        defaults.set(5, forKey: SaveDoodleVisitStore.countKey(id))
        defaults.set([id.uuidString: [1_600_000_000.0]], forKey: SaveDoodleVisitStore.datesKey)
        let store = SaveDoodleVisitStore(defaults: defaults)
        XCTAssertEqual(store.count(for: id), 5)
        XCTAssertTrue(store.recordVisit(for: id))
        XCTAssertEqual(store.count(for: id), 6)
        XCTAssertTrue(store.undoToday(for: id))
        XCTAssertEqual(store.count(for: id), 5)
    }

    func testEatLensKeepsFoodCafeBarAndDropsGo() {
        let now = Date()
        let food = place("Duck", "Beijing, China", .food, latitude: 39.88, longitude: 116.41, createdAt: now.addingTimeInterval(-2))
        let cafe = place("Grey", "Beijing, China", .cafe, latitude: 39.88, longitude: 116.40, createdAt: now.addingTimeInterval(-1))
        let park = place("Tiantan", "Beijing, China", .attraction, latitude: 39.88, longitude: 116.41, createdAt: now)
        let visible = SaveDoodleHomeCatalog.visiblePlaces(
            from: [food, cafe, park],
            lens: .eat,
            selection: .city("beijing"),
            location: nil,
            locationDenied: true
        )
        XCTAssertEqual(visible.map(\.name), ["Grey", "Duck"])
        XCTAssertEqual(SaveDoodleHomeCatalog.lens(for: .food), .eat)
        XCTAssertEqual(SaveDoodleHomeCatalog.lens(for: .attraction), .go)
    }

    func testGoLensKeepsAttractionStayShopping() {
        let now = Date()
        let park = place("Park", "Tokyo, Japan", .attraction, createdAt: now.addingTimeInterval(-3))
        let hotel = place("Hotel", "Tokyo, Japan", .stay, createdAt: now.addingTimeInterval(-2))
        let shop = place("Shop", "Tokyo, Japan", .shopping, createdAt: now.addingTimeInterval(-1))
        let ramen = place("Ramen", "Tokyo, Japan", .food, createdAt: now)
        let visible = SaveDoodleHomeCatalog.visiblePlaces(
            from: [park, hotel, shop, ramen],
            lens: .go,
            selection: .city("tokyo"),
            location: nil,
            locationDenied: true
        )
        XCTAssertEqual(visible.map(\.name), ["Shop", "Hotel", "Park"])
    }

    func testCityGroupsUseMetroAliases() {
        let ichiran = place(
            "Ichiran",
            "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
            .food
        )
        let siam = place(
            "The Siam Hotel",
            "3/2 Thanon Khao, Vachiraphayaban, Dusit, Bangkok 10300",
            .stay
        )
        let cafe = place("Fujin", "No. 353, Section 1, Fuxing S Rd, Da'an District, Taipei", .cafe)
        let groups = SaveDoodleHomeCatalog.cityGroups(from: [ichiran, siam, cafe])
        XCTAssertEqual(Set(groups.map(\.id)), ["tokyo", "bangkok", "taipei"])
        XCTAssertEqual(SaveHomeSearch.metroName(in: siam.address, traditionalChinese: false), "Bangkok")
        XCTAssertEqual(SaveHomeSearch.metroName(in: ichiran.address, traditionalChinese: true), "東京")
    }

    /// Header, Collected, and Passport share the all-category nearest city.
    /// A closer New Taipei Go save must not leave the Eat header saying Taipei.
    func testNearYouHeaderUsesAllCategoryCityNotEatLens() throws {
        let here = CLLocation(latitude: 25.0300, longitude: 121.5000)
        let newTaipeiGo = place(
            "Yingge Ceramics",
            "Yingge District, New Taipei",
            .attraction,
            latitude: 25.03005,
            longitude: 121.50005
        )
        let taipeiEat = place(
            "Fujin",
            "No. 353, Section 1, Fuxing S Rd, Da'an District, Taipei",
            .cafe,
            latitude: 25.0330,
            longitude: 121.5100
        )
        let places = [newTaipeiGo, taipeiEat]
        let eatListed = SaveDoodleHomeCatalog.listedPlaces(
            from: places,
            lens: .eat,
            selection: .nearYou,
            location: here,
            locationDenied: false
        )
        XCTAssertEqual(eatListed.map(\.place.name), ["Fujin"])
        XCTAssertEqual(
            SaveDoodleHomeCatalog.cityDisplayName(for: eatListed[0].place, language: .english),
            "Taipei"
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.nearYouCityID(from: places, location: here),
            "newTaipei"
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.nearYouCityName(from: places, location: here, language: .english),
            "New Taipei"
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.collectedScopePlaces(
                from: places,
                selection: .nearYou,
                location: here,
                locationDenied: false
            ).map(\.name),
            ["Yingge Ceramics"]
        )
        XCTAssertEqual(
            SaveDoodleHomeProgressCatalog.cityPlaces(
                from: places,
                selection: .nearYou,
                location: here,
                locationDenied: false
            ).map(\.name),
            ["Yingge Ceramics"]
        )
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        XCTAssertTrue(home.contains("nearYouCityName"))
        XCTAssertFalse(home.contains("listedPlaces.first"))
    }

    /// Unknown-metro addresses must cluster by locality, not state+ZIP.
    func testFallbackAddressUsesLocalityNotStateZip() {
        let one = place(
            "Chez Panisse",
            "1517 Shattuck Ave, Berkeley, CA 94704, USA",
            .food
        )
        let two = place(
            "Cheese Board",
            "1504 Shattuck Ave, Berkeley, CA 94709, USA",
            .cafe
        )
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: one.address), "Berkeley")
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: two.address), "Berkeley")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: one), "berkeley,ca")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: two), "berkeley,ca")
        XCTAssertNotEqual(SaveDoodleHomeCatalog.cityID(for: one), "ca 94704")
        let groups = SaveDoodleHomeCatalog.cityGroups(from: [one, two])
        XCTAssertEqual(groups.map(\.id), ["berkeley,ca"])
        XCTAssertEqual(groups.first?.count, 2)
        XCTAssertEqual(groups.first?.englishName, "Berkeley")
        XCTAssertEqual(
            SavedPlaceTripRecommender.areaLabel(for: one),
            "CA 94704",
            "share-label fallback stays ZIP; Home must not reuse it"
        )
    }

    /// Canadian (and other) admin/postal lines are not the city.
    func testFallbackAddressUsesLocalityNotCanadianPostcode() {
        let empress = place(
            "Fairmont Empress",
            "123 Main St, Victoria, BC V8W 1P6, Canada",
            .stay
        )
        let other = place(
            "Fisherman's Wharf",
            "1 Dallas Rd, Victoria, BC V8V 0B2, Canada",
            .attraction
        )
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: empress.address), "Victoria")
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: other.address), "Victoria")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: empress), "victoria,bc")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: other), "victoria,bc")
        XCTAssertNotEqual(SaveDoodleHomeCatalog.cityID(for: empress), "bc v8w 1p6")
        let groups = SaveDoodleHomeCatalog.cityGroups(from: [empress, other])
        XCTAssertEqual(groups.map(\.id), ["victoria,bc"])
        XCTAssertEqual(groups.first?.englishName, "Victoria")
    }

    /// Australian `STATE 2000` is admin+postcode, not the city. Victoria the
    /// Canadian city must stay a locality when the country is not Australia.
    func testFallbackAddressUsesLocalityNotAustralianStatePostcode() {
        let sydney = place(
            "Opera House cafe",
            "1 George St, Sydney, NSW 2000, Australia",
            .cafe
        )
        let otherSydney = place(
            "Circular Quay",
            "2 Alfred St, Sydney, NSW 2000, Australia",
            .attraction
        )
        let melbourne = place(
            "Flinders",
            "1 Flinders St, Melbourne, VIC 3000, Australia",
            .food
        )
        let namedState = place(
            "Harbour",
            "1 George St, Sydney, New South Wales, Australia",
            .cafe
        )
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: sydney.address), "Sydney")
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: otherSydney.address), "Sydney")
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: melbourne.address), "Melbourne")
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: namedState.address), "Sydney")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityDisplayName(for: sydney, language: .english), "Sydney")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: sydney), "sydney,nsw")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: otherSydney), "sydney,nsw")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: melbourne), "melbourne,vic")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: namedState), "sydney,nsw")
        XCTAssertNotEqual(SaveDoodleHomeCatalog.cityID(for: sydney), "nsw")
        XCTAssertNotEqual(SaveDoodleHomeCatalog.cityID(for: sydney), "nsw,australia")
        let groups = SaveDoodleHomeCatalog.cityGroups(from: [sydney, otherSydney, melbourne])
        XCTAssertEqual(Set(groups.map(\.id)), Set(["sydney,nsw", "melbourne,vic"]))
        XCTAssertEqual(Set(groups.map(\.englishName)), Set(["Sydney", "Melbourne"]))
        XCTAssertEqual(groups.first { $0.id == "sydney,nsw" }?.count, 2)
        let losAngelesChile = place(
            "Biobío cafe",
            "Los Ángeles, Biobío, Chile",
            .cafe
        )
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: losAngelesChile.address), "Los Ángeles")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: losAngelesChile), "los angeles,chile")
    }

    /// Postcode-first European lines are the city, not the country or ZIP.
    func testFallbackAddressParsesPostcodePrefixedEuropeanLocality() {
        let zurich = place(
            "Bahnhof",
            "Bahnhofstrasse 1, 8001 Zürich, Switzerland",
            .shopping
        )
        let lyon = place(
            "Bouchon",
            "Rue de la République, 69001 Lyon, France",
            .food
        )
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: zurich.address), "Zürich")
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: lyon.address), "Lyon")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityDisplayName(for: zurich, language: .english), "Zürich")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityDisplayName(for: lyon, language: .english), "Lyon")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: zurich), "zurich,switzerland")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: lyon), "lyon,france")
        XCTAssertNotEqual(SaveDoodleHomeCatalog.cityID(for: zurich), "switzerland")
        XCTAssertNotEqual(SaveDoodleHomeCatalog.cityID(for: lyon), "69001 lyon")
    }

    /// Same locality in two US states must not share a city ID.
    func testFallbackCityIDsKeepRegionQualifier() {
        let illinois = place(
            "Cozy Dog",
            "2935 S 6th St, Springfield, IL 62703, USA",
            .food
        )
        let massachusetts = place(
            "Student Prince",
            "8 Fort St, Springfield, MA 01103, USA",
            .food
        )
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: illinois.address), "Springfield")
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: massachusetts.address), "Springfield")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityDisplayName(for: illinois, language: .english), "Springfield")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: illinois), "springfield,il")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: massachusetts), "springfield,ma")
        let groups = SaveDoodleHomeCatalog.cityGroups(from: [illinois, massachusetts])
        XCTAssertEqual(Set(groups.map(\.id)), Set(["springfield,il", "springfield,ma"]))
        XCTAssertEqual(Set(groups.map(\.englishName)), Set(["Springfield"]))
    }

    /// Full state names must parse like `IL` / `MA`.
    func testFallbackLocalityKeepsSpringfieldFromIllinoisName() {
        let illinois = place(
            "Cozy Dog",
            "123 Main St, Springfield, Illinois, United States",
            .food
        )
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: illinois.address), "Springfield")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityDisplayName(for: illinois, language: .english), "Springfield")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: illinois), "springfield,il")
        XCTAssertNotEqual(SaveDoodleHomeCatalog.cityID(for: illinois), "illinois")
    }

    /// Allowlisted `paris` is France, not Paris, TX.
    func testAllowlistedParisDoesNotAbsorbParisTexas() {
        let france = place(
            "Café de Flore",
            "172 Boulevard Saint-Germain, Paris, France",
            .cafe
        )
        let texas = place(
            "Paris Bakery",
            "Paris, TX 75460, USA",
            .food
        )
        XCTAssertEqual(SaveHomeSearch.metroKey(in: france.address), "paris")
        XCTAssertNil(SaveHomeSearch.metroKey(in: texas.address))
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: france), "paris")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: texas), "paris,tx")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityDisplayName(for: texas, language: .english), "Paris")
        XCTAssertNotEqual(
            SaveDoodleHomeCatalog.cityID(for: france),
            SaveDoodleHomeCatalog.cityID(for: texas)
        )
        let groups = SaveDoodleHomeCatalog.cityGroups(from: [france, texas])
        XCTAssertEqual(Set(groups.map(\.id)), Set(["paris", "paris,tx"]))
    }

    /// Province without a country token must not inherit the UK `london` metro.
    func testMetroAliasesRejectNonUSRegionsWithoutCountry() {
        XCTAssertNil(SaveHomeSearch.metroKey(in: "London, Ontario"))
        XCTAssertNil(SaveHomeSearch.metroKey(in: "London, ON"))
        let ontario = place("Covent Garden Market", "130 King St, London, Ontario", .food)
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: ontario.address), "London")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityDisplayName(for: ontario, language: .english), "London")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: ontario), "london,on")
        XCTAssertNotEqual(SaveDoodleHomeCatalog.cityID(for: ontario), "london")
        let uk = place("Borough Market", "8 Southwark St, London, United Kingdom", .food)
        XCTAssertEqual(SaveHomeSearch.metroKey(in: uk.address), "london")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: uk), "london")
        XCTAssertNotEqual(SaveDoodleHomeCatalog.cityID(for: ontario), SaveDoodleHomeCatalog.cityID(for: uk))
        let groups = SaveDoodleHomeCatalog.cityGroups(from: [ontario, uk])
        XCTAssertEqual(Set(groups.map(\.id)), Set(["london,on", "london"]))
    }

    func testMetroAliasesRejectCountriesOutsideTheOriginalAllowlist() {
        for address in ["Los Ángeles, Biobío, Chile", "London, Ontario, Canada", "Paris, Santander, Colombia"] {
            XCTAssertNil(SaveHomeSearch.metroKey(in: address), address)
        }
        XCTAssertEqual(SaveHomeSearch.metroKey(in: "Los Angeles, California, United States"), "losAngeles")
        XCTAssertEqual(SaveHomeSearch.metroKey(in: "Los Angeles, California"), "losAngeles")
        XCTAssertEqual(SaveHomeSearch.metroKey(in: "Tokyo, Shibuya"), "tokyo")
        XCTAssertEqual(SaveHomeSearch.metroKey(in: "Paris, France"), "paris")
        XCTAssertEqual(SaveHomeSearch.metroKey(in: "台北市, 台灣"), "taipei")
    }

    func testMetroGroupingRejectsCityNamesInStreetComponents() {
        for address in ["123 London Road, Manchester, United Kingdom", "London Road, Manchester, United Kingdom", "Rue de Paris, Lyon, France", "香港路, 青島", "香港街, 青島", "香港大道, 青島"] {
            XCTAssertNil(SaveHomeSearch.metroKey(in: address), address)
        }
        let manchester = place("Street alias", "123 London Road, Manchester, United Kingdom", .cafe)
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: manchester), "manchester,united kingdom")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityDisplayName(for: manchester, language: .english), "Manchester")
        for (address, city) in [("10 Downing Street, London SW1A 2AA, UK", "london"), ("東京都渋谷区神南1丁目", "tokyo"), ("106台北市大安區仁愛路", "taipei"), ("北京市东城区天坛东里", "beijing"), ("18 Marina Gardens Dr, Singapore 018953", "singapore"), ("Rue de Rivoli, Paris 75001, France", "paris"), ("香港中環皇后大道中15號", "hongKong"), ("香港九龍尖沙咀", "hongKong")] {
            XCTAssertEqual(SaveHomeSearch.metroKey(in: address), city, address)
        }
    }

    func testTrailingPostcodesDoNotSplitLocalityGroups() {
        let places = ["1 King's Parade, Cambridge CB2 1ST, UK", "2 Trinity Street, Cambridge CB2 1SU, UK"].map {
            place("Cambridge fixture", $0, .cafe)
        }
        XCTAssertEqual(places.map { SaveDoodleHomeCatalog.localityLabel(in: $0.address) }, ["Cambridge", "Cambridge"])
        XCTAssertEqual(places.map { SaveDoodleHomeCatalog.cityID(for: $0) }, ["cambridge,united kingdom", "cambridge,united kingdom"])
        XCTAssertEqual(SaveDoodleHomeCatalog.cityGroups(from: places).first?.count, 2)
    }

    func testCountryAliasesShareCityGroupsAndRestoreExistingSelection() {
        let places = ["UK", "United Kingdom", "England", "Britain", "U.K."].map {
            place("Country alias", "1 King's Parade, Cambridge CB2 1ST, \($0)", .cafe)
        }
        let groups = SaveDoodleHomeCatalog.cityGroups(from: places)
        XCTAssertEqual(groups.map(\.id), ["cambridge,united kingdom"])
        XCTAssertEqual(groups.first?.count, 5)
        XCTAssertEqual(SaveDoodleCitySelection(storageValue: "cambridge,uk"), .city("cambridge,united kingdom"))
        XCTAssertEqual(SaveDoodleCitySelection(storageValue: "springfield,il"), .city("springfield,il"))
        for (alias, country) in [("USA", "united states"), ("US", "united states"), ("United States of America", "united states"), ("Schweiz", "switzerland"), ("Holland", "netherlands"), ("Österreich", "austria")] {
            XCTAssertEqual(SaveHomeSearch.countryToken(in: alias), country, alias)
        }
        XCTAssertNil(SaveHomeSearch.metroKey(in: "London, Holland"))
        XCTAssertEqual(SaveHomeSearch.metroKey(in: "London, U.K."), "london")
        XCTAssertEqual(SaveHomeSearch.metroKey(in: "Los Angeles, USA"), "losAngeles")
        let dutchCity = place("Amsterdam fixture", "Damrak, Amsterdam, Holland", .cafe)
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: dutchCity), "amsterdam,netherlands")
    }

    /// Prefix-through-first-`市` kept province+city (`江蘇省, 蘇州市`) and left
    /// simplified `中国` in the token. Take the municipality only.
    func testCJKLocalityExtractsMunicipalityNotProvincePrefix() {
        XCTAssertEqual(
            SaveDoodleHomeCatalog.localityLabel(in: "中國, 江蘇省, 蘇州市, 姑蘇區"),
            "蘇州市"
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.localityLabel(in: "中国, 江苏省, 苏州市, 姑苏区"),
            "苏州市"
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.localityLabel(in: "江蘇省蘇州市姑蘇區"),
            "蘇州市"
        )
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: "台北市, 台灣"), "台北市")
        let traditional = place("Humble Admin", "中國, 江蘇省, 蘇州市, 姑蘇區", .attraction)
        let compact = place("Garden", "江蘇省蘇州市", .attraction)
        let simplified = place("Pingjiang", "中国, 江苏省, 苏州市, 姑苏区", .attraction)
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: traditional), "蘇州市")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: compact), "蘇州市")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: simplified), "苏州市")
        XCTAssertFalse((SaveDoodleHomeCatalog.cityID(for: traditional) ?? "").contains("省"))
        XCTAssertFalse((SaveDoodleHomeCatalog.cityID(for: simplified) ?? "").contains("中国"))
        XCTAssertEqual(SaveHomeSearch.metroKey(in: "106台北市大安區仁愛路"), "taipei")
    }

    /// Device locale must not rewrite persisted fallback city IDs (`Isparta` / `ısparta`).
    func testFallbackCityIDsUseFixedLocaleForStableNormalization() {
        let turkish = Locale(identifier: "tr_TR")
        let posix = Locale(identifier: "en_US_POSIX")
        XCTAssertEqual("Isparta".lowercased(with: turkish), "ısparta")
        XCTAssertEqual("Isparta".lowercased(with: posix), "isparta")
        XCTAssertEqual(
            "Isparta".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: turkish).lowercased(with: turkish),
            "ısparta"
        )
        XCTAssertEqual(
            "Isparta".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: posix).lowercased(with: posix),
            "isparta"
        )
        let isparta = place("Rose Garden", "Isparta, Turkey", .attraction)
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: isparta.address), "Isparta")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: isparta), "isparta,turkey")
        XCTAssertNotEqual(SaveDoodleHomeCatalog.cityID(for: isparta), "ısparta,turkey")
    }

    /// Every Home city-parsing P2 on this PR, resolved and unresolved.
    func testAddressLocalityTableCoversHomeCityP2Cases() {
        let turkish = Locale(identifier: "tr_TR")
        XCTAssertEqual("India".lowercased(with: turkish), "ındia")
        XCTAssertEqual(SaveAddressLocality.normalizeIdentifier("India"), "india")
        XCTAssertEqual(SaveAddressLocality.country(in: "India"), "india")

        struct Case {
            let address: String
            let label: String?
            let cityID: String?
            let metro: String?
        }
        let cases: [Case] = [
            // Parse fallback addresses into actual cities
            Case(address: "1517 Shattuck Ave, Berkeley, CA 94704, USA", label: "Berkeley", cityID: "berkeley,ca", metro: nil),
            Case(address: "1504 Shattuck Ave, Berkeley, CA 94709, USA", label: "Berkeley", cityID: "berkeley,ca", metro: nil),
            // Strip non-US postcodes
            Case(address: "123 Main St, Victoria, BC V8W 1P6, Canada", label: "Victoria", cityID: "victoria,bc", metro: nil),
            // Parse postcode-prefixed European localities
            Case(address: "Bahnhofstrasse 1, 8001 Zürich, Switzerland", label: "Zürich", cityID: "zurich,switzerland", metro: nil),
            Case(address: "Rue de la République, 69001 Lyon, France", label: "Lyon", cityID: "lyon,france", metro: nil),
            // Disambiguate fallback city IDs by region
            Case(address: "2935 S 6th St, Springfield, IL 62703, USA", label: "Springfield", cityID: "springfield,il", metro: nil),
            Case(address: "8 Fort St, Springfield, MA 01103, USA", label: "Springfield", cityID: "springfield,ma", metro: nil),
            // Recognize full administrative-region names
            Case(address: "123 Main St, Springfield, Illinois, United States", label: "Springfield", cityID: "springfield,il", metro: nil),
            // Qualify allowlisted city IDs by region
            Case(address: "172 Boulevard Saint-Germain, Paris, France", label: "Paris", cityID: "paris", metro: "paris"),
            Case(address: "Paris, TX 75460, USA", label: "Paris", cityID: "paris,tx", metro: nil),
            // Reject metro aliases with unrecognized countries
            Case(address: "Los Ángeles, Biobío, Chile", label: "Los Ángeles", cityID: "los angeles,chile", metro: nil),
            // Restrict metro aliases to locality components
            Case(address: "123 London Road, Manchester, United Kingdom", label: "Manchester", cityID: "manchester,united kingdom", metro: nil),
            Case(address: "10 Downing Street, London SW1A 2AA, UK", label: "London", cityID: "london", metro: "london"),
            // Strip trailing postcodes from locality labels
            Case(address: "1 King's Parade, Cambridge CB2 1ST, UK", label: "Cambridge", cityID: "cambridge,united kingdom", metro: nil),
            Case(address: "2 Trinity Street, Cambridge CB2 1SU, UK", label: "Cambridge", cityID: "cambridge,united kingdom", metro: nil),
            // Canonicalize country aliases in city IDs
            Case(address: "1 King's Parade, Cambridge CB2 1ST, United Kingdom", label: "Cambridge", cityID: "cambridge,united kingdom", metro: nil),
            Case(address: "Damrak, Amsterdam, Holland", label: "Amsterdam", cityID: "amsterdam,netherlands", metro: nil),
            // Handle Australian state and postcode components
            Case(address: "1 George St, Sydney, NSW 2000, Australia", label: "Sydney", cityID: "sydney,nsw", metro: nil),
            Case(address: "1 Flinders St, Melbourne, VIC 3000, Australia", label: "Melbourne", cityID: "melbourne,vic", metro: nil),
            Case(address: "1 George St, Sydney, New South Wales, Australia", label: "Sydney", cityID: "sydney,nsw", metro: nil),
            // Canonicalize full Australian state qualifiers
            Case(address: "Melbourne, Victoria, Australia", label: "Melbourne", cityID: "melbourne,vic", metro: nil),
            // Extract only the CJK locality component
            Case(address: "中國, 江蘇省, 蘇州市, 姑蘇區", label: "蘇州市", cityID: "蘇州市", metro: nil),
            Case(address: "中国, 江苏省, 苏州市, 姑苏区", label: "苏州市", cityID: "苏州市", metro: nil),
            Case(address: "江蘇省蘇州市姑蘇區", label: "蘇州市", cityID: "蘇州市", metro: nil),
            Case(address: "台北市, 台灣", label: "台北市", cityID: "taipei", metro: "taipei"),
            // Reject metro aliases contradicted by non-US regions
            Case(address: "London, Ontario", label: "London", cityID: "london,on", metro: nil),
            Case(address: "130 King St, London, Ontario", label: "London", cityID: "london,on", metro: nil),
            Case(address: "8 Southwark St, London, United Kingdom", label: "London", cityID: "london", metro: "london"),
            // Normalize stable city IDs / country qualifiers with a fixed locale
            Case(address: "Isparta, Turkey", label: "Isparta", cityID: "isparta,turkey", metro: nil),
            Case(address: "Connaught Place, Delhi, India", label: "Delhi", cityID: "delhi,india", metro: nil),
            // Reject contradictory states for US metro aliases
            Case(address: "Los Angeles, TX 78014, USA", label: "Los Angeles", cityID: "los angeles,tx", metro: nil),
            Case(address: "Los Angeles, California, United States", label: "Los Angeles", cityID: "losAngeles", metro: "losAngeles"),
            Case(address: "Los Angeles, CA 90012, USA", label: "Los Angeles", cityID: "losAngeles", metro: "losAngeles"),
            // Preserve the locality after stripping its region
            Case(address: "1600 Pennsylvania Ave NW, Washington, DC 20500, USA", label: "Washington", cityID: "washington,dc", metro: nil),
            // Treat Japanese prefecture suffixes as locality boundaries
            Case(address: "日本神奈川県横浜市中区", label: "横浜市", cityID: "横浜市", metro: nil),
            Case(address: "横浜市中区, 神奈川県, 日本", label: "横浜市", cityID: "横浜市", metro: nil),
            Case(address: "東京都渋谷区神南1丁目", label: "東京都渋谷区神南1丁目", cityID: "tokyo", metro: "tokyo"),
        ]

        for item in cases {
            let resolved = SaveAddressLocality.resolve(item.address)
            XCTAssertEqual(resolved?.label, item.label, item.address)
            XCTAssertEqual(resolved?.cityID, item.cityID, item.address)
            XCTAssertEqual(resolved?.metroKey, item.metro, item.address)
            XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: item.address), item.label, item.address)
            let fixture = place("P2 fixture", item.address, .cafe)
            XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: fixture), item.cityID, item.address)
            XCTAssertEqual(SaveHomeSearch.metroKey(in: item.address), item.metro, item.address)
        }

        XCTAssertEqual(
            SaveDoodleCitySelection(storageValue: "cambridge,uk"),
            .city("cambridge,united kingdom")
        )
        XCTAssertEqual(SaveHomeSearch.countryToken(in: "India"), "india")
        XCTAssertNotEqual(SaveHomeSearch.countryToken(in: "India"), "ındia")
    }

    /// Selected `.city` must not stick after its last save is gone.
    func testResolvedSelectionReplacesCityWhoseLastSaveDisappeared() {
        let berkeley = place(
            "Chez Panisse",
            "1517 Shattuck Ave, Berkeley, CA 94704, USA",
            .food,
            createdAt: Date().addingTimeInterval(-10)
        )
        let tokyo = place(
            "Ichiran",
            "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
            .food,
            createdAt: Date()
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.resolvedSelection(
                .city("berkeley,ca"),
                places: [berkeley],
                locationDenied: false
            ),
            .city("berkeley,ca")
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.resolvedSelection(
                .city("berkeley,ca"),
                places: [tokyo],
                locationDenied: false
            ),
            .nearYou
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.resolvedSelection(
                .city("berkeley,ca"),
                places: [tokyo],
                locationDenied: true
            ),
            .city("tokyo")
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.resolvedSelection(
                .city("berkeley,ca"),
                places: [],
                locationDenied: false
            ),
            .nearYou
        )
        let edited = place(
            "Chez Panisse",
            "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
            .food
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.resolvedSelection(
                .city("berkeley,ca"),
                places: [edited],
                locationDenied: false
            ),
            .nearYou
        )
        XCTAssertTrue(
            SaveDoodleHomeCatalog.visiblePlaces(
                from: [tokyo],
                lens: .eat,
                selection: .city("berkeley,ca"),
                location: nil,
                locationDenied: true
            ).map(\.name) == ["Ichiran"]
        )
    }

    func testCachedLocationFreshnessExpiresBeforeNearYouFilter() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 39.88, longitude: 116.40),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-60)
        )
        let stale = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.24),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-SaveLocationFreshness.maxAge - 1)
        )
        XCTAssertFalse(SaveLocationFreshness.shouldRefresh(cached: fresh, at: now))
        XCTAssertTrue(SaveLocationFreshness.shouldRefresh(cached: stale, at: now))
        XCTAssertTrue(SaveLocationFreshness.shouldRefresh(cached: nil, at: now))
    }

    func testFallbackCityGroupingRecognizesCountriesOutsideMetroCatalogue() {
        let addresses = [
            "Santiago, Chile", "Valparaíso, Chile", "Bogotá, Colombia", "Medellín, Colombia",
            "Los Ángeles, Biobío, Chile", "Concepción, Biobío, Chile",
            "Calle 5, Los Ángeles, Biobío, Chile", "Paris, Santander, Colombia",
            "Rue de la République, Lyon, France", "Bahnhofstrasse 1, Zürich, Switzerland",
            "Damrak, Amsterdam, Netherlands", "La Rambla, Barcelona, Spain",
            "12 Damrak, Amsterdam, Netherlands", "Calle Mayor, Santander, Spain",
        ]
        let expectedIDs = [
            "santiago,chile", "valparaiso,chile", "bogota,colombia", "medellin,colombia",
            "los angeles,chile", "concepcion,chile", "los angeles,chile", "paris,colombia",
            "lyon,france", "zurich,switzerland",
            "amsterdam,netherlands", "barcelona,spain", "amsterdam,netherlands", "santander,spain",
        ]
        let expectedNames = [
            "Santiago", "Valparaíso", "Bogotá", "Medellín", "Los Ángeles", "Concepción",
            "Los Ángeles", "Paris", "Lyon", "Zürich", "Amsterdam", "Barcelona", "Amsterdam", "Santander",
        ]
        let places = addresses.map { address in
            place("City fixture", address, .cafe)
        }
        for (index, place) in places.enumerated() {
            XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: place), expectedIDs[index])
            XCTAssertEqual(SaveDoodleHomeCatalog.cityDisplayName(for: place, language: .english), expectedNames[index])
        }
        XCTAssertEqual(Set(SaveDoodleHomeCatalog.cityGroups(from: places).map(\.id)), Set(expectedIDs))
    }

    func testPassportCollectionModePreservesRootProgressAndOnlyScopesCollected() {
        let places = ReviewDemoSeed.doodleParityPlaces(now: Date(timeIntervalSince1970: 1_760_000_000))
        let full = SavePassportCollectionMode.collection.places(
            from: places, selection: .city("nonexistent"), location: nil, locationDenied: true
        )
        XCTAssertEqual(full.map(\.id), places.map(\.id), "Root and ordinary sheets ignore Home's city")
        let fourUnvisited = Array(places.prefix(4)).map { original in
            var place = original
            place.status = .wantToGo
            return place
        }
        let rootProgress = SavePassportCollectionMode.collection.progress(in: fourUnvisited)
        XCTAssertEqual(rootProgress.completed, 4)
        XCTAssertEqual(rootProgress.total, 12)
        let collected = SavePassportCollectionMode.homeCollected.places(
            from: places, selection: .nearYou, location: tiantanFix, locationDenied: false
        )
        let cityProgress = SavePassportCollectionMode.homeCollected.progress(in: collected)
        XCTAssertEqual(cityProgress.completed, 4)
        XCTAssertEqual(cityProgress.total, 12)
        XCTAssertTrue(SavePassportCollectionMode.homeCollected.places(
            from: places, selection: .city("nonexistent"), location: nil, locationDenied: true
        ).isEmpty, "An empty city must never fall back to unrelated stamps")
    }

    /// Closest pin without an address must not empty Near you / Collected.
    func testNearYouCitySkipsAddresslessClosestSave() {
        let here = CLLocation(latitude: 37.8796, longitude: -122.2697)
        let pin = place(
            "Coordinate only",
            "",
            .food,
            latitude: 37.8797,
            longitude: -122.2697
        )
        let berkeley = place(
            "Chez Panisse",
            "1517 Shattuck Ave, Berkeley, CA 94704, USA",
            .food,
            latitude: 37.8795,
            longitude: -122.2689
        )
        XCTAssertNil(SaveDoodleHomeCatalog.cityID(for: pin))
        XCTAssertEqual(
            SaveDoodleHomeCatalog.nearYouCityID(from: [pin, berkeley], location: here),
            "berkeley,ca"
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.collectedScopePlaces(
                from: [pin, berkeley],
                selection: .nearYou,
                location: here,
                locationDenied: false
            ).map(\.name),
            ["Chez Panisse"]
        )
    }

    /// Antimeridian neighbors must not fit as a world-scale mini-map.
    func testMiniMapFitsLongitudesAcrossTheDateLine() {
        let region = SaveDoodleMiniMap.region(fitting: [
            CLLocationCoordinate2D(latitude: 51.48, longitude: 179.99),
            CLLocationCoordinate2D(latitude: 51.48, longitude: -179.99),
        ])
        XCTAssertLessThan(region.span.longitudeDelta, 5)
        XCTAssertGreaterThan(abs(region.center.longitude), 170)
    }

    func testNearYouKeepsOnlyWalkingDistance() {
        let here = CLLocation(latitude: 39.882, longitude: 116.407)
        let near = place("Duck", "Beijing, China", .food, latitude: 39.883, longitude: 116.408)
        let far = place("Noodles", "Beijing, China", .food, latitude: 40.01, longitude: 116.50)
        let visible = SaveDoodleHomeCatalog.visiblePlaces(
            from: [near, far],
            lens: .eat,
            selection: .nearYou,
            location: here,
            locationDenied: false
        )
        XCTAssertEqual(visible.map(\.name), ["Duck"])
        XCTAssertTrue(
            SaveDoodleHomeCatalog.isNearbyEmpty(
                places: [far],
                lens: .eat,
                selection: .nearYou,
                location: here,
                locationDenied: false
            )
        )
    }

    func testLocationDeniedFallsBackToNewestSaveCity() {
        let older = place(
            "Ichiran",
            "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
            .food,
            createdAt: Date().addingTimeInterval(-100)
        )
        let newer = place(
            "Fujin",
            "No. 353, Section 1, Fuxing S Rd, Da'an District, Taipei",
            .cafe,
            createdAt: Date()
        )
        let resolved = SaveDoodleHomeCatalog.resolvedSelection(
            .nearYou,
            places: [older, newer],
            locationDenied: true
        )
        XCTAssertEqual(resolved, .city("taipei"))
        let visible = SaveDoodleHomeCatalog.visiblePlaces(
            from: [older, newer],
            lens: .eat,
            selection: .nearYou,
            location: nil,
            locationDenied: true
        )
        XCTAssertEqual(visible.map(\.name), ["Fujin"])
    }

    /// Denied Near you skips a newest save with no locality.
    func testLocationDeniedFallsBackToNewestResolvableCity() {
        let older = place(
            "Fujin",
            "No. 353, Section 1, Fuxing S Rd, Da'an District, Taipei",
            .cafe,
            createdAt: Date().addingTimeInterval(-100)
        )
        let newer = place(
            "Pin drop",
            "",
            .attraction,
            createdAt: Date()
        )
        let resolved = SaveDoodleHomeCatalog.resolvedSelection(
            .nearYou,
            places: [older, newer],
            locationDenied: true
        )
        XCTAssertEqual(resolved, .city("taipei"))
        let collected = SaveDoodleHomeCatalog.collectedScopePlaces(
            from: [older, newer],
            selection: .nearYou,
            location: nil,
            locationDenied: true
        )
        XCTAssertEqual(collected.map(\.name), ["Fujin"])
    }

    /// “Latest save” is recency, even when an older place is closer.
    func testLatestSaveJumpUsesRecencyNotDistance() {
        let here = CLLocation(latitude: 25.0330, longitude: 121.5654)
        let olderNear = place(
            "Close old",
            "Taipei, Taiwan",
            .food,
            latitude: 25.0331,
            longitude: 121.5655,
            createdAt: Date().addingTimeInterval(-1_000)
        )
        let newerFar = place(
            "Far new",
            "Tokyo, Japan",
            .food,
            latitude: 35.66,
            longitude: 139.70,
            createdAt: Date()
        )
        let listed = [olderNear]
        let latest = SaveDoodleHomeCatalog.nearestOtherSave(
            in: [olderNear, newerFar],
            excluding: listed,
            location: here
        )
        XCTAssertEqual(latest?.place.name, "Far new")
        XCTAssertNotNil(latest?.distance)
    }

    func testDistanceTextAndCollectedProgress() {
        XCTAssertEqual(SaveDoodleHomeCatalog.distanceText(450), "450m")
        XCTAssertEqual(SaveDoodleHomeCatalog.distanceText(1100), "1.1km")
        let visited = place("Duck", "Beijing, China", .food, status: .visited)
        let saved = place("Cafe", "Beijing, China", .cafe)
        let progress = SaveDoodleHomeCatalog.collectedProgress(in: [visited, saved])
        XCTAssertEqual(progress.visited, 1)
        XCTAssertEqual(progress.saved, 2)
        XCTAssertEqual(progress.goal, 2)
        XCTAssertEqual(SaveDoodleHomeCatalog.collectedStamps(in: [visited, saved]).map(\.name), ["Duck"])
    }

    func testNearYouWithoutLocationDoesNotReturnWorldwidePlaces() {
        let beijing = place("Duck", "Beijing, China", .food)
        let tokyo = place(
            "Ichiran",
            "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
            .food
        )
        let visible = SaveDoodleHomeCatalog.visiblePlaces(
            from: [beijing, tokyo],
            lens: .eat,
            selection: .nearYou,
            location: nil,
            locationDenied: false
        )
        XCTAssertTrue(visible.isEmpty)
        XCTAssertTrue(
            SaveDoodleHomeCatalog.collectedScopePlaces(
                from: [beijing, tokyo],
                selection: .nearYou,
                location: nil,
                locationDenied: false
            ).isEmpty
        )
    }

    /// T1: city A has 12 saves and 4 visited across Eat and Go. Home reads
    /// Collected 4/12 while the Eat list still shows three nearby rows.
    func testT1HomeCollectedFourOfTwelveWithThreeEatRows() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let places = ReviewDemoSeed.doodleParityPlaces(now: now)
        XCTAssertTrue(
            places.allSatisfy(\.hasValidCoordinate),
            "0,0 extras are dropped by SaveMemoryRecord.confirmedPlace"
        )
        let listed = SaveDoodleHomeCatalog.listedPlaces(
            from: places,
            lens: .eat,
            selection: .nearYou,
            location: tiantanFix,
            locationDenied: false
        )
        XCTAssertEqual(listed.count, 3)
        XCTAssertEqual(
            listed.map(\.place.name),
            ["Siji Minfu Roast Duck", "Fangzhuangchang Noodles", "Grey Cafe"]
        )
        let scope = SaveDoodleHomeCatalog.collectedScopePlaces(
            from: places,
            selection: .nearYou,
            location: tiantanFix,
            locationDenied: false
        )
        let count = SaveDoodleHomeCatalog.cityCollectedCount(in: scope)
        XCTAssertEqual(count.visited, 4)
        XCTAssertEqual(count.saved, 12)
        XCTAssertEqual(
            SaveDoodleHomeCatalog.collectedProgress(in: scope).goal,
            count.saved
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.cityDisplayName(for: listed[0].place, language: .english),
            "Tiantan"
        )
    }

    /// T2: switching Eat → Go must not change Collected X/Y.
    func testT2HomeCollectedUnchangedWhenSwitchingToGo() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let places = ReviewDemoSeed.doodleParityPlaces(now: now)
        let eat = SaveDoodleHomeCatalog.cityCollectedCount(
            in: SaveDoodleHomeCatalog.collectedScopePlaces(
                from: places,
                selection: .nearYou,
                location: tiantanFix,
                locationDenied: false
            )
        )
        let goListed = SaveDoodleHomeCatalog.listedPlaces(
            from: places,
            lens: .go,
            selection: .nearYou,
            location: tiantanFix,
            locationDenied: false
        )
        let go = SaveDoodleHomeCatalog.cityCollectedCount(
            in: SaveDoodleHomeCatalog.collectedScopePlaces(
                from: places,
                selection: .nearYou,
                location: tiantanFix,
                locationDenied: false
            )
        )
        XCTAssertNotEqual(goListed.count, 12)
        XCTAssertEqual(eat.visited, 4)
        XCTAssertEqual(eat.saved, 12)
        XCTAssertEqual(go.visited, eat.visited)
        XCTAssertEqual(go.saved, eat.saved)
    }

    /// T3: the production "I've been here" / Mark visited path increments
    /// X and leaves Y at 12. Do not mutate fixture `status` directly.
    func testT3HomeCollectedIncreasesAfterMarkVisited() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let suite = "save.doodle.t3.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SaveDoodleVisitStore(defaults: defaults)
        var places = ReviewDemoSeed.doodleParityPlaces(now: now)
        let greyIndex = places.firstIndex { $0.name == "Grey Cafe" }!
        XCTAssertEqual(places[greyIndex].status, .wantToGo)
        places[greyIndex] = store.markIveBeenHere(places[greyIndex])
        XCTAssertEqual(places[greyIndex].status, .visited)
        XCTAssertEqual(store.count(for: places[greyIndex].id), 1)
        let count = SaveDoodleHomeCatalog.cityCollectedCount(
            in: SaveDoodleHomeCatalog.collectedScopePlaces(
                from: places,
                selection: .nearYou,
                location: tiantanFix,
                locationDenied: false
            )
        )
        XCTAssertEqual(count.visited, 5)
        XCTAssertEqual(count.saved, 12)
    }

    /// T4: switching to city B (3 saved, 1 visited) reads 1/3, not a
    /// hardcoded passport-goal 12.
    func testT4HomeCollectedFollowsCitySwitch() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let cityA = ReviewDemoSeed.doodleParityPlaces(now: now)
        let tokyo = "1-22-7 Jinnan, Shibuya City, Tokyo, Japan"
        let cityB = [
            place("Ichiran", tokyo, .food, status: .visited, createdAt: now),
            place("Hotel", tokyo, .stay, createdAt: now.addingTimeInterval(-1)),
            place("Shop", tokyo, .shopping, createdAt: now.addingTimeInterval(-2)),
        ]
        let all = cityA + cityB
        let tiantan = SaveDoodleHomeCatalog.cityCollectedCount(
            in: SaveDoodleHomeCatalog.collectedScopePlaces(
                from: all,
                selection: .nearYou,
                location: tiantanFix,
                locationDenied: false
            )
        )
        XCTAssertEqual(tiantan.visited, 4)
        XCTAssertEqual(tiantan.saved, 12)
        let tokyoCount = SaveDoodleHomeCatalog.cityCollectedCount(
            in: SaveDoodleHomeCatalog.collectedScopePlaces(
                from: all,
                selection: .city("tokyo"),
                location: nil,
                locationDenied: true
            )
        )
        XCTAssertEqual(tokyoCount.visited, 1)
        XCTAssertEqual(tokyoCount.saved, 3)
        XCTAssertEqual(
            SaveDoodleHomeCatalog.collectedProgress(in: cityB).goal,
            tokyoCount.saved
        )
    }

    /// City has saves, current Eat/Go list is empty: keep Collected X/Y
    /// and show a filter-empty message instead of the whole empty Home.
    func testHomeCollectedStaysVisibleWhenLensHasNoRows() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let eatOnly = [
            place("Duck", "Beijing, China", .food, status: .visited, createdAt: now),
            place("Grey", "Beijing, China", .cafe, createdAt: now.addingTimeInterval(-1)),
        ]
        let goListed = SaveDoodleHomeCatalog.listedPlaces(
            from: eatOnly,
            lens: .go,
            selection: .city("beijing"),
            location: nil,
            locationDenied: true
        )
        let scope = SaveDoodleHomeCatalog.collectedScopePlaces(
            from: eatOnly,
            selection: .city("beijing"),
            location: nil,
            locationDenied: true
        )
        let count = SaveDoodleHomeCatalog.cityCollectedCount(in: scope)
        XCTAssertTrue(goListed.isEmpty)
        XCTAssertEqual(count.visited, 1)
        XCTAssertEqual(count.saved, 2)
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        XCTAssertTrue(home.contains("showsLensEmpty"))
        XCTAssertTrue(home.contains("home.lensEmpty"))
        XCTAssertTrue(home.contains("No \\(lens) saves here"))
        let bodyAt = try XCTUnwrap(home.range(of: "var body: some View"))
        let headerAt = try XCTUnwrap(home.range(of: "private var savesButton"))
        let body = home[bodyAt.lowerBound..<headerAt.lowerBound]
        XCTAssertTrue(body.contains("if showsLensEmpty"))
        XCTAssertTrue(body.contains("else if !showsEmptyHome"))
        XCTAssertTrue(body.contains("if !collectedPlaces.isEmpty"))
        let lensAt = try XCTUnwrap(body.range(of: "if showsLensEmpty"))
        let collectedAt = try XCTUnwrap(body.range(of: "if !collectedPlaces.isEmpty"))
        XCTAssertLessThan(
            lensAt.lowerBound,
            collectedAt.lowerBound,
            "Collected must stay after the Eat/Go empty branch, not inside it"
        )
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("keep the Collected strip and show a filter-empty message"))
        // DESIGN wraps "the nearest / save across every category".
        XCTAssertTrue(design.contains("save across every category"))
        XCTAssertTrue(design.contains("not the nearest Eat/Go row"))
        XCTAssertTrue(design.contains("locality (Berkeley)"))
    }

    /// T5: a city with no saves hides the strip (or would be 0/0) and
    /// does not crash.
    func testT5HomeCollectedHiddenWhenCityHasNoSaves() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let places = ReviewDemoSeed.doodleParityPlaces(now: now)
        let scope = SaveDoodleHomeCatalog.collectedScopePlaces(
            from: places,
            selection: .city("osaka"),
            location: nil,
            locationDenied: true
        )
        XCTAssertTrue(scope.isEmpty)
        let count = SaveDoodleHomeCatalog.cityCollectedCount(in: scope)
        XCTAssertEqual(count.visited, 0)
        XCTAssertEqual(count.saved, 0)
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        XCTAssertTrue(home.contains("if !collectedPlaces.isEmpty"))
        XCTAssertTrue(home.contains("collectedStrip"))
    }

    /// T6: the Collected strip opens the real Passport screen with the
    /// same city numbers. `SaveDoodleHomeProgressCatalog` is the Home X/Y
    /// type; PR #295 keeps `SaveDoodlePassportCatalog` for stamp-grid layout.
    func testT6HomeCollectedOpensPassportWithSameCount() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let places = ReviewDemoSeed.doodleParityPlaces(now: now)
        let homeScope = SaveDoodleHomeCatalog.collectedScopePlaces(
            from: places,
            selection: .nearYou,
            location: tiantanFix,
            locationDenied: false
        )
        let homeCount = SaveDoodleHomeCatalog.cityCollectedCount(in: homeScope)
        let passportPlaces = SaveDoodleHomeProgressCatalog.cityPlaces(
            from: places,
            selection: .nearYou,
            location: tiantanFix,
            locationDenied: false
        )
        XCTAssertEqual(homeCount.visited, 4)
        XCTAssertEqual(homeCount.saved, 12)
        XCTAssertEqual(SaveDoodleHomeProgressCatalog.visitedCount(in: passportPlaces), homeCount.visited)
        XCTAssertEqual(passportPlaces.count, homeCount.saved)
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        let strip = try XCTUnwrap(home.range(of: "private var collectedStrip"))
        let empty = try XCTUnwrap(home.range(of: "private var emptyHome"))
        XCTAssertTrue(home[strip.lowerBound..<empty.lowerBound].contains("onOpenCollectedPassport"))
        XCTAssertTrue(home.contains("Collected \\(progress.visited)/\\(progress.saved)"))
        let catalog = try source(at: "SAV-E/Services/SaveDoodleHomeCatalog.swift")
        XCTAssertTrue(catalog.contains("enum SaveDoodleHomeProgressCatalog"))
        XCTAssertFalse(catalog.contains("enum SaveDoodlePassportCatalog"))
        XCTAssertTrue(catalog.contains("collectedScopePlaces"))
        XCTAssertTrue(catalog.contains("PR #295 already owns"))
        let profile = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        XCTAssertTrue(profile.contains("collectionMode.places("))
        let content = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(content.contains("onOpenCollectedPassport: { openPassport(collectionMode: .homeCollected) }"))
        XCTAssertTrue(content.contains("openPassport(collectionMode: .collection)"))
        XCTAssertTrue(profile.contains("PassportTileTownCollection(places: cityStampPlaces"))
        XCTAssertTrue(profile.contains("accessibilityIdentifier(\"profile.stampProgress\")"))
        XCTAssertTrue(profile.contains("localSavedPlaces.isEmpty ? savedPlaces : localSavedPlaces"))
        XCTAssertTrue(profile.contains("collectionProgress.completed)/\\(collectionProgress.total)"))
        XCTAssertTrue(profile.contains("profile.stampProgress"))
        XCTAssertTrue(
            profile.contains("""
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("profile.stampGrid")
            """),
            "stampGrid without contain overwrites child stampProgress (AX: 4/12 becomes profile.stampGrid)"
        )
        XCTAssertFalse(
            profile.contains("accessibilityAddTraits(.isStaticText)"),
            "combine+traits on the progress HStack still lose to a flattening stampGrid parent"
        )
        XCTAssertTrue(profile.contains("try await onUpdatePlace(updated)"))
        XCTAssertTrue(profile.contains("SaveDoodleVisitStore().recordVisit"))
        XCTAssertFalse(profile.contains("markIveBeenHere(place)"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("func testHomeCollectedOpensPassportWithCityCount"))
        XCTAssertTrue(rail.contains("func testSavesTripsBackReturnsToSaves"))
        XCTAssertTrue(rail.contains("home.collected"))
        XCTAssertTrue(rail.contains("profile.stampProgress"))
        XCTAssertTrue(rail.contains("--uitest-doodle-parity-fixture"))
    }

    func testSessionDefaultsToEatAndNearYou() {
        let suite = "save.doodle.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let session = SaveDoodleSession(defaults: defaults)
        XCTAssertEqual(session.lens, .eat)
        XCTAssertEqual(session.city, .nearYou)
        XCTAssertFalse(session.mapFollowsHomeFilter)
        XCTAssertFalse(session.pendingMiniMapHandoff)
        session.lens = .go
        session.city = .city("tokyo")
        session.mapFollowsHomeFilter = true
        let restored = SaveDoodleSession(defaults: defaults)
        XCTAssertEqual(restored.lens, .go)
        XCTAssertEqual(restored.city, .city("tokyo"))
        XCTAssertTrue(restored.mapFollowsHomeFilter)
        XCTAssertFalse(restored.pendingMiniMapHandoff)
    }

    func testProductionHomeIsDoodleNotTileTown() throws {
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(root.contains("SaveDoodleHomeView("))
        XCTAssertTrue(root.contains("onOpenMap: onOpenMap"))
        XCTAssertFalse(root.contains("SaveTileTownHomeView()"))
        XCTAssertTrue(home.contains("home.miniMap"))
        XCTAssertTrue(home.contains("home.citySwitcher"))
        XCTAssertTrue(home.contains("nearYouCityName"))
        XCTAssertFalse(home.contains("listedPlaces.first"))
        XCTAssertTrue(home.contains("eatGoRow"))
        XCTAssertTrue(home.contains("fixedSize(horizontal: true, vertical: false)"))
        let headerAt = try XCTUnwrap(home.range(of: "private var header"))
        let eatRowAt = try XCTUnwrap(home.range(of: "private var eatGoRow"))
        XCTAssertTrue(home[headerAt.lowerBound..<eatRowAt.lowerBound].contains("eatGoRow"))
        let cluesAt = try XCTUnwrap(home.range(of: "cluesLine"))
        let mapAt = try XCTUnwrap(home.range(of: "miniMap"))
        let rowsAt = try XCTUnwrap(home.range(of: "placeList"))
        let collectedAt = try XCTUnwrap(home.range(of: "collectedStrip"))
        XCTAssertLessThan(cluesAt.lowerBound, mapAt.lowerBound)
        XCTAssertLessThan(mapAt.lowerBound, rowsAt.lowerBound)
        XCTAssertLessThan(rowsAt.lowerBound, collectedAt.lowerBound)
        XCTAssertTrue(home.contains("home.passport"))
        XCTAssertFalse(home.contains("accessibilityIdentifier(\"root.passport\")"))
        XCTAssertTrue(home.contains("lens.accessibilityIdentifier"))
        XCTAssertTrue(home.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(home.contains("accessibilityElement(children: .contain)"))
        XCTAssertTrue(home.contains(".accessibilityIdentifier(\"home.savedPlaces\")"))
        let catalog = try source(at: "SAV-E/Services/SaveDoodleHomeCatalog.swift")
        XCTAssertTrue(catalog.contains("home.\\(rawValue)"))
        XCTAssertTrue(catalog.contains("case eat"))
        XCTAssertTrue(catalog.contains("case go"))
        XCTAssertTrue(catalog.contains("var accessibilityIdentifier: String { \"home.\\(rawValue)\" }"))
        XCTAssertTrue(home.contains("home.collected"))
        XCTAssertTrue(home.contains("collectedScopePlaces"))
        XCTAssertTrue(home.contains("if !collectedPlaces.isEmpty"))
        XCTAssertTrue(home.contains("showsLensEmpty"))
        XCTAssertTrue(home.contains("home.lensEmpty"))
        XCTAssertTrue(home.contains("home.empty.capture"))
        XCTAssertTrue(home.contains("home.review"))
        let cluesFn = try XCTUnwrap(home.range(of: "private var cluesLine"))
        let locationFn = try XCTUnwrap(home.range(of: "private var locationPrompt"))
        let cluesBody = home[cluesFn.lowerBound..<locationFn.lowerBound]
        XCTAssertTrue(cluesBody.contains("minHeight: SaveLayout.minTap"))
        XCTAssertTrue(cluesBody.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(home.contains("accessibilityIdentifier(\"home.saves\")"))
        XCTAssertFalse(home.contains("home.openSaves"))
        XCTAssertFalse(home.contains("showsUITestSavesRoute"))
        XCTAssertFalse(home.contains("hiddenSavesRoute"))
        XCTAssertTrue(home.contains("SaveLayout.minTap"))
        XCTAssertTrue(home.contains("\"home.saves\""))
        XCTAssertFalse(home.contains("See all saves"))
        XCTAssertFalse(home.contains("看全部收藏"))
        XCTAssertTrue(home.contains("presentation.reviewCount > 0"))
        let factory = try source(at: "SAV-E/Views/Atlas/SaveAtlasProductionBridge.swift")
        XCTAssertFalse(factory.contains("presentation.reviewCount = mapViewModel.reviewCandidates.count"))
        XCTAssertFalse(home.contains("accessibilityIdentifier(\"home.trips\")"))
        XCTAssertTrue(home.contains("SaveDisplayTitle("))
        XCTAssertTrue(home.contains("text: \"Savvy\""))
        XCTAssertTrue(home.contains("pointSize: 34"))
        XCTAssertTrue(home.contains("locksPointSize: true"))
        XCTAssertTrue(home.contains("pointSize: 20"))
        XCTAssertTrue(home.contains(".frame(height: 2)"))
        XCTAssertTrue(home.contains("height: SaveLayout.chipHeight"))
        XCTAssertFalse(home.contains("minWidth: SaveLayout.minTap, height:"))
        XCTAssertTrue(home.contains(".frame(height: 160)"))
        XCTAssertTrue(home.contains("SaveLayout.screenMargin"))
        XCTAssertTrue(home.contains("SaveLayout.stickerBox"))
        XCTAssertTrue(home.contains("SaveLayout.stickerArt"))
        XCTAssertTrue(home.contains("SaveLayout.rowMinHeight"))
        XCTAssertTrue(home.contains("SaveDoodleOfficialSticker"))
        XCTAssertTrue(home.contains("DoodleSticker"))
        XCTAssertFalse(home.contains("SaveDoodleStickerShape"))
        XCTAssertFalse(home.contains("SaveDoodleElephantShape"))
        for name in ["Duck", "Noodle", "Coffee", "Temple", "Lantern", "Elephant"] {
            for suffix in ["Color", "Color48", "Outline"] {
                XCTAssertTrue(
                    FileManager.default.fileExists(
                        atPath: repositoryRoot.appendingPathComponent(
                            "SAV-E/Resources/Assets.xcassets/DoodleSticker\(name)\(suffix).imageset/Contents.json"
                        ).path
                    ),
                    "Missing official sticker imageset DoodleSticker\(name)\(suffix)"
                )
            }
        }
        XCTAssertTrue(home.contains(".frame(height: 44)"))
        XCTAssertTrue(home.contains("SaveDoodle.stampRed"))
        XCTAssertTrue(home.contains("AtlasTabBarMetrics.height"))
        XCTAssertFalse(home.contains("rootTabScrollClearance"))
        XCTAssertTrue(home.contains(".mapStyle(.standard(emphasis: .automatic))"))
        XCTAssertTrue(home.contains("Annotation("))
        XCTAssertTrue(home.contains("SaveDoodleNumberPin("))
        XCTAssertTrue(home.contains("SaveDoodle.stampRed"))
        XCTAssertTrue(home.contains("SaveAtlasPalette.coral"))
        XCTAssertTrue(home.contains("interactionModes: []"))
        XCTAssertFalse(home.contains("SaveTileTownCanvas"))
        XCTAssertFalse(home.contains("home.search"))
        XCTAssertFalse(home.contains("home.tileTown"))
        XCTAssertFalse(home.contains("map.lens.nearby"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "SAV-E/Views/TileTown/SaveTileTownHomeView.swift"
            ).path
        ))
        let design = try source(at: "DESIGN.md")
        XCTAssertTrue(design.contains("Savvy + Eat/Go in the header"))
        XCTAssertTrue(design.contains("official DESIGN color die-cut"))
        XCTAssertTrue(design.contains("removed the original elephant artwork"))
        XCTAssertTrue(design.contains("Codex packet and spec §8"))
        XCTAssertTrue(design.contains("0.90 visual-parity score is not evidence"))
        XCTAssertTrue(home.contains("placeCases"))
        XCTAssertFalse(home.contains("SaveDoodleElephant"), "Home no longer displays the retired elephant artwork")
        XCTAssertTrue(home.contains("SaveDoodleEmptyPlate"))
        XCTAssertTrue(design.contains("then the city, clues"))
        XCTAssertTrue(design.contains("eade369"))
        XCTAssertFalse(design.contains("home-mask.png"))
        XCTAssertTrue(design.contains("judged manually by DESIGN"))
        XCTAssertTrue(design.contains("v1 is retired"))
        XCTAssertFalse(design.contains("23cca55"))
        XCTAssertTrue(design.contains("像素小鎮已經不要了"))
        XCTAssertTrue(design.contains("tile-town is abandoned"))
        XCTAssertFalse(design.contains("Home hero and Map become a full-pixel isometric"))
        let bridge = try source(at: "SAV-E/Views/Atlas/SaveAtlasProductionBridge.swift")
        XCTAssertTrue(bridge.contains("Home is `SaveDoodleHomeView`"))
        XCTAssertFalse(bridge.contains("Live Home uses the tile-town peek"))
        let readme = try source(at: "Prototypes/AtlasPostcard/README.md")
        XCTAssertTrue(readme.contains("home-light.png"))
        XCTAssertTrue(readme.contains("eade369"))
        XCTAssertFalse(readme.contains("home-mask.png"))
        XCTAssertTrue(readme.contains("unmasked"))
        XCTAssertTrue(readme.contains("position"))
        XCTAssertFalse(readme.contains("23cca55"))
        XCTAssertFalse(readme.contains("layout boxes"))
        XCTAssertTrue(readme.contains("0.90"))
        XCTAssertTrue(readme.contains("402×874") || readme.contains("402 x 874") || readme.contains("402 × 874"))
        XCTAssertFalse(readme.contains("padded with paper"))
        XCTAssertFalse(readme.contains("nearest-neighbor tile-town peek"))
        let homeTarget = repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/home.png"
        )
        let homePNG = try Data(contentsOf: homeTarget)
        XCTAssertEqual([UInt8](homePNG.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(pngDimension(homePNG, at: 16), 402)
        XCTAssertEqual(pngDimension(homePNG, at: 20), 874)
        let homeDarkPNG = try Data(contentsOf: repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/home-dark.png"
        ))
        XCTAssertEqual(pngDimension(homeDarkPNG, at: 16), 402)
        XCTAssertEqual(pngDimension(homeDarkPNG, at: 20), 874)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "Prototypes/AtlasPostcard/Reference/ProductionTargets/home-mask.png"
            ).path
        ))
        let parity = try source(at: "Prototypes/AtlasPostcard/Scripts/VisualParity.swift")
        XCTAssertTrue(parity.contains("--mask"))
        XCTAssertTrue(parity.contains("white = ignore"))
        XCTAssertTrue(parity.contains("\"position\""))
        XCTAssertTrue(parity.contains("\"fontStyle\""))
        let parityRunner = try source(at: "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh")
        XCTAssertFalse(parityRunner.contains("home-mask.png"))
        XCTAssertFalse(parityRunner.contains("--mask"))
        XCTAssertTrue(parityRunner.contains("compare_args"))
        XCTAssertFalse(parityRunner.contains("mask_args"))
        let mapPNG = try Data(contentsOf: repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/map.png"
        ))
        XCTAssertEqual(pngDimension(mapPNG, at: 16), 402)
        XCTAssertEqual(pngDimension(mapPNG, at: 20), 874)
        XCTAssertTrue(root.contains("SaveDoodleHomeView("))
        XCTAssertFalse(root.contains("HomeAtlasScreen()"))
        XCTAssertTrue(root.contains("saves.trips"))
        XCTAssertTrue(root.contains("Trips ›"))
        XCTAssertTrue(root.contains("onOpenTrips"))
        XCTAssertTrue(design.contains("HoP acceptance H-6"))
        XCTAssertTrue(root.contains("accessibilityElement(children: .ignore)"))
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("app.buttons[\"saves.trips\"]"))
        XCTAssertTrue(rail.contains("home.passport"))
        XCTAssertTrue(rail.contains("home.locationPrompt"))
        XCTAssertTrue(rail.contains("home.locationAllow"))
        XCTAssertTrue(rail.contains("home.collected"))
        XCTAssertTrue(rail.contains("func testHomeCollectedOpensPassportWithCityCount"))
        XCTAssertTrue(rail.contains("func testSavesTripsBackReturnsToSaves"))
        XCTAssertTrue(rail.contains("--uitest-doodle-parity-fixture"))
        let chrome = try source(at: "SAV-E/App/SaveChromePresentation.swift")
        XCTAssertTrue(chrome.contains("path.contains(.saves) ? [.saves, .trips] : [.trips]"))
        let attach = try source(at: "Tests/SAVEUITests/SAVEUITestCase.swift")
        XCTAssertTrue(attach.contains("SAVE_SCREENSHOT_DIR"))
        XCTAssertTrue(attach.contains("pngRepresentation"))
        let workflow = try source(at: ".github/workflows/ios.yml")
        XCTAssertTrue(workflow.contains("SAVE_SCREENSHOT_DIR"))
        XCTAssertTrue(workflow.contains("/tmp/SAVE-First-Run"))
        XCTAssertTrue(workflow.contains("CoreSimulator/Devices"))
        XCTAssertTrue(workflow.contains("copied simulator SAVE_SCREENSHOT_DIR"))
        XCTAssertTrue(workflow.contains("TestingEnvironmentVariables"))
        XCTAssertTrue(workflow.contains("five-tab-home"))
        XCTAssertTrue(workflow.contains("light-home"))
        XCTAssertTrue(workflow.contains("dark-home"))
        XCTAssertTrue(workflow.contains("H1"))
        XCTAssertTrue(workflow.contains("H1-allowed-clues"))
        XCTAssertTrue(workflow.contains("H3-no-clues-saves"))
        XCTAssertTrue(workflow.contains("H4-empty"))
        XCTAssertTrue(rail.contains("func testHomeDesignProductStates"))
        XCTAssertTrue(rail.contains("\"H1\""))
        XCTAssertTrue(rail.contains("\"H1-allowed-clues\""))
        XCTAssertTrue(rail.contains("\"H2\""))
        XCTAssertTrue(rail.contains("\"H2-denied-clues\""))
        XCTAssertTrue(rail.contains("\"H3\""))
        XCTAssertTrue(rail.contains("\"H3-no-clues-saves\""))
        XCTAssertTrue(rail.contains("\"H4\""))
        XCTAssertTrue(rail.contains("\"H4-empty\""))
        XCTAssertTrue(rail.contains("H2-en-light"))
        XCTAssertTrue(rail.contains("H2-en-dark"))
        XCTAssertTrue(rail.contains("H2-zh-light"))
        XCTAssertTrue(rail.contains("H2-zh-dark"))
        XCTAssertTrue(rail.contains("accuracy: 0.01"))
        XCTAssertTrue(rail.contains("assertTapTargetHeight"))
        XCTAssertFalse(rail.contains("[\"home.savedPlaces.empty\"]"))
        XCTAssertTrue(rail.contains("home.empty.capture"))
        let locality = try source(at: "SAV-E/Services/SaveAddressLocality.swift")
        XCTAssertTrue(locality.contains("NSW 2000"))
        XCTAssertTrue(locality.contains("australianStatePostcodeCode"))
        XCTAssertFalse(locality.contains("[A-Za-z]{2,3}"))
        XCTAssertTrue(locality.contains("en_US_POSIX"))
        XCTAssertTrue(locality.contains("cjkMunicipalityToken"))
        XCTAssertTrue(locality.contains("中国"))
        XCTAssertTrue(locality.contains("県"))
        XCTAssertFalse(locality.contains("locale: .current"))
        XCTAssertFalse(catalog.contains("locale: .current"))
        let search = try source(at: "SAV-E/Services/SaveHomeSearch.swift")
        XCTAssertTrue(search.contains("nonUSAdminRegionCountry"))
        XCTAssertTrue(search.contains("London, Ontario"))
        XCTAssertTrue(search.contains("homeUSStates"))
        XCTAssertTrue(root.contains("scenePhase"))
        XCTAssertTrue(root.contains("forceRefresh: true"))
        XCTAssertTrue(home.contains("replaceMissingCitySelection"))
        let locationService = try source(at: "SAV-E/Services/LocationService.swift")
        XCTAssertTrue(locationService.contains("SaveLocationFreshness"))
        XCTAssertTrue(locationService.contains("forceRefresh"))
        XCTAssertFalse(locationService.contains("if let currentLocation {\n            return currentLocation"))
        let selector = try source(at: "scripts/select-ios-tests.py")
        XCTAssertTrue(selector.contains("testHomeDesignProductStates"))
        XCTAssertTrue(rail.contains("doodle-home-empty"))
        XCTAssertTrue(rail.contains("doodle-home-allowed"))
        XCTAssertTrue(rail.contains("doodle-home-multirow"))
        XCTAssertTrue(rail.contains("--uitest-location-allowed"))
        XCTAssertFalse(rail.contains("doodle-home-dark"))
        XCTAssertFalse(rail.contains("confirmed places"))
        let location = try source(at: "SAV-E/Services/LocationService.swift")
        XCTAssertTrue(location.contains("--uitest-location-allowed"))
        XCTAssertTrue(location.contains("--uitest-location-tiantan"))
        XCTAssertTrue(location.contains("uiTestTiantan"))
        XCTAssertTrue(location.contains("39.882192"))
        XCTAssertTrue(location.contains("simulatesAllowedAuthorization"))
        XCTAssertTrue(rail.contains("func captureFiveTabHomeParityRaster"))
        XCTAssertTrue(rail.contains("--uitest-location-tiantan"))
        XCTAssertTrue(rail.contains("attach(app, name: \"five-tab-home\")"))
        let seed = try source(at: "SAV-E/Services/ReviewDemoService.swift")
        XCTAssertTrue(seed.contains("--uitest-doodle-parity-fixture"))
        XCTAssertTrue(seed.contains("Codex packet / spec §8"))
        XCTAssertTrue(seed.contains("SaveMemoryRecord.confirmedPlace"))
        XCTAssertFalse(seed.contains("latitude: 0"))
        let profile = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        XCTAssertTrue(profile.contains("collectionMode.places("))
        XCTAssertTrue(profile.contains("var collectionMode: SavePassportCollectionMode = .collection"))
        XCTAssertTrue(profile.contains("SaveDoodleVisitStore().recordVisit"))
        XCTAssertTrue(profile.contains("try await onUpdatePlace(updated)"))
        let map = try source(at: "SAV-E/Views/TileTown/SaveTileTownRootMap.swift")
        XCTAssertTrue(map.contains("cityGroups.first(where: { $0.id == id })"))
        XCTAssertTrue(map.contains("group.englishName"))
        let contentView = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(contentView.contains(".environmentObject(doodleSession)"))
    }

    func testElephantStickerExistsLoadsAndIsNeverAPlaceMark() throws {
        let color = repositoryRoot.appendingPathComponent(
            "SAV-E/Resources/Assets.xcassets/DoodleStickerElephantColor48.imageset/elephant-color-48.png"
        )
        let outline = repositoryRoot.appendingPathComponent(
            "SAV-E/Resources/Assets.xcassets/DoodleStickerElephantOutline.imageset/elephant-outline.pdf"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: color.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outline.path))
        let png = try Data(contentsOf: color)
        XCTAssertEqual([UInt8](png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let image = try XCTUnwrap(UIImage(data: png))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        XCTAssertFalse(SaveDoodleOfficialSticker.placeCases.contains(.elephant))
        let elephantNames = ["Elephant Cafe", "White Elephant", "小象", ""]
        for category in PlaceCategory.allCases {
            for name in elephantNames {
                XCTAssertNotEqual(
                    SaveDoodleOfficialSticker.named(for: category, placeName: name),
                    .elephant,
                    "\(category.rawValue) / \(name) must not map to the brand elephant"
                )
            }
        }
    }

    func testHomeShowsLocationDeniedPromptIdentifiers() throws {
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(home.contains("home.locationPrompt"))
        XCTAssertTrue(home.contains("home.locationAllow"))
        XCTAssertTrue(home.contains("showsLocationPrompt"))
        XCTAssertTrue(home.contains("if locationService.isAuthorizationDenied"))
        XCTAssertFalse(home.contains("isAuthorizationDenied && !showsEmptyHome"))
        XCTAssertTrue(home.contains("needsLocationToResolveNearYou"))
        XCTAssertTrue(home.contains(".accessibilityIdentifier(\"home.locationPrompt\")"))
        XCTAssertTrue(rail.contains("func testHomeListProgressiveSearch"))
        XCTAssertTrue(rail.contains("func testCaptureFiveTabLanding"))
        XCTAssertTrue(rail.contains("home.locationPrompt"))
        XCTAssertTrue(rail.contains("home.locationAllow"))
    }

    func testMapAppliesSharedDoodleSessionFilter() throws {
        let tokyoEat = place(
            "Ichiran",
            "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
            .food
        )
        let tokyoGo = place(
            "teamLab",
            "1-3-8 Aomi, Koto City, Tokyo, Japan",
            .attraction
        )
        let taipeiEat = place(
            "Fujin",
            "No. 353, Section 1, Fuxing S Rd, Da'an District, Taipei",
            .cafe
        )
        let session = SaveDoodleSession(
            defaults: UserDefaults(suiteName: "save.doodle.map.\(UUID().uuidString)")!
        )
        session.lens = .go
        session.city = .city("tokyo")
        let homeIDs = SaveDoodleHomeCatalog.visiblePlaces(
            from: [tokyoEat, tokyoGo, taipeiEat],
            lens: session.lens,
            selection: session.city,
            location: nil,
            locationDenied: true
        ).map(\.id)
        XCTAssertEqual(homeIDs, [tokyoGo.id])

        let map = try source(at: "SAV-E/Views/TileTown/SaveTileTownRootMap.swift")
        let content = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(map.contains("@EnvironmentObject private var session: SaveDoodleSession"))
        XCTAssertTrue(map.contains("header(followsHomeFilter: followsHomeFilter)"))
        XCTAssertTrue(map.contains("onChange(of: session.mapVisitResidueID)"))
        XCTAssertTrue(map.contains("applyMiniMapHandoff()"))
        XCTAssertTrue(map.contains("guard session.mapFollowsHomeFilter else { return places }"))
        XCTAssertTrue(map.contains("SaveDoodleHomeCatalog.visiblePlaces("))
        XCTAssertTrue(map.contains("session.lens"))
        XCTAssertTrue(map.contains("session.city"))
        XCTAssertTrue(map.contains("mapAccessibilityIdentifier"))
        XCTAssertTrue(map.contains("map.city"))
        XCTAssertTrue(map.contains("map.eatGo"))
        XCTAssertTrue(map.contains("onChange(of: session.lens)"))
        XCTAssertTrue(map.contains("onChange(of: session.city)"))
        XCTAssertTrue(map.contains("onClearSelection()"))
        XCTAssertTrue(map.contains("accessibilityElement(children: .contain)"))
        XCTAssertTrue(map.contains("showsCityPicker = true"))
        XCTAssertTrue(map.contains("map.city.\\(group.id)"))
        XCTAssertTrue(content.contains("selectRootTab(_ tab: SaveRootTab, mapFollowsHomeFilter: Bool = false)"))
        XCTAssertTrue(content.contains("applyMapTabSelection(followsHomeFilter: mapFollowsHomeFilter)"))
        XCTAssertTrue(content.contains("private func openMapFromMiniMap()"))
        XCTAssertTrue(content.contains("beginMiniMapHandoff()"))
        XCTAssertTrue(content.contains("onOpenMap: { openMapFromMiniMap() }"))
        XCTAssertTrue(content.contains("let mapIdentity = doodleSession.mapSurfaceID"))
        XCTAssertTrue(content.contains(".id(mapIdentity)"))
        XCTAssertTrue(content.contains("resetMapVisitResidue()"))
        XCTAssertTrue(content.contains("clearSelectedMapObject()"))
        XCTAssertTrue(content.contains("onSelect: { selectRootTab($0) }"))
        XCTAssertTrue(content.contains("SaveDoodleTabIcon("))
        XCTAssertFalse(content.contains("SavePixelChromeIcon("))
        XCTAssertTrue(content.contains("private func showMapTab()"))
        XCTAssertTrue(content.contains("if !isExactSearchSessionActive"))
        XCTAssertTrue(content.contains("abandonMiniMapHandoff()"))
        XCTAssertTrue(content.contains("preservesExactSearchClue: isExactSearchSessionActive"))
        XCTAssertTrue(content.contains("hasActiveExactSearchResolution"))
        XCTAssertTrue(content.contains("if !isExactSearchSessionActive"))
        XCTAssertTrue(content.contains("invalidateExactSearchRequest()"))
        XCTAssertTrue(content.contains("onClose: closeMapSearch"))
        XCTAssertTrue(content.contains("onCollapse: closeMapSearch"))
        let closeSearch = try XCTUnwrap(content.components(separatedBy: "private func closeMapSearch()").last?.components(separatedBy: "@ViewBuilder").first)
        XCTAssertTrue(closeSearch.contains("invalidateExactSearchRequest()"))
        XCTAssertTrue(closeSearch.contains("collapseMapPanel()"))
        XCTAssertTrue(content.contains("exactSearchClueID"))
        XCTAssertTrue(content.contains("activateExactSearchSession(for:"))
        XCTAssertTrue(content.contains("restoreExactSearchResolutionIfNeeded()"))
        XCTAssertTrue(content.contains("endExactSearchSessionAfterCandidateSave()"))
        XCTAssertTrue(content.contains("onClearMapSearchResults: { endsExactSearch in"))
        let drawer = try source(at: "SAV-E/Views/Drawer/AIDrawerView.swift")
        XCTAssertTrue(drawer.contains("onClearMapSearchResults(false)"))
        XCTAssertTrue(drawer.contains("onClearMapSearchResults(true)"))
        XCTAssertTrue(map.contains("consumeMiniMapHandoff()"))
        let catalogSource = try source(at: "SAV-E/Services/SaveDoodleHomeCatalog.swift")
        XCTAssertTrue(catalogSource.contains("save.doodle.mapFollows."))
        XCTAssertTrue(catalogSource.contains("mapFollowsHomeFilter = defaults.bool(forKey: Self.followKey)"))
        XCTAssertTrue(catalogSource.contains("func beginMiniMapHandoff()"))
        XCTAssertTrue(catalogSource.contains("func consumeMiniMapHandoff()"))
        XCTAssertTrue(catalogSource.contains("func abandonMiniMapHandoff()"))
        XCTAssertTrue(catalogSource.contains("func applyMapTabSelection(followsHomeFilter: Bool)"))
        XCTAssertTrue(catalogSource.contains("mapVisitResidueID = UUID()"))
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(root.contains("session.consumeMiniMapHandoff()"))
        XCTAssertTrue(root.contains(".accessibilityIdentifier(\"map.root\")"))
        XCTAssertTrue(
            root.contains("accessibilityElement(children: .contain)"),
            "map.root must keep the contain container the other Map UI tests query"
        )
        let rail = try source(at: "Tests/SAVEUITests/SAVEScreenshotRailTests.swift")
        XCTAssertTrue(rail.contains("func testHomeAndPassportWarmDarkMode"))
        XCTAssertTrue(rail.contains("home.eat"))
        XCTAssertTrue(rail.contains("home.citySwitcher"))
        XCTAssertTrue(rail.contains("captureHomeAndPassportCanvas"))
        XCTAssertTrue(rail.contains("func testMiniMapOpensMapWithCarriedFilterAndCityChange"))
        XCTAssertTrue(rail.contains("app.buttons[\"map.go\"]"))
        XCTAssertTrue(rail.contains("app.buttons[\"map.eat\"]"))
        XCTAssertFalse(rail.contains("recordQ5ReusedMapTree"))
        XCTAssertFalse(rail.contains("q5-reused-map-debugDescription"))
        XCTAssertFalse(rail.contains("q5-reused-map"))
        XCTAssertEqual(
            content.components(separatedBy: "selectedRootTab = .map").count - 1,
            1,
            "Only showMapTab() may assign Map directly; other opens must go through it"
        )
        for name in [
            "func openMapSearch",
            "func openCollaborativeListOnMap",
            "func showMapCandidatesOnMap",
            "func addClueToReviewCandidate",
            "func openExactSearch",
        ] {
            XCTAssertTrue(content.contains(name), name)
        }
        XCTAssertGreaterThanOrEqual(
            content.components(separatedBy: "showMapTab()").count - 1,
            6,
            "Search, show-on-map, and list handoffs must clear the Home filter"
        )
        XCTAssertTrue(session.mapFollowsHomeFilter == false)
        session.mapFollowsHomeFilter = true
        XCTAssertTrue(session.mapFollowsHomeFilter)
        session.mapFollowsHomeFilter = false
        XCTAssertFalse(session.mapFollowsHomeFilter)
        XCTAssertTrue(map.contains("[.isButton, .isSelected] : .isButton"))
    }

    func testMiniMapHandoffSurvivesDefaultFalseAndShowOnMapClearsIt() {
        let defaults = UserDefaults(suiteName: "save.doodle.handoff.\(UUID().uuidString)")!
        let session = SaveDoodleSession(defaults: defaults)
        XCTAssertFalse(session.mapFollowsHomeFilter)
        XCTAssertFalse(session.pendingMiniMapHandoff)
        let firstSurface = session.mapSurfaceID

        session.beginMiniMapHandoff()
        XCTAssertTrue(session.pendingMiniMapHandoff)
        XCTAssertTrue(session.mapFollowsHomeFilter)
        XCTAssertNotEqual(session.mapSurfaceID, firstSurface)

        session.applyMapTabSelection(followsHomeFilter: false)
        XCTAssertTrue(
            session.mapFollowsHomeFilter,
            "A tab-bar default-false write must not beat a pending mini-map handoff"
        )

        session.consumeMiniMapHandoff()
        XCTAssertTrue(session.mapFollowsHomeFilter)
        XCTAssertFalse(session.pendingMiniMapHandoff)

        session.abandonMiniMapHandoff()
        XCTAssertFalse(session.mapFollowsHomeFilter)
        XCTAssertFalse(session.pendingMiniMapHandoff)

        session.beginMiniMapHandoff()
        session.consumeMiniMapHandoff()
        XCTAssertTrue(session.mapFollowsHomeFilter)
        session.applyMapTabSelection(followsHomeFilter: false)
        XCTAssertFalse(
            session.mapFollowsHomeFilter,
            "Direct Map tab after a consumed handoff must clear Eat/Go"
        )

        session.beginMiniMapHandoff()
        session.abandonMiniMapHandoff()
        XCTAssertFalse(
            session.mapFollowsHomeFilter,
            "show-on-map / search must abandon a leftover mini-map filter"
        )
        XCTAssertFalse(session.pendingMiniMapHandoff)
    }

    func testBeginMiniMapHandoffResetsPriorMapVisitResidue() throws {
        let defaults = UserDefaults(suiteName: "save.doodle.residue.\(UUID().uuidString)")!
        let session = SaveDoodleSession(defaults: defaults)
        session.mapFollowsHomeFilter = false
        let leftoverSurface = session.mapSurfaceID
        let leftoverResidue = session.mapVisitResidueID

        session.beginMiniMapHandoff()

        XCTAssertTrue(session.mapFollowsHomeFilter)
        XCTAssertTrue(session.pendingMiniMapHandoff)
        XCTAssertNotEqual(
            session.mapSurfaceID,
            leftoverSurface,
            "Mini-map must give Map a new identity so a reused tab remounts Eat/Go"
        )
        XCTAssertNotEqual(
            session.mapVisitResidueID,
            leftoverResidue,
            "Mini-map must drop leftover selected-pin / drawer / first-appear chrome"
        )

        session.consumeMiniMapHandoff()
        XCTAssertTrue(session.mapFollowsHomeFilter)
        XCTAssertFalse(session.pendingMiniMapHandoff)

        let content = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertTrue(content.contains("onChange(of: doodleSession.mapVisitResidueID)"))
        XCTAssertTrue(content.contains("mapVM.clearSelectedMapObject()"))
        XCTAssertTrue(content.contains("isMapPanelExpanded = false"))
        XCTAssertTrue(content.contains("drawerVM.returnToCommands()"))
        let map = try source(at: "SAV-E/Views/TileTown/SaveTileTownRootMap.swift")
        XCTAssertTrue(map.contains("lens = .saved"))
        XCTAssertTrue(map.contains("showsCityPicker = false"))
        XCTAssertTrue(map.contains(".id(visitResidue)"))
    }

    private var tiantanFix: CLLocation {
        CLLocation(latitude: 39.8822, longitude: 116.4066)
    }

    private func place(
        _ name: String,
        _ address: String,
        _ category: PlaceCategory,
        status: PlaceStatus = .wantToGo,
        latitude: Double = 25.033,
        longitude: Double = 121.5654,
        createdAt: Date = Date()
    ) -> Place {
        Place(
            id: UUID(),
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: nil,
            category: category,
            status: status,
            rating: nil,
            note: nil,
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: createdAt
        )
    }

    private func pngDimension(_ data: Data, at offset: Int) -> UInt32 {
        let bytes = [UInt8](data.subdata(in: offset..<(offset + 4)))
        return UInt32(bytes[0]) << 24
            | UInt32(bytes[1]) << 16
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3])
    }

    private func source(at relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
