// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("OnboardingProgress")
struct OnboardingProgressTests {
    @Test("both steps granted is complete")
    func whenBothGranted_thenComplete() {
        let progress = OnboardingProgress(accessibilityGranted: true, keyReady: true, accessibilitySkipped: false)

        #expect(progress.isComplete)
    }

    @Test("skipping Accessibility still lets the user finish once the key exists")
    func whenAccessibilitySkippedAndKeyReady_thenComplete() {
        let progress = OnboardingProgress(accessibilityGranted: false, keyReady: true, accessibilitySkipped: true)

        #expect(progress.isComplete)
    }

    @Test("without the key nothing is complete, granted or skipped")
    func whenKeyMissing_thenNotComplete() {
        #expect(!OnboardingProgress(accessibilityGranted: true, keyReady: false, accessibilitySkipped: false)
            .isComplete)
        #expect(!OnboardingProgress(accessibilityGranted: false, keyReady: false, accessibilitySkipped: true)
            .isComplete)
    }

    @Test("the key step is available before Accessibility is granted")
    func whenAccessibilityPending_thenKeyStepStillActive() {
        let progress = OnboardingProgress(accessibilityGranted: false, keyReady: false, accessibilitySkipped: false)

        #expect(progress.keyStep == .active)
        #expect(progress.accessibilityStep == .active)
    }

    @Test("a skipped Accessibility step is no longer asked for")
    func whenSkipped_thenStepIsSkipped() {
        let progress = OnboardingProgress(accessibilityGranted: false, keyReady: false, accessibilitySkipped: true)

        #expect(progress.accessibilityStep == .skipped)
        #expect(progress.offersSkip == false)
    }

    @Test("skip is offered only while Accessibility is neither granted nor skipped")
    func whenPending_thenOffersSkip() {
        #expect(OnboardingProgress(accessibilityGranted: false, keyReady: false, accessibilitySkipped: false)
            .offersSkip)
        #expect(!OnboardingProgress(accessibilityGranted: true, keyReady: false, accessibilitySkipped: false)
            .offersSkip)
    }

    @Test("a fresh install starts on the first step, which opens the shelf")
    func whenNothingIsDone_thenTheShelfStepShows() {
        let progress = OnboardingProgress(accessibilityGranted: false, keyReady: false, accessibilitySkipped: false)

        #expect(progress.screen == .shelf)
    }

    @Test("an existing key and a granted permission do not skip the first step")
    func whenEverythingExists_thenTheShelfStepStillComesFirst() {
        let progress = OnboardingProgress(accessibilityGranted: true, keyReady: true, accessibilitySkipped: false)

        #expect(progress.screen == .shelf)
    }

    @Test("the first step is not finished until the key exists, even when the person moved on")
    func whenKeyIsMissing_thenTheShelfStepStays() {
        let progress = OnboardingProgress(
            accessibilityGranted: false, keyReady: false, accessibilitySkipped: false, shelfIntroduced: true
        )

        #expect(progress.screen == .shelf)
    }

    @Test("after the shelf step the person is asked to allow pasting")
    func whenShelfIntroduced_thenPastingIsAsked() {
        let progress = OnboardingProgress(
            accessibilityGranted: false, keyReady: true, accessibilitySkipped: false, shelfIntroduced: true
        )

        #expect(progress.screen == .pasting)
    }

    @Test("a permission that is already granted does not skip the second step")
    func whenAccessibilityAlreadyGranted_thenPastingStepStillShows() {
        let progress = OnboardingProgress(
            accessibilityGranted: true, keyReady: true, accessibilitySkipped: false, shelfIntroduced: true
        )

        #expect(progress.screen == .pasting)
    }

    @Test("going on from the second step, granted or declined, shows the last step")
    func whenPastingConfirmed_thenTheLastStepShows() {
        #expect(OnboardingProgress(
            accessibilityGranted: true, keyReady: true, accessibilitySkipped: false, shelfIntroduced: true,
            pastingConfirmed: true
        ).screen == .lock)
        #expect(OnboardingProgress(
            accessibilityGranted: false, keyReady: true, accessibilitySkipped: true, shelfIntroduced: true,
            pastingConfirmed: true
        ).screen == .lock)
    }

    @Test("there are three steps, numbered one to three")
    func whenCounted_thenThreeSteps() {
        #expect(OnboardingProgress.stepCount == 3)
        #expect(OnboardingProgress.Screen.allCases.map(\.rawValue) == [1, 2, 3])
    }
}
