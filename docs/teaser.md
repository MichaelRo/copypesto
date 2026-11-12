# The website film

The film on copypesto.net (light and dark, 26 s) shows the real shelf, and its cards move. Its frames are taken from this app by a UI test, so
a change to what the shelf looks like needs the film remade. The film's own edit (script, timing, scenes, music) is in the
website repo's `video/teaser/`.

## When to remake it

Run `make teaser` (or `make teaser-frames` for the frames alone) when a change touches what the film shows:

- the shelf, a card, the chips, the search bar, the glass or the theme (`Sources/Features/Grid`, `Sources/Features/Overlay`, `Sources/Shared`);
- the film's seed or its drawings (`Sources/Core/Seeding/LunchRushSeed.swift`, `Sources/Core/Runtime/ShowcaseArt*`);
- the frame test itself (`Tests/PestoUITests/TeaserFramesTests.swift`).

`.githooks/pre-push` lists such changes since the last time the frames were taken (a reminder, never a failure). A change that
does not alter what the shelf shows needs nothing.

## How

```bash
make teaser-frames                              # retake the frames and pictures into the website checkout
make teaser TEASER_MUSIC=~/Downloads/morning_in_the_piazza.mp4   # frames, then render, mix and finish both films
```

- Quit Pesto and other apps first: the test drives real windows, and a second app behind the backdrop spoils the glass.
- The website checkout is found at `../copypesto-website` or `~/Projects/copypesto-website`; set `PESTO_WEBSITE` for another place.
- The music is not in either repository (`video/LICENSES.md` in the website repo says where it came from). The track's key decides
  the shift; `make_film.sh --semitones` changes it (the default fits `morning_in_the_piazza`), and `--bar` picks where its 13 bars start.
- `scripts/teaser.sh` writes the app commit it took the frames from to `video/teaser/FRAMES-SOURCE` in the website repo.
- After `make teaser`, in the website repo: `npm run build`, then `npm run poster` (the poster is remade every time the film is:
  it draws the same shelf frames), then `npx vitest run`, look at both films and both posters, then commit the changed files
  (`public/video`, `public/og.png`, `design/social`) in the website pull request.

## What the frame test does

`TeaserFramesTests` is one story in order (`test_film_story`: the shelf, find, a secret, hide): every scene starts on the shelf
the scene before left, because a copy or a paste moves a clip to the front (ADR 0021). The frames are named `<scene>-<nn>` and
the film's shot list in `video/teaser/src/copy.json` (`timeline.shots`) says when each one is on screen. Beside every frame the
test attaches `<scene>-<nn>-layout`: where each card is, in the backdrop's points, under the name the film knows the card by.
The film moves the cards between two frames by those names, so:

- **A card's name must be the same in every frame it is in and unlike every other card's.** It is the card's spoken label; a
  frame whose labels all change at once (the covered shelf) is taken with `cardsBy: .position`, and the film then cross-fades
  each card where it stands. The website's `make_layout.py` stops on two cards with one name.
- A card's own screenshot loses the focused card's lift and shadow, so the film cuts cards from the whole frame; the test only
  records places.
- A copy made while the shelf is open (`secretScene`) is what lets the film show a clip landing. It must be a text the seed
  does not hold, or the copy only moves the old clip to the front.

Rules that took a while to find:

- The shelf's glass keeps a yellower tint until the focus has moved once, so every frame is taken after a settle
  (`settleGlass`).
- A live copy is shown as made in the app the runner names: `copyFrom(bundleID, text)` writes `copy-source` before the copy.
- A paste cannot reach a real app in a UI-test launch, so each paste is attached as `<scene>-paste`.
- The seed is demo-only code (`#if DEBUG`, `DemoOnlyCodeTests`).

If you add a scene that needs a new frame, add it to the test, name it, and add it to `timeline.shots` in `copy.json`
(the website's `tests/teaser-beats.test.ts` fails on a shot whose state the frames do not have).
