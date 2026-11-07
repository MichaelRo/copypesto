# 0041. A picture fills the card only when it is near the card's shape; anything else is shown whole over a blurred copy of itself

Status: Accepted

Nothing about the network, storage, encryption, backup or sync changes. It supersedes one sentence of ADR 0026: "A picture whose aspect ratio is outside 0.6 to 2.0 … is fitted below the header instead of cropped".

## Context
A card is about as wide as it is tall. A 3:2 picture (a boarding-pass screenshot, most photos) filled into it lost a third of its width: the website film showed "ATE B7" for "GATE B7". The range 0.6 to 2.0 kept every ordinary picture on the fill path, which is the path that crops.

## Decision
- **`PictureFit.fillRange` is 0.8 to 1.35.** Inside it the picture fills the card, as before. Outside it, including 3:2 and 16:9, the whole picture is shown below the header.
- **A fitted picture sits on a blurred, darkened copy of itself** (14 pt blur, black at 35%), not on a flat ground, so a wide picture does not look like a small thumbnail in an empty card. The backdrop is always a still image, so a GIF starts one animation and not two, and a blurred copy of a covered card is never drawn (a covered card is `.standard`).
- **What does not change:** the scrim and header over a picture, the GIF pill, the 480 px thumbnail, the covered-card rules (ADR 0003).

## Consequences
- More cards show a letterboxed picture; their picture is smaller than before and complete.
- One extra image draw per fitted card. Scroll performance is checked with `make bench-scroll` before release.
- Tested: `PictureFitTests` (the range's edges, 3:2 and 16:9 fit) and `CardTreatmentTests`; the film's frames show the boarding pass whole.

## Docs affected
- `docs/design/website-shelf-spec.md` (the picture row)
- `decisions/README.md` (this record), `decisions/0026-cards-put-the-content-first.md` (status line)
