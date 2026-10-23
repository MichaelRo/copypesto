# Expanded entity detection

Research behind the entity-actions issue. Revised 2026-10-21: the first version (2026-10-20) was written
before phases 1 to 4 shipped and leaned on recalled carrier documentation. This version checks the code as it is
(probed with throwaway tests), the carrier algorithms against published test numbers, and the flight and URL claims
against their sources. Each claim says how it was checked: **tested** (run here), **sourced** (a linked page says so) or
**unverified**.

## How detection works today
- `EntityDetector.detect(in:)` (`Sources/Core/Pasteboard/EntityDetector.swift`) runs when a card's context menu opens
  (`EntityMenuSection`), on the card's preview text (`gridPreview`, about the first 500 characters). Results are never
  stored. The menu shows at most four.
- Actions: **Call**, **Compose Email**, **Open in Maps** (address or coordinates), **Add to Calendar**, **Track with
  *carrier***, **Open Link**. `EntityActionRunner` opens the URL in the person's own app or browser. Pesto fetches nothing.
- Regexes are compiled once (`regexCache`); a text over `maxDateScanLength` (400) is not scanned for dates.
- Colors are not entities: a color is its own clip type (`ContentClassifier`, `ColorLiteralParser`, `HexColorParser`).

## Status of each kind (as of 2026-10-21; items 2 to 4 of the order below were built the same day)
Built since the table: check digits for UPS, USPS, FedEx Express and Ground and DHL (`TrackingCheckDigit`, fixtures from
jkeen/tracking_number_data), DHL 11 digits, the 20-digit FedEx removed (a 22-digit `96` number with "fedex" named and no
check replaces it), coordinates with `;`, space and degrees-minutes-seconds (`CoordinateMatcher`), `#RGBA` (a digit or four
equal characters, so `#cafe` stays text, ADR 0002) and the space syntax of `rgb()` and `hsl()`. Flights remain for after 1.0.
The dataset's USPS "Legacy" 20-digit format (`7196 9010 7560 0307 7385`) is checked on the number with `91` in front of it
(its published definition, reproduced against its valid and invalid numbers), and is offered when "usps" is named. Spaced
numbers are not matched by the detector at all, in any format.

| Kind | Built | Not built |
|---|---|---|
| Phones | NANP pattern with a leading boundary and a `+` international pattern (7 to 15 digits); fixed in PR #178 | E.164 validation of the first digit |
| Tracking | UPS `1Z`+16, USPS `9[2-5]` + 18 to 20 digits, FedEx 12/15/20 and DHL 10 with the carrier named | check digits, DHL 11 digits, USPS without a `9[2-5]` prefix |
| Coordinates | decimal pair with a comma, directional decimal (`40.7° N, 74.0° W`) | `;` or space separators, degrees-minutes-seconds |
| Colors | `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb()`/`rgba()`/`hsl()`/`hsla()` (comma syntax) as whole clips | `#RGBA`, space syntax, a color inside longer text |
| Flights | nothing | everything; see the section below before starting |

## Found by probing the real detector (tested)
A throwaway test fed the detector these strings (not committed). The first finding is fixed in PR #178 (a leading
boundary, NANP shape, and a tracking number is not also a phone); the rest are open:
- **Every long digit run is also a phone number.** The US phone pattern has no leading boundary, so it matches the last
  ten digits of any run: `order 986578788855 shipped` offers **Call 6578788855**; a UPS number offers **Call 0357567127**;
  a FedEx or USPS tracking number offers both **Call** and **Track**. `000-000-0000` is offered too. This is a visible
  bug on exactly the cards this feature is for. Fix: a leading `(?<![\w+])`-style boundary plus NANP rules (area code and
  exchange start 2 to 9, neither is N11), test first.
- **A UPS number with a letter in the check position is still offered** (`1Z5R8939035756712X`): no check digit is
  computed.
- `3.14159, 2.71828` is offered as coordinates, as the old doc predicted; `37.7749; -122.4194` and
  `37.7749 -122.4194` are not offered; a degrees-minutes-seconds pair is not offered.

## Rules for every new pattern
1. **Bounded.** No nested quantifiers, no unbounded repetition of a group that can match the same text two ways.
2. **Short input.** Scan the preview text only (500 characters). 360 KB of near-miss text once took a pattern past 60 s
   (`Core/Pasteboard/CLAUDE.md`).
3. **Validate, then offer.** A regex finds a candidate; a cheap check decides.
4. **An offer, not an action.** A wrong guess costs one menu line, so favor precision over recall.
5. **New hosts need the allowlist and an ADR** (`NetworkGuardTests.allowedLiteralHosts`; AGENTS.md, security invariant 1).
6. **Tests first** (`EntityDetectorTests`): positives, false positives, and an adversarial case with a time limit.

## Phone numbers
- **Today (tested):** the bug above; international `+CC` numbers work (`+44 20 7946 0958`, `+1 (415) 555-0132`); the
  action is `tel://` plus digits, with `+` kept.
- **Add:** a leading boundary; NANP shape (`[2-9]\d{2}`, exchange `[2-9]\d{2}`, not N11); E.164 with 8 to 15 digits, first
  digit not 0.
- **`tel://` works.** Checked by hand on a Mac on 2026-10-21; the action keeps `tel://` (RFC 3966 and Apple's Phone Links document `tel:`, but nothing needs to change).

## Package tracking numbers
Algorithms **tested** against the published valid and invalid numbers in
[jkeen/tracking_number_data](https://github.com/jkeen/tracking_number_data) (UPS, FedEx, USPS and DHL definitions; the
JSON names the algorithm and weights, the procedure below is what reproduced its valid and invalid examples):

| Carrier | Shape | Check digit (all digits left to right) |
|---|---|---|
| UPS | `1Z` + 15 characters + a digit | Letters count as `(code - 63) mod 10`; weights 1, 2, 1, 2… over the 15 characters; check = `(10 - sum mod 10) mod 10`. all five valid numbers in the dataset and the UPS sample `1Z999AA10123456784` matched; the dataset's invalid `1Z1111111111111111` was rejected |
| USPS | 20 digits, or 22 starting 91 to 95 | Weights 3, 1, 3, 1… over all digits but the last (odd count, so left-to-right and right-to-left agree); check = `(10 - sum mod 10) mod 10` |
| FedEx Express | 12 digits | Weights 3, 1, 7 repeating over the first 11; `sum mod 11`, then `mod 10`, equals the 12th |
| FedEx Ground | 15 digits | Weights 1, 3, 1, 3… over the first 14; `(10 - sum mod 10) mod 10` equals the 15th |
| DHL Express | **10 or 11** digits | All digits but the last, read as a number, `mod 7` equals the last |

- **The carrier-name rule stays.** A check digit passes a random digit run about one time in ten, so it cannot replace
  "FedEx" or "DHL" next to a bare 10 to 15 digit run (order numbers, phone numbers). The earlier doc proposed dropping the
  rule once checks were in; that is withdrawn. UPS (`1Z`) and USPS (22 digits, `9[2-5]`) are distinctive enough that a
  check digit is a pure gain: it removes typos and near-misses.
- **Corrections to the detector:** DHL Express also has 11 digits (`73891051146` is a valid example); the UPS pattern lets
  the last character be a letter, the check digit is a digit.
- **Unverified:** the detector accepts a **20-digit FedEx** number when "fedex" is in the text. None of the FedEx formats in
  the dataset above is 20 digits (they are 12, 15, 22 starting 96, 32 and 34). Keep it only if a real label confirms it,
  otherwise remove it. The 22-digit `96` Ground number failed the simple check above, so its rule is **unverified** (the
  dataset's own regex splits it into parts and the check probably runs on the 14-digit serial).
- **Not done:** the carriers' links accept a number and show their own error for a bad one; Pesto sends nothing.

## Flight numbers
**The earlier plan was wrong in two places.**
1. **The link.** The old note planned `flightaware.com/live/flight/UA1234`. FlightAware staff say, in their forum, that
   they canonicalize to ICAO identifiers, that ICAO codes are globally unique and IATA codes are not, and one user's
   `B2846` lookup failed where `BRU846` found the flight
   ([thread](https://discussions.flightaware.com/t/case-of-mistaken-identity/15814),
   [thread](https://discussions.flightaware.com/t/cannot-find-flight-d84331/89212)). So the safe link is the ICAO ident,
   `UAL1234`, which means the bundled table needs the **pair** (IATA, ICAO) for each airline, not one code list. I could
   not confirm what `/live/flight/UA1234` returns today; treat the IATA form as unreliable.
2. **The pattern.** An IATA airline designator is two alphanumeric characters and may start with a digit (`3K`, `9W`,
   `7C`) ([Wikipedia: Airline codes](https://en.wikipedia.org/wiki/Airline_codes)). The old `[A-Z][A-Z0-9]` misses those.
   The backlog's `\b[A-Z0-9]{2,3} \d{1,4}` also matches `A1 1234`, `B2 4567` and part numbers. Accept only a pair on the
   bundled list, require a letter in the code, reject numbers starting with 0, and keep the 500-character, anchored scan.

**Cost against value.** Flights need a new host in the allowlist (FlightAware) and an ADR, a bundled table that goes stale
as airlines change, and a precision problem the other kinds do not have, because two airlines can share a designator.
The carrier pages and Maps were allowed because they are the destination of a package or an address; a flight is more
often looked up in the airline's own app. **Recommendation: defer flights until after 1.0** and spend the effort on
the phone fix and tracking checks, which fix visible bugs. If flights are built, the ADR is `decisions/00NN`, the pair
table has a no-duplicates test, and `NetworkGuardTests` gets `www.flightaware.com`.

## Geographic coordinates
- **Built (tested):** decimal pair separated by a comma, and `40.7° N, 74.0° W`.
- **Add:** `;` and space separators, and degrees-minutes-seconds (convert to decimal, minutes and seconds under 60). Keep
  four or more decimals to cut version numbers (`1.2.3.4` is not offered today, tested).
- **Action:** `https://maps.apple.com/?ll=lat,lon&q=lat,lon`. Apple's
  [Map Links](https://developer.apple.com/library/iad/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html)
  (an archived page) documents `ll` for the center, `q` as the search or label, and `address` for a street address,
  which is how the address action is built. I did not confirm the `maps.apple.com` host form against a current Apple
  page; it is what the app already ships. Keep `https`, not `maps://`, so the literal stays inside the allowlist's host
  list.

## Colors
- **Built:** whole clips of `#RGB`, `#RRGGBB`, `#RRGGBBAA`, a bare hex with a letter A to F (ADR 0002), and
  `rgb()/rgba()/hsl()/hsla()` in comma syntax (`ColorLiteralParser`); Copy As offers eight formats.
- **Gaps:** `#RGBA`; the space and `/` syntax (`rgb(255 0 0 / 50%)`); a color inside longer text (`color: #FF00AA;`),
  which would be an entity offering **Copy As…**, not a change to the classifier.

## What was run
- **Probe, 2026-10-21:** the detector on the strings listed above (Swift, not committed).
- **Algorithms, 2026-10-21:** Python scripts against the published valid and invalid numbers for UPS, USPS (its 20-digit, 91,
  94 and 92/93/95 examples), FedEx Express 12 and Ground 15, and DHL: every valid number accepted, every invalid rejected,
  except UPS `1Z12345E0205271688`, a number recalled from memory and absent from the dataset, which fails.
- **Earlier run, 2026-10-20:** Python regexes against positive, false-positive and adversarial strings, under 1 ms per
  5,000 characters. Python's engine backtracks like ICU's, so the numbers are indicative. The real measurement belongs
  in `EntityDetectorTests` with a `ContinuousClock` limit.

## Suggested order (revised)
1. ~~Phone boundary and NANP rules~~ (PR #178).
2. **Tracking check digits** for UPS and USPS, DHL 11 digits, and a decision on the 20-digit FedEx.
3. Coordinates with `;`, space and DMS.
4. Color function and `#RGBA` gaps.
5. Flights, after 1.0, if at all.

Update `docs/feature-reference.md`, `docs/guide/using-pesto.md` (the Open With bullet) and the README line in the same
change as any of these.
