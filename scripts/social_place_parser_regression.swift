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

        let caseCount = cases.count + sourceIntentCases.count
        if failures.isEmpty {
            print("social place parser regression: PASS (\(caseCount) cases)")
        } else {
            print("social place parser regression: FAIL")
            failures.forEach { print("- \($0)") }
            exit(1)
        }
    }
}
