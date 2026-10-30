// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("The mask a secret card shows is dots and a count")
struct SecretMaskTests {
    private static let badgeLabels: [SensitivityCategory: [String]] = [
        .creditCard: ["card"], .ssn: ["ssn"], .jwt: ["jwt"], .apiKey: ["api key"], .oauthToken: ["oauth"],
        .privateKey: ["private key"], .password: ["password"]
    ]

    @Test("no generic mask repeats the badge the card already wears", arguments: SensitivityCategory.allCases)
    func whenGenericMask_thenItDoesNotRepeatTheBadge(category: SensitivityCategory) {
        for count in [nil, 45] {
            let mask = SensitiveContentDetector.localizedMask(for: category, count: count).lowercased()
            for label in Self.badgeLabels[category] ?? [] {
                #expect(!mask.contains(label), "\(category) mask \(mask) repeats \(label)")
            }
        }
    }

    @Test("a high-entropy key is masked by dots and its length")
    func whenApiKey_thenDotsAndCount() throws {
        let key = "Zx9qLmP4vTn7RbK2wYc8HdJ5sGf3AeUi6OlN1"
        let result = try #require(SensitiveContentDetector.detect(in: key))

        #expect(result.category == .apiKey)
        #expect(result.maskedPreview == "•••• (\(key.count) characters hidden)")
    }

    @Test("a social security number is dots only")
    func whenSSN_thenDotsOnly() throws {
        let result = try #require(SensitiveContentDetector.detect(in: "123-45-6789"))

        #expect(result.maskedPreview == "•••-••-••••")
    }

    @Test("a JWT is dots and its length")
    func whenJWT_thenDotsAndCount() throws {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let result = try #require(SensitiveContentDetector.detect(in: jwt))

        #expect(result.category == .jwt)
        #expect(result.maskedPreview == "•••• (\(jwt.count) characters hidden)")
    }

    @Test("a card number inside text shows its last four digits and nothing else")
    func whenCardInText_thenLastFourOnly() throws {
        let result = try #require(SensitiveContentDetector.detect(in: "Order 7731 paid with 4242 4242 4242 4242 today"))

        #expect(result.maskedPreview == "•••• •••• •••• 4242")
    }

    @Test("a password line, an assignment and an access token are dots only")
    func whenLinePatterns_thenDotsOnly() throws {
        let password = try #require(SensitiveContentDetector.detect(in: "password: hunter2hunter2"))
        let assigned = try #require(SensitiveContentDetector.detect(in: "CLIENT_SECRET=abc123def456"))
        let bearer = try #require(SensitiveContentDetector
            .detect(in: "curl -H 'Authorization: Bearer abcdef0123456789abcdef' x"))

        #expect(password.maskedPreview == "••••")
        #expect(assigned.maskedPreview == "••••")
        #expect(bearer.maskedPreview == "••••")
    }

    @Test("a vendor key keeps its prefix and vendor, which the badge does not say")
    func whenVendorKey_thenPrefixAndVendorStay() throws {
        let result = try #require(SensitiveContentDetector.detect(in: "ghp_" + String(repeating: "a1B2c3", count: 6)))

        #expect(result.maskedPreview.hasPrefix("ghp_••••"))
        #expect(result.maskedPreview.contains("GitHub PAT"))
    }

    @Test("a mask stored by an older version is rewritten to the new form", arguments: [
        ("API key •••• (45 characters hidden)", "•••• (45 characters hidden)"),
        ("•••-••-•••• (SSN)", "•••-••-••••"),
        ("JWT (120 characters, 3 parts)", "•••• (120 characters hidden)"),
        ("Password hash (60 characters)", "•••• (60 characters hidden)"),
        ("Password line (hidden)", "••••"),
        ("Secret assignment (hidden)", "••••"),
        ("Access token (hidden)", "••••"),
        ("•••• •••• •••• 4242 (card number in text)", "•••• •••• •••• 4242"),
        ("🔒 BEGIN RSA PRIVATE KEY", "•••• (private key hidden)"),
        ("🔒 BEGIN PRIVATE KEY", "•••• (private key hidden)")
    ])
    func whenOldMask_thenModernised(old: String, expected: String) {
        #expect(SensitiveContentDetector.modernisedMask(old) == expected)
    }

    @Test("a mask already in the new form, or one with its own information, is left alone", arguments: [
        "•••• (45 characters hidden)", "••••", "•••-••-••••", "•••• •••• •••• 4242",
        "ghp_•••• (GitHub PAT, 36 characters hidden)", "Hidden by 1Password", "•••• (private key hidden)"
    ])
    func whenNewMask_thenUnchanged(mask: String) {
        #expect(SensitiveContentDetector.modernisedMask(mask) == mask)
        #expect(SensitiveContentDetector.modernisedMask(SensitiveContentDetector.modernisedMask(mask)) == mask)
    }
}

@Suite("Rewriting the masks stored by an older version")
struct SecretMaskMigrationTests {
    private func insert(_ mask: String, category: SensitivityCategory, in context: ModelContext) throws -> UUID {
        let item = ClipboardItem(
            type: .text, previewText: mask, sensitivity: category, sensitivityMaskedPreview: mask,
            contentHash: UUID().uuidString, byteSize: 40, deviceID: "t", sequenceNumber: 1
        )
        context.insert(item)
        try context.save()
        return item.id
    }

    @Test("an old mask becomes the new one in both columns; a new one and a clip with none are untouched")
    func whenMigrated_thenOldMasksAreRewritten() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        let old = try insert("API key •••• (45 characters hidden)", category: .apiKey, in: context)
        let current = try insert("•••• (45 characters hidden)", category: .apiKey, in: context)
        let vendor = try insert("ghp_•••• (GitHub PAT, 36 characters hidden)", category: .oauthToken, in: context)
        let plain = ClipboardItem(
            type: .text, previewText: "", contentHash: UUID().uuidString, byteSize: 4, deviceID: "t", sequenceNumber: 2
        )
        context.insert(plain)
        try context.save()
        let service = StorageService(modelContainer: container)

        let rewritten = try await service.modernizeSecretMasks()

        #expect(rewritten == 1)
        let fresh = ModelContext(container)
        func item(_ id: UUID) throws -> ClipboardItem {
            try #require(fresh.fetch(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })).first)
        }
        #expect(try item(old).sensitivityMaskedPreview == "•••• (45 characters hidden)")
        #expect(try item(old).previewText == "•••• (45 characters hidden)")
        #expect(try item(current).sensitivityMaskedPreview == "•••• (45 characters hidden)")
        #expect(try item(vendor).sensitivityMaskedPreview == "ghp_•••• (GitHub PAT, 36 characters hidden)")
        #expect(try item(plain.id).sensitivityMaskedPreview == nil)
    }

    @Test("running it twice changes nothing the second time")
    func whenMigratedTwice_thenNothingChanges() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        _ = try insert("•••-••-•••• (SSN)", category: .ssn, in: context)
        let service = StorageService(modelContainer: container)

        #expect(try await service.modernizeSecretMasks() == 1)
        #expect(try await service.modernizeSecretMasks() == 0)
    }

    @Test("the standard list runs it once, under its own version key")
    func whenStandardList_thenItHasTheMaskMigration() throws {
        let container = try ModelContainerSetup.makeInMemory()
        let names = LaunchMigration.standard(service: StorageService(modelContainer: container)).map(\.name)

        #expect(names.contains("Secret masks"))
    }
}

@Suite("Searching a secret by what it is")
struct SecretSearchTermsTests {
    @Test("a hidden secret is found by its category name, not by its text", arguments: [
        (SensitivityCategory.apiKey, "api key"), (.ssn, "ssn"), (.jwt, "jwt"), (.password, "password"),
        (.oauthToken, "oauth"), (.privateKey, "private key"), (.creditCard, "card")
    ])
    func whenSecret_thenCategoryNameIsSearched(category: SensitivityCategory, term: String) throws {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        let item = ClipboardItem(
            type: .text, previewText: "••••", sensitivity: category, sensitivityMaskedPreview: "••••",
            contentHash: UUID().uuidString, byteSize: 40, deviceID: "t", sequenceNumber: 1
        )
        context.insert(item)

        #expect(SearchMatching.matches(foldedText: item.searchableGridPreview, foldedQuery: SearchMatching.fold(term)))
    }
}
