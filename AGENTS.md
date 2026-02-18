# AGENTS.md — Rectangle

## Project Overview

Rectangle is a macOS window management app (menu bar utility) written in **Swift 5** using **AppKit/Cocoa**.
It uses a notification-driven, manager-centric architecture — not MVC/MVVM. The UI is storyboard-based (no SwiftUI).

**Targets:** Rectangle (main app), RectangleLauncher (launch-at-login helper), RectangleTests.

## Build Commands

```bash
# Debug build
xcodebuild -project Rectangle.xcodeproj -scheme Rectangle build

# Archive (release) build
xcodebuild -project Rectangle.xcodeproj -scheme Rectangle archive \
  CODE_SIGN_IDENTITY="-" -archivePath build/Rectangle.xcarchive

# Run all tests
xcodebuild -project Rectangle.xcodeproj -scheme Rectangle test

# Run a single test class
xcodebuild -project Rectangle.xcodeproj -scheme Rectangle test \
  -only-testing:RectangleTests/RectangleTests

# Run a single test method
xcodebuild -project Rectangle.xcodeproj -scheme Rectangle test \
  -only-testing:RectangleTests/RectangleTests/testExample
```

There is no linter configured (no SwiftLint, no formatter). Match existing style manually.

### Build Notes

- CI runs on `macos-26`. Building on macOS < 26 requires deleting "Asset Catalog Other Flags"
  from the Xcode build settings (Liquid Glass icon support). Do NOT commit that change.
- Dependencies (MASShortcut, Sparkle) are managed via Swift Package Manager integrated in Xcode.
  They resolve automatically on first build.
- Ad-hoc signing (`CODE_SIGN_IDENTITY="-"`) works for local development.

## Code Style Guidelines

Match the existing coding style (per CONTRIBUTING.md). The conventions below are derived
from the codebase — follow them strictly.

### Indentation & Braces

- **4 spaces**, no tabs.
- **K&R braces** — opening brace on the same line, always:
  ```swift
  func doSomething() {
      if condition {
          ...
      }
  }
  ```
- No strict line length limit. Lines up to ~200 chars exist, but keep things readable.

### Imports

- `Cocoa` when AppKit types are needed (most files); `Foundation` for non-UI code.
- System frameworks first, then third-party (`MASShortcut`, `Sparkle`). Not alphabetized.
- One import per line.

### Access Control

- **Never** write `internal` explicitly — rely on the default.
- Use `private` liberally for implementation details.
- Use `fileprivate` only for file-scoped free functions or constants.
- Use `public private(set)` for externally-readable but internally-writable properties.
- Use `public` sparingly — only for API surfaces.

### Naming Conventions

| Element          | Convention      | Example                              |
|------------------|-----------------|--------------------------------------|
| Classes/Structs  | UpperCamelCase  | `WindowManager`, `ExecutionParameters` |
| Enums            | UpperCamelCase  | `WindowAction`, `SubsequentExecutionMode` |
| Enum cases       | lowerCamelCase  | `leftHalf`, `topLeftSixth`           |
| Protocols        | UpperCamelCase  | `WindowMover`, `OrientationAware`    |
| Properties/Vars  | lowerCamelCase  | `windowElement`, `initialWindowRect` |
| Functions        | lowerCamelCase  | `detectScreens(using:)`              |
| Static constants | lowerCamelCase  | `static let instance`, `static let launcherAppId` |
| Booleans         | Descriptive     | `enabled`, `logging`; computed: `isFullScreen`, `isLandscape` |

### Type Annotations

- **Prefer type inference** when the type is obvious from the right-hand side.
- Use explicit annotations for optionals, protocol types, or when the type is unclear.
- Always annotate function parameters and return types.

### Guard vs If-Let

- **Prefer `guard`** for early returns:
  ```swift
  guard let element = windowElement else { return }
  ```
- Use `if let` for conditional branches that don't exit.
- Swift 5.7 shorthand (`if let value { ... }`) is used in newer code.
- Multi-clause guards have each clause on a new line:
  ```swift
  guard let a = foo(),
        let b = bar()
  else { return }
  ```

### Closures

- Use trailing closure syntax when the closure is the last argument.
- Use `$0` shorthand in short single-expression closures.
- Use named parameters in longer closures.
- Capture `[weak self]` only when needed (not by default):
  ```swift
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self else { return }
      ...
  }
  ```

### Error Handling

- **`try?`** is the dominant pattern — used for most failable operations.
- **`do/try/catch`** only when error recovery or logging is needed.
- No `Result` types. Heavy use of optional chaining (`?.`).

### Strings

- Prefer **string interpolation** over concatenation.
- Localization: `NSLocalizedString(key, tableName:, value:, comment:)` or the custom `.localized` extension.

### Enums

- Int raw values are common (especially for `Codable`/`UserDefaults` storage).
- Cases are comma-separated on separate lines in large enums:
  ```swift
  enum WindowAction: Int, Codable {
      case leftHalf = 0,
           rightHalf = 1,
           maximize = 2
  }
  ```

### Protocol Conformance

- Core identity protocols go in the main declaration: `class Foo: NSObject, NSApplicationDelegate`.
- Adopted protocols (delegates, Equatable, etc.) go in **extensions**:
  ```swift
  extension AppDelegate: NSMenuDelegate {
      func menuWillOpen(_ menu: NSMenu) { ... }
  }
  ```

### Comments & Documentation

- Standard Xcode file headers on every file (author, copyright).
- Use `//` for inline comments; keep them concise.
- `///` doc comments are rare — use only when genuinely needed.
- `// MARK:` pragmas are almost never used. Organize via extensions instead.
- `// TODO:` is acceptable for known incomplete work.

### Blank Lines & Spacing

- 1 blank line between methods.
- Properties grouped together without blank lines; blank line between logical groups.
- Usually 1 blank line after an opening class/struct brace.
- 1 blank line between top-level declarations (classes, extensions).

### Notifications

The codebase uses a custom `Notification.Name` extension pattern:
```swift
Notification.Name.configImported.post()
Notification.Name.windowSnapping.onPost { notification in ... }
```
Follow this pattern — do NOT use raw `NotificationCenter.default.post(name:)` for app-defined notifications.

### Singletons

Use `static let instance` with `private init()`:
```swift
class MyManager {
    static let instance = MyManager()
    private init() {}
}
```

### Defaults / UserDefaults

Use the `Defaults` static registry with typed wrappers (`BoolDefault`, `FloatDefault`,
`IntEnumDefault`, `JSONDefault<T>`). These auto-persist via `didSet`. Do NOT access
`UserDefaults.standard` directly for app settings.

## Architecture Quick Reference

- **AppDelegate** — central coordinator; instantiates all managers.
- **WindowAction** (enum) — command hub; each case is a window action with shortcuts, display info, and post methods.
- **WindowCalculation** (base class) + **WindowCalculationFactory** — strategy pattern for geometry math.
- **WindowMover** (protocol) — chain of responsibility: `StandardWindowMover` → `BestEffortWindowMover`.
- **SnappingManager** — drag-to-snap via CGEvent monitoring.
- **ShortcutManager** — keyboard shortcut registration and dispatch.
- **ApplicationToggle** — per-app enable/disable logic.
- **Defaults** — static registry wrapping UserDefaults with typed properties.
