# 0015. A declined suggestion comes back once, after the clip is used twice as much and thirty days pass

Status: Accepted

Supersedes the ledger and suppression part (section 3) of [0014](0014-shelf-suggestions.md).

## Context
ADR 0014 said a declined clip needs double its paste count before it can be suggested again. The code never did that:
a decline made the kind final for the clip, an ignored suggestion muted every kind for the clip after three shows, and
the doubling rule only lifted the mute for other kinds. Michael pasted one clip many times and saw no offer, which also
exposed why: offers appear only when the shelf opens (after a 1.5 s dwell, never around a paste), the first open after
launch had no facts loaded, and Paste As, the floating window and the quick menu did not count toward the tally.

The banner design (board E of the Homebrew and shelf suggestions canvas) was reviewed again against the shelf: bottom
overlay, ring and ghost keycap, no moved cards. It stays as decided in 0014.

## Decision
1. **No Thanks backs off, once.** The same kind returns for that clip only when its paste count is at least double the
   count at the decline and thirty days have passed. A second No Thanks on the same kind and clip is final.
2. **An ignored suggestion is a soft decline of its own kind.** After three shows that ended with the shelf closing
   unanswered, the kind counts as one decline (same back-off). Other kinds for the clip stay open.
3. **Four declines in a row still turn suggestions off**, with the notice. Got It (reminder) is not a decline.
4. **Facts are loaded when the dwell ends**, so the first shelf open after launch can suggest and the numbers include
   the paste that just closed the shelf.
5. **Counting.** The shelf's Return, double click and ⌘1–9, Paste As and ⇧Return, and the floating window count as
   pastes. ⌃1–9 does not: it proves the shortcut works and is tracked by `shortcutLastUsedAt`. Paste All, stacks, URL
   scheme, AppleScript and quick-paste-last do not count.
6. **The ledger forgets clips that no longer exist** whenever the facts load.

## Consequences
- The ledger line gains a decline date and count: `kind|clip|shows|declined|pasteCount|epoch|declines`. Older lines parse.
- `SuggestionLedger.isBlocked(_:_:pastes:now:)` replaces `isSilenced` and `isResolved`.
- Reset Suggestions still clears everything.

## Docs affected
- `docs/guide/settings.md`
