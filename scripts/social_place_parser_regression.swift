import Foundation

struct ParserRegressionCase {
    let name: String
    let sourceURL: String
    let evidence: String
    let expectedName: String
    let expectedAddress: String?
    let rejectedNameFragments: [String]
    let rejectedAddressFragments: [String]
}

struct SourceIntentRegressionCase {
    let name: String
    let sourceURL: String
    let evidence: String
    let ocrLines: [String]
    let expectedIntent: SocialPlaceSourceIntent
    let expectedUnderstandingType: SocialPlaceSourceType
    let expectedTopic: String?
    let expectedRegion: String?
    let expectedCandidateCount: Int
}

let cases: [ParserRegressionCase] = [
    ParserRegressionCase(
        name: "Instagram launch headline extracts Standard Bread and pin location",
        sourceURL: "https://www.instagram.com/p/DY1nVh0n8mu/",
        evidence: """
        GIRLSTALK on Instagram: "#GIRLSTALK美食
        在韓國掀起排隊熱潮的法式吐司 Standard Bread 5/29即將在台北信義新天地A11正式開幕！

        主打「每30分鐘現烤出爐」的吐司，加上獨特的撕開沾醬吐司吃法，在韓國迅速爆紅。就連 BLACKPINK Jisoo、Super Junior 銀赫都曾到店朝聖！

        品牌必點招牌 「焦糖烤布蕾法式吐司」 外層炙燒成金黃焦糖脆殼，內層則柔軟濕潤，一口能同時吃到焦糖香與蛋奶香，另外更推薦「杜拜巧克力法式吐司」，吃得到開心果酥脆口感✨搭配歐洲鄉村風格的門市空間與剛出爐的奶油麵包香氣，讓信義區多一間新的排隊打卡美食！

        📍台北信義新天地 A11 B2
        📅 開幕日期：5/29正式開幕
        #StandardBread #韓國咖啡 #聖水洞美食 #Na編"
        """,
        expectedName: "Standard Bread",
        expectedAddress: "台北信義新天地 A11 B2",
        rejectedNameFragments: ["5/29", "在韓國掀起", "法式吐司 Standard Bread 5"],
        rejectedAddressFragments: ["品牌必點招牌", "焦糖烤布蕾", "現烤出爐"]
    ),
    ParserRegressionCase(
        name: "Instagram Taiwan headline uses quoted restaurant name instead of caption headline",
        sourceURL: "https://www.instagram.com/p/DY4EPGgkckS/",
        evidence: """
        波波發胖 on Instagram: "#波波發胖 ➡西門也韓其林了！弘大必喝「百年土種參雞湯」
        台北市萬華區萬壽里中華路一段88號3樓
        #西門美食 #台北美食 #韓式料理"
        """,
        expectedName: "百年土種參雞湯",
        expectedAddress: "台北市萬華區萬壽里中華路一段88號3樓",
        rejectedNameFragments: ["#波波發胖", "西門也韓其林", "弘大必喝"],
        rejectedAddressFragments: []
    )
]

// Public dogfood caption, with tracking parameters omitted. Source dates/prices
// are unverified claims; this fixture tests extraction, not their accuracy.
let museumCaption = """
George Lucas is about to open a museum, and he funded it himself. The Lucas Museum of Narrative Art opens in Exposition Park, Los Angeles, on Tuesday, September 22, after twelve years and more than a billion dollars of his own money. Ma Yansong of MAD lifted the building clear of the ground on a curving underbelly, so the first space visitors reach is not a lobby but a shaded plaza that open on all sides to the park. Inside, more than 1,300 works across some thirty galleries put van Gogh, Frida Kahlo and Jacob Lawrence in the same institution as Beatrix Potter, Charles Schulz, Robert Crumb and Takashi Murakami. Admission is $25, the Research Library is free to walk into, and anyone living in the surrounding 90037 zip code gets in free with a guest. Read more via link in bio.
"""

struct ProseVenueRegressionCase {
    let caption: String
    let venues: [String: String]
}

let proseVenueCases: [ProseVenueRegressionCase] = [
    .init(caption: museumCaption, venues: ["Lucas Museum of Narrative Art": "Exposition Park, Los Angeles"]),
    .init(caption: "The Aurora Museum of Design is located in Wellington, New Zealand.", venues: ["Aurora Museum of Design": "Wellington, New Zealand"]),
    .init(caption: "Northbank Gallery sits near Bristol. Cedar Observatory stands in Bath.", venues: ["Northbank Gallery": "Bristol", "Cedar Observatory": "Bath"]),
    .init(caption: "Maple Restaurant reopens at Harbor Square, Boston, after renovations.", venues: ["Maple Restaurant": "Harbor Square, Boston"]),
    .init(caption: "Museum of Modern Craft can be found in Portland.", venues: ["Museum of Modern Craft": "Portland"]),
    .init(caption: "Aurora Museum opens in London\nTickets Available Soon", venues: ["Aurora Museum": "London"]),
    .init(caption: "Coming Soon\nAurora Museum opens in London", venues: ["Aurora Museum": "London"]),
    .init(caption: "Coming Soon\r\nAurora Museum opens in London\r\nTickets Available Soon", venues: ["Aurora Museum": "London"]),
    .init(caption: "Aurora Museum opens in London,\nTickets Available Soon", venues: ["Aurora Museum": "London"]),
    .init(caption: "Aurora Museum opens in London\nNorthbank Gallery sits near Bristol", venues: ["Aurora Museum": "London", "Northbank Gallery": "Bristol"]),
    .init(caption: "Aurora Museum\topens\tin\tLondon", venues: ["Aurora Museum": "London"]),
    .init(caption: "Aurora Museum opens\nin London", venues: [:]),
    .init(caption: "Aurora Museum opens in Rio de Janeiro.", venues: ["Aurora Museum": "Rio de Janeiro"]),
    .init(caption: "Aurora Museum opens in St. Louis.", venues: ["Aurora Museum": "St. Louis"]),
    .init(caption: "Aurora Museum opens in Washington, D.C.", venues: ["Aurora Museum": "Washington, D.C."]),
    .init(caption: "Coming Soon\rAurora Museum opens in London\rTickets Available Soon", venues: ["Aurora Museum": "London"]),
    .init(caption: "Coming Soon\r\n\r\nAurora Museum opens in St. Louis.\r\nTickets Available Soon", venues: ["Aurora Museum": "St. Louis"]),
    .init(caption: "Aurora Museum opens in Washington,D.C.\nTickets Available Soon", venues: ["Aurora Museum": "Washington,D.C."]),
    .init(caption: "Aurora Museum opens in Rio de Janeiro, Brazil.", venues: ["Aurora Museum": "Rio de Janeiro, Brazil"]),
    .init(caption: "Aurora Museum opens in San Juan de la Cruz.", venues: ["Aurora Museum": "San Juan de la Cruz"]),
    .init(caption: "Aurora Museum opens in St. Louis. Cedar Gallery opens in Washington, D.C.", venues: ["Aurora Museum": "St. Louis", "Cedar Gallery": "Washington, D.C."]),
    .init(caption: "Aurora Museum opens in May in London.", venues: ["Aurora Museum": "London"]),
    .init(caption: "Aurora Museum opens at Noon in London.", venues: ["Aurora Museum": "London"]),
    .init(caption: "Aurora Museum opens near Christmas in London.", venues: ["Aurora Museum": "London"]),
    .init(caption: "Aurora Museum opens at Noon.", venues: [:]),
    .init(caption: "Aurora Museum opens near Christmas.", venues: [:]),
    .init(caption: "Aurora Museum opens in May.", venues: [:]),
    .init(caption: "Aurora Museum opens in Mayfair.", venues: ["Aurora Museum": "Mayfair"]),
    .init(caption: "St. Louis Museum opens in Missouri.", venues: ["St. Louis Museum": "Missouri"]),
    .init(caption: "Solomon R. Guggenheim Museum is located in New York.", venues: ["Solomon R. Guggenheim Museum": "New York"]),
    .init(caption: "J. Paul Getty Museum is located in Los Angeles.", venues: ["J. Paul Getty Museum": "Los Angeles"]),
    .init(caption: "Welcome. St. Louis Museum opens in Missouri.", venues: ["St. Louis Museum": "Missouri"]),
    .init(caption: "Aurora Museum opens in Christmas Island.", venues: ["Aurora Museum": "Christmas Island"]),
    .init(caption: "Aurora Museum opens in Sunset District.", venues: ["Aurora Museum": "Sunset District"]),
    .init(caption: "Aurora Museum opens in São Paulo.", venues: ["Aurora Museum": "São Paulo"]),
    .init(caption: "Aurora Museum opens in Montréal.", venues: ["Aurora Museum": "Montréal"]),
    .init(caption: "Étoile Museum opens in Zürich.", venues: ["Étoile Museum": "Zürich"]),
    .init(caption: "Café Étoile Restaurant is located in Québec.", venues: ["Café Étoile Restaurant": "Québec"]),
    .init(caption: "Aurora Museum opens in São Paulo, Brazil.", venues: ["Aurora Museum": "São Paulo, Brazil"]),
    .init(caption: "Aurora Museum opens in Rio de", venues: [:]),
    .init(caption: "Aurora Museum opens in Washington, D.Curious", venues: [:]),
    .init(caption: "Aurora Museum opens in St.\nLouis", venues: [:]),
    .init(caption: "", venues: [:]),
    .init(caption: "George Lucas and Frida Kahlo inspired my art today in Los Angeles.", venues: [:]),
    .init(caption: "George Lucas is about to open a museum in Los Angeles.", venues: [:]),
    .init(caption: "The museum opens in Los Angeles, but no name has been announced.", venues: [:]),
    .init(caption: "This Museum opens in London.", venues: [:]),
    .init(caption: "Museum Girl is located in London. Follow her art account.", venues: [:]),
    .init(caption: "Aurora Museum Team is located in London.", venues: [:]),
    .init(caption: "The Lucas Museum of Narrative Art appears in a painting by Frida Kahlo.", venues: [:]),
    .init(caption: "Aurora Museum opens in my imagination. A gallery of memories.", venues: [:]),
    .init(caption: "Aurora Museum opens in ??? <script>alert(1)</script>", venues: [:]),
    .init(caption: "Log in to Instagram. Sign up to see photos and videos from your friends.", venues: [:])
]

let sourceIntentCases: [SourceIntentRegressionCase] = [
    SourceIntentRegressionCase(
        name: "Instagram Reel cover OCR classifies hidden in-video Tainan ice-shop list as place-bearing list",
        sourceURL: "https://www.instagram.com/reel/DYYmBrXzw2S/",
        evidence: """
        小妡（ㄒㄧㄣ）台南美食/台北美食 Tai Hsin Yu on Instagram: "台南的夏天有多熱？
        熱到每天都想衝去吃刨冰
        吃下去整個人瞬間被救回來

        不管是芒果冰、粉粿冰、八寶冰還是布丁冰
        只要端上桌，心情直接好一半

        #台南 #台南小吃#台南冰品"
        """,
        ocrLines: ["台南夏天吃什麼", "推薦４間冰店"],
        expectedIntent: .multiPlaceList,
        expectedUnderstandingType: .multiPlaceList,
        expectedTopic: "推薦４間冰店",
        expectedRegion: "台南",
        expectedCandidateCount: 0
    )
]

@main
struct SocialPlaceParserRegressionRunner {
    static func main() {
        let parser = SocialPlaceParser()
        var failures: [String] = []

        for testCase in cases {
            let analysis = parser.analyze(
                evidence: SocialPlaceSourceEvidence(
                    sourceURL: testCase.sourceURL,
                    resolvedURL: nil,
                    sharedTitle: nil,
                    sharedText: testCase.evidence,
                    metadataTitle: nil,
                    metadataDescription: nil,
                    ocrLines: []
                )
            )

            guard let first = analysis.placesFound.first else {
                failures.append("\(testCase.name): no places found; intent=\(analysis.sourceIntent.rawValue), type=\(analysis.sourceType.rawValue)")
                continue
            }

            if first.displayName != testCase.expectedName {
                failures.append("\(testCase.name): expected name \(testCase.expectedName), got \(first.displayName)")
            }
            if let expectedAddress = testCase.expectedAddress, first.locationClues.first != expectedAddress {
                failures.append("\(testCase.name): expected address \(expectedAddress), got \(first.locationClues.first ?? "nil")")
            }
            for fragment in testCase.rejectedNameFragments where first.displayName.contains(fragment) {
                failures.append("\(testCase.name): rejected name fragment leaked: \(fragment)")
            }
            for fragment in testCase.rejectedAddressFragments where first.locationClues.joined(separator: " | ").contains(fragment) {
                failures.append("\(testCase.name): rejected address fragment leaked: \(fragment)")
            }
            // The classifier reports modern singlePlaceRecommendation for what
            // older cases called singleVenuePost; both mean one-venue source.
            let isSingleVenueType = analysis.sourceType == .singleVenuePost || analysis.sourceType == .singlePlaceRecommendation
            if !isSingleVenueType || analysis.sourceIntent != .singleVenuePost {
                failures.append("\(testCase.name): expected single venue post; got type=\(analysis.sourceType.rawValue), intent=\(analysis.sourceIntent.rawValue)")
            }
        }

        for testCase in sourceIntentCases {
            let analysis = parser.analyze(
                evidence: SocialPlaceSourceEvidence(
                    sourceURL: testCase.sourceURL,
                    resolvedURL: nil,
                    sharedTitle: nil,
                    sharedText: testCase.evidence,
                    metadataTitle: nil,
                    metadataDescription: nil,
                    ocrLines: testCase.ocrLines
                )
            )

            if analysis.sourceIntent != testCase.expectedIntent {
                failures.append("\(testCase.name): expected intent \(testCase.expectedIntent.rawValue), got \(analysis.sourceIntent.rawValue)")
            }
            if analysis.sourceType != testCase.expectedUnderstandingType {
                failures.append("\(testCase.name): expected type \(testCase.expectedUnderstandingType.rawValue), got \(analysis.sourceType.rawValue)")
            }
            if analysis.placesFound.count != testCase.expectedCandidateCount {
                failures.append("\(testCase.name): expected \(testCase.expectedCandidateCount) candidates, got \(analysis.placesFound.count)")
            }
            if !analysis.isPlaceBearing {
                failures.append("\(testCase.name): expected place-bearing source")
            }
            if let expectedTopic = testCase.expectedTopic, analysis.topic != expectedTopic {
                failures.append("\(testCase.name): expected topic \(expectedTopic), got \(analysis.topic ?? "nil")")
            }
            if let expectedRegion = testCase.expectedRegion, analysis.regionClues.first != expectedRegion {
                failures.append("\(testCase.name): expected first region \(expectedRegion), got \(analysis.regionClues.first ?? "nil")")
            }
            if let expectedTopic = testCase.expectedTopic,
               !analysis.recoveryHints.contains(where: { $0.queryFragment == expectedTopic }) {
                failures.append("\(testCase.name): expected recovery hint for topic \(expectedTopic)")
            }
        }

        var additionalCaseCount = 0
        for testCase in proseVenueCases {
            // Same caption path for both clean and query-bearing links; the
            // synthetic query is not a copied user token.
            for suffix in ["", "?utm_source=regression"] {
                additionalCaseCount += 1
                let source = "https://www.instagram.com/p/Dc11noPGkTO/" + suffix
                let bundle = SocialShareTextNormalizer.normalize(source)
                if bundle.platform != .instagram || bundle.primaryURLString != source {
                    failures.append("Normalizer lost query-bearing Instagram source")
                }
                let analysis = parser.analyze(evidence: SocialPlaceSourceEvidence(
                    sourceURL: source, resolvedURL: nil, sharedTitle: nil,
                    sharedText: testCase.caption, metadataTitle: nil,
                    metadataDescription: nil, ocrLines: []
                ))
                let actual = Dictionary(analysis.placesFound.map { ($0.displayName, $0.locationClues.joined(separator: " | ")) }, uniquingKeysWith: { first, _ in first })
                if actual != testCase.venues || analysis.placesFound.count != testCase.venues.count {
                    failures.append("Prose fixture: expected \(testCase.venues), got \(actual) for \(testCase.caption.prefix(100))")
                }
                if analysis.resolverDecision.allowsDirectSave {
                    failures.append("Prose/source fixture must never allow direct save")
                }
                if !testCase.venues.isEmpty {
                    if !analysis.isPlaceBearing || !analysis.recoveryStrategies.contains(.publicSearchRecovery) {
                        failures.append("Named prose venue must remain eligible for corroboration")
                    }
                    for candidate in analysis.placesFound {
                        if testCase.caption.contains("\r\n" + candidate.displayName),
                           candidate.evidence.contains(where: {
                               $0.source == .captionSentence && $0.role == .venueName && $0.line.hasPrefix("\n")
                           }) {
                            failures.append("Prose evidence starts halfway through a CRLF character")
                        }
                        if !candidate.evidence.contains(where: { $0.role == .sourceAccount && $0.value == source }) {
                            failures.append("Prose candidate lost original source")
                        }
                        if candidate.evidence.contains(where: { $0.role == .address }) {
                            failures.append("Prose region clue must not become a verified street address")
                        }
                        if !candidate.missingInfo.contains("Prose location clue; verify exact venue and address") {
                            failures.append("Prose candidate lost verification requirement")
                        }
                    }
                }
            }
        }

        additionalCaseCount += 1
        let mixedEvidence = parser.analyze(evidence: SocialPlaceSourceEvidence(
            sourceURL: "https://www.instagram.com/p/FixturePost/", resolvedURL: nil,
            sharedTitle: nil,
            sharedText: "Dinner at Harbor Square, Boston. Aurora Museum opens at Harbor Square, Bristol.",
            metadataTitle: nil, metadataDescription: nil, ocrLines: []
        ))
        if !mixedEvidence.placesFound.contains(where: { $0.displayName == "Harbor Square" }) ||
            !mixedEvidence.placesFound.contains(where: { $0.displayName == "Aurora Museum" }) {
            failures.append("Prose location suppression removed a separate earlier venue mention")
        }

        additionalCaseCount += 1
        let laterVenue = parser.analyze(evidence: SocialPlaceSourceEvidence(
            sourceURL: "https://www.instagram.com/p/FixturePost/", resolvedURL: nil,
            sharedTitle: nil,
            sharedText: "Aurora Museum opens at Harbor Square, Bristol. Dinner at Sunset Cafe, Boston.",
            metadataTitle: nil, metadataDescription: nil, ocrLines: []
        ))
        let laterNames = Set(laterVenue.placesFound.map(\.displayName))
        if !laterNames.contains("Aurora Museum") || !laterNames.contains("Sunset Cafe") || laterNames.contains("Harbor Square") {
            failures.append("Suppressed prose location prevented a later independent venue")
        }
        if laterVenue.resolverDecision.allowsDirectSave {
            failures.append("Mixed prose candidates must remain unconfirmed")
        }

        for name in ["Noon Cafe", "Home Cafe", "Midnight Garden"] {
            additionalCaseCount += 1
            let analysis = parser.analyze(evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/p/FixturePost/", resolvedURL: nil,
                sharedTitle: nil, sharedText: "Dinner at \(name), Boston. Meet at Home, later.",
                metadataTitle: nil, metadataDescription: nil, ocrLines: []
            ))
            if !analysis.placesFound.contains(where: { $0.displayName == name }) || analysis.placesFound.contains(where: { $0.displayName == "Home" }) {
                failures.append("Non-venue filter lost specific venue: \(name)")
            }
        }
        for falseName in ["Noon", "Home", "Link In Bio", "Midnight", "Our Website"] {
            additionalCaseCount += 1
            let analysis = parser.analyze(evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/p/FixturePost/", resolvedURL: nil,
                sharedTitle: nil,
                sharedText: "Dinner at Sunset Cafe, Boston. Meet at \(falseName), then leave.\n📍123 Main Street, Boston",
                metadataTitle: nil, metadataDescription: nil, ocrLines: []
            ))
            if !analysis.placesFound.contains(where: { $0.displayName == "Sunset Cafe" }) ||
                analysis.placesFound.contains(where: { $0.displayName == falseName }) {
                failures.append("Expanded at matches accepted non-venue \(falseName)")
            }
        }
        for address in ["123 Main Street, Boston", "123 Main St., Boston", "123 Main Street, Montréal"] {
            additionalCaseCount += 1
            let analysis = parser.analyze(evidence: SocialPlaceSourceEvidence(
                sourceURL: "https://www.instagram.com/p/FixturePost/", resolvedURL: nil,
                sharedTitle: nil, sharedText: "Aurora Museum is located at \(address).",
                metadataTitle: nil, metadataDescription: nil, ocrLines: []
            ))
            guard let venue = analysis.placesFound.first(where: { $0.displayName == "Aurora Museum" }) else {
                failures.append("Numeric street address lost named venue: \(address)")
                continue
            }
            if !venue.locationClues.contains(address) || analysis.resolverDecision.allowsDirectSave ||
                !venue.missingInfo.contains("Prose location clue; verify exact venue and address") {
                failures.append("Numeric address lost unverified named association: \(address)")
            }
        }

        let redirectSources = [
            "https://www.instagram.com/p/FixturePost/",
            "https://www.instagram.com/reel/FixturePost/?utm_source=regression"
        ]
        let deadEnds = [
            "https://www.instagram.com/accounts/login/?next=%2Fp%2FFixturePost%2F",
            "https://www.instagram.com/challenge/",
            "https://www.instagram.com/accounts/suspended/",
            "https://account.dianping.com/login?redir=https%3A%2F%2Fwww.dianping.com%2Fshop%2Fother",
            "https://www.instagram.com/",
            "https://www.instagram.com/404/",
            "https://www.instagram.com/p/UnrelatedPost/",
            "https://www.instagram.com/p/FixturePost/comments/",
            "https://www.instagram.com.evil.example/p/FixturePost/",
            "https://example.com/accounts/login/?next=https://www.instagram.com/p/FixturePost/",
            "http://www.instagram.com/p/FixturePost/"
        ]
        for source in redirectSources {
            let original = URL(string: source)!
            for destination in deadEnds {
                additionalCaseCount += 1
                let actual = SocialShareURLCanonicalizer.analysisURL(originalURL: original, resolvedURL: URL(string: destination)!)
                if actual != original {
                    failures.append("Instagram redirect replaced original post: \(destination)")
                }
            }
            for resolved in [nil, URL(string: "https://instagram.com/reel/FixturePost/")] {
                additionalCaseCount += 1
                let actual = SocialShareURLCanonicalizer.analysisURL(originalURL: original, resolvedURL: resolved)
                if actual != (resolved ?? original) {
                    failures.append("Instagram same-post or unavailable-response resolution regressed")
                }
            }
        }
        // Other providers and legitimate Instagram share-to-post expansion keep
        // their existing redirect behavior.
        for source in ["https://example.com/article", "https://www.instagram.com/share/reel/ShareCode/"] {
            additionalCaseCount += 1
            let target = URL(string: "https://www.instagram.com/reel/ExpandedPost/")!
            if SocialShareURLCanonicalizer.analysisURL(originalURL: URL(string: source)!, resolvedURL: target) != target {
                failures.append("Non-post redirect expansion regressed")
            }
        }

        let caseCount = cases.count + sourceIntentCases.count + additionalCaseCount
        if failures.isEmpty {
            print("social place parser regression: PASS (\(caseCount) cases)")
        } else {
            print("social place parser regression: FAIL")
            failures.forEach { print("- \($0)") }
            exit(1)
        }
    }
}
