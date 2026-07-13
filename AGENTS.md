# Agent Guidelines for md-vault

Development note: always build, kill, and restart the app after making changes. Do this in one command like:

```sh
xcodebuild -project md-vault.xcodeproj -scheme md-vault -configuration Debug build 2>&1 | tail -3 && pkill -x md-vault 2>/dev/null; sleep 0.5 && open ~/Library/Developer/Xcode/DerivedData/md-vault-*/Build/Products/Debug/md-vault.app
```

Run tests with:

```sh
xcodebuild -project md-vault.xcodeproj -scheme md-vault test 2>&1 | tail -5
```

## Project Overview

md-vault is a native macOS app for viewing and editing a folder ("vault") of markdown files. It is built to coexist with coding agents that read, edit, and create the same files on disk. The editor is a hybrid live-styled source view: the raw markdown source is always the document of record; styling is overlaid attributes only.

## Architecture

Pure SwiftUI, macOS 26 deployment target (requires the AttributedString-backed `TextEditor`). Single `WindowGroup` scene.

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
- `FSEventStream*` (CoreServices C API) -- recursive vault directory watching

If a feature requires deeper AppKit integration, reconsider whether it's needed.

Known framework limits (macOS 26.5, verified): the AttributedString `TextEditor` ignores "Check Spelling While Typing" (the toggle never latches), and there is no SwiftUI spell-checking API. `TextEditingCommands()` is in the app commands because its Find & Replace bar works; do not add an NSTextView escape hatch just for spelling. It also ignores `contentMargins`; inset the text with `safeAreaPadding` instead.

**Swift 6 strict concurrency.** Model types conform to `Sendable`. Build and test in Release mode before pushing; it is stricter than Debug for concurrency.

**One dependency.** Apple's swift-markdown (the `Markdown` product), for parsing only. No other packages.

**Never clobber external edits.** Agents edit vault files while they're open in the app. Saves are atomic, pre-checked against the last-known disk content, and our own writes are recognized by content comparison (not tokens or mtimes). See `ExternalChange.determine` once it exists; its decision matrix is exhaustively unit-tested.

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
