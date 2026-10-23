// SPDX-License-Identifier: MIT
import Foundation

/// Everything `StorageService` depends on that is not the store: where the latest clip is mirrored, who reads text out
/// of pictures, how new text is embedded, what the clock says. It is built once and handed to the service, so the
/// service reads no process-wide state of its own and a test builds the one it needs instead of patching a service
/// after the fact (W-07). `live()` is the app; the default is also what a test host gets, because a hosted test must
/// not write the real last-item file or load the language model.
public struct StorageEnvironment: Sendable {
    public var lastItemStore: any LastItemStoring
    public var linkPreviews: LinkPreviewImageStore
    public var linkPreviewCache: LinkPreviewCache
    public var imageScreener: any ImageSensitivityScreening
    public var textRecognizer: any TextRecognizing
    public var embedder: any TextEmbedding
    /// Seals a preview with the given associated data; nil seals with the install's key. A test injects a failure.
    public var previewSealer: (@Sendable (Data, Data) throws -> BlobEncryption.EncryptedEnvelope)?
    /// Fetches the GIF a browser's Copy Image named (ADR 0005); nil keeps the still the browser put on the pasteboard.
    public var remoteGIFFetcher: (@Sendable (URL) async -> Data?)?
    public var clock: @Sendable () -> Date
    public var rules: ClipboardRules
    /// Hands out the sequence numbers. One per service: two counters over the same key can emit a number twice.
    public var sequenceCounter: SequenceCounter
    /// Names this Mac on every clip; read on the first ingest.
    public var deviceID: @Sendable () throws -> String
    /// Replaces the install key once Clear Everything has deleted the rows (`StorageService.clearEverything`).
    public var keyRotator: @Sendable () throws -> Void
    /// What ⌘Z undoes; wiped with the history (ADR 0008).
    public var undoHistory: UndoHistory

    public init(
        lastItemStore: any LastItemStoring, linkPreviews: LinkPreviewImageStore,
        imageScreener: any ImageSensitivityScreening, textRecognizer: any TextRecognizing,
        embedder: any TextEmbedding,
        previewSealer: (@Sendable (Data, Data) throws -> BlobEncryption.EncryptedEnvelope)?,
        remoteGIFFetcher: (@Sendable (URL) async -> Data?)?, clock: @escaping @Sendable () -> Date,
        rules: ClipboardRules, sequenceCounter: SequenceCounter, deviceID: @escaping @Sendable () throws -> String,
        keyRotator: @escaping @Sendable () throws -> Void = { try BlobEncryption().rotateKey() },
        undoHistory: UndoHistory = UndoHistory(), linkPreviewCache: LinkPreviewCache = .shared
    ) {
        self.lastItemStore = lastItemStore
        self.linkPreviews = linkPreviews
        self.linkPreviewCache = linkPreviewCache
        self.imageScreener = imageScreener
        self.textRecognizer = textRecognizer
        self.embedder = embedder
        self.previewSealer = previewSealer
        self.remoteGIFFetcher = remoteGIFFetcher
        self.clock = clock
        self.rules = rules
        self.sequenceCounter = sequenceCounter
        self.deviceID = deviceID
        self.keyRotator = keyRotator
        self.undoHistory = undoHistory
    }

    /// The app's choices. Outside a normal launch (a test host, a UI-test launch) the last-item file is not written
    /// and no language model is loaded.
    public static func live(
        rules: ClipboardRules = .init(),
        remoteGIFFetcher: (@Sendable (URL) async -> Data?)? = nil
    )
    -> StorageEnvironment {
        let mode = LaunchMode.current
        return StorageEnvironment(
            lastItemStore: mode == .hostedTests ? NoLastItemFile() : FileLastItemStore(),
            linkPreviews: LinkPreviewImageStore(),
            imageScreener: OnDeviceImageScreener(),
            textRecognizer: OCRService(),
            embedder: mode.usesSystemIntegrations ? SemanticIndexer.shared : NoEmbedding(),
            previewSealer: nil,
            remoteGIFFetcher: remoteGIFFetcher,
            clock: { .now },
            rules: rules,
            sequenceCounter: SequenceCounter(defaults: AppDefaults.store),
            deviceID: {
                let configuration = RuntimeConfiguration.current
                guard configuration.mode.usesSystemIntegrations else { return "uitest-device-\(configuration.session)" }
                return try DeviceIdentity().loadOrCreate()
            }
        )
    }

    /// `live()` with what a test wants different. The last-item file and the language model stay off whatever the host.
    public static func testing(_ configure: (inout StorageEnvironment) -> Void = { _ in }) -> StorageEnvironment {
        var environment = live()
        environment.lastItemStore = NoLastItemFile()
        environment.embedder = NoEmbedding()
        environment.linkPreviewCache = LinkPreviewCache(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-test-link-previews-\(UUID().uuidString)")
                .appendingPathComponent("metadata-cache.sealed")
        )
        configure(&environment)
        return environment
    }
}
