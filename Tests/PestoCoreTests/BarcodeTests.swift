// SPDX-License-Identifier: MIT
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PestoCore

@Suite("QR code and barcode detection and payload parsing")
struct BarcodeTests {
    private func renderBarcodePNG(filterName: String, message: String) throws -> Data {
        let filter = try #require(CIFilter(name: filterName))
        filter.setValue(Data(message.utf8), forKey: "inputMessage")
        let output = try #require(filter.outputImage)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let padded = scaled.cropped(to: scaled.extent.insetBy(dx: -24, dy: -24))
        let context = CIContext()
        let cgImage = try #require(context.createCGImage(padded, from: padded.extent))
        let encoded = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, cgImage, nil)
        #expect(CGImageDestinationFinalize(destination))
        return encoded as Data
    }

    @Test("parses safe HTTP/HTTPS URLs and falls back to plain text for unsafe schemes")
    func whenBarcodeIsURL_thenLinkOpenPolicyGatesIt() throws {
        let web = try #require(BarcodePayload(rawValue: "https://copypesto.net/guide", kind: .qr))
        #expect(web.urlToOpen?.absoluteString == "https://copypesto.net/guide")
        #expect(web.displaySummary == "copypesto.net")
        #expect(web.copyableValue == "https://copypesto.net/guide")

        let unsafe = try #require(BarcodePayload(rawValue: "javascript:alert(1)", kind: .qr))
        #expect(unsafe.urlToOpen == nil)
        #expect(unsafe.content == .text("javascript:alert(1)"))
    }

    @Test("parses Wi-Fi QR payloads without exposing passwords in the visible summary")
    func whenWiFiQRCode_thenPasswordIsMaskedInSummary() throws {
        let payload = try #require(
            BarcodePayload(rawValue: #"WIFI:T:WPA;S:Basil\:Cafe;P:p@ss\;word;H:true;;"#, kind: .qr)
        )
        guard case let .wifi(ssid, password, security, isHidden) = payload.content else {
            Issue.record("Expected Wi-Fi payload")
            return
        }
        #expect(ssid == "Basil:Cafe")
        #expect(password == "p@ss;word")
        #expect(security == "WPA")
        #expect(isHidden)
        #expect(payload.displaySummary.contains("Basil:Cafe"))
        #expect(!payload.displaySummary.contains("p@ss"))
        #expect(payload.copyableValue == "p@ss;word")
        #expect(payload.secondaryCopyValue == "Basil:Cafe")
    }

    @Test("Vision detects QR codes and 1D Code 128 barcodes from rendered image data")
    func whenImageContainsQRCodeOrBarcode_thenVisionDecodesIt() async throws {
        guard !OCRService.isDisabled(environment: ProcessInfo.processInfo.environment) else { return }
        let qrPNG = try renderBarcodePNG(filterName: "CIQRCodeGenerator", message: "https://copypesto.net/qr")
        let qrPayloads = await BarcodeDetector.detect(in: qrPNG)
        #expect(qrPayloads.contains { $0.rawValue == "https://copypesto.net/qr" && $0.kind == .qr })

        let code128PNG = try renderBarcodePNG(filterName: "CICode128BarcodeGenerator", message: "PESTO-12345")
        let barPayloads = BarcodeDetector.detectSync(in: code128PNG)
        #expect(barPayloads.contains { $0.rawValue == "PESTO-12345" && $0.kind == .barcode })
    }
}
