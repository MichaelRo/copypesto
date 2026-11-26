// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

extension StorageService {
    /// The clips that hold this content, the one used most recently first (ADR 0053): an edit can give two clips one
    /// text, and a fresh copy of it moves only that one.
    static func holding(_ forms: [String]) -> FetchDescriptor<ClipboardItem> {
        FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { forms.contains($0.contentHash) },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.sequenceNumber, order: .reverse)]
        )
    }

    /// When this content is already in the history, moves that clip to the front (and records where it was copied
    /// from) instead of storing a second one. True when it did.
    func popExistingDuplicate(
        matching descriptor: FetchDescriptor<ClipboardItem>,
        hash: String,
        now: Date,
        bundleID: String?,
        isRemote: Bool? = nil,
        onlyAdvanceTimestamp: Bool = false,
        collectionID: UUID? = nil,
        assignCollectionOnlyIfUnfiled: Bool = false
    ) async throws
    -> Bool {
        guard let existing = try modelContext.fetch(descriptor).first else { return false }
        existing.contentHash = hash // upgrades an item stored under the old plain hash
        if !onlyAdvanceTimestamp || now > existing.timestamp {
            existing.bringToFront(at: now)
        }
        if let collectionID, try !assignCollectionOnlyIfUnfiled || isUnfiled(existing.collectionID) {
            existing.collectionID = collectionID
        }
        lastIngestedHash = (hash, now)
        lastInsertedClip = nil
        if let isRemote {
            if !isRemote {
                existing.isRemote = false
            } else if existing.isRemote {
                existing.sourceBundleID = nil
                existing.sourceAppName = PasteboardCapture.remoteSourceName
                existing.sourceDominantColorHex = nil
            }
        }
        if let bundleID, isRemote != true {
            let appRecord = await resolver.resolve(bundleID: bundleID)
            existing.sourceBundleID = bundleID
            existing.sourceAppName = appRecord.displayName
            existing.sourceDominantColorHex = appRecord.dominantColorHex
        }
        try saveOrRollback()
        return true
    }

    func validatedManualCollectionID(_ id: UUID?) throws -> UUID? {
        guard let id, let board = try pinboard(id: id), !board.isSmart else { return nil }
        return board.id
    }

    func isUnfiled(_ existingID: UUID?) throws -> Bool {
        guard let existingID else { return true }
        return try pinboard(id: existingID) == nil
    }

    func perceptualDuplicate(
        of candidateHash: String,
        payload: Data,
        fingerprint: PictureFingerprint? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    )
    -> ClipboardItem? {
        let imageTypeRaw = ClipboardType.image.rawValue
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.typeRaw == imageTypeRaw },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        guard let recent = try? modelContext.fetch(descriptor) else { return nil }
        let dimensionMatched = recent.filter { item in
            if let pixelWidth, let itemWidth = item.pixelWidth, itemWidth != pixelWidth { return false }
            if let pixelHeight, let itemHeight = item.pixelHeight, itemHeight != pixelHeight { return false }
            return true
        }
        let nominatedIDs = Set(PerceptualHasher.nominees(
            for: candidateHash, among: dimensionMatched.map { (id: $0.id, hash: $0.perceptualHash) }
        ))
        let comparable = dimensionMatched.filter { item in
            guard nominatedIDs.contains(item.id) else { return false }
            guard let fingerprint, let stored = item.metadata.pictureFingerprint else { return true }
            return !fingerprint.rulesOut(stored)
        }
        guard !comparable.isEmpty else { return nil }
        let digest = pixelDigest(payload)
        return comparable.first { item in
            guard let existingData = item.blob?.decryptedData() else { return false }
            if let digest, pixelDigest(existingData) == digest {
                return true
            }
            guard let width = item.pixelWidth, let height = item.pixelHeight,
                  width == pixelWidth, height == pixelHeight,
                  Self.hasLossyEncoding(payload) || Self.hasLossyEncoding(existingData) else { return false }
            return Self.isCrossFormatNearMatch(payload, existingData)
        }
    }

    private static func hasLossyEncoding(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ),
            let identifier = CGImageSourceGetType(source) as String?,
            let utType = UTType(identifier) else
        {
            return false
        }
        return utType == .jpeg || utType == .heic || utType == .heif || utType == .webP
    }

    private static func isCrossFormatNearMatch(_ lhs: Data, _ rhs: Data) -> Bool {
        guard let left = normalizedSmallPixels(lhs),
              let right = normalizedSmallPixels(rhs),
              left.count == right.count,
              !left.isEmpty else
        {
            return false
        }
        var maxDiff = 0
        var totalRGBDiff = 0
        var totalAlphaDiff = 0
        let pixelCount = left.count / 4
        guard pixelCount > 0 else { return false }
        for index in left.indices {
            let diff = abs(Int(left[index]) - Int(right[index]))
            if diff > maxDiff { maxDiff = diff }
            if maxDiff > 36 { return false }
            if index % 4 == 3 {
                totalAlphaDiff += diff
            } else {
                totalRGBDiff += diff
            }
        }
        let meanRGBDiff = Double(totalRGBDiff) / Double(pixelCount * 3)
        let meanAlphaDiff = Double(totalAlphaDiff) / Double(pixelCount)
        return meanRGBDiff <= 6.0 && meanAlphaDiff <= 6.0
    }

    private static func normalizedSmallPixels(_ data: Data) -> [UInt8]? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: 64
        ]
        guard let source = CGImageSourceCreateWithData(
            data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary
        ),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else
        {
            return nil
        }
        let side = 16
        let bytesPerRow = side * 4
        var buffer = [UInt8](repeating: 0, count: side * bytesPerRow)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &buffer,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return buffer
    }

    func storeEmbedding(itemID: UUID, contentHash: String, embeddingData: Data) throws {
        var desc = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.id == itemID && $0.contentHash == contentHash }
        )
        desc.fetchLimit = 1
        guard let item = try modelContext.fetch(desc).first else { return }
        item.embeddingData = embeddingData
        try saveOrRollback()
    }
}
