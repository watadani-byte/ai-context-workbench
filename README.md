# AI Context Workbench v0.1

AI Context Workbench is a macOS-first authoring environment for maintaining a human-controlled canonical source document.

The project separates editable source from derived results such as previews, validation diagnostics, and structural navigation. Derived processing must not silently replace or rewrite the canonical source.

## Platform and project requirements

- macOS application built with Swift and SwiftUI
- Xcode project: `AIContextWorkbench.xcodeproj`
- Swift package manifest: `Package.swift`
- Swift tools version: Swift 6.0
- Current project deployment target: macOS 14.0

The deployment target and prototype bundle identifiers remain implementation settings and are not final release commitments.

## Current implementation

The repository currently contains the following implementation foundations.

### Editor and canonical source

- Native macOS text-editing surface
- Canonical source text, revision, snapshot, and selection state
- Basic insert, delete, replace, cut, paste, and platform editing behavior
- Dirty-state tracking against the last accepted clean snapshot
- IME composition transaction handling
- Editor-state and canonical-source synchronization boundaries

### Document persistence

- New, Open, Save, and Save As lifecycle paths
- UTF-8 file reading and writing
- Atomic file writes
- Immutable save snapshots
- Structured read and write outcomes
- Rejection of stale, mismatched, duplicate, or superseded persistence completions
- Serialized persistence execution
- Dirty-document Save, Discard, and Cancel decisions
- Lifecycle-command gating while a write is active
- Save As URL adoption only after an accepted successful write

Recognized file extensions are:

- `.md`
- `.markdown`
- `.txt`
- `.xmd`
- `.xml`
- `.yaml`
- `.yml`

An unknown extension is advisory rather than an automatic reason to reject an otherwise valid UTF-8 document.

### Project structure

- `AIContextWorkbenchApp` macOS application target
- `WorkbenchCore` framework target
- `WorkbenchCoreTests` test target
- `AIContextWorkbenchAppTests` test target
- Swift Package equivalents for the application, library, and tests

## Current limitations

The project is not yet a complete v0.1 product.

The following capabilities have approved v0.1 definitions but are not represented here as completed implementation:

- Search and Replace
- Markdown Preview
- Tag Helper
- Copy All
- Document Semantic Validation
- XMD Pair navigation and highlighting
- Full cross-feature Undo / Redo completion against the approved acceptance conditions

The following items are deliberately deferred or unresolved:

- Whole-word search
- Extended Markdown features such as tables, task lists, and footnotes
- Markdown-specific lint rules
- Self-closing Tag Helper insertion
- Concrete contents of the human-approved built-in Tag Catalog
- `.xmd` Markdown Preview behavior
- Automatic validation
- Automatic repair or source rewriting

AI generation, AI correction, AI rewriting, and Multi-AI Runtime Expansion are not current v0.1 application capabilities.

## Approved v0.1 behavior

The approved v0.1 Definition Baseline establishes the following boundaries.

### Canonical source

- The canonical source changes only through human input or an explicitly invoked editing operation.
- Preview, validation, search results, and pair displays are derived results.
- Derived results do not automatically modify the canonical source.
- Derived results retain the identity of their input snapshot.
- Results derived from an obsolete snapshot must not be adopted as current.

### Validation

Document Semantic Validation is read-only and advisory.

It may report unmatched tags, incorrect nesting, or malformed delimiters, but it does not automatically repair the document or prohibit saving it. Persistence and lifecycle validation separately determine whether an asynchronous read or write completion may be adopted.

### XMD Pair

For v0.1, XMD Pair means read-only identification, highlighting, and navigation between matching opening and closing tags in the same `.xmd` document.

It does not mean cross-file pairing, automatic repair, automatic counterpart renaming, or generated content.

### Undo and Redo

The v0.1 completion criteria cover canonical source consistency, editor state, selection, dirty state, and the last successfully saved snapshot.

Replace All, Tag Helper insertion or wrapping, and a committed IME composition are defined as single editing transactions where applicable.

## Known verification status

The current source contains Stage 1 through Stage 4 implementation work; the earlier `Stage 0 only` description is obsolete.

However, implementation presence, automated verification, and successful human runtime verification are separate status claims.

A Stage 4 human runtime verification identified that editor input could remain displayed as `Clean` at `Revision 0`. That finding prevented completion of the dirty-document Save, Discard, and Cancel runtime path verification.

Accordingly:

- Stage 4 implementation is present in the repository baseline.
- The affected runtime path must not be represented as fully verified.
- v0.1 product completion has not been declared.
- The Stage 5 Definition Baseline defines later work but does not itself constitute implementation.

## Build and test

Open the Xcode project:

```text
AIContextWorkbench.xcodeproj
```

Available shared schemes include:

```text
AIContextWorkbenchApp
WorkbenchCore
```

Typical Xcode operations are:

```text
Destination: My Mac
Build: Command-B
Run: Command-R
Test: Command-U
```

The Swift Package structure also supports:

```sh
swift build
swift test
```

These commands describe the project interfaces. This README update does not itself constitute a new build, test, or runtime verification result.

## Project status

```text
Documentation status date:
2026-08-06

Repository baseline identified by the approved project record:
c657fbbc8483c02a120129d41290154adf16fa56

Stage 5 — v0.1 Definition Closure:
COMPLETE

Stage 5 Definition Baseline:
APPROVED / CANONICAL

v0.1 implementation:
IN PROGRESS

v0.1 product completion:
NOT DECLARED

Known Stage 4 runtime verification finding:
OPEN
```

Stage numbers describe project governance and work progression. They must not be used alone as evidence that a product capability is implemented or verified.
