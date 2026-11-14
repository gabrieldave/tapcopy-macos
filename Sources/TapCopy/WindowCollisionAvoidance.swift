import AppKit
import ApplicationServices
import CoreGraphics

/// Prevents TapCopy from overlapping both native macOS floating popups
/// (`CGWindowListCopyWindowInfo`: PopClip, Raycast, DeepL, Grammarly) AND
/// in-page DOM floating buttons/toolbars (`AXUIElementCopyElementAtPosition`
/// directly on the target app: Gemini's "Pregúntale a Gemini", Notion, ChatGPT,
/// Medium, Google Docs) without requiring Screen Recording permission.
enum WindowCollisionAvoidance {

    struct ScreenMetrics {
        let primaryHeight: CGFloat
        let visibleFrame: NSRect
        let fullFrame: NSRect
    }

    private static let safetyMargin: CGFloat = 10.0
    private static let screenEdgeMargin: CGFloat = 8.0

    private static let popupControlRoles: Set<String> = [
        "AXButton", "AXPopUpButton", "AXMenuButton", "AXToolbar",
        "AXMenu", "AXMenuBar", "AXPopover", "AXDialog", "AXSheet"
    ]

    /// Must be called on the main thread to snapshot NSScreen geometry safely.
    static func captureScreenMetrics(near point: NSPoint) -> ScreenMetrics {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let full = screen?.frame ?? visible
        return ScreenMetrics(primaryHeight: primaryHeight, visibleFrame: visible, fullFrame: full)
    }

    /// Evaluates candidate slots around `selectionRect` (or `anchor`) on any queue:
    /// 1. Above-right (`maxY + 12`): stays clear of Gemini's bottom "Pregúntale a Gemini" chip.
    /// 2. Below-right (`minY - height - 12`): stays clear of Notion/Medium/ChatGPT top bars.
    /// 3. Further below (`minY - height - 62`): clears any 44pt chip right below the selection.
    /// 4. Higher above (`maxY + 58`): clears any 44pt toolbar right above the selection.
    /// 5. Above-left
    /// 6. Below-left
    static func bestOrigin(
        anchor: NSPoint,
        selectionRect: NSRect?,
        pillSize: NSSize,
        targetPID: pid_t?,
        ownPanelNumber: Int?,
        metrics: ScreenMetrics
    ) -> NSPoint {
        let selBox: NSRect
        if let selectionRect, selectionRect.width > 0, selectionRect.height > 0, selectionRect.height < 500 {
            selBox = selectionRect
        } else {
            selBox = NSRect(x: anchor.x - 12, y: anchor.y - 11, width: 24, height: 22)
        }

        let cgObstacles = externalFloatingWindowRects(ownPanelNumber: ownPanelNumber, metrics: metrics)
        let baseX = selBox.minX
        let altX = anchor.x - (pillSize.width * 0.35)

        let rawCandidates: [NSPoint] = [
            NSPoint(x: altX, y: selBox.maxY + 12),
            NSPoint(x: altX, y: selBox.minY - pillSize.height - 12),
            NSPoint(x: baseX, y: selBox.minY - pillSize.height - 62),
            NSPoint(x: baseX, y: selBox.maxY + 58),
            NSPoint(x: anchor.x - pillSize.width - 10, y: selBox.maxY + 12),
            NSPoint(x: anchor.x - pillSize.width - 10, y: selBox.minY - pillSize.height - 12)
        ]

        var domObstacleCache: [NSRect] = []

        for raw in rawCandidates {
            let clamped = clamp(origin: raw, size: pillSize, within: metrics.visibleFrame)
            let pillRect = NSRect(origin: clamped, size: pillSize)
            let paddedRect = pillRect.insetBy(dx: -safetyMargin, dy: -safetyMargin)

            // Never cover the selected text itself when single/few lines.
            if selBox.height <= 90 && pillRect.intersects(selBox.insetBy(dx: -2, dy: -4)) {
                continue
            }

            if cgObstacles.contains(where: { $0.intersects(paddedRect) }) {
                continue
            }

            if domObstacleCache.contains(where: { $0.intersects(paddedRect) }) {
                continue
            }

            if let targetPID, targetPID > 0,
               let hitObstacle = firstDOMFloatingObstacle(in: pillRect, targetPID: targetPID, primaryHeight: metrics.primaryHeight) {
                domObstacleCache.append(hitObstacle)
                continue
            }

            return clamped
        }

        return clamp(origin: rawCandidates[0], size: pillSize, within: metrics.visibleFrame)
    }

    static func collidesWithAnyObstacle(
        frame: NSRect,
        targetPID: pid_t?,
        ownPanelNumber: Int?,
        metrics: ScreenMetrics
    ) -> Bool {
        let padded = frame.insetBy(dx: -6, dy: -6)
        let cgObstacles = externalFloatingWindowRects(ownPanelNumber: ownPanelNumber, metrics: metrics)
        if cgObstacles.contains(where: { $0.intersects(padded) }) {
            return true
        }
        if let targetPID, targetPID > 0,
           firstDOMFloatingObstacle(in: frame, targetPID: targetPID, primaryHeight: metrics.primaryHeight) != nil {
            return true
        }
        return false
    }

    // MARK: - In-App / Web DOM Accessibility Obstacle Probe

    /// Queries the target app's AX tree directly (ignoring TapCopy's own panel above it)
    /// to detect floating DOM chips/buttons such as Gemini's "Pregúntale a Gemini",
    /// Notion's toolbar, ChatGPT's quote chip, or browser chrome toolbars.
    private static func firstDOMFloatingObstacle(
        in rect: NSRect,
        targetPID: pid_t,
        primaryHeight: CGFloat
    ) -> NSRect? {
        guard primaryHeight > 0 else { return nil }
        let appRef = AXUIElementCreateApplication(targetPID)

        let midY = rect.midY
        let samplePoints: [NSPoint] = [
            NSPoint(x: rect.minX + 18, y: midY),
            NSPoint(x: rect.minX + rect.width * 0.35, y: midY),
            NSPoint(x: rect.midX, y: midY),
            NSPoint(x: rect.minX + rect.width * 0.68, y: midY),
            NSPoint(x: rect.maxX - 18, y: midY)
        ]

        for pt in samplePoints {
            let axX = Float(pt.x)
            let axY = Float(primaryHeight - pt.y)
            var hitElement: AXUIElement?
            guard AXUIElementCopyElementAtPosition(appRef, axX, axY, &hitElement) == .success,
                  let startNode = hitElement else {
                continue
            }

            if let obstacleRect = inspectAncestorChainForFloatingUI(startNode: startNode, primaryHeight: primaryHeight) {
                return obstacleRect
            }
        }
        return nil
    }

    private static func inspectAncestorChainForFloatingUI(
        startNode: AXUIElement,
        primaryHeight: CGFloat
    ) -> NSRect? {
        var current: AXUIElement? = startNode
        var depth = 0

        while let node = current, depth <= 6 {
            if let nodeRole = axRole(of: node) {
                // Stop once we hit the root document or window.
                if nodeRole == "AXWebArea" || nodeRole == "AXWindow" || nodeRole == "AXApplication" {
                    break
                }

                if popupControlRoles.contains(nodeRole),
                   let frame = axFrame(of: node, primaryHeight: primaryHeight),
                   frame.height >= 18, frame.height <= 100,
                   frame.width >= 24, frame.width <= 900 {
                    return frame
                }

                // Catch custom floating chips rendered as compact AXGroup pills with an icon/button inside.
                if nodeRole == "AXGroup",
                   let frame = axFrame(of: node, primaryHeight: primaryHeight),
                   frame.width >= 64, frame.width <= 460,
                   frame.height >= 26, frame.height <= 58,
                   groupContainsInteractiveChild(node) {
                    return frame
                }
            }

            current = axParent(of: node)
            depth += 1
        }
        return nil
    }

    private static func groupContainsInteractiveChild(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? NSArray,
              array.count > 0, array.count <= 12 else {
            return false
        }
        for item in array {
            let ref = item as CFTypeRef
            guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { continue }
            if let childRole = axRole(of: ref as! AXUIElement),
               popupControlRoles.contains(childRole) {
                return true
            }
        }
        return false
    }

    private static func axRole(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func axParent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func axFrame(of element: AXUIElement, primaryHeight: CGFloat) -> NSRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let rawPos = posRef, CFGetTypeID(rawPos) == AXValueGetTypeID(),
              let rawSize = sizeRef, CFGetTypeID(rawSize) == AXValueGetTypeID() else {
            return nil
        }
        var pt = CGPoint.zero
        var sz = CGSize.zero
        guard AXValueGetValue(rawPos as! AXValue, .cgPoint, &pt),
              AXValueGetValue(rawSize as! AXValue, .cgSize, &sz),
              sz.width > 0, sz.height > 0 else {
            return nil
        }
        let appKitY = primaryHeight - (pt.y + sz.height)
        return NSRect(x: pt.x, y: appKitY, width: sz.width, height: sz.height)
    }

    // MARK: - CGWindowList Native Popup Discovery

    private static func externalFloatingWindowRects(
        ownPanelNumber: Int?,
        metrics: ScreenMetrics
    ) -> [NSRect] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard metrics.primaryHeight > 0,
              let infoList = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]] else {
            return []
        }

        var rects: [NSRect] = []
        for entry in infoList {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID != ownPID else {
                continue
            }
            if let ownPanelNumber,
               let winNum = entry[kCGWindowNumber as String] as? Int,
               winNum == ownPanelNumber {
                continue
            }

            let alpha = (entry[kCGWindowAlpha as String] as? Double) ?? 1.0
            guard alpha > 0.05 else { continue }

            let layer = (entry[kCGWindowLayer as String] as? Int) ?? 0
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary else { continue }
            var cgRect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &cgRect) else { continue }

            guard cgRect.width >= 24, cgRect.width <= 680,
                  cgRect.height >= 16, cgRect.height <= 220 else {
                continue
            }

            let isFloatingLayer = (layer > 0 && layer < 1000)
            let isCompactOverlayWindow = (layer == 0 && cgRect.width <= 420 && cgRect.height <= 96)
            guard isFloatingLayer || isCompactOverlayWindow else { continue }

            let appKitY = metrics.primaryHeight - (cgRect.origin.y + cgRect.size.height)
            let appKitRect = NSRect(
                x: cgRect.origin.x,
                y: appKitY,
                width: cgRect.size.width,
                height: cgRect.size.height
            )

            if cgRect.height <= 40, abs(appKitRect.maxY - metrics.fullFrame.maxY) <= 4 {
                continue
            }

            rects.append(appKitRect)
        }
        return rects
    }

    // MARK: - Clamping

    private static func clamp(origin: NSPoint, size: NSSize, within visible: NSRect) -> NSPoint {
        let lowerX = visible.minX + screenEdgeMargin
        let lowerY = visible.minY + screenEdgeMargin
        let upperX = Swift.max(lowerX, visible.maxX - size.width - screenEdgeMargin)
        let upperY = Swift.max(lowerY, visible.maxY - size.height - screenEdgeMargin)
        return NSPoint(
            x: min(Swift.max(origin.x, lowerX), upperX),
            y: min(Swift.max(origin.y, lowerY), upperY)
        )
    }
}
