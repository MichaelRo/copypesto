// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The first-launch offer to bring a history over")
struct ImportOfferTests {
    @Test("each source names its apps by bundle identifier, so an install is found without reading anyone's data")
    func whenSources_thenBundleIdentifiers() {
        #expect(ImportSource.paste.bundleIDs == ["com.wiheads.paste", "com.wiheads.paste-setapp"])
        #expect(ImportSource.maccy.bundleIDs == ["org.p0deje.Maccy"])
        #expect(ImportSource.alfred.bundleIDs == ["com.runningwithcrayons.Alfred"])
        #expect(ImportSource.cleanclip.bundleIDs == ["com.antiless.cleanclip.mac"])
        #expect(ImportSource.pastenow.bundleIDs == ["app.pastenow.PasteNow"])
        #expect(ImportSource.copyclip.bundleIDs == ["com.fiplab.clipboard", "com.fiplab.copyclip"])
        #expect(ImportSource.pastepal.bundleIDs == ["com.onmyway133.PastePal", "com.cmhaertling.PastePal"])
        #expect(ImportSource.pastebot.bundleIDs == ["com.tapbots.Pastebot3Mac", "com.tapbots.PastebotMac"])
        #expect(ImportSource.clipy.bundleIDs == ["com.clipy-app.Clipy"])
        #expect(ImportSource.flycut.bundleIDs == ["com.generalarcade.flycut"])
        #expect(ImportSource.unclutter.bundleIDs == ["com.softwareambience.Unclutter"])
        #expect(ImportSource.allCases.map(\.name) == [
            "Paste", "Maccy", "Alfred", "CleanClip", "PasteNow",
            "CopyClip", "PastePal", "Pastebot", "Clipy", "Flycut", "Unclutter"
        ])
    }

    @Test("nothing is offered before setup is done, after an answer, or when nothing is installed")
    func whenNotTheTime_thenNoOffer() {
        #expect(ImportOfferPolicy.sources(installed: [.maccy], alreadyOffered: false, hasOnboarded: false).isEmpty)
        #expect(ImportOfferPolicy.sources(installed: [.maccy], alreadyOffered: true, hasOnboarded: true).isEmpty)
        #expect(ImportOfferPolicy.sources(installed: [], alreadyOffered: false, hasOnboarded: true).isEmpty)
    }

    @Test("every installed app is offered, in the order of the import list: Paste, then Maccy, then Alfred")
    func whenSeveral_thenAllInImportOrder() {
        #expect(ImportOfferPolicy.sources(
            installed: [.alfred, .maccy, .paste], alreadyOffered: false, hasOnboarded: true
        ) == [.paste, .maccy, .alfred])
        #expect(ImportOfferPolicy.sources(
            installed: [.unclutter, .alfred], alreadyOffered: false, hasOnboarded: true
        ) == [.alfred, .unclutter])
        #expect(ImportOfferPolicy.sources(installed: [.alfred], alreadyOffered: false, hasOnboarded: true) == [.alfred])
    }

    @Test("an app listed twice is offered once")
    func whenDuplicates_thenOnce() {
        #expect(ImportOfferPolicy.sources(
            installed: [.maccy, .maccy], alreadyOffered: false, hasOnboarded: true
        ) == [.maccy])
    }

    @Test("the banner names up to three apps, and past three the first two and a count", arguments: [
        ([ImportSource.maccy], ["Maccy"], 0),
        ([.paste, .maccy], ["Paste", "Maccy"], 0),
        ([.paste, .maccy, .alfred], ["Paste", "Maccy", "Alfred"], 0),
        ([.paste, .maccy, .alfred, .clipy], ["Paste", "Maccy"], 2),
        (ImportSource.allCases, ["Paste", "Maccy"], 9)
    ])
    func whenBanner_thenNamesAndMore(sources: [ImportSource], shown: [String], more: Int) {
        let names = ImportOfferPolicy.bannerNames(for: sources)
        #expect(names.shown == shown)
        #expect(names.more == more)
    }

    @Test("a UI-test launch finds the apps its fixture names, in import order, and a hosted test finds none")
    func whenDetector_thenFixtureOrNone() {
        #expect(FixtureAppDetector(fixture: "maccy").installed() == [.maccy])
        #expect(FixtureAppDetector(fixture: "paste").installed() == [.paste])
        #expect(FixtureAppDetector(fixture: "maccy,paste").installed() == [.paste, .maccy])
        #expect(FixtureAppDetector(fixture: "maccy,unknown").installed() == [.maccy])
        #expect(FixtureAppDetector(fixture: nil).installed().isEmpty)
        #expect(FixtureAppDetector(fixture: "unknown").installed().isEmpty)
    }

    @Test(
        "the offer is remembered in a setting that is registered, off until an answer, and not carried to another Mac"
    )
    func whenSetting_thenRegistered() {
        #expect(Setting.importOffered.defaultValue == false)
        #expect(Setting.importOffered.name == "importOffered")
        #expect(Setting.allNames.contains(Setting.importOffered.name))
    }
}
