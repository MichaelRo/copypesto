# 0020. Decode JWT is a second way into a hidden clip

Status: Accepted

Extends [0003](0003-secrets-are-masked-and-shown-on-request.md).

## Context
A JWT on the shelf is masked like any token (`sensitivity == .jwt`). People copy one to read what is in it: who it is
for, when it expires. Today that means Show, which prints the whole token, then a website that sees it. A token's
header and payload are only base64url JSON, so Pesto can show them on the Mac, without the signature part, which is
the secret that matters.

Decode shows part of what the mask hides, so it is a way into the clip and must not weaken ADR 0003.

## Decision
A hidden clip whose category is JWT gets a context-menu command, **Decode JWT**, under Show.

- **Same gate as Show.** It asks through `actions.authenticate` (`AppState.authenticateInShelf`, so the shelf stays
  open) and honours `AuthenticationGrace`: one window, no second timer. No authentication available, no command
  (`canRevealHidden`).
- **Not on a covered card.** `CardConcealment.allowsDecode` is false while the screen-share blur or Hide Clip Contents
  covers the card, and while a content-filter or pending-analysis cover is on it. A masked secret that is only
  unshown is the case Decode is for.
- **Read-only, in view state.** The decoded text is held by the popover's card as view state. It is never stored,
  never put in a clip, a note, search, a log line or Undo (`UndoHistory` is unaffected: nothing is changed), and never
  sent to the AI: Decode is not an AI action and `allowsAIActions` is unchanged.
- **Closes where Show closes.** The shelf closing, the card leaving the screen, the History Lock, a cover and
  `hideSecretsGeneration` all clear it, through the same hooks as `hideSecret()`.
- **Not verified.** Pesto never checks the signature and says so on the popover. A token with `alg: none` says it has
  no signature. A malformed token says it cannot be read and shows nothing else.
- **The signature part is never shown.** Header and payload only.
- **Copy Payload** writes the payload JSON through `AppState.writeText(_:protected: true)`: concealed, kept off
  Universal Clipboard, cleared after `secretClearDelay`.
- **Bounded.** Input over 16 KB is refused before decoding, and each part is decoded to at most 64 KB.

## Consequences
- The payload of a JWT, which can hold names and addresses, is readable after one authentication, as the whole token
  already is after Show. No new place keeps it.
- `JWTDecoder` lives in `Core/Paste` and is tested without a view.

## Docs affected
- `README.md` (Features: Decode JWT)
- `docs/guide/privacy-and-security.md` (Decode JWT beside Show)
