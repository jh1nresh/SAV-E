import XCTest
@testable import SAVE

/// The onboarding sample is demo content. It is auto-filled so the walkthrough
/// has something to show, which used to mean every completed onboarding queued
/// a Review Candidate for a cafe that does not exist — the shipped vault held
/// three "Hidden Moon Cafe" clues and four unparseable ones, 7 of its 116
/// pending clues.
final class OnboardingSampleClueTests: XCTestCase {
    @MainActor
    func testUntouchedSampleIsNotImported() {
        for language in [AppLanguage.english, .traditionalChinese] {
            let sample = OnboardingView.sampleClue(language: language)
            XCTAssertNil(
                OnboardingView.clueWorthKeeping(rawClue: sample, language: language),
                "the untouched \(language) sample must not become a Review Candidate"
            )
        }
    }

    @MainActor
    func testSampleWithSurroundingWhitespaceIsStillTheSample() {
        let sample = OnboardingView.sampleClue(language: .english)
        XCTAssertNil(OnboardingView.clueWorthKeeping(rawClue: "  \(sample)\n", language: .english))
    }

    @MainActor
    func testAnEditedSampleIsTheUsersOwnClue() {
        let edited = OnboardingView.sampleClue(language: .english) + " in Taipei"
        XCTAssertEqual(
            OnboardingView.clueWorthKeeping(rawClue: edited, language: .english),
            edited
        )
    }

    @MainActor
    func testARealClueIsKept() {
        XCTAssertEqual(
            OnboardingView.clueWorthKeeping(rawClue: " 鼎泰豐 信義店 ", language: .traditionalChinese),
            "鼎泰豐 信義店"
        )
    }

    @MainActor
    func testEmptyClueIsNotImported() {
        XCTAssertNil(OnboardingView.clueWorthKeeping(rawClue: "   ", language: .english))
    }

    @MainActor
    func testTheSampleInOneLanguageIsNotTreatedAsAClueInTheOther() {
        // Switching language mid-onboarding leaves the other sample in the
        // field; it is still demo content, not something the user wrote.
        let chineseSample = OnboardingView.sampleClue(language: .traditionalChinese)
        XCTAssertNil(OnboardingView.clueWorthKeeping(rawClue: chineseSample, language: .english))
    }
}
