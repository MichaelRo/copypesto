// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("QuickLookFileExtension")
struct QuickLookFileExtensionTests {
    @Test("a captured GIF is stored as com.compuserve.gif and previews as a GIF, not as a text file of binary")
    func whenCapturedGIF_thenGIF() {
        #expect(QuickLookFileExtension.forTypeIdentifier("com.compuserve.gif") == "gif")
        #expect(QuickLookFileExtension.forTypeIdentifier("public.gif") == "gif")
    }

    @Test("a PDF and a WebP picture preview as themselves")
    func whenPDFOrWebP_thenTheirOwnExtension() {
        #expect(QuickLookFileExtension.forTypeIdentifier("com.adobe.pdf") == "pdf")
        #expect(QuickLookFileExtension.forTypeIdentifier("org.webmproject.webp") == "webp")
        #expect(QuickLookFileExtension.forTypeIdentifier("public.webp") == "webp")
    }

    @Test("the types that always worked still do")
    func whenCommonTypes_thenUnchanged() {
        #expect(QuickLookFileExtension.forTypeIdentifier("public.png") == "png")
        #expect(QuickLookFileExtension.forTypeIdentifier("public.jpeg") == "jpg")
        #expect(QuickLookFileExtension.forTypeIdentifier("public.svg-image") == "svg")
        #expect(QuickLookFileExtension.forTypeIdentifier("video/mp4") == "mp4")
        #expect(QuickLookFileExtension.forTypeIdentifier("public.url") == "webloc")
    }

    @Test("a picture type the table does not list previews as itself")
    func whenOtherImageType_thenSystemExtension() {
        #expect(QuickLookFileExtension.forTypeIdentifier("com.microsoft.bmp") == "bmp")
    }

    @Test("anything unknown previews as text")
    func whenUnknown_thenText() {
        #expect(QuickLookFileExtension.forTypeIdentifier("public.utf8-plain-text") == "txt")
        #expect(QuickLookFileExtension.forTypeIdentifier("") == "txt")
    }
}
