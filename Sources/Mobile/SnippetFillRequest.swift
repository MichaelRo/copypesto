// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// A snippet copied from the library: either it copies at once (dates, times and IDs fill themselves) or it asks
/// first. Only a pinned, non-secret clip with placeholders is a snippet (ADR 0017).
struct SnippetFillRequest: Identifiable, Equatable {
    enum Outcome: Equatable {
        case ask(SnippetFillRequest)
        case copy(String)
    }

    let id: UUID
    let title: String
    let text: String
    let plan: SnippetCopyPlan
    let initial: SnippetFills

    @MainActor
    static func make(for item: ClipboardItem, text: String, at date: Date) -> Outcome? {
        guard item.sensitivityRaw == nil,
              let plan = SnippetCopyPlan.plan(for: text, isSnippet: item.isTemplate) else { return nil }
        let remembers = AppDefaults.store.value(for: Setting.rememberFillIns)
        let remembered = remembers ? item.metadata.fieldMemory ?? [:] : [:]
        let initial = SnippetFills.initial(for: plan.fields, remembered: remembered)
        guard plan.needsSheet else { return .copy(plan.expanded(text, fills: initial, pastedClipboard: "", at: date)) }
        return .ask(SnippetFillRequest(
            id: item.id, title: item.metadata.customTitle ?? String(localized: "Snippet"), text: text, plan: plan,
            initial: initial
        ))
    }

    func expanded(fills: SnippetFills, pastedClipboard: String, at date: Date) -> String {
        plan.expanded(text, fills: fills, pastedClipboard: pastedClipboard, at: date)
    }
}
