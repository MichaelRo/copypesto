# Core/AI — notes

On-device AI only (ADR 0005). `AppleIntelligenceClient` wraps Apple's Foundation Models; `AIActionCoordinator` runs one action with an injectable completion; `AIAvailability` says whether the model can run and why not. Nothing in this folder may touch the network or hold credentials.

## Key Invariants

- **No network code and no keys.** Adding an AI provider again means a new ADR, `NetworkGuardTests` changes and a privacy-copy review. `NetworkGuardTests.noAIProviderHosts` fails if a provider host reappears.
- **Every AI surface must degrade visibly.** Menus and Settings grey out with `AIAvailability.message`; Ask Pesto falls back to `RuleBasedQueryInterpreter`. Never hide a feature silently and never crash when the model is missing.
- **`LegacyAIKeyCleanup` deletes keys older builds saved** (Claude/ChatGPT/Gemini). It runs once at launch and only outside test launches.
- Image work (`describe`, screening) needs the macOS 27 SDK and `compiler(>=6.4)`; keep it behind those guards.
- **The model reads the whole clip up to a budget, and the answer says when it did not** (`AIInput`, `AIInputBudget`, `AIResult.coverage`). The budget is `(contextSize - 1200) * 3` characters, clamped to 4,000 to 40,000, and 8,000 where the context size cannot be asked. Never cut text anywhere but in `AIInput.make`, and never feed a secret's real text: `GridView+Actions.aiSource` keeps a masked clip masked and falls back to the preview for a clip too big to decrypt on the main thread.
- **A long Summarize or Key Points is read a part at a time, and only when asked** (`AIChunker`, `AIRun`, `AppState+AIParts`, `docs/design/ai-chunked-summary.md`). Each part is one model call made on a click, never prefetched (ADR 0005: nothing automatic); parts answer independently and stay on screen, Cancel keeps them, a failure keeps the earlier ones, and at most `AIChunker.maxCharacters` (100,000) are ever copied, so a 5 MB clip costs no more. The rest of the text lives in `AppState.aiRun` only while the panel is open: `aiResult = nil` (Done, Paste, the history lock) drops it. Rewrites never chunk. `AIChunker` is, with `AIInput.make`, the only place text is cut for the model.
