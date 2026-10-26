// SPDX-License-Identifier: MIT
import XCTest
@testable import PestoCore

final class NSFWURLDetectorTests: XCTestCase {
    // MARK: - Blocklist

    func test_blocklistedDomain_isExplicit() {
        XCTAssertTrue(NSFWURLDetector.isExplicit(urlString: "https://pornhub.com/video/123"))
    }

    func test_blocklistedDomainWithWwwPrefix_isExplicit() {
        XCTAssertTrue(NSFWURLDetector.isExplicit(urlString: "https://www.pornhub.com/video"))
    }

    func test_blocklistedSubdomain_isExplicit() {
        XCTAssertTrue(NSFWURLDetector.isExplicit(urlString: "https://sub.xvideos.com/path"))
    }

    // MARK: - Hosts that run words together

    func test_hostWithAStrongStemInsideOneLabel_isExplicit() {
        for url in [
            "https://namethatpornad.com/", "https://www.freepornvideos.example/x", "https://myhentaiworld.net/a",
            "https://nsfwpics.org/1", "https://best-xvideos-clone.io/"
        ] {
            XCTAssertTrue(NSFWURLDetector.isExplicit(urlString: url), url)
        }
    }

    func test_innocentHostsThatContainTheLettersAreNotExplicit() {
        for url in [
            "https://www.middlesex.ac.uk/", "https://essex.gov.uk/", "https://sussex.ac.uk/",
            "https://scunthorpe.gov.uk/",
            "https://popcorn.example.com/", "https://xxxl-sizes.example/", "https://harborcity.example/porcelain",
            "https://analytics.example.com/"
        ] {
            XCTAssertFalse(NSFWURLDetector.isExplicit(urlString: url), url)
        }
    }

    // MARK: - Safe domains

    func test_safeDomain_isNotExplicit() {
        XCTAssertFalse(NSFWURLDetector.isExplicit(urlString: "https://github.com/user/project"))
    }

    func test_appleCom_isNotExplicit() {
        XCTAssertFalse(NSFWURLDetector.isExplicit(urlString: "https://www.apple.com/iphone"))
    }

    func test_emptyString_isNotExplicit() {
        XCTAssertFalse(NSFWURLDetector.isExplicit(urlString: ""))
    }

    func test_malformedURL_isNotExplicit() {
        XCTAssertFalse(NSFWURLDetector.isExplicit(urlString: "not a url at all"))
    }

    // MARK: - Keyword scoring in path

    func test_strongKeywordInPath_isExplicit() {
        XCTAssertTrue(NSFWURLDetector.isExplicit(urlString: "https://example.com/porn/video"))
    }

    func test_xxxKeywordInHost_isExplicit() {
        XCTAssertTrue(NSFWURLDetector.isExplicit(urlString: "https://xxx.example.com/gallery"))
    }

    func test_neutralPathOnSafeDomain_isNotExplicit() {
        XCTAssertFalse(NSFWURLDetector.isExplicit(urlString: "https://stackoverflow.com/questions/adult-learning"))
    }

    // MARK: - Internal: isBlocklisted

    func test_isBlocklisted_returnsTrueForKnownDomain() {
        XCTAssertTrue(NSFWURLDetector.isBlocklisted(host: "pornhub.com"))
    }

    func test_isBlocklisted_stripsWwwPrefix() {
        XCTAssertTrue(NSFWURLDetector.isBlocklisted(host: "www.xvideos.com"))
    }

    func test_isBlocklisted_returnsFalseForSafeDomain() {
        XCTAssertFalse(NSFWURLDetector.isBlocklisted(host: "apple.com"))
    }

    // MARK: - Internal: keywordScore

    func test_keywordScore_strongHit_returnsHighScore() {
        let score = NSFWURLDetector.keywordScore(in: "porn video")
        XCTAssertGreaterThanOrEqual(score, 0.85)
    }

    func test_keywordScore_noHits_returnsZero() {
        let score = NSFWURLDetector.keywordScore(in: "swift programming tutorial")
        XCTAssertEqual(score, 0)
    }

    func test_keywordScore_singleWeakHit_returnsBelowThreshold() {
        let score = NSFWURLDetector.keywordScore(in: "adult education resources")
        XCTAssertLessThan(score, 0.85)
    }

    // MARK: - Newly added blocklist entries

    func test_eromeDomain_isExplicit() {
        XCTAssertTrue(NSFWURLDetector.isExplicit(urlString: "https://www.erome.com/a/AbCd1234"))
    }

    func test_redgifsDomain_isExplicit() {
        XCTAssertTrue(NSFWURLDetector.isExplicit(urlString: "https://www.redgifs.com/watch/foo"))
    }

    func test_redgifsCDNSubdomain_isExplicit() {
        XCTAssertTrue(NSFWURLDetector.isExplicit(urlString: "https://media.redgifs.com/Foo.mp4"))
    }

    func test_coomerDomain_isExplicit() {
        XCTAssertTrue(NSFWURLDetector.isExplicit(urlString: "https://coomer.su/onlyfans/user/foo"))
    }

    // MARK: - Metadata-aware classification

    func test_metadataAware_opaqueHostWithExplicitTitle_isExplicit() {
        // CDN-style URL whose host is not in the blocklist; the title carries the signal.
        let signals = NSFWURLDetector.LinkPreviewSignals(
            title: "Free Porn Videos — Sample",
            description: nil,
            siteName: nil
        )
        XCTAssertTrue(NSFWURLDetector.isExplicit(
            urlString: "https://cdn-foo.example.net/asset/abc",
            metadata: signals
        ))
    }

    func test_metadataAware_safeURLWithSafeMetadata_isNotExplicit() {
        let signals = NSFWURLDetector.LinkPreviewSignals(
            title: "Swift Programming Tutorial",
            description: "Learn Swift from scratch",
            siteName: "GitHub"
        )
        XCTAssertFalse(NSFWURLDetector.isExplicit(
            urlString: "https://github.com/user/swift-tutorial",
            metadata: signals
        ))
    }

    func test_metadataAware_redditMatureContentPrefix_isExplicit() {
        let signals = NSFWURLDetector.LinkPreviewSignals(
            title: "[Mature Content] Some Reddit post title",
            description: nil,
            siteName: "Reddit"
        )
        XCTAssertTrue(NSFWURLDetector.isExplicit(
            urlString: "https://www.reddit.com/r/talkedintoit/s/dj3NIjoDUu",
            metadata: signals
        ))
    }

    func test_metadataAware_nilMetadata_matchesHostOnlyVariant() {
        XCTAssertEqual(
            NSFWURLDetector.isExplicit(urlString: "https://www.erome.com/a/foo"),
            NSFWURLDetector.isExplicit(urlString: "https://www.erome.com/a/foo", metadata: nil)
        )
    }
}
