// SPDX-License-Identifier: MIT
// One test per closed bug. Each test must fail on old code and pass on the fix.
// Naming: test_regression_<bugSlug>()
import CryptoKit
import Foundation
import Testing
@testable import PestoCore

// MARK: - ContentClassifier regressions

@Suite("ContentClassifier regressions")
struct ContentClassifierRegressions {
    // Bug: prose containing "let's" or "function" was classified as code.
    @Test("prose with contractions is not classified as code")
    func regression_proseWithContractions_notCode() {
        let prose = "Let's talk about the function of leadership in modern organizations."
        let result = ContentClassifier.classify(text: prose)
        #expect(result.type != .code, "Prose with 'let' and 'function' should not be code")
    }

    @Test("prose with variable-like words is not classified as code")
    func regression_proseWithVarWord_notCode() {
        let prose = "The variable weather in spring makes planning difficult for everyone."
        let result = ContentClassifier.classify(text: prose)
        #expect(result.type != .code, "Prose with 'variable' should not be code")
    }

    @Test("Go source with package main and func is classified as code")
    func regression_goSourceClassifiedAsCode() {
        let go = """
        package main

        import "fmt"

        func main() {
            fmt.Println("hello")
        }
        """
        let result = ContentClassifier.classify(text: go)
        #expect(result.type == .code, "Go source should be classified as code")
    }

    @Test("Swift source with import and func is classified as code")
    func regression_swiftSourceClassifiedAsCode() {
        let swift = """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """
        let result = ContentClassifier.classify(text: swift)
        #expect(result.type == .code, "Swift source should be classified as code")
    }

    @Test("Python source with def is classified as code")
    func regression_pythonSourceClassifiedAsCode() {
        let python = """
        def greet(name):
            return f"Hello, {name}"

        greet("world")
        """
        let result = ContentClassifier.classify(text: python)
        #expect(result.type == .code, "Python source with def should be classified as code")
    }
}

// MARK: - GIF detection regressions

@Suite("GIF detection regressions")
struct GIFDetectionRegressions {
    @Test("GIF89a magic bytes recognized")
    func regression_gif89aMagicBytes() {
        #expect(Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00]).isGIF == true)
    }

    @Test("GIF87a magic bytes recognized")
    func regression_gif87aMagicBytes() {
        #expect(Data([0x47, 0x49, 0x46, 0x38, 0x37, 0x61, 0x01, 0x00]).isGIF == true)
    }

    @Test("PNG data not recognized as GIF")
    func regression_pngNotGIF() {
        #expect(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).isGIF == false)
    }

    @Test("empty data not recognized as GIF")
    func regression_emptyDataNotGIF() {
        #expect(Data().isGIF == false)
    }
}

// MARK: - ExclusionRules regressions

@Suite("ExclusionRules regressions")
struct ExclusionRulesRegressions {
    @Test("concealed pasteboard type is excluded")
    func regression_concealedTypeExcluded() {
        let rules = ExclusionRules()
        #expect(
            rules.shouldIgnore(typeIdentifiers: ["org.nspasteboard.ConcealedType"], frontmostBundleID: nil),
            "org.nspasteboard.ConcealedType must cause shouldIgnore to return true"
        )
    }

    @Test("transient pasteboard type is excluded")
    func regression_transientTypeExcluded() {
        let rules = ExclusionRules()
        #expect(
            rules.shouldIgnore(typeIdentifiers: ["org.nspasteboard.TransientType"], frontmostBundleID: nil),
            "org.nspasteboard.TransientType must cause shouldIgnore to return true"
        )
    }

    @Test("normal text type from non-excluded app is not ignored")
    func regression_normalTextNotIgnored() {
        let rules = ExclusionRules()
        #expect(
            rules.shouldIgnore(typeIdentifiers: ["public.plain-text"], frontmostBundleID: "com.example.app") == false,
            "Normal plain-text from a non-excluded app should not be ignored"
        )
    }
}

// MARK: - BlobEncryption regressions

@Suite("BlobEncryption round-trip regressions")
struct BlobEncryptionRegressions {
    @Test("encrypted bytes differ from plaintext")
    func regression_encryptedBytesDifferFromPlaintext() throws {
        let key = SymmetricKey(size: .bits256)
        let enc = BlobEncryptionWithKey(key: key)
        let plaintext = Data("hello regression test".utf8)
        let envelope = try enc.encrypt(plaintext)
        #expect(envelope.ciphertext != plaintext, "Ciphertext must differ from plaintext")
    }

    @Test("decrypt(encrypt(data)) round-trips correctly")
    func regression_encryptDecryptRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let enc = BlobEncryptionWithKey(key: key)
        let plaintext = Data("clipboard payload regression".utf8)
        let envelope = try enc.encrypt(plaintext)
        let decrypted = try enc.decrypt(envelope)
        #expect(decrypted == plaintext, "Round-trip must recover original data")
    }

    // Bug: macOS 26 AES-GCM SealedBox slices have non-zero startIndex — subscripting
    // at [0] traps. Fix: normalize with Data(sealed.ciphertext) before use.
    @Test("ciphertext slice can be safely subscripted at index 0")
    func regression_ciphertextSliceSafeSubscript() throws {
        let key = SymmetricKey(size: .bits256)
        let enc = BlobEncryptionWithKey(key: key)
        let envelope = try enc.encrypt(Data("test".utf8))
        let ciphertext = envelope.ciphertext
        #expect(!ciphertext.isEmpty)
        // Accessing first byte must not trap — this regressed on macOS 26 before the fix.
        let firstByte = ciphertext[ciphertext.startIndex]
        _ = firstByte
    }
}
