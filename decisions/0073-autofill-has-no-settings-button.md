# 0073. AutoFill has no settings button

Status: Accepted (owner, 2026-11-26, backlog triage)

Amends ADR 0072's AutoFill bullet. The keyboard's way to its settings is unchanged.

## Context
ADR 0072 kept a gear in the AutoFill picker's toolbar that opened nothing: no API lets a credential provider open its
app, so the gear showed an alert saying "Open Pesto, then Settings → Keyboard & AutoFill." A button whose only result
is a sentence of directions reads as broken, takes a toolbar slot from the picker, and the person is in the middle of
filling a field, not changing settings.

## Decision
- The AutoFill picker has no settings button and no directions alert. Its toolbar is Cancel and the search field.
- The way to the settings is the app: Settings → Keyboard & AutoFill, the AutoFill tip banner and its Set Up action.
- `ExtensionRuntimeCallTests` fails on a `gearshape` or a "Pesto Settings" alert in `Sources/MobileAutoFill`.

## Consequences
- A person who wants to change what AutoFill shows has to know the page is in the app; the setup guide and the tip
  banner already point there.

## Docs affected
- `decisions/README.md`
