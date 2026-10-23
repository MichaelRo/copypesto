// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Which copied links may be fetched for a preview")
struct LinkPreviewEligibilityTests {
    private func eligible(_ text: String) -> Bool {
        LinkPreviewEligibility.isEligible(URL(string: text) ?? URL(fileURLWithPath: "/"))
    }

    @Test("ordinary public pages are fetched", arguments: [
        "https://example.com/recipes/pesto-genovese",
        "http://example.com/",
        "https://en.wikipedia.org/wiki/Pesto",
        "https://example.com/search?q=basil&page=2"
    ])
    func whenOrdinary_thenEligible(url: String) {
        #expect(eligible(url), "\(url)")
    }

    @Test("links that can carry a secret or trigger an action are never fetched", arguments: [
        "https://example.com/reset?token=abc123",
        "https://example.com/verify?code=884211",
        "https://example.com/login?access_token=xyz",
        "https://example.com/x?api_key=abc",
        "https://example.com/x?sig=abc&expires=1",
        "https://example.com/unsubscribe/abc123",
        "https://example.com/account/reset-password/abc",
        "https://example.com/magic/abc",
        "https://user:pass@example.com/"
    ])
    func whenSecretOrAction_thenNotEligible(url: String) {
        #expect(!eligible(url), "\(url)")
    }

    @Test("a signed URL from a cloud store is never fetched", arguments: [
        "https://bucket.s3.amazonaws.com/file.pdf?X-Amz-Signature=abc&X-Amz-Expires=300",
        "https://bucket.s3.amazonaws.com/file.pdf?X-Amz-Credential=AKIA%2F2026&X-Amz-Date=20261016",
        "https://example.com/f?X-Amz-Security-Token=abc",
        "https://storage.googleapis.com/b/o?X-Goog-Signature=abc&X-Goog-Expires=60",
        "https://www.dropbox.com/scl/fi/abc/file.pdf?rlkey=abc123&dl=0",
        "https://example.com/x?Signature=abc&Key-Pair-Id=K1&Policy=p"
    ])
    func whenSignedURL_thenNotEligible(url: String) {
        #expect(!eligible(url), "\(url)")
    }

    @Test("a link whose address is the key to a shared document is never fetched", arguments: [
        "https://docs.google.com/document/d/1AbCdEfGh/edit?usp=sharing",
        "https://drive.google.com/file/d/1AbCdEfGh/view",
        "https://www.notion.so/team/Roadmap-0123456789abcdef",
        "https://acme.slack.com/archives/C012345/p1700000000000100",
        "https://www.figma.com/file/AbCdEf/Design",
        "https://1drv.ms/b/s!AbCdEfGh",
        "https://wetransfer.com/downloads/abc123"
    ])
    func whenSharedDocument_thenNotEligible(url: String) {
        #expect(!eligible(url), "\(url)")
    }

    @Test("addresses on this Mac or its network are never fetched", arguments: [
        "http://localhost:3000/admin",
        "http://127.0.0.1/",
        "http://192.168.0.1/status",
        "http://10.0.0.5/",
        "http://172.16.4.2/",
        "http://169.254.169.254/latest/meta-data/",
        "http://100.64.0.1/",
        "http://[::1]/",
        "http://printer.local/",
        "http://intranet/wiki",
        "https://build.internal/job/1",
        "http://127.1/",
        "http://0x7f.0.0.1/",
        "http://0177.0.0.1/",
        "http://0x7f000001/",
        "http://2130706433/",
        "http://192.168.1/",
        "http://1.2.3.4.5/",
        "http://0300.0250.0.1/"
    ])
    func whenLocalOrPrivate_thenNotEligible(url: String) {
        #expect(!eligible(url), "\(url)")
    }

    @Test("only web schemes are fetched", arguments: [
        "file:///Users/me/secret.txt", "ftp://example.com/file", "javascript:alert(1)", "mailto:a@example.com"
    ])
    func whenNotWeb_thenNotEligible(url: String) {
        #expect(!eligible(url), "\(url)")
    }

    @Test("a public address is fine")
    func whenPublicAddress_thenEligible() {
        #expect(eligible("http://93.184.216.34/"))
        #expect(eligible("http://172.32.0.1/"), "172.32 is outside the private 172.16/12 range")
    }

    @Test("a link inside a redirect wrapper is fetched only when the address inside is itself eligible", arguments: [
        ("https://www.google.com/url?q=http://192.168.0.1/admin", false),
        ("https://www.google.com/url?q=https://example.com/reset?token=abc", false),
        ("https://x.safelinks.protection.outlook.com/?url=https%3A%2F%2Flocalhost%2Fadmin", false),
        ("https://a.google.evil.example/url?q=https://example.com/page", true),
        ("https://www.google.com/url?q=https://example.com/recipes", true),
        ("https://example.com/recipes", true)
    ])
    func whenWrapped_thenTheInnerAddressIsJudged(url: String, fetched: Bool) throws {
        let parsed = try #require(URL(string: url))
        #expect((LinkPreviewEligibility.fetchTarget(for: parsed) != nil) == fetched, "\(url)")
    }

    @Test("the target of a wrapper is what is fetched, and an unwrapped link is fetched as it is")
    func whenEligible_thenTheTargetIsTheUnwrappedAddress() throws {
        let wrapped = try #require(URL(string: "https://www.google.com/url?q=https://example.com/recipes"))
        let plain = try #require(URL(string: "https://example.com/recipes"))
        #expect(LinkPreviewEligibility.fetchTarget(for: wrapped)?.absoluteString == "https://example.com/recipes")
        #expect(LinkPreviewEligibility.fetchTarget(for: plain) == plain)
    }
}
