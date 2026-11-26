# 0072. The keyboard opens Pesto only as Apple shows; AutoFill says where the settings are

Status: Accepted (owner, 2026-11-25, after an App Review consult); the AutoFill gear is removed by ADR 0073

Amends ADR 0066 (the keyboard's Pesto chip and AutoFill's gear, through `HostURLOpener`). Numbers 0068 to 0071 are taken
by records on other branches.

## Context
The Pesto chip and AutoFill's gear opened Pesto's Keyboard & AutoFill page with a selector built from a string and a
method looked up at run time, a pattern App Review reads as hiding a private API (guideline 2.5.1).
`NSExtensionContext.open` works only in Today and iMessage extensions. Guideline 4.4.1 says a keyboard must not "launch other apps besides
Settings", and an Apple DTS engineer confirmed in January 2026 (developer forums thread 812091) that a keyboard may
open its own app, posting the plain `UIApplication.open` reached through the responder chain as the way. On iOS 26
that call needs Full Access. No such statement covers a credential provider.

## Decision
- **The keyboard** opens Pesto with the plain call (`HostURLOpener`, now in `Sources/MobileKeyboard`), only from the
  person's tap and only with Full Access. Without Full Access its settings panel says "More settings are in Pesto:
  Settings → Keyboard & AutoFill."
- **AutoFill's gear** shows where the settings are ("Open Pesto, then Settings → Keyboard & AutoFill.") and opens
  nothing.
- **No extension calls an API through a selector built from a string** (`ExtensionRuntimeCallTests`).
- The App Review notes for a submission mention the keyboard's button and cite 4.4.1's "other apps".

## Consequences
- If review still objects to the keyboard's button, the panel's line is the fallback: the button goes, nothing else.
- Whether the jump works on a device (iOS 26, Full Access on and off) is a hand check.

## Docs affected
- `decisions/README.md`
