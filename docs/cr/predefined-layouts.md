# CR: Predefined Layouts — Focus Layout

**Author:** —
**Date:** 2026-02-18
**Status:** Draft

## Problem Statement

Rectangle can move/resize the **frontmost window** or arrange **all windows** into generic
grids/cascades, but there is no single-shortcut action that arranges the focused app
prominently while stacking all other windows to the side.

Users who want a "focus" workspace — main app taking most of the screen, everything else
tucked away — must trigger multiple shortcuts manually, one per window.

## Goals

1. Add a **Focus Layout** action: one shortcut arranges all windows on the current screen.
2. The **frontmost app** gets **70% of the screen width** on the left.
3. All **other windows** are **stacked vertically** in the remaining 30% on the right.
4. **Two shortcuts for cycling** the focused app through all visible apps:
   - `Ctrl+Shift+)` — cycle forward (next app becomes focus).
   - `Ctrl+Shift+(` — cycle backward (previous app becomes focus).
5. Layout is **hardcoded** — no configuration UI, no saved layouts, no data model.
6. Works like `tileAll` / `cascadeAll` — new `WindowAction` enum cases routed through
   `MultiWindowManager`.

## Non-Goals

- User-configurable layout ratios or positions.
- Saving/restoring custom named layouts.
- Per-app targeting or bundle ID matching.
- New preferences UI tab.
- Multi-screen awareness (operates on the current screen only, like `tileAll`).

## Existing Architecture (Context)

| Component | Role |
|---|---|
| `WindowAction` enum (highest raw value: 91) | Each case = one action with shortcut, name, dispatch |
| `MultiWindowManager.execute()` | Routes multi-window actions; returns `true` if handled |
| `MultiWindowManager.allWindowsOnScreen()` | Enumerates visible windows on current screen; cross-references with CGWindowList filtering by layer 0, alpha > 0, and non-zero size to exclude ghost windows |
| `AccessibilityElement` | AX wrapper: `setFrame()`, `bringToFront()`, `pid`, `frame` |
| `ShortcutManager` | Subscribes to all `WindowAction` notification names |

The `tileAll` action is the closest precedent. It:
1. Gets all windows on the current screen via `allWindowsOnScreen(sortByPID: true)`.
2. Computes a grid layout from the screen's `adjustedVisibleFrame().screenFlipped`.
3. Calls `w.setFrame(rect)` on each window.

Focus Layout follows the same pattern with different geometry math, plus cycling state.

## Design

### New WindowAction Cases

```swift
// WindowAction.swift — add after bottomVerticalTwoThirds = 91
focusLayoutNext = 92,
focusLayoutPrev = 93
```

Two cases — one per cycle direction. Both apply the same 70/30 layout but rotate the
focused app in opposite directions.

Wire into all `WindowAction` computed properties following existing patterns:

| Property | `focusLayoutNext` | `focusLayoutPrev` |
|---|---|---|
| `name` | `"focusLayoutNext"` | `"focusLayoutPrev"` |
| `displayName` | `nil` | `nil` |
| `image` | `NSImage()` | `NSImage()` |
| `isDragSnappable` | `false` | `false` |
| `gapsApplicable` | `.none` | `.none` |

Add both to `WindowAction.active` array (at the end, after `tileActiveApp`).

### Default Keyboard Shortcuts

```swift
// In alternateDefault (Rectangle defaults):
case .focusLayoutNext: return Shortcut( ctrl|shift, kVK_ANSI_0 )  // Ctrl+Shift+)
case .focusLayoutPrev: return Shortcut( ctrl|shift, kVK_ANSI_9 )  // Ctrl+Shift+(

// In spectacleDefault:
case .focusLayoutNext: return Shortcut( ctrl|shift, kVK_ANSI_0 )  // same
case .focusLayoutPrev: return Shortcut( ctrl|shift, kVK_ANSI_9 )  // same
```

- `kVK_ANSI_0` (`0x1D`) = `0` key. With Shift held, types `)`.
- `kVK_ANSI_9` (`0x19`) = `9` key. With Shift held, types `(`.
- `Ctrl+Shift` is not used by any existing Rectangle shortcut, so no conflicts.

### MultiWindowManager Routing

```swift
// MultiWindowManager.execute() — add cases
case .focusLayoutNext:
    focusLayoutOnScreen(windowElement: parameters.windowElement, direction: .next)
    return true
case .focusLayoutPrev:
    focusLayoutOnScreen(windowElement: parameters.windowElement, direction: .prev)
    return true
```

### Cycling State

A single static property tracks which app PID currently holds the focus position:

```swift
private static var focusedPid: pid_t?

private enum CycleDirection {
    case next, prev
}
```

**Cycle logic:**
1. Get all unique app PIDs from the visible windows (ordered by PID for stability).
2. If `focusedPid` is `nil` or no longer present in the window list, use the frontmost
   app's PID — apply layout without cycling.
3. If `focusedPid` is still present, advance to the next (or previous) PID in the
   circular list based on the direction.
4. Apply layout with the resolved PID as the focus app.
5. Store the resolved PID in `focusedPid`.
6. Call `bringToFront()` on the new focus app's window.

This means:
- **First press (either direction):** Frontmost app goes to left 70%, others stack right.
- **Subsequent `Ctrl+Shift+)`:** Next app rotates into the left 70%.
- **Subsequent `Ctrl+Shift+(`:** Previous app rotates into the left 70%.
- Wraps around circularly in both directions.

### Layout Algorithm

```swift
private static var focusedPid: pid_t?

private enum CycleDirection {
    case next, prev
}

static func focusLayoutOnScreen(windowElement: AccessibilityElement? = nil, direction: CycleDirection) {
    guard let (screens, windows) = allWindowsOnScreen(windowElement: windowElement, sortByPID: true)
    else {
        return
    }

    let screenFrame = screens.currentScreen.adjustedVisibleFrame().screenFlipped
    let focusRatio: CGFloat = 0.7

    // Build ordered list of unique PIDs
    var uniquePids = [pid_t]()
    for w in windows {
        if let pid = w.pid, !uniquePids.contains(pid) {
            uniquePids.append(pid)
        }
    }

    guard !uniquePids.isEmpty else { return }

    // Determine which PID gets focus
    let resolvedPid: pid_t
    if let currentFocus = focusedPid,
       let currentIndex = uniquePids.firstIndex(of: currentFocus) {
        // Cycle in the requested direction
        let offset = direction == .next ? 1 : uniquePids.count - 1
        let nextIndex = (currentIndex + offset) % uniquePids.count
        resolvedPid = uniquePids[nextIndex]
    } else {
        // First press or focusedPid gone — use frontmost app
        let frontPid = AccessibilityElement.getFrontWindowElement()?.pid
        resolvedPid = frontPid ?? uniquePids[0]
    }

    focusedPid = resolvedPid

    // Split windows: only the largest window of the focused app gets the
    // left zone. Extra windows (helper/utility) go to the right stack.
    let allFocusWindows = windows.filter { $0.pid == resolvedPid }
    let primaryWindow = allFocusWindows.max(by: {
        let a = $0.frame; let b = $1.frame
        return (a.width * a.height) < (b.width * b.height)
    })
    let otherWindows = windows.filter { $0 != primaryWindow }

    // Left zone: 70% width, full height — single primary window
    let leftWidth = screenFrame.width * focusRatio

    if let primaryWindow {
        let rect = CGRect(
            x: screenFrame.origin.x,
            y: screenFrame.origin.y,
            width: leftWidth,
            height: screenFrame.height
        )
        primaryWindow.setFrame(rect)
    }

    // Right zone: 30% width — all other windows stacked
    guard !otherWindows.isEmpty else { return }
    let rightX = screenFrame.origin.x + leftWidth
    let rightWidth = screenFrame.width - leftWidth
    let stackHeight = screenFrame.height / CGFloat(otherWindows.count)

    for (i, w) in otherWindows.enumerated() {
        let rect = CGRect(
            x: rightX,
            y: screenFrame.origin.y + stackHeight * CGFloat(i),
            width: rightWidth,
            height: stackHeight
        )
        w.setFrame(rect)
    }

    // Bring the focused app to front
    primaryWindow?.bringToFront()
}
```

### Cycling Walkthrough

Given 3 apps on screen: **Xcode** (PID 100), **Safari** (PID 200), **Terminal** (PID 300).
Xcode is frontmost.

```
Ctrl+Shift+) (first press):
  focusedPid = nil -> use frontmost Xcode (100)
  Layout: [Xcode 70%] [Safari | Terminal 30%]

Ctrl+Shift+) (second press):
  focusedPid = 100 -> next -> Safari (200)
  Layout: [Safari 70%] [Xcode | Terminal 30%]

Ctrl+Shift+) (third press):
  focusedPid = 200 -> next -> Terminal (300)
  Layout: [Terminal 70%] [Xcode | Safari 30%]

Ctrl+Shift+) (fourth press):
  focusedPid = 300 -> next -> wraps to Xcode (100)
  Layout: [Xcode 70%] [Safari | Terminal 30%]

Ctrl+Shift+( (reverse):
  focusedPid = 100 -> prev -> Terminal (300)
  Layout: [Terminal 70%] [Xcode | Safari 30%]

Ctrl+Shift+( (again):
  focusedPid = 300 -> prev -> Safari (200)
  Layout: [Safari 70%] [Xcode | Terminal 30%]
```

### URL Scheme

Automatically available via existing URL handler since `WindowAction.active` includes them:

```
rectangle://execute-action?name=focus-layout-next
rectangle://execute-action?name=focus-layout-prev
```

No additional code needed — `getUrlName()` in `AppDelegate` converts camelCase to
kebab-case automatically.

## Files Changed

| File | Change |
|---|---|
| `Rectangle/WindowAction.swift` | Add `focusLayoutNext = 92`, `focusLayoutPrev = 93`; wire into `name`, `displayName`, `image`, `isDragSnappable`, `gapsApplicable`, `spectacleDefault`, `alternateDefault`, `active` array |
| `Rectangle/MultiWindow/MultiWindowManager.swift` | Add `focusedPid` state, `CycleDirection` enum, both `.focusLayoutNext`/`.focusLayoutPrev` cases in `execute()`, shared `focusLayoutOnScreen(direction:)` method |

**No new files. No new Defaults. No UI changes.** Two files, ~70 lines of new code.

## Edge Cases

| Case | Behavior |
|---|---|
| Only one app on screen | It gets the left 70%; cycling is a no-op (only one PID) |
| Only front app windows, no others | Front app tiles in left 70%; right 30% empty; no cycling |
| No front window detected | `guard` fails, early return (same as `tileAll`) |
| Many other windows (e.g., 20) | Each gets a thin horizontal slice in the right 30% |
| Front app has multiple windows | Only the largest window gets the left 70%; extra windows (helper/utility) go to the right stack |
| Minimized/hidden/sheet windows | Filtered out by `allWindowsOnScreen()` (existing behavior) |
| Zero-size / invisible windows | Filtered out by `allWindowsOnScreen()` — AX windows must match a CGWindowList entry with layer 0 (normal window level), alpha > 0 (not fully transparent), and non-zero frame size |
| App quit while focused | `focusedPid` no longer in PID list; falls back to frontmost app |
| New app launched between presses | Appears in PID list; naturally joins the cycle |

## Future Extensions

These are explicitly out of scope but could build on this foundation:

- **Configurable ratio** — Add a `Defaults.focusLayoutRatio` (`FloatDefault`, default 0.7).
- **More fixed layouts** — Additional `WindowAction` cases (e.g., `sideBySideLayout`,
  `presentationLayout`) using the same pattern.
- **User-defined layouts** — Full save/restore system (if demand exists).
