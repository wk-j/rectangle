//
//  MultiWindowManager.swift
//  Rectangle
//
//  Created by Mikhail (Dirondin) Polubisok on 2/20/22.
//  Copyright © 2021 Ryan Hanson. All rights reserved.
//

import Cocoa
import MASShortcut

class MultiWindowManager {
    static func execute(parameters: ExecutionParameters) -> Bool {
        // TODO: Protocol and factory for all multi-window positioning algorithms
        switch parameters.action {
        case .reverseAll:
            ReverseAllManager.reverseAll(windowElement: parameters.windowElement)
            return true
        case .tileAll:
            tileAllWindowsOnScreen(windowElement: parameters.windowElement)
            return true
        case .cascadeAll:
            cascadeAllWindowsOnScreen(windowElement: parameters.windowElement)
            return true
        case .cascadeActiveApp:
            cascadeActiveAppWindowsOnScreen(windowElement: parameters.windowElement)
            return true
        case .tileActiveApp:
            tileActiveAppWindowsOnScreen(windowElement: parameters.windowElement)
            return true
        case .focusLayoutNext:
            focusLayoutOnScreen(windowElement: parameters.windowElement, direction: .next)
            return true
        case .focusLayoutPrev:
            focusLayoutOnScreen(windowElement: parameters.windowElement, direction: .prev)
            return true
        default:
            return false
        }
    }

    private static func allWindowsOnScreen(windowElement: AccessibilityElement? = nil, sortByPID: Bool = false) -> (screens: UsableScreens, windows: [AccessibilityElement])? {
        let screenDetection = ScreenDetection()

        guard let windowElement = windowElement ?? AccessibilityElement.getFrontWindowElement(),
              let screens = screenDetection.detectScreens(using: windowElement)
        else {
            NSSound.beep()
            Logger.log("Can't detect screen for multiple windows")
            return nil
        }

        let currentScreen = screens.currentScreen

        var windows = AccessibilityElement.getAllWindowElements()
        if sortByPID {
            windows.sort(by: { (w1: AccessibilityElement, w2: AccessibilityElement) -> Bool in
                w1.pid ?? pid_t(0) > w2.pid ?? pid_t(0)
            })
        }

        var actualWindows = [AccessibilityElement]()
        for w in windows {
            if Defaults.todo.userEnabled, TodoManager.isTodoWindow(w) { continue }
            let screen = screenDetection.detectScreens(using: w)?.currentScreen
            if screen == currentScreen,
               w.isWindow == true,
               w.isSheet != true,
               w.isMinimized != true,
               w.isHidden != true,
               w.isSystemDialog != true
            {
                actualWindows.append(w)
            }
        }

        return (screens, actualWindows)
    }

    static func tileAllWindowsOnScreen(windowElement: AccessibilityElement? = nil) {
        guard let (screens, windows) = allWindowsOnScreen(windowElement: windowElement, sortByPID: true) else {
            return
        }

        let screenFrame = screens.currentScreen.adjustedVisibleFrame().screenFlipped
        let count = windows.count

        let columns = Int(ceil(sqrt(CGFloat(count))))
        let rows = Int(ceil(CGFloat(count) / CGFloat(columns)))
        let size = CGSize(width: (screenFrame.maxX - screenFrame.minX) / CGFloat(columns), height: (screenFrame.maxY - screenFrame.minY) / CGFloat(rows))

        for (ind, w) in windows.enumerated() {
            let column = ind % Int(columns)
            let row = ind / Int(columns)
            tileWindow(w, screenFrame: screenFrame, size: size, column: column, row: row)
        }
    }

    private static func tileWindow(_ w: AccessibilityElement, screenFrame: CGRect, size: CGSize, column: Int, row: Int) {
        var rect = w.frame

        // TODO: save previous position in history

        rect.origin.x = screenFrame.origin.x + size.width * CGFloat(column)
        rect.origin.y = screenFrame.origin.y + size.height * CGFloat(row)
        rect.size = size

        w.setFrame(rect)
    }

    static func cascadeAllWindowsOnScreen(windowElement: AccessibilityElement? = nil) {
        guard let (screens, windows) = allWindowsOnScreen(windowElement: windowElement, sortByPID: true) else {
            return
        }

        let screenFrame = screens.currentScreen.adjustedVisibleFrame().screenFlipped

        let delta = CGFloat(Defaults.cascadeAllDeltaSize.value)

        for (ind, w) in windows.enumerated() {
            cascadeWindow(w, screenFrame: screenFrame, delta: delta, index: ind)
        }
    }

    private struct CascadeActiveAppParameters {
        let right: Bool
        let bottom: Bool
        let numWindows: Int
        let size: CGSize

        init(windowFrame: CGRect, screenFrame: CGRect, numWindows: Int, size: CGSize, delta: CGFloat) {
            right = windowFrame.midX > screenFrame.midX
            bottom = windowFrame.midY > screenFrame.midY
            self.numWindows = numWindows
            let maxSize = CGSize(width: screenFrame.width - CGFloat(numWindows - 1) * delta, height: screenFrame.height - CGFloat(numWindows - 1) * delta)
            self.size = CGSize(width: min(size.width, maxSize.width), height: min(size.height, maxSize.height))
        }
    }

    static func cascadeActiveAppWindowsOnScreen(windowElement: AccessibilityElement? = nil) {
        guard let (screens, windows) = allWindowsOnScreen(windowElement: windowElement, sortByPID: true),
              let frontWindowElement = AccessibilityElement.getFrontWindowElement()
        else {
            return
        }

        let screenFrame = screens.currentScreen.adjustedVisibleFrame().screenFlipped

        let delta = CGFloat(Defaults.cascadeAllDeltaSize.value)

        // keep windows with a pid equal to the front window's pid
        var filtered = windows.filter(hasFrontWindowPid(_:))

        // parameters for cascading active app windows
        var cascadeParameters: CascadeActiveAppParameters?

        if let first = filtered.first {
            // move the first to become the last (top)
            filtered.append(filtered.removeFirst())
            // set up parameters
            cascadeParameters = CascadeActiveAppParameters(windowFrame: first.frame, screenFrame: screenFrame, numWindows: filtered.count, size: first.size!, delta: delta)
        }

        // cascade the filtered windows
        for (ind, w) in filtered.enumerated() {
            cascadeWindow(w, screenFrame: screenFrame, delta: delta, index: ind, cascadeParameters: cascadeParameters)
        }

        // return true for a w pid equal to the front window's pid
        func hasFrontWindowPid(_ w: AccessibilityElement) -> Bool {
            return w.pid == frontWindowElement.pid
        }
    }

    private static func cascadeWindow(_ w: AccessibilityElement, screenFrame: CGRect, delta: CGFloat, index: Int, cascadeParameters: CascadeActiveAppParameters? = nil) {
        var rect = w.frame

        // TODO: save previous position in history

        rect.origin.x = screenFrame.origin.x + delta * CGFloat(index)
        rect.origin.y = screenFrame.origin.y + delta * CGFloat(index)

        if let cascadeParameters {
            rect.size.width = cascadeParameters.size.width
            rect.size.height = cascadeParameters.size.height

            if cascadeParameters.right {
                rect.origin.x = screenFrame.origin.x + screenFrame.size.width - cascadeParameters.size.width - delta * CGFloat(index)
            }
            if cascadeParameters.bottom {
                rect.origin.y = screenFrame.origin.y + screenFrame.size.height - cascadeParameters.size.height - delta * CGFloat(cascadeParameters.numWindows - 1 - index)
            }
        }

        w.setFrame(rect)
        w.bringToFront()
    }

    static func tileActiveAppWindowsOnScreen(windowElement: AccessibilityElement? = nil) {
        guard let (screens, windows) = allWindowsOnScreen(windowElement: windowElement, sortByPID: true),
              let frontWindowElement = AccessibilityElement.getFrontWindowElement()
        else {
            return
        }

        let screenFrame = screens.currentScreen.adjustedVisibleFrame().screenFlipped

        // keep windows with a pid equal to the front window's pid
        let filtered = windows.filter { $0.pid == frontWindowElement.pid }

        let count = filtered.count

        let columns = Int(ceil(sqrt(CGFloat(count))))
        let rows = Int(ceil(CGFloat(count) / CGFloat(columns)))
        let size = CGSize(width: (screenFrame.maxX - screenFrame.minX) / CGFloat(columns), height: (screenFrame.maxY - screenFrame.minY) / CGFloat(rows))

        for (ind, w) in filtered.enumerated() {
            let column = ind % Int(columns)
            let row = ind / Int(columns)
            tileWindow(w, screenFrame: screenFrame, size: size, column: column, row: row)
        }
    }

    // MARK: Focus Layout

    private static var focusedPid: pid_t?

    private enum CycleDirection {
        case next, prev
    }

    private static func focusLayoutOnScreen(windowElement: AccessibilityElement? = nil, direction: CycleDirection) {
        guard let (screens, windows) = allWindowsOnScreen(windowElement: windowElement, sortByPID: true)
        else {
            return
        }

        let rawFrame = screens.currentScreen.adjustedVisibleFrame().screenFlipped
        let focusRatio: CGFloat = 0.7
        let gap: CGFloat = 15.0

        // Inset the screen frame by the gap on all sides
        let screenFrame = CGRect(
            x: rawFrame.origin.x + gap,
            y: rawFrame.origin.y + gap,
            width: rawFrame.width - gap * 2,
            height: rawFrame.height - gap * 2
        )

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

        // Split windows by focus
        let focusWindows = windows.filter { $0.pid == resolvedPid }
        let otherWindows = windows.filter { $0.pid != resolvedPid }

        // Left zone: 70% width, full height — tile focus app windows vertically
        let leftWidth = screenFrame.width * focusRatio - gap / 2
        let focusCount = max(focusWindows.count, 1)
        let focusHeight = screenFrame.height / CGFloat(focusCount)

        for (i, w) in focusWindows.enumerated() {
            let rect = CGRect(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y + focusHeight * CGFloat(i),
                width: leftWidth,
                height: focusHeight
            )
            w.setFrame(rect)
        }

        // Right zone: remaining width — all windows get full height
        guard !otherWindows.isEmpty else { return }
        let rightX = screenFrame.origin.x + leftWidth + gap
        let rightWidth = screenFrame.width - leftWidth - gap

        for w in otherWindows {
            let rect = CGRect(
                x: rightX,
                y: screenFrame.origin.y,
                width: rightWidth,
                height: screenFrame.height
            )
            w.setFrame(rect)
        }

        // Bring the focused app to front
        focusWindows.first?.bringToFront()
    }
}
