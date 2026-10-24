# Roadmap

This document tracks high-level product directions for Pesto across **Now**, **Next**, and **Later** horizons. It has no dates and is not a promise: items move or drop as we learn what works best on the Mac.

For bug reports, feature requests, or contributor-ready work, see [GitHub Issues](https://github.com/MichaelRo/copypesto/issues) and [CONTRIBUTING.md](CONTRIBUTING.md). For what has already shipped, see [CHANGELOG.md](CHANGELOG.md).

## Now — 1.0.x Polish & Accessibility

- **Shelf & filter polish.** Compact app chips on the shelf that expand on hover, selection, or focus; clearer drag affordances when reordering collections; any-of app filtering across the shelf and search bar.
- **Toast & panel contrast.** Stronger dark-mode border and surface contrast for floating notices and the on-device AI result panel over bright windows, plus an in-app notice when a manual update check finds Pesto is already up to date.
- **VoiceOver & keyboard navigation.** Smoother VoiceOver traversal across cards and the Settings panes, and cleaner Tab navigation in the Settings search bar.
- **Guide & import documentation.** Per-app sections in [Moving from another app](docs/guide/moving-from.md) for every supported clipboard manager.

## Next — Distribution & Everyday Ergonomics

- **Developer ID signing and notarization.** Sign and notarize releases with an Apple Developer ID so Pesto opens on first launch without the *Open Anyway* step in System Settings.
- **Ship the `pesto` CLI inside the app bundle.** Bundle the command-line tool inside `Pesto.app/Contents/MacOS/pesto` so it is available without building from source.
- **Shelf placement options.** Optional placement of the shelf or quick menu near the active window or cursor.
- **Markdown and code preview polish.** Richer formatting and syntax highlighting in the hover card and Quick Look preview.

## Later — Under Consideration

- **End-to-end encrypted multi-device Mac sync.** Building on the encrypted backup format ([ADR 0010](decisions/0010-backup.md)) so two Macs you own can keep their shelves in step through iCloud without Pesto running a server or reading your clips.
- **Richer snippet placeholders.** Date math, secondary clipboard references, and fill-in fields when expanding a snippet.
- **Rule-based collection routing.** Additional predicates for smart collections while keeping the rule engine deterministic and local.
