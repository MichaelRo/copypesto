# Releasing Pesto

The release steps (`make publish-release`, `make marketing-images`) are the maintainer's alone; a contributor never runs
them. The website takes what it needs from this repository on its own side. Dependabot watches the GitHub Actions only: Sparkle and swift-snapshot-testing are pinned
by commit in `Pesto.yml`, so check their releases by hand before each release.

Pesto 1.0 is distributed unsigned: built with a self-signed "Pesto Release" identity (no Gatekeeper trust, no
notarization, no hardened runtime), outside the Mac App Store. Developer ID signing and notarization come later, once
the Apple Developer Program is paid for (the sections headed "Later, once enrolled"). Nothing here has been run end to
end yet: the first release is also the test of this pipeline, so do it with a throwaway version first.

## What a dry run already proved (2026-09-25, unsigned)
A Release build (`CODE_SIGNING_ALLOWED=NO`) succeeds, embeds Sparkle, reports 1.0.0 (1), carries the compiled icon
(`Pesto.icns` + `Assets.car`) and the appcast URL and public key, and packages into a DMG with `hdiutil`. The release DMG is laid out by `scripts/make-dmg.sh` (Pesto, an Applications
shortcut and a background with an arrow); `make dmg-preview` builds an unsigned one to look at the window. It also caught
internal `CLAUDE.md` notes being copied into the app bundle (now excluded in `Pesto.yml`). Signing, notarization and
stapling are the parts that still need your account.

## What the gate checks about release (2026-10-03)
`scripts/verify.sh` builds the Release configuration unsigned, ad-hoc signs it with the hardened runtime and verifies the
bundle (`make release-check`); it cannot launch it, because an ad hoc signature fails library validation for Sparkle.
The Team ID reaches `xcodebuild archive` as `DEVELOPMENT_TEAM`, and `scripts/render-export-options.sh` fills
`exportOptions.plist` (it refuses anything but 10 letters and digits). Sparkle and SnapshotTesting are pinned by commit
in `Pesto.yml`, and `Pesto.resolved` holds every transitive revision (`make generate` restores it, `make
update-resolved` refreshes it: review the diff). CI installs SwiftFormat, SwiftLint and XcodeGen through
`scripts/install-tools.sh`, which checks each download's SHA-256 in `scripts/tool-versions.env`.

## One-time setup, unsigned (1.0)
1. **Release signing identity.** `make setup-release-signing` creates the self-signed "Pesto Release" identity once.
   Export its `.p12` and back it up with the Sparkle key (below), encrypted, in two places that are not this Mac: a new
   identity is a new signature, and a Mac that has the old one stops trusting updates less gracefully.
2. **Sparkle keys**: as in "Later, once enrolled", step 3 (the same key signs the unsigned and the later releases; back
   it up before the first release).
3. **Where the appcast lives**: as in "Later, once enrolled", step 4. `https://copypesto.net/appcast.xml` never changes.

## Each release, unsigned (1.0)
1. Set `MARKETING_VERSION` and bump `CURRENT_PROJECT_VERSION` (an integer that only goes up) in `Pesto.yml`.
2. `scripts/verify.sh` is green, and the manual checklist in `docs/testing.md` ("Before a release") is done.
3. `make release-unsigned` builds the app, signs it with "Pesto Release" and writes `Pesto-<version>.dmg` and its
   `.sha256` file.
4. Sparkle signature: `sign_update <dmg>` prints `sparkle:edSignature` and `length`.
5. SHA-256: read the `.sha256` file, or `shasum -a 256 <dmg>`.
6. Put these in the GitHub release body of `MichaelRo/copypesto`: the commit or tag, the Xcode version
   (`xcodebuild -version`), the SHA-256 of the DMG, the `codesign -dv --verbose=2 /Applications/Pesto.app` lines, and
   the checks a person can run: `shasum -a 256 ~/Downloads/Pesto-<version>.dmg`, `codesign -dv --verbose=2
   /Applications/Pesto.app`, and the Open Anyway steps (`docs/guide/getting-started.md`, step 3). There is no `spctl` or
   `stapler` line: those apply to notarized builds. Build output is not reproducible bit for bit (signatures carry
   timestamps), so do not say it is.
7. Local update test before the release ships: install 1.0.0, serve a throwaway 1.0.1 from a local appcast, and Check
   for Updates. Pass: it updates, the history opens with no Keychain prompt, and paste still works without granting
   Accessibility again (`docs/testing.md`, "Before a release").
8. Upload the DMG to the GitHub release and publish the appcast, then check for updates from an older build. Do not
   turn on immutable releases yet (see below).

## Later, once enrolled: one-time setup (needs an Apple Developer account)
1. **Developer ID Application certificate** in your login keychain, and your 10-character **Team ID**. `make archive`
   reads the team from `security find-identity`, or pass `APPLE_TEAM_ID=XXXXXXXXXX`.
2. **Notarization credentials**: `xcrun notarytool store-credentials pesto-notarytool` (Apple ID + app-specific password
   or an App Store Connect API key). The Makefile expects the profile name `pesto-notarytool`.
3. **Sparkle keys**: `generate_keys` from the Sparkle package prints the public EdDSA key (already in
   `Info.plist` as `SUPublicEDKey`); the private key lives in your keychain. Lose it and existing installs can't update. **Back it up before the first
   release:** `generate_keys -x <file>` exports it; keep the file encrypted, in two places that are not this Mac, and
   keep the Developer ID certificate (a `.p12` from Keychain Access) the same way. A key can be rotated only while the
   Developer ID team stays the same (Sparkle's publishing guide), so do not lose the team either. The registrar and
   Cloudflare accounts for `copypesto.net` get hardware-key two-factor, and the domain is registered for several years.
4. **Where the appcast lives.** `SUFeedURL` points at `https://copypesto.net/appcast.xml`, which returns 404 until the
   website is deployed: it builds `/appcast.xml` from its release notes (`src/content/releases/`). Every shipped copy polls this URL forever, so it must be live and
   must not move after the first public release. If it ever has to, keep a redirect on the old host.
5. **iCloud is not part of v1**: `Pesto.entitlements` is empty, so no provisioning profile is needed. Backup and
   multi-device sync are a later feature (`docs/sync-design.md`).

## Later, once enrolled: each release
1. Set `MARKETING_VERSION` and bump `CURRENT_PROJECT_VERSION` (an integer that only goes up) in `Pesto.yml`.
2. `scripts/verify.sh` is green, and the manual checklist in `docs/testing.md` is done.
3. `make release` (archive, export, notarize the app, build a DMG, sign, notarize and staple it).
4. Sparkle signature: `sign_update <dmg>` prints `sparkle:edSignature` and `length`. In the website repo, add
   `src/content/releases/<version>.md`: front matter `version` (`MARKETING_VERSION`), `build` (`CURRENT_PROJECT_VERSION`),
   `date`, `dmgURL` (the GitHub release asset), `length`, `edSignature`, `sha256` (`shasum -a 256 <dmg>`) and
   `minimumSystemVersion`, and the release notes as the body. The same file feeds the changelog page and `/appcast.xml`, and
   `npm run verify` there checks the URL and the shape of every field.
5. Upload the DMG to a GitHub release, publish the appcast, then check for updates from an older build.
6. Put these in the GitHub release body, so anyone can check a download against the source: the commit or tag, the Xcode
   version (`xcodebuild -version`), the SHA-256 of the DMG, the `codesign -dvvv` lines for the Team ID, and the three
   commands a person can run (`shasum -a 256`, `spctl --assess --type execute -vv`, `xcrun stapler validate`). Build
   output is not reproducible bit for bit (signatures carry timestamps), so do not say it is. Turn on immutable
   releases only after one full update from build N to N+1 has worked: assets cannot be replaced afterwards and a tag
   name cannot be reused, so a bad 1.0.0 becomes 1.0.1.

## Later, once enrolled: checks that prove the artifact is right
```bash
codesign -dvvv Pesto.app          # Developer ID, your team, hardened runtime
codesign -dvvv Pesto.app/Contents/PlugIns/PestoControls.appex   # the Control Center extension: same team, sandboxed
spctl --assess --type execute -vv Pesto.app
xcrun stapler validate Pesto-<version>.dmg
curl -sI https://copypesto.net/appcast.xml | head -1   # 200
```

There is deliberately no release workflow in CI: the Developer ID identity and notary credentials stay on your Mac, so a compromised third-party action can never see them. `WorkflowSafetyTests` enforces it.
