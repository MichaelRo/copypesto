# Automation

Pesto can be driven from scripts, Alfred, Keyboard Maestro, Shortcuts and the shell. Nothing here sends data anywhere.

## `pesto://` links
| Link | Does |
|---|---|
| `pesto://open` | Opens the shelf |
| `pesto://list` | Shows or hides the floating window |
| `pesto://search?q=text` | Opens the shelf with that search |
| `pesto://summary?id=<id>` | Opens the shelf with a search that finds that clip |
| `pesto://paste?id=<id>` | Pastes a clip |
| `pesto://pin?id=<id>` | Pins or unpins a clip |
| `pesto://collection?name=Work` | Switches to a collection (`pinboard?name=` still works, deprecated) |
| `pesto://clear?range=hour` | Clears history for `hour`, `today` or `all`; always asks you to confirm, and the range is required |

Try one from Terminal: `open "pesto://search?q=invoice"`. Links never call an AI service.

## Services menu
Select text in any app and choose *Services → Copy to Pesto* (the app's name menu, or a right-click). It copies the text, and Pesto records it like any copy.

## AppleScript
```applescript
tell application "Pesto"
    copy item "hello from a script"
    copy item "a secret" concealed true
    get last item
    search history with query "invoice"
    paste item id "UUID"
    list collections
    clear history range "hour"
end tell
```
`search history` and `list collections` return an AppleScript list, one text per clip or collection (earlier versions returned one text with line breaks). `clear history` asks for confirmation. `concealed true` keeps a copy on this Mac, off Universal Clipboard and out of other
clipboard managers; Pesto drops a concealed copy too, so it is not added to your history.

## The `pesto` command
A small command-line tool is in the source tree but is not part of the app download yet. Build it with `make build-cli`.
```bash
pesto copy "some text"     # adds text to your clipboard (Pesto captures it)
echo "a secret" | pesto copy   # from stdin, so the text is not visible in the process list
echo "a secret" | pesto copy --concealed   # host-only and concealed; Pesto does not keep it
pesto last                 # prints the latest clip without a secret (nothing while the history lock is on)
pesto last --json          # the same, as JSON
pesto install              # links it into /usr/local/bin, or ~/.local/bin when that folder cannot be written
```

## Shortcuts (Apple's app)
Pesto adds five actions to the Shortcuts app and Spotlight: **Open Pesto**, **Search Pesto** (opens the shelf with your
search already typed), **Copy from Pesto** (searches for text and puts the best match on the clipboard, ready for ⌘V), **Copy Text to Pesto** (with a *Concealed* switch that keeps the copy on this Mac and out of your history) and
**Hide Clip Contents** (blurs the shelf's clips for a screen share, or shows them again). Find them in the Shortcuts app
under Pesto, where any of them can have a keyboard shortcut. While the history is locked, they cannot read or paste your
clips. **Hide Clip Contents** is also a Focus filter (*System Settings → Focus*), so a Focus can cover your clips while
it is on.

## Control Center
On macOS 26 and later, Pesto offers an **Open Pesto** control. Open Control Center, choose *Edit Controls*, and add it;
pressing it opens the shelf. It carries no data: it only opens `pesto://open`.

