# Security policy

Pesto keeps clipboard history, which is sensitive by nature, so security and privacy reports matter a lot here.
Thank you for looking.

## Reporting a vulnerability

**Please do not open a public issue for a security or privacy problem.**

Report it privately, either way:

1. **GitHub private vulnerability reporting.** Open a
   [private advisory](https://github.com/MichaelRo/copypesto/security/advisories/new). This keeps the discussion and any
   fix in one place.
2. **Email** security@copypesto.net, if you do not use GitHub.

Please include what you found and its impact, the Pesto and macOS versions, and the steps to reproduce it (a small
proof of concept helps). Say how you would like to be contacted and whether you would like to be credited.

## What to expect

Pesto is free and maintained by one person. Every report is read, and you will get an acknowledgement within seven
days. There is no promised fix date: a confirmed problem is fixed in a release, and you are credited in the release
notes or the advisory if you wish. Please keep the report private until a fix is out, or for 90 days after you report
it, whichever comes first; if a fix is not ready by then, say what you plan to publish and we will agree on a date.

## In scope

- History or clipboard content leaving the Mac other than through the requests listed in
  [Privacy and security](docs/guide/privacy-and-security.md): update checks, link previews (which can be turned off),
  links the person chooses to open, and the automatic backup file in a folder the person picked.
- Clip content, previews, titles, notes, tags, page titles or search vectors written to disk unencrypted. The guide
  documents what is not encrypted by design: app names, times and sizes; clip kinds, pins and counts; collection names
  and rules; the masked previews of secrets (a card's last four digits); colors; the preview of the latest clip without a
  secret, kept for the `pesto` command while the history lock is off; and the plain-text export.
- A backup that can be read without its passphrase or recovery key.
- A secret (card number, key, token, password line) shown on the shelf without the Show action and Touch ID or the
  account password.
- The exclusion list or the concealed-copy rules bypassed, so a password manager's copies are kept, or a timed
  allowance that outlasts its time or applies to another app.
- The history lock bypassed through the shelf, `pesto://` links, AppleScript, Shortcuts, the Control Center control,
  the `pesto` command or any other entry point.
- A link preview fetched for a link Pesto should skip: links that carry a token, code or signature, addresses on the
  Mac or its network, or any link or browser GIF while the history is locked.
- The update path: anything that lets someone install an update that was not signed with Pesto's key.

## Out of scope

- Anything that needs control of the unlocked Mac, or a process running as the same user. The guide explains this
  limit.
- The plain-text export (Settings, Data, Import and export), which is documented as unencrypted.
- Denial of service through malformed pasteboard data, without a data-exposure impact.
- Output from automated scanners with no demonstration that it can be exploited.
- Vulnerabilities in third-party components (Sparkle, Apple frameworks): please report them upstream. Tell us as well
  if Pesto uses them in an unsafe way.
- Builds that were not made and signed by this project, such as forks (see [TRADEMARKS.md](TRADEMARKS.md)).

## Supported versions

Only the latest release receives security fixes.
