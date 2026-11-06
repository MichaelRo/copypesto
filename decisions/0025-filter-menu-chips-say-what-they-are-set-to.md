# 0025. The Format and From chips say what they are set to

Status: Accepted

Supersedes one sentence of [0023](0023-time-filter-is-one-chip-and-a-custom-range.md): that From reads "From" until an app is chosen, and by the same pattern Format read "Format". Nothing about what the menus list, storage, sync or the network changes.

## Context
The search bar groups its chips under small captions: Kind, Format, When, From, Other. The Format and From menu chips were labelled with the caption's own word, so "Format" sat directly over a chip that said "Format" and "From" over "From". The repeat tells a person nothing, and the chip at rest says nothing about its state, unlike a Mac pop-up, which shows its current value.

## Decision
- **The captions stay.** They group the row and cost no height.
- **At rest the chips read their value:** Format says "Any" and From says "Any app". Once chosen they read the format ("JSON") or the app ("Safari", or "Safari +2"), as before. The menus' own first item is still Any Format and Any App.
- The text lives in Core (`FilterMenuLabel`), so the website's demo shelf, which is drawn by hand from `docs/design/website-shelf-spec.md`, can be checked against it.
- VoiceOver is unchanged: the chips already spoke "Format, any" and "From, any app".

## Consequences
- The row looks the same and is the same length; only two chips' resting text changes.
- The pictures of the shelf with search open and the film's frames that show the bar carry the old text until the next `make pictures` and film render.
- The website's demo shelf changes in the same release (a separate pull request).

## Docs affected
- `docs/guide/using-pesto.md` (the filter chips)
- `docs/design/website-shelf-spec.md` (the filter groups)
- `decisions/README.md` (this record in the table)
