// SPDX-License-Identifier: MIT
import Testing

/// Every suite that reads or writes the test process's one clipboard (`AppPasteboard.general`) nests here, so they run
/// one at a time: Swift Testing runs suites in parallel, and two of them changing the clipboard under each other failed
/// on CI (2026-11-19). The Mac's hosted tests do the same with `HostedGlobals`.
@Suite(.serialized)
enum MobilePasteboardGlobals {}
