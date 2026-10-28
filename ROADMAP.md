# Pesto Roadmap

What is planned for Pesto, grouped into **Now**, **Next** and **Later**. For shipped releases, see the [changelog](https://copypesto.net/releases/).

---

## Now: 1.0.x polish and accessibility

- **Shelf and chip bar refinements.** App chips on the shelf show only their icon at rest and open their name on hover, focus or selection; reordering collections shows one accent bar where the chip will land; choosing several apps shows clips from any of them.
- **Floating panel contrast and dragging.** Card material across the AI result panel, status toasts, stack HUD and hover card so text stays readable over bright windows in dark mode, plus header dragging on the AI result panel.
- **Keyboard and VoiceOver polish.** VoiceOver reads cards and the Settings panes in order, and Tab moves straight from an empty Settings search field into the pane.
- **Update checks.** A switch in Settings → General to turn automatic update checks on or off, and a quiet menu-bar toast when a manual check finds Pesto is already up to date.

## Next: distribution and everyday use

- **Apple Developer ID signing and notarization.** Signing release builds with a Developer ID certificate and notarizing with Apple so macOS opens Pesto without the first-launch Gatekeeper confirmation and keeps Keychain and Accessibility permissions across updates without re-prompting.
- **Homebrew Cask.** Publishing an official Cask once builds are Developer ID notarized.
- **Additional clipboard importers.** Expanding Settings → Data → Import to cover more macOS clipboard managers alongside the 11 already supported.
- **Smart / Dynamic Snippets.** Snippets that ask for a value when you paste (a name, a choice, an optional paragraph) and remember what you typed, and a suggestion that notices clips differing in a few words and turns them into one snippet, all on your Mac and never sent anywhere ([ADR 0017](decisions/0017-smart-snippets.md), built, awaiting its release).

## Later: under consideration

- **End-to-end encrypted multi-device Mac sync.** Building on the encrypted backup format ([ADR 0010](decisions/0010-backup.md)) so two Macs you own can keep their shelves in step through iCloud Drive without Pesto running a server or reading your clips.
- **Desktop widgets.** A macOS WidgetKit extension showing recent non-sensitive clips while respecting the History Lock and secret masking rules.
- **Expanded smart collection rules.** More rules for smart collections, evaluated on your Mac.
