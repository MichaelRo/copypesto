# 0014. Shelf suggestions offer shortcuts, free idle keys and suggest snippets without moving cards

Status: Accepted

## Context
People who use Pesto often paste the same clips repeatedly from the shelf without realizing they can pin them to a global
shortcut (`⌃1` to `⌃9`) or turn repetitive text into expandable snippets. Furthermore, shortcuts that were assigned
often become dormant when tasks finish, leaving the 9 slots occupied. Other clipboard tools interrupt the user with modal
prompts, move existing cards, bind new keys without consent, or send clip data to remote services.

## Decision
Pesto introduces shelf suggestions, governed strictly by on-device policy (`ShelfSuggestionPolicy`) and local paste
counts kept on the Mac. UI text and code strictly use the term "suggestion" (never "magic", "smart slot", or similar terms).

1. **Four suggestion moments**:
   - **Shortcut offer**: Offered when an unassigned clip has been pasted at least 6 times in the last 14 days, with at least
     one paste from the shelf in the current run, and a shortcut slot (`⌃1`–`⌃9`) is free. Accepting pins the clip, assigns
     the slot, and offers Undo.
   - **Shortcut reminder**: Offered when a clip already assigned to `⌃1`–`⌃9` is pasted from the shelf at least 5 times in
     the current run, while its global shortcut has not been used in at least 14 days. Carries a single "Got It" button.
   - **Dormant shortcut release**: Offered when a pinned shortcut has not been used in at least 60 days (measured against
     `shortcutLastUsedAt` or the suggestion feature arming date). Accepting frees the shortcut slot while keeping the clip
     pinned in history.
   - **Snippet suggestion**: Offered when an unpinned text clip has been pasted at least 8 times in the last 14 days and
     meets template eligibility (`SnippetSuggester`). Accepting navigates to Settings → Snippets with the clip pre-filled.

2. **Presentation and non-intrusiveness invariants**:
   - Suggestions draw inside a bottom overlay (`BannerFill(tint: accent)`), sharing the bottom slot with the Undo bar.
     They never move existing cards or the toolbar.
   - Banners say "this clip", never quoting or naming clip contents.
   - Suggestions never take keyboard focus and never bind global keyboard shortcuts.
   - A target card is highlighted with a 2 pt accent ring and a dashed ghost keycap with `pestoPop` spring settle.
   - Suggestions wait for a 1.5 s dwell time before appearing, and respect a 3-day quiet period after first onboarding
     and a 24-hour minimum interval between presentations.

3. **Ledger and suppression**:
   - A 200-line capped ledger (`SuggestionLedger`) tracks shown suggestions, declines, and resolutions.
   - Declining a clip requires doubling its paste count before it can ever be suggested again. Declining four suggestions
     in a row turns the feature off with a temporary notice.
   - **Wipe paths**: Clear History (`.all`), Clear Everything, and Backup Restore wipe the ledger, declines, and runtime tally.
     Locking history or covering cards (e.g. screen sharing) suppresses active suggestion UI and cancels dwell timers without
     clearing the ledger or user preferences.

## Consequences
- `ClipboardItem` adds a lightweight nullable column `shortcutLastUsedAt: Date?`, backed up in encrypted metadata.
- Pesto discovers shortcuts and snippets naturally with zero network activity and strict local privacy.

## Docs affected
- `README.md`
- `docs/guide/shortcuts.md`
- `docs/guide/settings.md`
- `docs/guide/using-pesto.md`
- `docs/guide/privacy-and-security.md`
