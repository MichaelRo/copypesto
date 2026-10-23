// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("DragTypes")
struct DragTypesTests {
    @Test("a PNG is offered as PNG only")
    func whenPNG_thenOnlyPNG() {
        #expect(DragTypes.imageIdentifiers(storedUTI: "public.png") == ["public.png"])
    }

    @Test("a TIFF is offered as TIFF first, then as a PNG conversion")
    func whenTIFF_thenTIFFThenPNG() {
        #expect(DragTypes.imageIdentifiers(storedUTI: "public.tiff") == ["public.tiff", "public.png"])
    }

    @Test("a JPEG keeps its own type instead of being mislabelled PNG")
    func whenJPEG_thenJPEGFirst() {
        #expect(DragTypes.imageIdentifiers(storedUTI: "public.jpeg").first == "public.jpeg")
    }

    @Test("a GIF is offered as GIF so animation survives, with PNG as the static fallback")
    func whenGIF_thenGIFThenPNG() {
        #expect(DragTypes.imageIdentifiers(storedUTI: "com.compuserve.gif") == ["com.compuserve.gif", "public.png"])
        #expect(DragTypes.imageIdentifiers(storedUTI: "public.gif") == ["com.compuserve.gif", "public.png"])
    }

    @Test("an SVG is offered as SVG so a design tool gets the vector, with a PNG fallback")
    func whenSVG_thenSVGThenPNG() {
        #expect(DragTypes.imageIdentifiers(storedUTI: "public.svg-image") == ["public.svg-image", "public.png"])
    }

    @Test("an unknown stored type falls back to PNG rather than nothing")
    func whenUnknown_thenPNG() {
        #expect(DragTypes.imageIdentifiers(storedUTI: "com.example.weird") == ["public.png"])
    }

    @Test("text is offered as UTF-8 plain text and the abstract plain-text type")
    func textIdentifiers() {
        #expect(DragTypes.textIdentifiers == ["public.utf8-plain-text", "public.plain-text"])
    }

    @Test("filenames use NSFilenamesPboardType for file list drop")
    func filenamesPboardType() {
        #expect(DragTypes.filenamesPboardType == "NSFilenamesPboardType")
    }
}
