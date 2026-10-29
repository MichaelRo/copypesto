# Pesto master handoff (website redesign + "The Lunch Rush" film), 2026-10-29

## 0. How to use this, and a candid assessment

Paste this whole file into a fresh Claude Code conversation on your Mac, run from `~/Projects/copypesto-website`. Then say which TO DO item (section 7) to start with. Tell the new session to read section 9 first.

Limits of this file:
- It merges two sources: (A) the cloud page-redesign thread and (B) the video thread. The redesign code lives only on your Mac, so section A facts are relayed from earlier reports ("per the RC session"), not seen firsthand. Verify against git before trusting them.
- Nothing here contains secrets. Verify commit hashes and PR states before acting.

Candid quality assessment:
- The film's first cut (70 s, narration only) is weak. Picture gags (order tickets, PASTED stamp, kettle, blender emoji, theme chips, Basil the jar) are placeholders built in React/CSS: charming but amateur.
- The ten raw takes `.build/lunch-rush/*-light.mov` are dimmed by macOS, show the whole screen, and show private windows in the first seconds. Never publish or commit them.
- The shelf strips look near-identical because the strip crop (bottom 400 px) misses the real action (search bar, sheets).
- The finale ingredients are emoji, not real clips (you want real clips).
- A clean recorder exists, but only one test take (beat g, `clean-g.mov`) was recorded with it.
- No music or sfx are in the cut. Nothing is delivered to `public/video/`. No website PR exists for the film.
- The page redesign is built locally but not re-verified against the final build, and has no PR yet.

## 1. Goal

- Elevate copypesto.net (Astro, static, no client JS, strict CSP `default-src 'none'` plus `media-src 'self'`, CSS-only motion, reduced-motion and light/dark) into a modern, innovative, tech-savvy site that explains Pesto at a glance.
- Build a funny, graphic 55-70 s film into the page: "The Lunch Rush". Real recordings of the real app, burned-in captions, narrator, music, small sounds, picture gags, Basil the jar.
- Inspiration: Lemonade's 2019 Giveback page (one scroll-drawn line), built as a CSS "Basil line".
- Film delivery: `public/video/lunch-rush.mp4` (+ `.webm`, `lunch-rush-poster.jpg`, `.vtt`, `lunch-rush.json`), shown by `Film.astro` (native controls, preload none, poster, no autoplay, CSP `media-src 'self'`).
- Budgets: MP4 and WebM at most 6 MB each, poster at most 150 KB, VTT at most 8 KB.

## 2. Decisions

### Project rules (memory facts)
- Work runs on Michael's Mac. The local folder is `copypesto-website` (`pesto-website` is retired/dead).
- Website PRs must include screenshots (light and dark, phone and desktop), before/after.
- All design goes through Claude Design (canvas "Pesto Shelf Story": https://claude.ai/artifact/Uxx73wCHA7WH4Sni3E2zZG).
- Michael will not record sounds himself. Synthesize locally or use approved CC0; log licences in `video/LICENSES.md`.
- The banned-claims test exemption for the "What Pesto does not do" block is approved (narrow: lines starting No / Not / It does not).
- The redesign must not remove existing features (parity; any removal is listed in the PR as "Removed: ... because ..."). The preview shelf must match the real app shelf (build uses the real `Shelf.astro`, not the canvas sketch).
- Homebrew changelog hotfix, PR #11 on copypesto-website, merged 2026-10-28.
- Michael must run `scripts/verify.sh` before merging copypesto PR #27.
- Launch video playbook: Brain vault, 00-Inbox, "Pesto - macos-app-launch-video-playbook".

### Film
- Script v2, 12 beats (website `video/script.json`): 1 A Tuesday, 2 Masked card, 3 Support reply, 4 QA answer, 5 Pinned command, 6 Supplier links, 7 Agent prompt, 8 Prepare a pesto (Paste All finale), 9 The jar, 10 Four themes, 11 The spoon (covered clip reveal), 12 End card.
- One film with a ~4 s theme flip: Basil, Parmesan, Pine nut, Mortar (one film per theme was rejected as too heavy).
- Captions burned in, plain and true; the joke lives in narrator and clip text. No "magic", no exclamation marks, no health or allergen claims, example.com links only, no real brands, numbers under ten as words, "Paste All" / "Paste One by One" never "merge". "Secret" only for card numbers/keys, "sensitive" for blurred clips.
- Real fill-in syntax: `{{input:Label}}`, `{{choice:Label options="a|b"}}`, `{{input:Ticket default="PEST-142"}}`. A bare `{{name}}` would paste as typed.
- Narrator: Kokoro `bm_george` (local).
- Music: the Gemini pizzicato track (`music-C-pizzicato-sting`, 60.6 s, about -11.6 LUFS, loop/extend to 62-70 s) is the single bed. Kitchen ambience loop dropped (optional ambience 2 was at about -38 LUFS; cut if it fights the music).
- SFX: Michael rejected the first synthesized set and the Gemini sfx. He keeps the page thread's synthesized UI and kitchen sounds (`video/tools`: `ui_sounds.py` 13 interface sounds, `foley_synth.py` 12 kitchen sounds, `synth.py`; numpy/scipy, ffmpeg for mixing only; rated Keep). Stable Audio Open is a last resort (gated on Hugging Face, Stability Community License, free below USD 1M revenue; not downloaded).
- Mix targets (`video/gemini/sfx-sources.md`): narrator about -16 LUFS, music about -28 under voice, final -16 LUFS, true peak at most -1 dBFS.
- Paste destinations (note, form) cannot be real apps in `-UITestMode`: the edit draws them from text the app logs (`paste-log.jsonl`). The pinned ctrl-1 shortcut cannot be pressed in UI test, so that beat finds the clip by search and shows a badge.
- Covered ("filtered") clip: cheeky food-glamour pesto. The Gemini clip (10 s source, 6.6 s silent cut `reveal.mp4`) is the reveal in the spoon beat as VIDEO, not GIF (`docs/motion.md` bans GIF on the site). Crop in about 4% to hide a faint fingertip at the top edge (or start 0.4 s later). Caption "Sensitive. Handle with bread." Narrator "A blurred clip. Show. Even the clipboard blushes." Never commit or share the original "nsfw" filename; no "nsfw" in any filename.
- Gemini terms check for public use (video and music, and open-source sample content) is STILL PENDING (Michael). Keep generated assets out of git until cleared.
- App seed uses the drawn picture `ShowcaseArt.pestoSpoon`. A ~10 KB still from the clip in the app repo was proposed; on hold. (The app's seeded GIF sample was 3 s, 480 px, 1.4 MB, over the 400 KB target.)
- Recording setup lives in the app repo (PR #27). The sample shelf has every clip kind plus a simple no-prompt snippet.
- Earlier concept alternatives (kept for reference): B "Mise en Place" (cooking show played straight), C "Basil's Shift" (mascot-led; jar tilt = found, rattle = masked, clink = done). Craft rules: one committed premise, deadpan captions over absurd clips, rule of three with a break, hold punchline ~1.2 s, show the result not the act, running object (jar) as callback, end on the plainest line, one wink per beat.

### Page
- Keep all ten original beats' spirit; finale: copy basil, parmesan, pine nuts, olive oil, garlic, salt, then Paste All.
- Show simple and advanced snippets, rich clip kinds (images, GIFs, video, color, emoji, code, markdown, PDFs, links), fun and professional use cases.
- Website card set "What people keep on the shelf": replies you send twice a day (snippet); commands you do not retype (pinned); test cards and keys, masked; answers you can find by word (search); links that sort themselves (smart collection).
- Do not caption the agent prompt as a Pesto feature (Pesto only stores and fills text; no on-device AI claim).
- Added by the redesign: closed shelf with the Cmd-Shift-V keycap, interactive secret reveal with demo Touch ID sheet, scroll-drawn Basil line, count-up numbers, "What Pesto does not do" block, video with poster, "What people keep on the shelf" cards.

## 3. Learnings

Recording
- Dimming cause: during a UI test macOS draws a full-screen system window `AutomationModeUI` (layer 1000, `/System/Library/PrivateFrameworks/AutomationMode.framework`) with an "Automation Running" notice and dim scrim; no setting turns it off.
- Workaround: capture only Pesto's windows with ScreenCaptureKit. `scripts/dev/window-recorder.swift` (PR #27) uses `SCContentFilter(display:including:[app])` cropped to the backdrop at 2x (3024x1898): full colour, no notice, no other windows, hover cards captured. Verified on beat g only. `screencapture -l <windowID>` also works.
- Untested: driving the app without XCUITest (command queue + synthetic events, needs Accessibility); third-party tools.
- `ffmpeg -f avfoundation` needs Screen Recording for the terminal; `-list_devices` always exits non-zero (it killed the script under `set -euo pipefail`; fixed).
- UI-test result bundles keep no video on passing runs.

Edit tooling
- Remotion: the downloaded headless shell fails to spawn (spawn -88); use system Chrome (`--browser-executable`). Pin `typescript@5.6.3`. Avoid circular imports between `Film.tsx` and `Gags.tsx`. ffmpeg here has no `drawtext`.

App and seed
- Paste All joins selected clips in shelf order (newest first). Seed pitfalls: clip source apps must be `com.apple.*`; generate PDF/video once; the covered picture is the newest image among seeded.
- Full `swift test` in a worktree fails PersonalDataTests (worktree `.git` file holds a home path; unrelated). NetworkGuardTests needed `LunchRushSeed.swift` in its seed-file list (done).
- UI tests need `make generate` after new Swift files, and signing flags `CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`.
- Verified: UI-test mode stubs Touch ID; masked 4242 card pastes the real number; a smart collection with a link rule gathers supplier links; Paste All is Cmd-P joining with a blank line; "Merge" is retired.

Process (page thread)
- Remote Control (RC) session reads only Michael's typed messages (not cloud-thread messages, attachments or decision-card taps); folder tools are blocked while RC is active.
- Published pages block external audio; audio must be embedded.
- `npm run verify` runs a drift check against the app repo (`PESTO_APP_REPO`, default `../copypesto`); only CI sets `PESTO_SKIP_DRIFT=1`. Node via `mise exec -- npm ...` if `npm` is missing.
- Canvas errors previously found and fixed: bare `{{name}}`, a gluten-free line, "Merge", "<100 ms", stale titles, missing nav.

## 4. Where everything lives

App repo `MichaelRo/copypesto` (`~/Projects/copypesto`)
- PR #27 https://github.com/MichaelRo/copypesto/pull/27, branch `feat/lunch-rush-recording`, worktree `~/Projects/copypesto/.claude/worktrees/lunch-rush`. Not reviewed or merged; full `scripts/verify.sh` NOT run; eight commits.
- Files: `Sources/Core/Seeding/LunchRushSeed.swift`, `LunchRushMedia.swift`; `Sources/Core/Runtime/ShowcaseArt.swift` (pestoBowl, pestoSpoon); seed profile `lunchRush` in `RuntimeConfiguration.swift` and `SeedFixtures.swift`; `Sources/App/AppDelegate+MarketingBackdrop.swift` (seedLunchRush: pins snippets ctrl-1..4, smart collection "Supplier links", marks covered picture) and `AppDelegate+UITest.swift`; `Tests/PestoCoreTests/LunchRushSeedTests.swift`; `Tests/PestoRegressionTests/NetworkGuardTests.swift`; `Tests/PestoUITests/LunchRushRecordingTests.swift`; `scripts/record-lunch-rush.sh`; `scripts/dev/window-recorder.swift`; `scripts/README.md`.
- Beats a-j: a masked card + Show + paste; b support reply (3 fill-ins); c "audit" search; d pinned command; e supplier links collection; f agent prompt (2 fill-ins); g six live copies then Paste All; h covered picture Show; i four themes (relaunch per theme); j quick snippet.
- Snippets: Restart staging (ctrl-1), Order reply (2), Failing test (3), Quick thanks (4, no questions).

Website repo `MichaelRo/copypesto-website` (`~/Projects/copypesto-website`)
- Redesign branch `claude/project-thread-6vh2jf`: `video/script.json` (v2), `video/REVIEW.md`, `video/gemini/*`, `video/tools/*` (narrate.py, synth.py, ui_sounds.py, foley_synth.py), `video/LICENSES.md`, `Film.astro` slot, `src/components/Shelf.astro`, `src/lib/shelf-demo.ts`, `public/_headers` (media-src), tests, `docs/performance.md`, `docs/motion.md`, `TASKS.md`, screenshots in `docs/screenshots/shelf-kinds/`. Commit ed73882 is the UI sounds commit. (Per the RC session; diff and test run not seen by the cloud thread.)
- Video branch `video/lunch-rush` (pushed), worktree `~/Projects/copypesto-website-video`: `video/remotion/` (`cuts.json`, `src/Root.tsx`, `Film.tsx`, `Gags.tsx`, `Jar.tsx`, `theme.ts`), `video/tools/finish.py`, `prep_footage.py`. No PR yet.
- Git-ignored drop folder `~/Projects/copypesto-website/video/audio-in/`: `music-C-pizzicato-sting.m4a`, `amb-kitchen-loop*.m4a`, `reveal.mp4` (6.6 s, no audio), `source-spoon-gemini.mp4`, `reveal-seed.gif`.
- Narration wavs `video/audio/*.wav` (git-ignored; regenerate with `narrate.py`), `timings.json`.

LOCAL ONLY, NEVER COMMIT OR PUBLISH: raw takes `.build/lunch-rush/*-light.mov` and `clean-g.mov`; review renders in `video/out/`; Gemini originals until terms cleared.

Artifacts
- Claude Design canvas "Pesto Shelf Story": https://claude.ai/artifact/Uxx73wCHA7WH4Sni3E2zZG (boards Main, HeroOpen, Thread, Film; version 8 at last publish; sketches only. Not drawn: search, collections, privacy flow/lock/ledger, importers, open-source sections).
- Lunch Rush Listening Room https://claude.ai/artifact/DUkn1W5nFpzeFTanrWW4jy ; Sound Lab (27 sounds) https://claude.ai/artifact/14m4YkijbHHQmVHyHhTywX ; Sound Picker (redundant) https://claude.ai/artifact/MZG893rRADVUfe1zRTuemY
- Team memory: `pesto-website-redesign-2026-10`, `website-prs-carry-screenshots`.

Relevant files in `/mnt/project-files/pesto-site/` (cloud checkout)
- `handoff-page-redesign-2026-10-29.md` (source A)
- `feature-parity-checklist.md`: before/after table; keep everything. Five rows NOT YET on the artboards must stay: Type to find it (search + Ask in a sentence), Keep the clips you reuse (collections, pinned ctrl-1..9, snippets), Private by design (flow, masked secrets, History Lock, ledger), Switching clipboard managers (importers, Paste import), Open source panel. Also kept: header/nav, footer, skip link, theme try-on (CSS :has), touch "Download the Mac app", pre-launch mode, CSP. Risks: closed-by-default shelf must start open for no-:has or Reduce Motion; video must stay behind poster with preload none; other pages (Features, Privacy, Guide, Download, Releases, Security, Contribute, License, 404, appcast) must not break.
- `work-beats-2026-10-28.md`: beat table, corrections (QA answer should be the answer clip; harmless alternates "Does it keep? Five days, under oil." / "Is it vegan? Not with the parmesan."; dates as words), 20 extra clip ideas by role, narrator line options.
- `video-concepts-2026-10-28.md`: three concepts, craft rules, end-card lines, voice-rule risks (4111 card triggers the mask; keep key prefixes generic).
- `review-sheet-narration-and-music.md` and `gemini-audio-prompts.md`: superseded by repo `video/gemini/` pack, but the rules checklist (caption plain/true, no brands, Paste All wording, real shipped features, at least three work-relevant beats before the dinner finale) is still a good gate.
- `web-research-2026-10-28.md`, `paste-to-this-thread.md`: background.

## 5. How to run things

- Core seed tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter LunchRushSeedTests`
- One beat: `xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -only-testing:PestoUITests/LunchRushRecordingTests/test_g_pasteAllJoinsTheIngredients test` (run `make generate` after new Swift files).
- Record all: `scripts/record-lunch-rush.sh all light` (terminal needs Screen Recording; Mac unlocked; hands off about 5 minutes; no running Pesto).
- Edit: `cd video/remotion; npm install; npx remotion studio src/index.ts; npm run render` (outputs `video/out/lunch-rush-master.mp4`, system Chrome). Footage in `video/remotion/public/footage/`.
- Finish: `python3 video/tools/finish.py [poster-second]`.
- Website verify: `npm run verify` (drift check vs app repo; `mise exec -- npm ...` if npm missing).

## 6. Status

- Film: first cut weak (see section 0). Script v2 locked. Narration generated. Seed, ten beats and recorder exist in PR #27; only beat g re-recorded cleanly. No music or sfx mixed. Nothing delivered; no PR.
- Page (per RC session): new card kinds, Film.astro, `media-src`, tests, docs, screenshots built locally. Feature parity mapped, not re-verified on the final build. Nothing intentionally removed so far.
- Hotfix PR #11 merged. PR #27 open, unreviewed, verify.sh not run.
- Gemini terms: pending.
- Dark-theme footage never recorded.

## 7. Still to do (prioritized)

1. Decide the approach (section 8, third-party tools). If keeping the pipeline, first record ONE beat end-to-end with the clean recorder and watch the full edit of it, then re-record all ten beats and redo the cut.
2. Michael: check Gemini terms (generated video and music in a public film and open-source sample content); tell the session so it records the result in `video/LICENSES.md`. Blocks anything Gemini going into git.
3. Real clips for the finale ingredients (replace emoji).
4. Real design for gags and Basil (through Claude Design), timing against narration, remove the empty strips; fix the crop so search bar and sheets show.
5. Mix: pizzicato quiet under narrator, UI sounds + foley in about ten sub-second slots, targets in section 2.
6. Reveal scene with `reveal.mp4` after the terms check (crop ~4%).
7. Frame-by-frame privacy check, render, `finish.py`, poster/VTT/JSON; deliver to `public/video/`.
8. Review PR #27, Michael runs `scripts/verify.sh`, then merge.
9. Page side: wire the film, run `npm run verify` with the app repo, fix the large empty space under the closed shelf, check the shelf demo in all eight themes light and dark, draw canvas artboards for missing sections (optional), confirm parity.
10. Open the redesign PR from `claude/project-thread-6vh2jf` (and film PR against it) with before/after screenshots (light/dark, phone/desktop), any "Removed: ... because ..." lines, PR attribution block; request review from MichaelRo.
11. Confirm light-only footage is acceptable (dark never recorded).
12. Optional: second copywriter round for punchier narrator lines; confirm Sound Lab play buttons work in his view.

## 8. Open questions

- Evaluate third-party recording/editing tools? (Michael wants to; he may restart.)
- Gemini terms result?
- Put a ~10 KB still of the Gemini clip in the app seed, or keep the drawn picture?
- Quality bar: crisp real-app footage with simple graphics, or heavier illustrated gags?
- Music: confirm pizzicato; is ambience wanted at all?
- Second copywriter round wanted?
- Is light-only footage OK?

## 9. What went poorly, and advice for next time

- Whole-display capture caught the dimming overlay and private windows, found only after recording all ten. Test ONE beat end-to-end (record, cut, look at it with sound) before building anything around it.
- The strip crop hid the interesting UI; emoji ingredients and placeholder gags shipped into the cut.
- Too much effort on pipeline, not enough on an early end-to-end look. Get a rough, ugly full cut first and judge it.
- Consider third-party recording/editing tools (screen recorders with window capture, a real editor) rather than custom Remotion plumbing for everything; use code only where it clearly wins.
- Set the quality bar up front (crisp real footage, simple purposeful graphics) and review against the launch video playbook in the Brain vault.
- Page thread: a wrong-folder RC request, a claimed message that failed to send, a blank review sheet, and external audio that would not play. Cross-session limits: RC sees only Michael's typed text, so paste decisions in as text.
