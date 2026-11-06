# 0033. Paste As and Copy As offer JSON and Markdown, only for a clip that qualifies

Status: Accepted

Nothing about storage, encryption, sync or the network changes.

## Context
People copy rows from a spreadsheet, a JSON document written on one line, or formatted text from a web page, Word or Google Docs, and want it in another shape: JSON for a script, Markdown for an issue or a note. Paste As already had a "JSON Pretty-Print" entry that every text clip showed, prose included, that sorted the keys and that turned a 20-digit id into a rounded number. Pesto keeps the HTML, RTF and RTFD flavours of a text copy beside its plain text (`RichTextPayload`), so a table copied from a browser is still a table in the history.

## Decision
- **Two entries, `JSON` and `Markdown`, are the first rows of Paste As… and Copy As…**, above a divider, and only on a clip that qualifies. A clip that does not qualify shows neither, and a transform that fails when it runs writes nothing and says nothing (no error toast). The main menu does not change.
- **`JSON` replaces `JSON Pretty-Print`.** It is offered for (1) a JSON object or array that is not already written with two-space indent, laid out with keys in their original order and every number as written, and (2) comma or tab separated rows with a header, written as an array of objects. Every value of a table is the text of its cell (`"02134"`, `""` for an empty cell); no number or null is inferred. Semicolon separated rows, and the way back from JSON to rows, are not done. `JSON Minify` stays as it was. `TextTransform` has 27 cases (`json` for the renamed one, `markdown`).
- **`Markdown` is offered for a clip that kept HTML, RTFD or RTF with structure** (headings, bold, italic, strikethrough, links, code, quotes, lists, pictures and tables), and for a code clip that is HTML source. It writes GitHub-Flavored Markdown: nested lists, tables with `|` escaped, a cell's lists and nested tables flattened with `<br>`, merged cells padded with empty ones, Markdown characters in text escaped. A link is kept only when it is `http`, `https`, `mailto` or relative; a `data:` picture keeps only its alt text. Nothing the markup names is requested.
- **HTML is read by `HTMLTree`, never by AppKit** (WebKit-based import can request what the markup names). **RTF and RTFD use `NSAttributedString` on the main actor.** HTML wins over RTFD over RTF.
- **What is never read** (`StructuredPaste`, the one place that decides, before any decryption): a hidden clip (even while shown), a clip filtered or still being screened, anything but text and code, a clip over 1 MB, a sealed rich payload over 2 MB, and a clip whose blob will not open (never its preview). The card's menu offers the rows only when the card is not covered, and the entries are in neither `CardMenuItem.coveredAllowed` nor a VoiceOver action, so a covered card gains no side door.
- **Bounds.** Table text 1 MB in, 5 MB out, 200 columns, header names of 40 characters or fewer; HTML 128 KB, 96 levels, 150,000 nodes, 100,000 table cells; RTF 32 KB; the sealed rich payload 2 MB. What qualifies is worked out when the menu opens (a table is sampled by its first 50 rows), not when a card draws.
- **Prose is not a table**: one column, a row of another width, an empty or repeated header name, a header that ends like a sentence, and a comma separated text whose every line ends in `.`, `?` or `!` are refused.

## Consequences
- A text clip's Paste As… loses a row that did nothing for most clips; a JSON document gets its keys in the order it had, which is a change from the sorted output.
- A clip that kept formatting costs the menu one decryption and one conversion when it opens. Measured in a release build on an Apple M5 Pro: a 1 MB table 0.05 ms to say it is one and 18 ms to write; 1 MB of JSON 9 ms; HTML about 0.1 ms per KB (13 ms at its limit); AppKit reads RTF at about 0.6 ms per KB (19 ms at its limit), which is why RTF is bounded far lower. A copy over a limit does not get the row.
- `JWTDecoder` keeps its own sorted layout for a token's header and payload (its tests pin it).
- Markdown from RTF cannot see a heading (RTF has no heading style), only emphasis, links, lists, code in a fixed-width font and tables.

## Docs affected
- `docs/guide/using-pesto.md` (the Paste As… line: 27 transforms, the two new entries and when they appear; synced to the website)
- `README.md`, `docs/feature-reference.md`
- `docs/testing.md` (hand checks)
- `decisions/README.md` (this record in the table)
