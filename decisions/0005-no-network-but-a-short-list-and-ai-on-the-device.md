# 0005. Pesto uses the network only for a closed list, and every AI feature runs on the device

Status: Accepted

## Context
Clipboard text is the most private text on a Mac, so "no clip content leaves the Mac" is worth stating only if it has no
exceptions. A few features need the network at the person's request (link previews, Maps, carrier tracking pages, the
update feed). Cloud AI providers would each add an endpoint, a stored API key and header and logging rules. Apple's
on-device model removes all of that, at the cost of a smaller model that exists only on some Macs.

Copying a GIF with "Copy Image" from Chrome, Arc or Edge puts only the first frame (a PNG) on the pasteboard, with the
picture's address in an `<img>` tag of the HTML flavor. Nothing local can recover the missing frames.

## Decision
**The network use is a closed list**, enforced by `Tests/PestoRegressionTests/NetworkGuardTests.swift`: the update feed
host in `Info.plist` (`copypesto.net`), the update download host named in the appcast (`github.com` releases, only after
the person accepts an update), link previews, `maps.apple.com`, and the UPS, USPS, FedEx and DHL tracking pages (links
the
person opens, never fetched by Pesto). Only `URLMetadataFetcher.swift` and `BoundedDownload.swift` may open a connection
themselves. A new endpoint needs a new decision, an allowlist entry and a privacy-copy review.

**Link previews** use `LPMetadataProvider` plus bounded direct downloads in `URLMetadataFetcher` (a page's head up to
64 KB for its picture, the picture itself, and a GIF), all through `BoundedDownload`. They are off until the person
turns
them on in Settings → Privacy (`LinkPreviewPolicy`), and always off in a test host or UI-test launch, whatever is
stored.
Addresses vetted by `LinkPreviewEligibility` only: no addresses on this Mac or its network, no credentials in the
address,
no token, code or signature in the query, no reset, verify or unsubscribe paths.

**A browser GIF is fetched under the same switch.** The watcher reads the `<img src>` of the HTML flavor next to a still
picture (PNG, TIFF or JPEG), reading only the first 100 KB (`ImageSourceAddress`), and keeps it on the capture
(`PasteboardCapture.sourceImageURL`) only if it is `https`, its path ends in `.gif` and it passes eligibility. After the
still is saved, the fetcher checks `LinkPreviewPolicy.mayFetchGIF` (the switch, eligibility, and that the history
is not locked: a locked history causes no request), then calls
`URLMetadataFetcher.downloadGIF`: at most 16 MB, 15 seconds, status 200, and the body must start with a GIF header. The
GIF
replaces the still (`StorageService.upgrade(_:toGIF:)`), re-encrypted bound to the clip (ADR 0002). Switch off or any
failure, or a locked history, leaves the still.

**AI is on the device only.** Every AI feature (Summarize, Translate, Extract, Describe Image, picture screening, Ask
Pesto's sentence understanding) uses Apple's on-device model through `AppleIntelligenceClient`. No cloud provider, API
key
or AI host exists in the sources: `NetworkGuardTests.noAIProviderHosts` fails if one returns, `LegacyAIKeyCleanup`
removes
a key an older build saved, and `AIActionCoordinator` takes an injectable completion, the only seam where a provider
could
be added (which needs a new decision). Text actions send the whole text up to `AIInputBudget` (`(context size - 1,200
tokens) * 3` characters, clamped to 4,000...40,000; 8,000 only where the window cannot be asked) and the answer says
when
the text was cut (`AIResult.coverage`). One switch, Settings → General → Apple Intelligence
(`AIAvailability.isUserEnabled`,
on by default), turns all of it off.

**Unavailable features say why** (`AIAvailability.presentation`): a Mac that can never run it (`needsNewerMacOS`,
`deviceNotEligible`) hides the controls; a fixable state (`notEnabled`, `modelNotReady`) or Pesto's own switch off
(`turnedOff`) disables them with the reason, and for `notEnabled` a button to the System Settings pane. Describe Image
also
needs a model that reads pictures (`supportsVision`). Ask Pesto keeps working through `RuleBasedQueryInterpreter`
(`FallbackQueryInterpreter`). Pesto's floor is macOS 15, so a Mac without Apple Intelligence gets no AI actions.

**Picture screening.** When the content filter is Blur or Hide (`NSFWMode.detectsContent`; Blur is the default), a
captured
picture, and the picture of a linked page when first fetched, is shown to the model downscaled to 768 px
(`OnDeviceImageScreener`) with a trivial request. If its guardrails stop it or it refuses (`guardrailViolation`,
`refusal`), the item is flagged and handled by the person's mode; the reply is discarded. Any other outcome is "not
flagged".

## Consequences
- No clip content reaches any AI service and Pesto holds no AI credentials. Screening is the one automatic AI use: it
  needs
  no key and no network, and costs about a second per new picture in the background.
- Screening is best-effort: guardrails are a safety filter, not a classifier, can miss partial nudity, art or memes, may
  trip on other unsafe content, and may change with the OS. Any card can be marked by hand.
- A GIF from a browser plays on the shelf a second or two after the copy, and the host sees one GET for a picture it
  already
  served the browser. A GIF behind a login or short-lived token stays a still.
- `NetworkGuardTests` names this record by its file path in a comment and must be updated when the file is renamed.
- Tests: `NetworkGuardTests`, `GIFUpgradeTests`, `ImageSourceAddressTests`, `LinkPreviewEligibilityTests`,
  `LinkPreviewPolicyTests`; the `ImageSensitivityScreening` protocol lets storage tests inject a fake screener.

## Docs affected
- `docs/guide/privacy-and-security.md` (link previews, the GIF, screening, on-device AI)
- `docs/guide/settings.md` (Apple Intelligence and Link Previews switches)
- `Sources/Core/AI/CLAUDE.md`
- `AGENTS.md` (security invariant 1)
