# 0042. Link previews and copies from other devices start on for a new install

Status: Accepted

It supersedes the default in ADR 0005 ("link previews are off until the person turns them on") and in ADR 0004 (`Setting.keepsRemoteCopies` is off by default). Nothing else in either changes: the endpoints, eligibility rules, concealed-marker handling and the switches stay.

## Context
Both switches improve the first hour with Pesto (cards with a title and picture, clips from an iPhone) and neither is discoverable once buried in Settings. Setup already carries a "More options" disclosure, and it already holds the remote-copies switch.

## Decision
- **Setup turns both on, once, for a new install** (`OnboardingDefaults.applyOnce`, run when the setup choices appear), without overwriting a value already stored by a restore or import (`hasValue`). A Mac that finished setup before this change (`Setting.hasOnboarded`) is never switched on; its stored answer stands. `Setting.linkPreviews` and `Setting.keepsRemoteCopies` still default to false everywhere else.
- **The switches live inside setup's More options disclosure**, collapsed by default so setup stays quick (three steps); opening it shows each toggle with a caption stating what is sent, alongside Keep clips for and Check for updates automatically.
- **The person's answer is theirs after the first offer** (`Setting.onboardingDefaultsOffered`, a per-Mac marker, not exported).
- **What does not change:** `LinkPreviewEligibility` (no reset, token or signed links), bounded downloads, the locked-history rule, and that a test host or UI-test launch never contacts the network.

## Consequences
- A new install makes a request to the site of an eligible link it copies, and the site sees the Mac's address. The privacy guide says so.
- An existing user is not offered the change here. A one-time shelf suggestion for them is a separate decision.
- Tested: `OnboardingDefaultsTests` (first run, already onboarded, answer kept, not live, registry).

## Docs affected
- `docs/guide/privacy-and-security.md`, `settings.md`, `faq.md`, `getting-started.md`, `README.md`
- `Sources/Core/Pasteboard/CLAUDE.md`, `decisions/README.md`
- The Settings footer for link previews, and the setup pictures (`make pictures`)
