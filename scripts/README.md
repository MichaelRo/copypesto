# Scripts

Run them from the repository root. `make help` lists the `make` targets that wrap most of them.

## The gate
| Script | What it does |
|---|---|
| `verify.sh` | The full gate: lint, Core tests, Debug build with warnings as errors, hosted and UI tests, screenshots. About 40 minutes (`make verify`; `--fast` skips the UI tests). |
| `verify-changed.sh` | Lint, Core and hosted tests, plus only the UI suites the changed files can affect. |
| `verify-rerun-failed.sh` | Re-runs just the tests that failed in a gate run. |
| `verify_judge.py`, `verify_failures.py`, `verify-allowed-skips.txt` | Judge a run (test counts, allowed skips) and list failures. Used by the scripts above. |
| `check-memory-budget.sh`, `check-release-build.sh` | Gate steps: the memory budget on a 5,000-clip history, and an ad hoc signed Release build. |

## Benchmarks
| Script | What it does |
|---|---|
| `bench-latency.sh` (+ `bench-latency/`) | Paste, copy, shelf-open, hover and memory timings with a real target app (`make bench-latency`). |
| `bench-scroll.sh`, `profile-scroll.sh` (+ `profile-scroll/`) | Animation Hitches traces of the shelf while a scroll runs (`make bench-scroll`). |

## Release
| Script | What it does |
|---|---|
| `make-dmg.sh`, `make-dmg-background.swift` | Build the installer disk image. |
| `render-export-options.sh` | Writes `exportOptions.plist` with the team ID filled in. |
| `install-tools.sh`, `tool-versions.env`, `select-xcode.sh` | Pinned lint and project tools, and Xcode selection, for CI. |

## Documentation and housekeeping
| Script | What it does |
|---|---|
| `export-doc-images.sh` | Copies the documentation screenshots from the newest gate run into `docs/images`. |
| `take-pictures.sh` | `make pictures`: retakes the documentation and website pictures from one build and stamps the commit (`docs/pictures.md`). |
| `export-marketing-images.sh` | Copies the website pictures out of the newest UI-test result (`make marketing-images`). |
| `record-lunch-rush.sh` | Records one beat of the website demo video (`LunchRushRecordingTests`) with the window recorder; needs Screen Recording for the terminal and a person at an unlocked Mac. |
| `clean-test-defaults.sh` | Removes throwaway preferences files that old test runs left in `~/Library/Preferences` (`--dry-run` lists them). |

## Developer tools (`dev/`)
| Script | What it does |
|---|---|
| `window-recorder.swift` | Records only Pesto's own windows with ScreenCaptureKit, so a UI-test run is captured without macOS's dimming notice (`record-lunch-rush.sh` builds and uses it). |
| `probe-pasteboard.swift` | Read-only: records what each copy puts on the pasteboard. |
