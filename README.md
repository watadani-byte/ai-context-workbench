# AI Context Workbench v0.1

Stage 0 project scaffold for the approved macOS-first implementation.

## Current stage

- Stage 0 only
- Formal macOS Application target
- SwiftUI application shell placeholder
- Shared `WorkbenchCore` framework target
- `WorkbenchCoreTests` unit-test target
- Existing Swift Package manifest retained
- No Stage 1 or later functionality implemented

## Xcode verification

Open:

```text
AIContextWorkbench.xcodeproj
```

Use:

```text
Scheme: AIContextWorkbenchApp
Destination: My Mac
Build: Command-B
Run: Command-R
Test: Command-U
```

Expected placeholder window:

```text
AI Context Workbench
```

The deployment target (`macOS 14.0`) and bundle identifier
(`com.watadani.prototype.AIContextWorkbench`) are temporary prototype settings
and are not final release decisions.

## Swift Package verification

The original Swift Package structure remains available:

```sh
swift build
swift test
```

## Stage 0 correction v2

`WorkbenchCore` is an Xcode framework target. Its Debug and Release configurations explicitly set `GENERATE_INFOPLIST_FILE = YES` so Xcode can code sign the framework as part of the macOS application build.
