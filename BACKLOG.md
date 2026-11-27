# Backlog

## Privacy & Sensitivity
- **Adaptive sensitivity filtering (issue #10):** Learn from manual Mark as Sensitive / Mark as Not Sensitive overrides per device so recurring false positives or missed sensitive clips adjust automatically without relaxing hard secret detectors.
  - *Scope needed before building:* ADR defining an encrypted per-device rule store, false-negative protection, and a management UI to inspect/reset learned rules.

## Platform Compatibility
- **Older iOS (< 26) deployment target:** All iOS targets (`PestoMobile`, `PestoWidget`, `PestoKeyboard`, `PestoAutoFill`, `PestoShare`) currently require `iOS 26.0` in `Pesto.yml` due to iOS 26 Liquid Glass (`glassEffect`, `.scrollEdgeEffectHidden`) and layered `.icon` bundle assets. Non-Apple-Intelligence devices on macOS 15+ and iOS 26 already degrade cleanly via `AIAvailability` and `#if canImport(FoundationModels)` guards.
  - *Scope needed to lower iOS minimum version:* Wrap `glassEffect` (`MobileGlassChrome.swift`, `MobileChipStyle.swift`) and `.scrollEdgeEffectHidden` (`KeyboardRootView.swift`, `KeyboardSearchPage.swift`) with `#available(iOS 26, *)` fallbacks and provide fallback AppIcon asset sets for pre-iOS 26 builds.

## Cards & Organization
- **Clip card color marking (especially in collections):** Let users tag individual clips with a curated color marker synced across devices.
  - *Recommended design:* Override the card's foot glow (or add a top-edge pill/dot) using 5–6 curated semantic palette tokens stored as an optional enum on `ItemMetadata` / `SyncCuration` rather than painting full card backgrounds (which would fight selection washes, themes, and `CardMetaLineContrastTests >= 4.5:1`), keeping picture/color/covered cards glow-free.

## Website & Launch
- **Post-iOS-release website expansion (`copypesto.net`):** After App Store approval, expand beyond the initial `site.iosAppStoreURL` link (`copypesto#228` / `copypesto-website#137`) to pitch iPhone and iPad alongside the macOS DMG.
  - *Scope needed before building:* Dedicated `/plan` pass covering hero framing, iOS/iPadOS simulator captures via `make pictures`, `AGENTS.md` page-weight/CSS budgets, and localized pages.
