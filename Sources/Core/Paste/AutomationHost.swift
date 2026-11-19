// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// What a `pesto://` link needs from the running app: the windows, the search field and the paste flow, none of which
/// Core owns. The app delegate conforms; a test supplies a spy.
@MainActor
public protocol AutomationHost: AnyObject {
    var isHistoryLocked: Bool { get }
    /// Clip contents are covered (Hide Clip Contents, or a screen share with that setting on, ADR 0003): a link may
    /// not put a clip's text on screen or open it.
    var isContentCovered: Bool { get }
    var historyContainer: ModelContainer? { get }
    func showShelf()
    func togglePinnedWindow()
    func search(for text: String)
    func selectCollection(_ id: UUID?)
    func paste(_ item: ClipboardItem)
    func togglePin(id: UUID) async
    func requestClear(_ range: ClearRange)
    /// A widget's Copy: the clip through the app's one copy path, moved to the front as a shelf copy is.
    func copyClip(_ item: ClipboardItem)
    /// A widget's Open on a link clip whose whole text is one web address.
    func openWebLink(_ url: URL)
}
