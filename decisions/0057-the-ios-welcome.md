# 0057. The iPhone and iPad welcome

Status: Accepted

It supersedes the line in `docs/design/ios-library.md` that left onboarding out on purpose and kept link previews off on iOS because there was no setup screen to ask. It applies the condition of ADR 0042 (a visible switch with a caption saying what is sent) to the iOS app.

## Context
A new iPhone or iPad install opened on an empty library with no word on how clips get in (iOS lets an app read the clipboard only when it is open and the person allows it), and link previews stayed off because nothing could ask.

## Decision
- **Three steps, shown once** over the library (`Setting.welcomeShown`, set when it is presented): a full-screen cover on iPhone, a form sheet on iPad where swiping it down is Skip. Skip is on every step. Settings has Show Welcome Again, which shows the stored values and applies no default. A test or UI-test launch shows it only when `Setting.uitestShowsWelcome` asks.
- **Link previews are switched on when step two appears and only then**, with the switch and its caption in view, and only where no value is stored (`hasValue`, as ADR 0042). A welcome skipped on step one leaves them off. A stored answer is never overwritten.
- **The History Lock is offered off.** Turning it on asks for Face ID, Touch ID or the passcode on the spot; a refusal leaves it off.
- **Sync is offered, never started.** Turn On Sync and Not Now close the welcome with equal weight; Turn On Sync then opens the existing sync flow over the library. Nothing nags about sync later.
- **AutoFill is an in-context tip, not a step**: the first time a clip is pinned or saved as a snippet, a dismissible card in the library says "Insert your clips in any app. Clips only, never passwords. You switch Pesto on in Settings." Turn On switches `Setting.quickInsertEnabled` on and opens iOS's AutoFill provider settings (`ASSettingsHelper.openCredentialProviderAppSettings`, iOS 17; Settings where it fails). Shown once (`Setting.autoFillTipShown`), never while the lock is on.
- **No permission prompts, no network** while the welcome is open: no paste, Photos or notification request, no fetch, no "Recommended" badge. Art is decorative, hidden from VoiceOver, and moves once per step through `Motion.animation` with the named curves; Reduce Motion draws the final frame.
- **Art** is layered SVG exported by `design/source/brand-art.py --mobile` into `Sources/Mobile/Resources/Assets.xcassets`.

## Consequences
- A new iOS install that continues past step one makes a request to the site of a link it copies, and the site sees the device's IP address.
- A person who skips on step one finds link previews off and can switch them on in Settings.
- Tested: `MobileWelcomeTests`, `MobileAutoFillTipTests`, `WelcomeUITests`.

## Docs affected
- `docs/design/ios-library.md`, `decisions/README.md`, `docs/testing.md`
