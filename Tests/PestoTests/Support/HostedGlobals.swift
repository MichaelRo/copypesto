// SPDX-License-Identifier: MIT
import Testing

/// Swift Testing runs suites concurrently and `.serialized` only orders the tests inside one suite. A suite that reads
/// or writes process-wide state (`AppDefaults.store`, `AppPasteboard.general`, `ScriptingContext.appState`,
/// `PreviewTextCache.shared`, `Motion.reduceMotionOverride`, `LastItemStore.testFileURL`, `BlobEncryption.keyState`)
/// nests here, so all of them run one after another.
@Suite(.serialized)
enum HostedGlobals {}
