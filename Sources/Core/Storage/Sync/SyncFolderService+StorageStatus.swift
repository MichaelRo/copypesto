// SPDX-License-Identifier: MIT
import Foundation

public extension SyncFolderService {
    struct FolderProbe: Sendable {
        public var writeData: @Sendable (Data, URL) throws -> Void
        public var willWrite: @Sendable (URL) throws -> Void
        public var uploadingError: @Sendable (URL) -> (any Error)?
        public var isICloud: @Sendable (URL) -> Bool

        public init(
            writeData: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
            willWrite: @escaping @Sendable (URL) throws -> Void = { _ in },
            uploadingError: @escaping @Sendable (URL) -> (any Error)? = SyncFolderService.defaultUploadingError,
            isICloud: @escaping @Sendable (URL) -> Bool = SyncFolderService.defaultIsICloud
        ) {
            self.writeData = writeData
            self.willWrite = willWrite
            self.uploadingError = uploadingError
            self.isICloud = isICloud
        }
    }

    nonisolated static func defaultIsICloud(_ url: URL) -> Bool {
        if url.path.contains("/Library/Mobile Documents/com~apple~CloudDocs") {
            return true
        }
        for candidate in [url, url.deletingLastPathComponent()]
            where (try? candidate.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
        {
            return true
        }
        return false
    }

    nonisolated static func defaultUploadingError(_ url: URL) -> (any Error)? {
        guard let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemUploadingErrorKey
        ]), values.isUbiquitousItem == true else { return nil }
        return values.ubiquitousItemUploadingError
    }
}

extension SyncFolderService {
    static func isStorageFullError(_ error: any Error) -> Bool {
        matchesErrorChain(error) { nsError in
            if nsError.domain == NSCocoaErrorDomain {
                return nsError.code == CocoaError.fileWriteOutOfSpace.rawValue
                    || nsError.code == CocoaError.ubiquitousFileNotUploadedDueToQuota.rawValue
            }
            if nsError.domain == NSPOSIXErrorDomain {
                return nsError.code == Int(POSIXErrorCode.ENOSPC.rawValue)
                    || nsError.code == Int(POSIXErrorCode.EDQUOT.rawValue)
            }
            return false
        }
    }

    nonisolated static func isQuotaUploadError(_ error: any Error) -> Bool {
        matchesErrorChain(error) { nsError in
            nsError.domain == NSCocoaErrorDomain
                && nsError.code == CocoaError.ubiquitousFileNotUploadedDueToQuota.rawValue
        }
    }

    private nonisolated static func matchesErrorChain(_ error: any Error, predicate: (NSError) -> Bool) -> Bool {
        var queue: [NSError] = [error as NSError]
        var remaining = 16
        while !queue.isEmpty, remaining > 0 {
            remaining -= 1
            let current = queue.removeFirst()
            if predicate(current) { return true }
            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError {
                queue.append(underlying)
            }
            if let multiple = current.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
                queue.append(contentsOf: multiple)
            }
        }
        return false
    }

    func hasUploadQuotaError() async -> Bool {
        let layout = layout
        let deviceID = identity.deviceID
        let probe = folderProbe
        return await Task.detached(priority: .utility) {
            var urls: [URL] = [
                layout.root,
                layout.device(deviceID),
                layout.deviceRecord(deviceID),
                layout.head(deviceID)
            ]
            let logDirectory = layout.log(deviceID)
            let ownSegments = ((try? FileManager.default.contentsOfDirectory(atPath: logDirectory.path)) ?? [])
                .filter { $0.hasSuffix(".pestolog") }
                .sorted(by: >)
                .prefix(16)
            urls.append(contentsOf: ownSegments.map { logDirectory.appendingPathComponent($0) })

            let blobsDirectory = layout.blobs(deviceID)
            let ownBlobs = ((try? FileManager.default.contentsOfDirectory(atPath: blobsDirectory.path)) ?? [])
                .filter { $0.hasSuffix(".pestoblob") }
                .sorted(by: >)
                .prefix(16)
            urls.append(contentsOf: ownBlobs.map { blobsDirectory.appendingPathComponent($0) })

            return urls.contains { url in
                guard let error = probe.uploadingError(url) else { return false }
                return Self.isQuotaUploadError(error)
            }
        }.value
    }
}
