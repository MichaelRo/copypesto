# Pictures

Every picture in the README, the guide and the website, where it comes from and where it appears. `make pictures` retakes
all of them from one build and writes the app commit into `docs/images/SOURCE`; the website repo checks that its
pictures carry the same commit. `PicturesMapTests` fails when a README or guide picture, or a file in `docs/images`,
is missing from the first table.

A change to any user-visible screen retakes all pictures, and the README, the guide and the site are updated in the same
pair of pull requests.

## README and guide (`docs/images`)

| File | Taken by | Appears in |
|---|---|---|
| `shelf-light.png` | `DocScreenshotTests` | README, guide (`README.md`, `using-pesto.md`) |
| `shelf-dark.png` | `DocScreenshotTests` | README |
| `search.png` | `DocScreenshotTests` | README, guide (`using-pesto.md`) |
| `ask-pesto.png` | `DocScreenshotTests` | README |
| `collections.png` | `DocScreenshotTests` | guide (`using-pesto.md`) |
| `settings-collections.png` | `DocScreenshotTests` | guide (`settings.md`) |
| `sensitive-card.png` | `DocScreenshotTests` | README, guide (`privacy-and-security.md`) |
| `settings-general-light.png`, `settings-general-dark.png` | `DocScreenshotTests` (settings panes in both modes) | guide (`settings.md`, light) |
| `settings-appearance-light.png`, `settings-appearance-dark.png` | `DocScreenshotTests` | guide (`settings.md`, light) |
| `settings-privacy-light.png`, `settings-privacy-dark.png` | `DocScreenshotTests` | guide (`settings.md`, light) |
| `settings-snippets.png`, `settings-data.png` | `SettingsFlowTests` | guide (`settings.md`) |
| `settings-snippet-fields.png` | `SnippetSuggestionsTests` | guide (`using-pesto.md`) |
| `settings-shortcuts.png` | `SettingsReorganisationTests` | guide (`settings.md`) |
| `fill-in-prompt.png` | snapshot baseline `FillInPromptTests/test_allKindsOfField_light` (record snapshots to retake) | guide (`using-pesto.md`) |
| `about.png` | `AboutWindowTests` | guide (`settings.md`) |
| `history-locked.png` | `HistoryLockTests` | guide (`privacy-and-security.md`), `docs/testing.md` |
| `onboarding.png`, `onboarding-welcome.png`, `onboarding-ready.png` | `OnboardingAndStatesTests` | guide (`getting-started.md`) |
| `theme-basil-light.png`, `theme-basil-dark.png` | `ThemeShelfTests` | README |
| `theme-parmesan-light.png`, `theme-parmesan-dark.png` | `ThemeShelfTests` | README, guide (`settings.md`, light) |
| `theme-pine-nut-light.png`, `theme-pine-nut-dark.png` | `ThemeShelfTests` | README |
| `theme-mortar-light.png`, `theme-mortar-dark.png` | `ThemeShelfTests` | README, guide (`settings.md`, light) |
| `installer.png` | `scripts/make-installer-image.swift` | guide (`getting-started.md`) |

`scripts/export-doc-images.sh` copies them out of the UI-test screenshots and renames them. The website syncs this folder
into `src/assets/guide` (`scripts/sync-from-app.sh` there), so the guide pictures on the site are these files.
`docs/images/SOURCE` is the commit stamp.

## Website (`.build/marketing`, then `src/assets/marketing` in the website repo)

All come from `MarketingScreenshotTests` (`make pictures`, or `make marketing-images` alone), as 2x masters named
`<name>-<light|dark>@2x.png`; `scripts/marketing/copy-from-app.sh` in the website repo copies them and stamps the commit.

| Name | Test | Appears on |
|---|---|---|
| `hero`, `hero-narrow` | `test_hero` | home hero |
| `01-shelf`, `01-shelf-narrow`, `01-detail-cards` | `test_shelf` | features, home |
| `02-search` (and per theme) | `test_search` | home, features |
| `03-ask` | `test_ask` | features |
| `04-collections` (and per theme) | `test_collections` | home, features |
| `05-secrets` | `test_secrets` | features |
| `06-lock` | `test_lock` | features |
| `07-privacy-pane` | `test_privacyPane` | features |
| `09-smart-clips` | `test_smartClips` | features |
| `theme-<theme>` | `test_themes` | theme try-on |
| `scenes/loop-*` | `MarketingLoopTests` (`make marketing-loops`) | scroll scenes |
| `public/og.png` | `scripts/marketing/compose-social-card.swift` from the pictures above (website repo) | share card on every page |
