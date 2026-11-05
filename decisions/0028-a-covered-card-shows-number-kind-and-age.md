# 0028. A covered card shows its number, its kind and its age, and nothing else

Status: Accepted

Relates to [0003](0003-secrets-are-masked-and-shown-on-request.md) and keeps it whole: the cover, Show, the authentication window and "paste without showing" are unchanged. Nothing about storage, sync or the network changes.

## Context
A card covered for a screen share or by Hide Clip Contents was an identical "Hidden for sharing" block with a Show link. Every covered clip still pastes on its own (Return, ⌘1 to ⌘9, a double click), but eight identical blocks cannot be told apart, so the ⌘ numbers were unusable while covered. The cover must tell clips apart without telling a watcher anything about the content.

## Decision
- A covered card shows three facts: its ⌘ number (cards 1 to 9), the kind of clip as one plain word from `ClipboardType` (Text, Link, Image, File, Color, Code) and its relative age (the same text the card uses). The eye symbol and Show stay.
- A masked secret, and any clip with a sensitivity category, reads **Text**: no lock, no category, so the word never says "card" or "key".
- **Never shown on a covered card:** the source app's name or tile, the sensitivity category, a length or size, a title, a file name, a link's domain, a color's hex or tint, a thumbnail.
- The rule is one tested value in Core, `CoverFacts`, built from the clip and its index. The cover's view (`CoveredCardFace`) takes a `CoverFacts` and nothing else, so no other fact can be drawn there, and the card's VoiceOver label and value on a covered card are built from the same value: "text, hidden" and "command 3, 5 minutes ago". `CoverFactsTests` checks that for a card number, an API key, a file with a revealing name, a link, a color, a pinned titled clip and a picture none of that kind's identifying strings appears in any string the value can produce.
- Two gaps found in review are closed. The cover was drawn over the card's own border, so a focused or selected covered card showed no ring: the cover draws the ring itself. The tooltip said a click pastes, but a single click only focuses (ADR 0009): it now says Return or a double click.

## Consequences
- A person sharing a screen can say "paste the third one" and use ⌘3, and a watcher learns the kind and the age of a clip, as they already could from the shelf's own order.
- A clip's kind and age are shown on a covered card even for a secret; the kind of a secret is always Text, so it is not a hint.
- A card blurred by the content filter (not the share cover) is unchanged by this decision, and its VoiceOver text still names the app.
- The pictures of the shelf with Hide Clip Contents on need to be retaken, and the website's shelf follows separately.

## Docs affected
- `docs/guide/privacy-and-security.md`, `docs/guide/using-pesto.md` (what a covered card shows)
- `decisions/README.md` (this record in the table)
