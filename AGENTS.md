# Agent Guidelines for md-vault

Development note: always build, kill, and restart the app after making changes. Do this in one command like:

```sh
xcodebuild -project md-vault.xcodeproj -scheme md-vault -configuration Debug build 2>&1 | tail -3 && pkill -x md-vault 2>/dev/null; sleep 0.5 && open ~/Library/Developer/Xcode/DerivedData/md-vault-*/Build/Products/Debug/md-vault.app
```

Run tests with:

```sh
xcodebuild -project md-vault.xcodeproj -scheme md-vault test 2>&1 | tail -5
```

## Development Journal

Keep a local `JOURNAL.md` at the repository root while working. Read existing entries at the start of a task, then append a timestamped update at meaningful milestones such as decisions, implementation changes, validation results, and blockers. Keep entries concise and factual. Do not include secrets. `JOURNAL.md` is ignored by git and must not be committed.

## Project Overview

md-vault is a native macOS app for viewing and editing a folder ("vault") of markdown files. It is built to coexist with coding agents that read, edit, and create the same files on disk. The editor is a hybrid live-styled source view: the raw markdown source is always the document of record; styling is overlaid attributes only.

## Architecture

SwiftUI, macOS 26 deployment target (requires the AttributedString-backed `TextEditor`). Single `WindowGroup` scene. The sidebar file tree is the one AppKit-backed pane; see the SwiftUI-only constraint below.

Application state lives in a single `AppState` object (`@Observable` + `.environment()`). Per-file editor state lives in `OpenDocument`.

### The restyle pipeline (do not break these invariants)

1. `TextEditor(text:selection:)` binds to `OpenDocument.text` (an `AttributedString` whose characters are ALWAYS the raw markdown source) and `OpenDocument.selection`.
2. `onChange(of: text)` extracts `String(text.characters)`; if it equals `plainText` the change was attribute-only (our own restyle) and is ignored. Otherwise it's a real edit: `plainText` updates and `editGeneration` bumps. This single string comparison is both the re-entrancy guard and the dirty detector.
3. `.task(id: editGeneration)` debounces 150 ms, then restyles: `MarkdownStyler.runs(for:)` produces attribute runs from the source, `applyRuns` resets the string to base attributes and overlays them. Character content is never touched by a restyle.
4. **Selection preservation is manual.** `AttributedString.transform(updating:)` fails to remap a mid-document insertion point across a whole-string `setAttributes` (verified on macOS 26.5: the caret jumps to the end of the document). `OpenDocument.restyle` therefore captures the selection as character offsets before applying runs and rebuilds it afterward. Offsets stay valid because restyles are attribute-only.

`MarkdownStyler.runs(for:)` is a pure function of the source string and the primary unit-test surface.

## Key Constraints

**Minimal code footprint.** Prefer SwiftUI built-ins over custom styling. Let the framework handle materials, spacing, and colors. Every custom modifier is a maintenance burden; only add one when the default is clearly wrong.

**Don't fight the framework.** If a feature requires fighting SwiftUI's opinions, reconsider whether the feature is needed. Concessions that simplify code are better than clever hacks.

**SwiftUI only.** Avoid AppKit except where SwiftUI has no reasonable alternative. Current exceptions:
- `NSOpenPanel` -- vault folder pick/create (`fileImporter` cannot guarantee directory creation)
- `NSApplication.willTerminateNotification` -- flushing unsaved buffers on quit (no SwiftUI scene-teardown hook on macOS)
- `NSPasteboard` -- writing full paths from explicitly labeled context-menu actions
- `NSWorkspace.activateFileViewerSelecting` -- revealing one or more tree items in Finder
- `FSEventStream*` (CoreServices C API) -- recursive vault directory watching
- `NSOutlineView` via `NSViewRepresentable` (`Views/FileTreeView.swift`) -- the whole sidebar file tree

If a feature requires deeper AppKit integration, reconsider whether it's needed.

### Why the file tree is AppKit

`List(selection:)` + `OutlineGroup` cannot own selection and row dragging at the same time on macOS 26. `draggable(containerItemID:)` consumes clicks in its hit region, so rows over the filename text stopped selecting. Working around that with `simultaneousGesture` tap gestures made the row a second writer to `selectedItemURLs` alongside the `List` binding: two event paths, no ordering guarantee, and rapid clicking left extra rows selected without a modifier held.

`NSOutlineView` resolves selection, dragging, rename, and the context menu in one delegate, which is the coordination SwiftUI could not express here. Do not reintroduce a SwiftUI `List` for the tree. Keep `AppState` the source of truth: the coordinator writes selection on `outlineViewSelectionDidChange` and then re-syncs the view from the model, guarded by `isSyncingSelection`.

Two AppKit behaviours the implementation depends on, both verified on macOS 26.5:
- Escape aborts the table's field editor **without** posting `controlTextDidEndEditing`, so cancelling a rename is intercepted in `control(_:textView:doCommandBy:)`. Without it the cell stays permanently editable.
- `NSOutlineView` keys expansion state on item identity, so `FileTreeNode` objects are cached by normalized path and reused across reloads. Rebuilding nodes on every rescan would collapse every folder on each filesystem event.

Known framework limits (macOS 26.5, verified): the AttributedString `TextEditor` ignores "Check Spelling While Typing" (the toggle never latches), and there is no SwiftUI spell-checking API. `TextEditingCommands()` is in the app commands because its Find & Replace bar works; do not add an NSTextView escape hatch just for spelling. It also ignores `contentMargins`; inset the text with `safeAreaPadding` instead.

**Swift 6 strict concurrency.** Model types conform to `Sendable`. Build and test in Release mode before pushing; it is stricter than Debug for concurrency.

**One dependency.** Apple's swift-markdown (the `Markdown` product), for parsing only. No other packages.

**Never clobber external edits.** Agents edit vault files while they're open in the app. Saves are atomic, pre-checked against the last-known disk content, and our own writes are recognized by content comparison (not tokens or mtimes). See `ExternalChange.determine`; its decision matrix is exhaustively unit-tested.

## Style Preferences

- Lean on SwiftUI defaults for spacing, colors, and materials
- Use semantic styles (`.secondary`, `.tertiary`) not custom colors
- Keep views flat and declarative; avoid deep nesting or coordinator patterns
- Load data with `.task {}`, not `onAppear` + Task
- Error and loading states as simple inline views, not separate components
- Prefer computed properties over helper methods when no parameters needed
- Use `@AppStorage` for simple user preferences
- Tests use Swift Testing (`@Test`, `#expect`), not XCTest
- Always ask the user before git operations (commit, push, tag)
