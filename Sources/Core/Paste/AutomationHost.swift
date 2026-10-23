// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// What a `pesto://` link needs from the running app: the windows, the search field and the paste flow, none of which
/// Core owns. The app delegate conforms; a test supplies a spy.
@MainActor
public protocol AutomationHost: AnyObject {
    var isHistoryLocked: Bool { get }
    var historyContainer: ModelContainer? { get }
    func showShelf()
    func togglePinnedWindow()
    func search(for text: String)
    func selectCollection(_ id: UUID?)
    func paste(_ item: ClipboardItem)
    func togglePin(id: UUID) async
    func requestClear(_ range: ClearRange)
}
