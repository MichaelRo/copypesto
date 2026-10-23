# 0001. Pesto is free and open source, every feature ships on every install, and it installs as one copy in Applications

Status: Accepted

## Context
A paywall in front of the features that make a clipboard manager useful works against the goal of a tool anyone can
rely on; the product is meant to win on craft rather than scarcity. The code has been published under the MIT license, Pesto
is distributed from its own website (not the Mac App Store), and multi-device sync is designed but not built, so a paid
tier, even a cosmetic one, has nothing to attach to.

Pesto also needs exactly one installed copy. Launch at login registers only an app in an Applications folder, updates
replace the app in place, and the Accessibility grant belongs to the copy that asked for it. People who run an app from
a disk image or the Downloads folder rarely move it.

## Decision
**No gating.**
- Every feature is available on every install: no history cap, no collection cap, no gate on AI actions, insights, the
  History Lock or the content filter. There is no feature-flag, tier or gate code, and no StoreKit.
- Support is voluntary and outside the app: a plain link to the project's GitHub Sponsors page (`.github/FUNDING.yml`,
  the README). No badge, icon, theme, credit or capability inside Pesto depends on having donated, and the app never
  nags. A link in About is one quiet line.
- Pesto never handles payment: no payment form, card field or checkout in the app.
- A paid tier of any kind needs a new decision record. If sync ships later, it is free by this decision.

**One installed copy.**
- The release disk image (`scripts/make-dmg.sh`) shows Pesto, an arrow and an Applications shortcut over a background
  that says "Drag Pesto into Applications" (`scripts/make-dmg-background.swift`). Finder lays the window out, so the
  script needs a logged-in session. `make dmg-preview` builds an unsigned copy to look at.
- On a normal launch from anywhere other than an Applications folder, Pesto asks once per launch whether to move itself
  (`InstallLocation.evaluate`, `AppDelegate.offerToMoveToApplicationsIfNeeded`). Accepting runs `AppInstaller`: it
  copies the app to `/Applications` (or `~/Applications` when that is not writable), moves an older copy there to the
  Trash, opens the new copy and quits; from a disk image it also ejects the image shortly after. "Don't ask again" is
  remembered (`Setting.installPromptSuppressed`).
- A copy run from `.build`, `DerivedData` or `Build/Products` is never asked: development builds run in place on
  purpose. The prompt requires `LaunchMode.usesSystemIntegrations`, so a UI-test or hosted-test launch never shows it.
- If the copy fails, an alert tells the person to drag the app into Applications themselves.

## Consequences
- No revenue mechanism ships; adoption and quality are the goals.
- A quarantined app launched from Downloads runs from a translocated read-only path; copying from it works, so the move
  needs no knowledge of the original folder.
- Replacing a copy that is running in Applications trashes it, so two instances can run until the old one quits. This
  is rare and accepted.
- `InstallLocationTests` cover the location classification, the copy, replacement of an older copy and leaving a copy
  that is already in place alone. The disk image layout and the alert are checked by hand.

## Docs affected
`README.md`, `.github/FUNDING.yml`, `docs/development.md`, `AGENTS.md` ("No feature gating").
