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

    /// Dotted US country forms, region+postcode, and Indian states.
    func testLongTailLocalityDottedUSPostcodeAndIndianStates() {
        XCTAssertEqual(SaveAddressLocality.country(in: "U.S."), "united states")
        XCTAssertEqual(SaveAddressLocality.country(in: "U.S.A."), "united states")
        XCTAssertEqual(SaveAddressLocality.country(in: "U.K."), "united kingdom")

        let dotted = place("Cozy Dog", "Springfield, IL 62703, U.S.", .food)
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: dotted.address), "Springfield")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: dotted), "springfield,il")

        let illinoisZip = place("Cozy Dog", "Springfield, Illinois 62703, USA", .food)
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: illinoisZip.address), "Springfield")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: illinoisZip), "springfield,il")
        XCTAssertNotEqual(SaveDoodleHomeCatalog.cityID(for: illinoisZip), "illinois,united states")

        let toronto = place("St Lawrence", "Toronto, Ontario M5V 3A8, Canada", .food)
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: toronto.address), "Toronto")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: toronto), "toronto,on")
        XCTAssertNotEqual(SaveDoodleHomeCatalog.cityID(for: toronto), "ontario,canada")

        let ottawa = place("ByWard", "Ottawa, Ontario K1P 5G8, Canada", .attraction)
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: ottawa.address), "Ottawa")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: ottawa), "ottawa,on")
        XCTAssertNotEqual(SaveDoodleHomeCatalog.cityID(for: ottawa), "ontario,canada")

        let pune = place("Vada Pav", "123 MG Road, Pune, Maharashtra 411001, India", .food)
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: pune.address), "Pune")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: pune), "pune,mh")
        XCTAssertNotEqual(SaveDoodleHomeCatalog.cityID(for: pune), "maharashtra,india")

        let delhi = place("CP", "Connaught Place, Delhi, India", .attraction)
        XCTAssertEqual(SaveDoodleHomeCatalog.localityLabel(in: delhi.address), "Delhi")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: delhi), "delhi,india")
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
        for (alias, country) in [("USA", "united states"), ("US", "united states"), ("U.S.", "united states"), ("U.S.A.", "united states"), ("United States of America", "united states"), ("Schweiz", "switzerland"), ("Holland", "netherlands"), ("Österreich", "austria")] {
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
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: traditional), "蘇州市,江蘇省")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: compact), "蘇州市,江蘇省")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: simplified), "苏州市,江苏省")
        XCTAssertFalse((SaveDoodleHomeCatalog.localityLabel(in: traditional.address) ?? "").contains("省"))
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
            Case(address: "Springfield, IL 62703, U.S.", label: "Springfield", cityID: "springfield,il", metro: nil),
            Case(address: "Springfield, Illinois 62703, USA", label: "Springfield", cityID: "springfield,il", metro: nil),
            Case(address: "Toronto, Ontario M5V 3A8, Canada", label: "Toronto", cityID: "toronto,on", metro: nil),
            Case(address: "Ottawa, Ontario K1P 5G8, Canada", label: "Ottawa", cityID: "ottawa,on", metro: nil),
            Case(address: "123 MG Road, Pune, Maharashtra 411001, India", label: "Pune", cityID: "pune,mh", metro: nil),
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
            Case(address: "中國, 江蘇省, 蘇州市, 姑蘇區", label: "蘇州市", cityID: "蘇州市,江蘇省", metro: nil),
            Case(address: "中国, 江苏省, 苏州市, 姑苏区", label: "苏州市", cityID: "苏州市,江苏省", metro: nil),
            Case(address: "江蘇省蘇州市姑蘇區", label: "蘇州市", cityID: "蘇州市,江蘇省", metro: nil),
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
            Case(address: "日本神奈川県横浜市中区", label: "横浜市", cityID: "横浜市,神奈川県", metro: nil),
            Case(address: "横浜市中区, 神奈川県, 日本", label: "横浜市", cityID: "横浜市,神奈川県", metro: nil),
            Case(address: "東京都府中市宮町", label: "府中市", cityID: "府中市,東京都", metro: nil),
            Case(address: "広島県府中市元町", label: "府中市", cityID: "府中市,広島県", metro: nil),
            Case(address: "大阪府大阪市北区", label: "大阪市", cityID: "osaka", metro: "osaka"),
            Case(address: "北海道札幌市中央区", label: "札幌市", cityID: "札幌市,北海道", metro: nil),
            Case(address: "Rue Charles Morin, Eu, France", label: "Eu", cityID: "eu,france", metro: nil),
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
        let stale = SavePassportCollectionMode.homeCollected.places(
            from: places, selection: .city("nonexistent"), location: nil, locationDenied: true
        )
        let resolved = SaveDoodleHomeCatalog.resolvedSelection(
            .city("nonexistent"), places: places, locationDenied: true
        )
        XCTAssertNotEqual(resolved, .city("nonexistent"))
        XCTAssertFalse(
            stale.isEmpty,
            "A missing city falls back to the newest resolvable city, not an empty stamp set"
        )
        XCTAssertEqual(
            stale.map(\.id),
            SaveDoodleHomeCatalog.collectedScopePlaces(
                from: places, selection: resolved, location: nil, locationDenied: true
            ).map(\.id)
        )
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

    func testHomeHintTimeCutoffsAndCounts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func at(_ hour: Int, _ minute: Int) -> Date {
            DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 2026,
                month: 10,
                day: 24,
                hour: hour,
                minute: minute
            ).date!
        }
        XCTAssertEqual(SaveDoodleHomeHint.period(at: at(4, 59), calendar: calendar), .evening)
        XCTAssertEqual(SaveDoodleHomeHint.period(at: at(5, 0), calendar: calendar), .morning)
        XCTAssertEqual(SaveDoodleHomeHint.period(at: at(11, 59), calendar: calendar), .morning)
        XCTAssertEqual(SaveDoodleHomeHint.period(at: at(12, 0), calendar: calendar), .afternoon)
        XCTAssertEqual(SaveDoodleHomeHint.period(at: at(17, 59), calendar: calendar), .afternoon)
        XCTAssertEqual(SaveDoodleHomeHint.period(at: at(18, 0), calendar: calendar), .evening)

        let morning = at(8, 0)
        let three = SaveDoodleHomeHint.copy(
            clueCount: 3, at: morning, language: .english, calendar: calendar
        )
        XCTAssertEqual(three.leadingFull, "Good morning · 3 clues waiting ·")
        XCTAssertEqual(three.leadingShort, "Good morning · 3 clues ·")
        XCTAssertEqual(three.review, "Review ›")
        XCTAssertEqual(three.spoken, "Good morning · 3 clues waiting · Review ›")

        let one = SaveDoodleHomeHint.copy(
            clueCount: 1, at: morning, language: .english, calendar: calendar
        )
        XCTAssertEqual(one.leadingFull, "Good morning · 1 clue waiting ·")
        XCTAssertEqual(one.leadingShort, "Good morning · 1 clue ·")
        XCTAssertEqual(one.spoken, "Good morning · 1 clue waiting · Review ›")

        let evening = at(20, 0)
        let oneEvening = SaveDoodleHomeHint.copy(
            clueCount: 1, at: evening, language: .english, calendar: calendar
        )
        XCTAssertEqual(oneEvening.leadingFull, "Good evening · 1 clue waiting ·")
        XCTAssertEqual(oneEvening.leadingShort, "Good evening · 1 clue ·")
        XCTAssertEqual(oneEvening.review, "Review ›")
        XCTAssertEqual(oneEvening.spoken, "Good evening · 1 clue waiting · Review ›")
        XCTAssertFalse(oneEvening.review?.contains("·") == true)

        let oneEveningZh = SaveDoodleHomeHint.copy(
            clueCount: 1, at: evening, language: .traditionalChinese, calendar: calendar
        )
        XCTAssertEqual(oneEveningZh.leadingFull, "晚安 · 1 條線索待看 ·")
        XCTAssertEqual(oneEveningZh.leadingShort, "晚安 · 1 條線索待看 ·")
        XCTAssertEqual(oneEveningZh.review, "去看看 ›")
        XCTAssertEqual(oneEveningZh.spoken, "晚安 · 1 條線索待看 · 去看看 ›")
        XCTAssertFalse(oneEveningZh.review?.contains("·") == true)

        let overflow = SaveDoodleHomeHint.copy(
            clueCount: 100, at: morning, language: .english, calendar: calendar
        )
        XCTAssertEqual(overflow.leadingFull, "Good morning · 99+ clues waiting ·")
        XCTAssertEqual(overflow.leadingShort, "Good morning · 99+ clues ·")
        XCTAssertEqual(overflow.spoken, "Good morning · 99+ clues waiting · Review ›")
        XCTAssertEqual(SaveDoodleHomeHint.displayCount(99), "99")
        XCTAssertEqual(SaveDoodleHomeHint.displayCount(100), "99+")

        let none = SaveDoodleHomeHint.copy(
            clueCount: 0, at: morning, language: .english, calendar: calendar
        )
        XCTAssertEqual(none.leadingFull, "Good morning")
        XCTAssertEqual(none.leadingShort, "Good morning")
        XCTAssertNil(none.review)
        XCTAssertEqual(none.spoken, "Good morning")

        let zh = SaveDoodleHomeHint.copy(
            clueCount: 3, at: morning, language: .traditionalChinese, calendar: calendar
        )
        XCTAssertEqual(zh.leadingFull, "早安 · 3 條線索待看 ·")
        XCTAssertEqual(zh.leadingShort, "早安 · 3 條線索待看 ·")
        XCTAssertEqual(zh.review, "去看看 ›")
        XCTAssertEqual(zh.spoken, "早安 · 3 條線索待看 · 去看看 ›")
        let eveningZh = SaveDoodleHomeHint.copy(
            clueCount: 0, at: at(18, 0), language: .traditionalChinese, calendar: calendar
        )
        XCTAssertEqual(eveningZh.leadingFull, "晚安")
        let afternoon = SaveDoodleHomeHint.copy(
            clueCount: 0, at: at(12, 0), language: .english, calendar: calendar
        )
        XCTAssertEqual(afternoon.leadingFull, "Good afternoon")
    }

    func testUITestClockParsesDeviceLocalFixedNow() throws {
        let evening = try XCTUnwrap(SaveUITestClock.parseLocal("2026-10-24T20:00:00"))
        XCTAssertEqual(Calendar.current.component(.hour, from: evening), 20)
        XCTAssertEqual(SaveDoodleHomeHint.period(at: evening), .evening)
        let morning = try XCTUnwrap(SaveUITestClock.parseLocal("2026-10-24T08:00:00"))
        XCTAssertEqual(SaveDoodleHomeHint.period(at: morning), .morning)
        let afternoon = try XCTUnwrap(SaveUITestClock.parseLocal("2026-10-24T14:00:00"))
        XCTAssertEqual(SaveDoodleHomeHint.period(at: afternoon), .afternoon)
        XCTAssertNil(SaveUITestClock.parseLocal("not-a-date"))
    }

    func testHomeTPEAFixtureDefaultEatShowsFourInRadiusComputedDistances() throws {
        let now = try XCTUnwrap(SaveUITestClock.parseLocal("2026-10-24T20:00:00"))
        let places = ReviewDemoSeed.homeTPEAPlaces(now: now)
        XCTAssertEqual(places.count, 8)
        XCTAssertEqual(places[0].name, "Fujin Tree 353 Cafe")
        XCTAssertNil(places[0].businessPhotoUrls)
        XCTAssertNil(places[0].sourceImageUrl)
        let daan = CLLocation(latitude: 25.0296, longitude: 121.5347)
        let eat = SaveDoodleHomeCatalog.listedPlaces(
            from: places,
            lens: .eat,
            selection: .nearYou,
            location: daan,
            locationDenied: false
        )
        XCTAssertEqual(eat.map(\.place.name), [
            "Fujin Tree 353 Cafe",
            "Lunch Noodle",
            "Roast Duck Kitchen",
            "Window Cafe",
        ])
        // Same path as production rows: CLLocation.distance + distanceText.
        // HoP fixture 280/650/1200/2100 is not what the formatter shows.
        let eatLabels = try eat.map { item -> String in
            let distance = try XCTUnwrap(item.distance)
            let viaCatalog = try XCTUnwrap(SaveDoodleHomeCatalog.distance(from: daan, to: item.place))
            XCTAssertEqual(distance, viaCatalog, accuracy: 0.001, item.place.name)
            return SaveDoodleHomeCatalog.distanceText(distance)
        }
        XCTAssertEqual(eatLabels, ["279m", "651m", "1.2km", "2.1km"])
        XCTAssertEqual(eat[0].distance!, 278.94, accuracy: 0.05)
        XCTAssertEqual(eat[1].distance!, 651.12, accuracy: 0.05)
        XCTAssertEqual(eat[2].distance!, 1_198.78, accuracy: 0.05)
        XCTAssertEqual(eat[3].distance!, 2_092.04, accuracy: 0.05)
        let e5 = try XCTUnwrap(places.first { $0.name == "Night Market Bar" })
        let e5Meters = daan.distance(from: CLLocation(latitude: e5.latitude, longitude: e5.longitude))
        XCTAssertGreaterThan(e5Meters, SaveDoodleHomeCatalog.nearbyRadius)
        XCTAssertEqual(SaveDoodleHomeCatalog.distanceText(e5Meters), "3.4km")
        XCTAssertEqual(
            SaveDoodleHomeCatalog.visitStatusText(
                status: .visited,
                visitedAt: places[0].createdAt,
                now: now,
                language: .english
            ),
            "visited today"
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.visitStatusText(
                status: .visited,
                visitedAt: places[2].createdAt,
                now: now,
                language: .english
            ),
            "visited 3d ago"
        )
        let go = SaveDoodleHomeCatalog.listedPlaces(
            from: places,
            lens: .go,
            selection: .nearYou,
            location: daan,
            locationDenied: false
        )
        XCTAssertEqual(go.map(\.place.name), [
            "Temple Courtyard",
            "Lantern Alley Park",
        ])
        let goLabels = try go.map { item -> String in
            let distance = try XCTUnwrap(item.distance)
            let viaCatalog = try XCTUnwrap(SaveDoodleHomeCatalog.distance(from: daan, to: item.place))
            XCTAssertEqual(distance, viaCatalog, accuracy: 0.001, item.place.name)
            return SaveDoodleHomeCatalog.distanceText(distance)
        }
        XCTAssertEqual(goLabels, ["899m", "1.6km"])
        let g3 = try XCTUnwrap(places.first { $0.name == "Forest Walk" })
        let g3Meters = daan.distance(from: CLLocation(latitude: g3.latitude, longitude: g3.longitude))
        XCTAssertGreaterThan(g3Meters, SaveDoodleHomeCatalog.nearbyRadius)
        XCTAssertEqual(SaveDoodleHomeCatalog.distanceText(g3Meters), "4.0km")
        XCTAssertEqual(SaveDoodleOfficialSticker.named(for: .cafe, placeName: "Fujin Tree 353 Cafe"), .coffee)
        XCTAssertEqual(SaveDoodleOfficialSticker.named(for: .food, placeName: "Lunch Noodle"), .noodle)
        XCTAssertEqual(SaveDoodleOfficialSticker.named(for: .food, placeName: "Roast Duck Kitchen"), .duck)
        XCTAssertEqual(SaveDoodleOfficialSticker.named(for: .bar, placeName: "Night Market Bar"), .lantern)
        XCTAssertEqual(SaveDoodleOfficialSticker.named(for: .attraction, placeName: "Temple Courtyard"), .temple)
    }

    func testTaipeiFixtureFirstRowDistanceIsNotEmpty() throws {
        let here = CLLocation(latitude: 25.0330, longitude: 121.5654)
        let cafe = place(
            "Taipei Window Cafe",
            "台北市大安區",
            .cafe,
            latitude: 25.04,
            longitude: 121.54
        )
        let listed = SaveDoodleHomeCatalog.listedPlaces(
            from: [cafe],
            lens: .eat,
            selection: .nearYou,
            location: here,
            locationDenied: false
        )
        XCTAssertEqual(listed.count, 1)
        let meters = try XCTUnwrap(listed.first?.distance)
        let distance = SaveDoodleHomeCatalog.distanceText(meters)
        XCTAssertFalse(distance.isEmpty)
        let meta = SaveDoodleHomeCatalog.rowMetaText(
            distance: meters,
            place: cafe,
            language: .english
        )
        XCTAssertTrue(meta.hasPrefix(distance), meta)
        XCTAssertTrue(meta.contains("saved, not yet"), meta)
        XCTAssertFalse(meta.contains("…"))
        XCTAssertFalse(meta.contains("..."))

        let denied = SaveDoodleHomeCatalog.rowMetaText(
            distance: nil,
            place: cafe,
            language: .traditionalChinese
        )
        XCTAssertTrue(denied.contains("大安區"), denied)
        XCTAssertTrue(denied.contains("已存，還沒去"), denied)

        let now = Date(timeIntervalSince1970: 1_760_000_000)
        XCTAssertEqual(
            SaveDoodleHomeCatalog.visitStatusText(
                status: .visited,
                visitedAt: now.addingTimeInterval(-3 * 86_400),
                now: now,
                language: .english
            ),
            "visited 3d ago"
        )
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

    /// T5: a city with no saves hides the strip. A stale persisted city ID
    /// is replaced, so Collected only disappears when nothing resolves.
    func testT5HomeCollectedHiddenWhenCityHasNoSaves() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let places = ReviewDemoSeed.doodleParityPlaces(now: now)
        let stale = SaveDoodleHomeCatalog.collectedScopePlaces(
            from: places,
            selection: .city("osaka"),
            location: nil,
            locationDenied: true
        )
        XCTAssertFalse(stale.isEmpty, "Stale Osaka falls back to the newest resolvable city")
        let empty = SaveDoodleHomeCatalog.collectedScopePlaces(
            from: [],
            selection: .city("osaka"),
            location: nil,
            locationDenied: true
        )
        XCTAssertTrue(empty.isEmpty)
        let count = SaveDoodleHomeCatalog.cityCollectedCount(in: empty)
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
        session.lens = .go
        session.city = .city("tokyo")
        let restored = SaveDoodleSession(defaults: defaults)
        XCTAssertEqual(restored.lens, .go)
        XCTAssertEqual(restored.city, .city("tokyo"))
    }

    func testProductionHomeIsDoodleNotTileTown() throws {
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertTrue(root.contains("SaveDoodleHomeView("))
        XCTAssertFalse(root.contains("onOpenMap"))
        XCTAssertFalse(root.contains("SaveTileTownHomeView()"))
        XCTAssertFalse(home.contains("home.miniMap"))
        XCTAssertFalse(home.contains("SaveDoodleMiniMap"))
        XCTAssertFalse(home.contains("miniMap"))
        XCTAssertFalse(home.contains("Map("), "Home files must contain zero Map(")
        XCTAssertFalse(home.contains("MKMapView"))
        XCTAssertFalse(home.contains("import MapKit"))
        XCTAssertTrue(home.contains("home.citySwitcher"))
        XCTAssertTrue(home.contains("nearYouCityName"))
        XCTAssertFalse(home.contains("listedPlaces.first"))
        XCTAssertTrue(home.contains("eatGoRow"))
        XCTAssertTrue(home.contains("fixedSize(horizontal: true, vertical: false)"))
        let headerAt = try XCTUnwrap(home.range(of: "private var header"))
        let eatRowAt = try XCTUnwrap(home.range(of: "private var eatGoRow"))
        XCTAssertTrue(home[headerAt.lowerBound..<eatRowAt.lowerBound].contains("eatGoRow"))
        let cluesAt = try XCTUnwrap(home.range(of: "cluesLine"))
        let rowsAt = try XCTUnwrap(home.range(of: "placeList"))
        let collectedAt = try XCTUnwrap(home.range(of: "collectedStrip"))
        XCTAssertLessThan(cluesAt.lowerBound, rowsAt.lowerBound)
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
        XCTAssertTrue(home.contains("SaveDoodleHomeHint"))
        XCTAssertTrue(home.contains("home.review.action"))
        XCTAssertTrue(home.contains(".padding(.trailing, 4)"))
        let catalogHint = try source(at: "SAV-E/Services/SaveDoodleHomeCatalog.swift")
        XCTAssertTrue(catalogHint.contains("\\(fullPhrase) ·\""))
        XCTAssertTrue(catalogHint.contains("\\(shortPhrase) ·\""))
        XCTAssertTrue(catalogHint.contains("spoken: \"\\(leadingFull) \\(review)\""))
        XCTAssertTrue(home.contains("MemoMascotMark"))
        XCTAssertFalse(home.contains("import MapKit"))
        XCTAssertFalse(home.contains("MKMapView"))
        XCTAssertFalse(home.contains("Map(initialPosition:"))
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
        XCTAssertFalse(home.contains("if presentation.reviewCount > 0"))
        XCTAssertTrue(home.contains("clueCount: presentation.reviewCount"))
        let factory = try source(at: "SAV-E/Views/Atlas/SaveAtlasProductionBridge.swift")
        XCTAssertFalse(factory.contains("presentation.reviewCount = mapViewModel.reviewCandidates.count"))
        XCTAssertTrue(factory.contains("uiTestHintCountOverride"))
        XCTAssertTrue(factory.contains("--uitest-home-hint-count="))
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
        let theme = try source(at: "SAV-E/Extensions/Color+Theme.swift")
        XCTAssertTrue(theme.contains("static let rowMinHeight: CGFloat = 68"))
        XCTAssertEqual(SaveAtlasPalette.coralLightHex, "F26B4A")
        XCTAssertEqual(SaveAtlasPalette.coralDarkHex, "D97861")
        XCTAssertEqual(SaveAtlasPalette.homeReviewActionLightHex, "C8442A")
        XCTAssertEqual(SaveAtlasPalette.homeReviewActionDarkHex, "F26B4A")
        XCTAssertEqual(SaveAtlasPalette.brandCoralHex, "F26B4A")
        XCTAssertTrue(home.contains("SaveAtlasPalette.homeReviewAction"))
        XCTAssertFalse(
            cluesLine(in: home).contains("SaveAtlasPalette.coral"),
            "Review › is the only light coral that uses #C8442A"
        )
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
        XCTAssertFalse(home.contains(".mapStyle(.standard(emphasis: .automatic))"))
        XCTAssertFalse(home.contains("Annotation("))
        XCTAssertFalse(home.contains("SaveDoodleNumberPin("))
        XCTAssertTrue(home.contains("SaveDoodle.stampRed"))
        XCTAssertTrue(home.contains("SaveAtlasPalette.coral"))
        XCTAssertFalse(home.contains("interactionModes: []"))
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
        XCTAssertTrue(design.contains("Savvy + small elephant + Eat/Go in the header"))
        XCTAssertTrue(design.contains("no map component"))
        XCTAssertTrue(design.contains("official DESIGN color die-cut"))
        XCTAssertTrue(design.contains("small Memo elephant"))
        XCTAssertTrue(design.contains("68pt"))
        XCTAssertTrue(design.contains("hint row is always shown"))
        XCTAssertTrue(design.contains("DESIGN v2 is the Home layout contract"))
        XCTAssertTrue(design.contains("79ae24aaf02002cd10f429c2869dcfc0"))
        XCTAssertTrue(design.contains("expected FAIL on the current list-only Home"))
        XCTAssertTrue(home.contains("placeCases"))
        XCTAssertFalse(home.contains("SaveDoodleElephant"), "Home no longer displays the retired elephant artwork")
        XCTAssertTrue(home.contains("SaveDoodleEmptyPlate"))
        XCTAssertTrue(design.contains("always-visible hint row"))
        XCTAssertTrue(design.contains("eade369"))
        XCTAssertFalse(design.contains("home-mask.png"))
        XCTAssertTrue(design.contains("judged manually by DESIGN"))
        XCTAssertTrue(design.contains("v1 is retired") || design.contains("v1 is\nretired"))
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
        XCTAssertTrue(readme.contains("79ae24aaf02002cd10f429c2869dcfc0"))
        XCTAssertTrue(readme.contains("not** DESIGN v2") || readme.contains("**not** DESIGN v2"))
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
        XCTAssertTrue(parity.contains("0.35 * edgeF1 + 0.65 * appearanceSimilarity"))
        XCTAssertTrue(parity.contains("useGraded ? gradedComposite : legacyComposite"))
        let parityRunner = try source(at: "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh")
        XCTAssertTrue(parityRunner.contains("home-mask.png"))
        XCTAssertTrue(parityRunner.contains("--mask"))
        XCTAssertTrue(parityRunner.contains("mask_args"))
        XCTAssertTrue(parityRunner.contains("extra_args"))
        XCTAssertTrue(parityRunner.contains("${#mask_args[@]}"))
        XCTAssertTrue(parityRunner.contains("${#extra_args[@]}"))
        let mapPNG = try Data(contentsOf: repositoryRoot.appendingPathComponent(
            "Prototypes/AtlasPostcard/Reference/ProductionTargets/map.png"
        ))
        XCTAssertEqual(pngDimension(mapPNG, at: 16), 1206)
        XCTAssertEqual(pngDimension(mapPNG, at: 20), 2622)
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
        XCTAssertTrue(home.contains("syncPersistedCitySelection"))
        XCTAssertTrue(home.contains("persistedCityAfterCollectionChange"))
        XCTAssertTrue(home.contains("collectionReady: !allPlaces.isEmpty"))
        XCTAssertTrue(home.contains("visitedAt: SaveDoodleVisitStore().latestVisit"))
        let locationService = try source(at: "SAV-E/Services/LocationService.swift")
        XCTAssertTrue(locationService.contains("SaveLocationFreshness"))
        XCTAssertTrue(locationService.contains("forceRefresh"))
        XCTAssertFalse(locationService.contains("if let currentLocation {\n            return currentLocation"))
        let selector = try source(at: "scripts/select-ios-tests.py")
        XCTAssertTrue(selector.contains("testHomeDesignProductStates"))
        XCTAssertTrue(selector.contains("testHomeHintCountEvidence"))
        XCTAssertTrue(selector.contains("testHomeTaipeiGrantedDistances"))
        XCTAssertTrue(selector.contains("testHomeTPEAEvidence"))
        XCTAssertTrue(rail.contains("func testHomeHintCountEvidence"))
        XCTAssertTrue(rail.contains("func testHomeTaipeiGrantedDistances"))
        XCTAssertTrue(rail.contains("func testHomeTPEAEvidence"))
        XCTAssertTrue(rail.contains("func captureAtlasHomeTPEA"))
        XCTAssertTrue(rail.contains("assertTPEALocatedEatRows"))
        XCTAssertTrue(rail.contains("assertTPEALocatedGoRows"))
        XCTAssertTrue(rail.contains("assertTPEBDeniedEatRows"))
        XCTAssertTrue(rail.contains("279m"))
        XCTAssertTrue(rail.contains("651m"))
        XCTAssertTrue(rail.contains("1.2km"))
        XCTAssertTrue(rail.contains("2.1km"))
        XCTAssertTrue(rail.contains("899m"))
        XCTAssertTrue(rail.contains("1.6km"))
        XCTAssertTrue(rail.contains("--uitest-home-\\(fixture)"))
        XCTAssertTrue(rail.contains("\"tpea\""))
        XCTAssertTrue(rail.contains("--uitest-fixed-now=\\(clock)"))
        XCTAssertTrue(rail.contains("2026-10-24T20:00:00"))
        XCTAssertTrue(rail.contains("TPE-A-dark-en"))
        XCTAssertTrue(rail.contains("TPE-A-go-light-en"))
        XCTAssertTrue(rail.contains("TPE-B-denied-light-en"))
        XCTAssertTrue(rail.contains("TPE-C-n0-light-en"))
        XCTAssertTrue(rail.contains("TPE-D-402pt-\\(label)"))
        XCTAssertTrue(rail.contains("TPE-E-long-wrap-denied-en"))
        XCTAssertTrue(rail.contains("TPE-F"))
        XCTAssertTrue(rail.contains("Lunch Noodle"))
        XCTAssertTrue(rail.contains("map.camera"))
        XCTAssertTrue(rail.contains("waiting · Review ›"))
        XCTAssertTrue(rail.contains("待看 · 去看看 ›"))
        XCTAssertTrue(rail.contains("H3b-\\(label)"))
        XCTAssertTrue(rail.contains("taipei-granted-light-en"))
        XCTAssertTrue(rail.contains("taipei-granted-dark-en"))
        XCTAssertTrue(rail.contains("taipei-granted-light-zh"))
        XCTAssertTrue(rail.contains("taipei-granted-dark-zh"))
        XCTAssertTrue(rail.contains("doodle-home-empty"))
        XCTAssertTrue(rail.contains("doodle-home-allowed"))
        XCTAssertTrue(rail.contains("doodle-home-multirow"))
        XCTAssertTrue(rail.contains("--uitest-location-allowed"))
        XCTAssertFalse(rail.contains("doodle-home-dark"))
        XCTAssertFalse(rail.contains("confirmed places"))
        let location = try source(at: "SAV-E/Services/LocationService.swift")
        XCTAssertTrue(location.contains("--uitest-location-allowed"))
        XCTAssertTrue(location.contains("--uitest-location-tiantan"))
        XCTAssertTrue(location.contains("--uitest-location-daan"))
        XCTAssertTrue(location.contains("uiTestTiantan"))
        XCTAssertTrue(location.contains("uiTestDaan"))
        XCTAssertTrue(location.contains("39.882192"))
        XCTAssertTrue(location.contains("25.0296"))
        XCTAssertTrue(location.contains("25.0330"))
        XCTAssertTrue(location.contains("121.5654"))
        XCTAssertTrue(location.contains("simulatesAllowedAuthorization"))
        XCTAssertTrue(rail.contains("func captureFiveTabHomeParityRaster"))
        XCTAssertTrue(rail.contains("--uitest-location-tiantan"))
        XCTAssertTrue(rail.contains("attach(app, name: \"five-tab-home\")"))
        let seed = try source(at: "SAV-E/Services/ReviewDemoService.swift")
        XCTAssertTrue(seed.contains("--uitest-doodle-parity-fixture"))
        XCTAssertTrue(seed.contains("--uitest-home-taipei-granted"))
        XCTAssertTrue(seed.contains("--uitest-home-tpea"))
        XCTAssertTrue(seed.contains("func homeTPEAPlaces"))
        XCTAssertTrue(seed.contains("func taipeiGrantedPlaces"))
        XCTAssertTrue(seed.contains("Codex packet / spec §8"))
        XCTAssertTrue(seed.contains("SaveMemoryRecord.confirmedPlace"))
        XCTAssertFalse(seed.contains("latitude: 0"))
        let profile = try source(at: "SAV-E/Views/Profile/ProfileView.swift")
        XCTAssertTrue(profile.contains("collectionMode.places("))
        XCTAssertTrue(profile.contains("var collectionMode: SavePassportCollectionMode = .collection"))
        XCTAssertTrue(profile.contains("SaveDoodleVisitStore().recordVisit"))
        XCTAssertTrue(profile.contains("try await onUpdatePlace(updated)"))
        let map = try source(at: "SAV-E/Views/Map/SaveDoodleMapView.swift")
        XCTAssertTrue(map.contains("map.eatGo"))
        XCTAssertTrue(map.contains("\"map.city\""))
        XCTAssertTrue(catalog.contains("pendingShowOnMapPlaceID"))
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

        let map = try source(at: "SAV-E/Views/Map/SaveDoodleMapView.swift")
        let catalog = try source(at: "SAV-E/Services/SaveDoodleHomeCatalog.swift")
        let content = try source(at: "SAV-E/App/ContentView.swift")
        XCTAssertFalse(map.contains("applyMiniMapHandoff()"))
        XCTAssertFalse(map.contains("beginMiniMapHandoff()"))
        XCTAssertFalse(map.contains("consumeMiniMapHandoff()"))
        XCTAssertTrue(map.contains("SaveDoodleHomeCatalog.listedPlaces("))
        XCTAssertTrue(map.contains("session.lens = item"))
        XCTAssertTrue(map.contains("session.city = .city"))
        XCTAssertFalse(map.contains("if session.mapFollowsHomeFilter"))
        XCTAssertTrue(map.contains("map.eatGo"))
        XCTAssertTrue(map.contains("\"map.city\""))
        XCTAssertTrue(catalog.contains("pendingShowOnMapPlaceID"))
        XCTAssertTrue(content.contains("private func selectRootTab(_ tab: SaveRootTab)"))
        XCTAssertFalse(content.contains("mapFollowsHomeFilter"))
        XCTAssertFalse(content.contains("openMapFromMiniMap"))
        XCTAssertFalse(content.contains("beginMiniMapHandoff"))
        XCTAssertFalse(content.contains("onOpenMap"))
        XCTAssertFalse(content.contains("mapSurfaceID"))
        XCTAssertFalse(content.contains("resetMapVisitResidue()"))
        XCTAssertTrue(content.contains("clearSelectedMapObject()"))
        XCTAssertTrue(content.contains("onSelect: { selectRootTab($0) }"))
        XCTAssertTrue(content.contains("SaveDoodleTabIcon("))
        XCTAssertFalse(content.contains("SavePixelChromeIcon("))
        XCTAssertTrue(content.contains("private func showMapTab()"))
        XCTAssertFalse(content.contains("abandonMiniMapHandoff()"))
        XCTAssertTrue(content.contains("preservesExactSearchClue: isExactSearchSessionActive"))
        XCTAssertTrue(content.contains("hasActiveExactSearchResolution"))
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
        let catalogSource = try source(at: "SAV-E/Services/SaveDoodleHomeCatalog.swift")
        XCTAssertFalse(catalogSource.contains("save.doodle.mapFollows."))
        XCTAssertTrue(catalogSource.contains("mapFollowsHomeFilter"))
        XCTAssertFalse(catalogSource.contains("func beginMiniMapHandoff()"))
        XCTAssertFalse(catalogSource.contains("func consumeMiniMapHandoff()"))
        XCTAssertFalse(catalogSource.contains("func abandonMiniMapHandoff()"))
        XCTAssertFalse(catalogSource.contains("func applyMapTabSelection"))
        XCTAssertFalse(catalogSource.contains("pendingMiniMapHandoff"))
        let root = try source(at: "SAV-E/Views/Home/SaveRootViews.swift")
        XCTAssertFalse(root.contains("consumeMiniMapHandoff()"))
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
        XCTAssertFalse(rail.contains("func testMiniMapOpensMapWithCarriedFilterAndCityChange"))
        XCTAssertFalse(rail.contains("func testMiniMapHandoffStillRemountsEatGo"))
        XCTAssertTrue(rail.contains("func testHomeShowOnMapFocusesPlace"))
        XCTAssertTrue(rail.contains("home.row.showOnMap"))
        XCTAssertTrue(rail.contains("Home has no map component"))
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
            "func showSavedPlaceOnMap",
            "func addClueToReviewCandidate",
            "func openExactSearch",
        ] {
            XCTAssertTrue(content.contains(name), name)
        }
        XCTAssertGreaterThanOrEqual(
            content.components(separatedBy: "showMapTab()").count - 1,
            6,
            "Search, show-on-map, and list handoffs still open Map"
        )
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

    func testColdLaunchEmptyCollectionDoesNotWashPersistedCityToNearYou() {
        let tokyo = place(
            "Ichiran",
            "1-22-7 Jinnan, Shibuya City, Tokyo, Japan",
            .food,
            status: .visited
        )
        let taipei = place(
            "Fujin",
            "No. 353, Section 1, Fuxing S Rd, Da'an District, Taipei",
            .cafe
        )
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: tokyo), "tokyo")
        XCTAssertEqual(SaveDoodleHomeCatalog.cityID(for: taipei), "taipei")
        let current = SaveDoodleCitySelection.city("tokyo")

        XCTAssertEqual(
            SaveDoodleHomeCatalog.persistedCityAfterCollectionChange(
                current: current,
                places: [],
                locationDenied: false,
                collectionReady: false
            ),
            current,
            "Cold launch empty collection is not a deleted-city fallback"
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.persistedCityAfterCollectionChange(
                current: current,
                places: [tokyo],
                locationDenied: false,
                collectionReady: true
            ),
            current
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.persistedCityAfterCollectionChange(
                current: current,
                places: [taipei],
                locationDenied: false,
                collectionReady: true
            ),
            .nearYou
        )
        XCTAssertEqual(
            SaveDoodleHomeCatalog.persistedCityAfterCollectionChange(
                current: current,
                places: [taipei],
                locationDenied: true,
                collectionReady: true
            ),
            .city("taipei")
        )
    }

    func testHomeRowMetaUsesRecordedVisitNotCreatedAt() throws {
        let suite = "save.doodle.visit-meta.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let created = now.addingTimeInterval(-30 * 86_400)
        let cafe = place(
            "Grey",
            "Beijing, China",
            .cafe,
            status: .visited,
            createdAt: created
        )
        let withoutHistory = SaveDoodleHomeCatalog.rowMetaText(
            distance: 120,
            place: cafe,
            now: now,
            language: .english
        )
        XCTAssertTrue(withoutHistory.contains("visited"), withoutHistory)
        XCTAssertFalse(
            withoutHistory.contains("visited 30d ago"),
            "Save date must not be presented as the visit date"
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = SaveDoodleVisitStore(defaults: defaults, calendar: calendar, now: { now })
        XCTAssertTrue(store.recordVisit(for: cafe.id))
        let visitedAt = try XCTUnwrap(store.latestVisit(for: cafe.id))
        XCTAssertEqual(
            SaveDoodleHomeCatalog.visitStatusText(
                status: .visited,
                visitedAt: visitedAt,
                now: now,
                language: .english
            ),
            "visited today"
        )
        let withHistory = SaveDoodleHomeCatalog.rowMetaText(
            distance: 120,
            place: cafe,
            visitedAt: visitedAt,
            now: now,
            language: .english
        )
        XCTAssertTrue(withHistory.hasPrefix("120m · visited today"), withHistory)
        XCTAssertFalse(withHistory.contains("30d"))
    }

    func testHomeReviewActionUsesFounderC8442AOnLightOnly() throws {
        let theme = try source(at: "SAV-E/Extensions/Color+Theme.swift")
        let home = try source(at: "SAV-E/Views/Home/SaveDoodleHomeView.swift")
        XCTAssertEqual(SaveAtlasPalette.homeReviewActionLightHex, "C8442A")
        XCTAssertEqual(SaveAtlasPalette.homeReviewActionDarkHex, "F26B4A")
        XCTAssertEqual(SaveAtlasPalette.coralLightHex, "F26B4A")
        XCTAssertEqual(SaveAtlasPalette.coralDarkHex, "D97861")
        XCTAssertEqual(SaveAtlasPalette.brandCoralHex, "F26B4A")
        XCTAssertTrue(theme.contains("homeReviewActionLightHex = \"C8442A\""))
        XCTAssertTrue(theme.contains("static let coral = Color(light: coralLightHex, dark: coralDarkHex)"))
        XCTAssertTrue(cluesLine(in: home).contains("SaveAtlasPalette.homeReviewAction"))
        XCTAssertFalse(cluesLine(in: home).contains("SaveAtlasPalette.coral"))
        // WCAG 2.1 contrast vs Home cream #FFF9EB / dark canvas #1E1C19.
        // Recalculated for #C8442A (light Review ›) and #F26B4A (dark Review ›).
        XCTAssertEqual(
            wcagContrast("C8442A", on: SaveAtlasPalette.creamHex),
            4.63,
            accuracy: 0.02,
            "light Review › #C8442A on cream must stay AA for 13pt body"
        )
        XCTAssertEqual(
            wcagContrast("F26B4A", on: "1E1C19"),
            5.63,
            accuracy: 0.05,
            "dark Review › #F26B4A on canvas"
        )
    }

    private func cluesLine(in home: String) -> String {
        guard let start = home.range(of: "private var cluesLine") else { return "" }
        let rest = home[start.lowerBound...]
        if let end = rest.range(of: "\n    private var ") {
            return String(rest[..<end.lowerBound])
        }
        return String(rest)
    }

    private func wcagContrast(_ hex: String, on background: String) -> Double {
        func luminance(_ hex: String) -> Double {
            func channel(_ pair: Substring) -> Double {
                let value = Double(Int(pair, radix: 16) ?? 0) / 255
                return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            let r = channel(hex.prefix(2))
            let g = channel(hex.dropFirst(2).prefix(2))
            let b = channel(hex.dropFirst(4).prefix(2))
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        let first = luminance(hex)
        let second = luminance(background)
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
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
