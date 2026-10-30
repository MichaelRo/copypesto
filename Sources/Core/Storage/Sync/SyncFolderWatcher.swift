// SPDX-License-Identifier: MIT
import CoreServices
import Foundation

/// Tells the sync service when something in the folder changed, so a segment from another Mac is read within a second
/// or two of arriving. A poll still runs, because a provider that fills a folder in the background may not raise
/// events.
final class SyncFolderWatcher: @unchecked Sendable {
    private let url: URL
    private let latency: TimeInterval
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "net.copypesto.pesto.sync.watcher")

    init(url: URL, latency: TimeInterval = 0.3, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.latency = latency
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<SyncFolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
