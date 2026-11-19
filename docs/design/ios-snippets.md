# Snippets on iPhone and iPad: Create and Edit with Fill-Ins

Extends ADR 0017 (snippets and fill-in questions), ADR 0046 (iOS app), ADR 0048 (text edit and sealing), ADR 0051 (AutoFill quick-insert), and `docs/design/ios-library.md`.

A snippet on iPhone and iPad uses the exact same model as the Mac (`docs/design/snippets-and-suggestions.md`): a pinned clip whose text contains a `{{placeholder}}`, automatically filed in the smart `Snippets` collection (`PredicateRuleSet.snippetsCollectionID`) and synced across devices without any schema change.

---

## Entry Points

1. **Create from the library (`New Snippet…`):**
   - The library toolbar's trailing create menu (`+`) offers **New Note** and **New Snippet…**. (`⌘N` on iPad continues to open New Note.)
   - When viewing an empty `Snippets` smart collection, `LibraryEmptyState` also offers **New Snippet…**.
   - Inside New Snippet mode, a **Starters…** menu offers `SnippetStarters.all` to pre-fill a ready-made template (name + text).
2. **Edit an existing snippet (`Edit Snippet…`):**
   - In `CardMenu` (long press on a card) and `ClipDetailView` (alongside `Edit Text` and in the `More` menu), any unlocked, non-concealed snippet (`item.isTemplate && appState.canEditText(item)`) offers **Edit Snippet…**.
   - Plain **Edit Text** remains untouched for quick raw edits.
   - **Save as Snippet** stays in `CardMenu` and `ClipDetailView` for unpinned plain text and code clips (`canSaveAsSnippet`), converting `{variable}` placeholders into fill-ins and pinning in place.

---

## Editor (`MobileSnippetEditorView`)

One sheet handles both creation and editing, with `.interactiveDismissDisabled` and a Discard confirmation when unsaved edits exist:

1. **Title:** `TextField` mapped to `customTitle` (trimmed; blank clears the title to `nil`).
2. **Body (`TextEditor(text:selection:)`):** Monospaced editor bound to SwiftUI `TextSelection?`. Inserting a question, automatic fill, or starter uses `SnippetDraft.inserting(_:into:selection:)` (UTF-16 range clamped to bounds, advancing the insertion point right past the inserted token).
3. **Menus below the editor:**
   - **Add Question…:** Opens a compact naming sheet for `Text Field…`, `Multi-Line Field…`, `Choice…`, or `Optional Section…`, building a `SnippetField` and inserting `field.insertion` without requiring users to type attribute syntax by hand.
   - **Automatic Fill…:** Inserts the nine built-in tokens supported on iOS (`MobileSnippetPlaceholders.automaticFills`): `{{date}}`, `{{time}}`, `{{datetime}}`, `{{isodate}}`, `{{weekday}}`, `{{date+1d}}`, `{{clipboard}}`, `{{uuid}}`, and `{{cursor}}`. Mac-only `{{selection}}` and `{{app}}` are excluded.
   - **Starters…** *(new snippets only)*: Fills from `SnippetStarters.all`.
4. **Questions & detected placeholders (`MobileSnippetQuestionList`):**
   - Lists `FillInParser.fields(in: text)`. Each row lets the user rename the question (`FillInParser.renaming`), expand to edit its default value / multiline flag / comma-separated choices (`FillInParser.updating`), or remove it (`FillInParser.removing`).
   - Lists `FillInParser.detectedVariables(in: text)` (`{name}` or bare `{{name}}`) with one-step **Turn into Question** / **Use Fill** and **Turn All into Questions** actions.
   - Displays a quiet pill row of built-in fills detected in the body (`FillInParser.highlights`).
5. **Live preview (`Copies as`):**
   - Renders `SnippetPreview.pieces(from: text, clipboardProvider: { "" })` using `@Environment(\.pestoAccent)` chips for questions, secondary chips for `{{clipboard}}`, dimmed runs for optional sections, and an accent caret mark where `{{cursor}}` sits (noting it is removed on copy). `{{clipboard}}` stays empty in the preview so iOS never triggers a paste prompt while editing.

---

## Storage, Sealing, Undo, and Sheet Hosting

- **Creation (`MobileAppState.createSnippet(title:text:)`):** Validates non-empty text, converts any remaining bare variables if the user saved before converting them manually, calls `StorageService.addSnippet(text, title: title)`, refreshes `HistoryStore`, bumps `textEdits`, offers Undo (`offerUndo`), and notifies `clipWasKept()`.
- **Update (`MobileAppState.updateSnippet(id:title:text:)`):** Calls `StorageService.updateSnippet(id:title:text:)`, waits briefly for the main `ModelContext` to reflect the updated hash/title, refreshes `HistoryStore`, bumps `textEdits`, and offers Undo (`UndoLabel.editSnippet` -> *"Changed a snippet"*).
- **Errors:** `ClipSizePolicy.TooLarge` and empty-text errors render inline inside the sheet (`appState.notice`) without discarding the user's draft.
- **Sheet presentation:** `LibraryModel.snippetEditor` holds the active editor state so it survives iPad size-class layout swaps and clears on `LibraryModel.closeEverything()` (History Lock). Following `ClipResultSheets`, `ClipDetailView` presents the sheet when `isSheet == true` (compact width over detail), and `LibraryPresentations` presents it otherwise (grid or regular-width iPad inspector), guaranteeing at most one sheet on screen.

---

## Left Out on iOS

- Global `⌃1`–`⌃9` shortcut slot assignment (macOS-only).
- Automatic look-alike snippet suggestions & AI name suggestions in the editor (may be added later; keeps the iOS editor focused and lightweight).
- `{{selection}}` and `{{app}}` placeholders (iOS apps cannot inspect another app's selection or frontmost app name).
