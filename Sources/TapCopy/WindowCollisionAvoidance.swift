import AppKit
import CoreGraphics

/// Prevents TapCopy from overlapping with other apps' floating selection bars
/// (PopClip, Raycast, DeepL, Grammarly, LookUp) as well as in-page web toolbars
/// (Notion, ChatGPT, Claude, Medium, Google Docs) without Screen Recording TCC.
enum WindowCollisionAvoidance {

    private static let safetyMargin: CGFloat = 10.0
    private static let screenEdgeMargin: CGFloat = 8.0

    /// Picks the cleanest non-overlapping origin around `anchor`:
    /// 1. Below-right (`y - height - 18`): leaves the entire upper band free for
    ///    web DOM popovers (Notion, ChatGPT, Medium) and PopClip's default top bar.
    /// 2. Below-left
    /// 3. Further below (`y - height - 58`): dodges popups placed right under text.
    /// 4. High above-right (`y + 52`): clears any standard 36pt top popover.
    /// 5. Standard above-right (`y + 16`)
    /// 6. Standard above-left
    static func bestOrigin(anchor: NSPoint, pillSize: NSSize, ownPanelNumber: Int?) -> NSPoint {
        let screen = screenContaining(point: anchor) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let obstacles = externalFloatingRects(ownPanelNumber: ownPanelNumber, screenFrame: screen?.frame)

        let rawCandidates: [NSPoint] = [
            NSPoint(x: anchor.x + 10, y: anchor.y - pillSize.height - 18),
            NSPoint(x: anchor.x - pillSize.width - 10, y: anchor.y - pillSize.height - 18),
            NSPoint(x: anchor.x + 10, y: anchor.y - pillSize.height - 58),
            NSPoint(x: anchor.x + 10, y: anchor.y + 52),
            NSPoint(x: anchor.x + 10, y: anchor.y + 16),
            NSPoint(x: anchor.x - pillSize.width - 10, y: anchor.y + 16)
        ]

        for raw in rawCandidates {
            let clamped = clamp(origin: raw, size: pillSize, within: visible)
            let testRect = NSRect(origin: clamped, size: pillSize).insetBy(dx: -safetyMargin, dy: -safetyMargin)
            let collides = obstacles.contains { $0.intersects(testRect) }
            if !collides {
                return clamped
            }
        }

        // Fallback if all 6 slots intersect something: use below-right clamped.
        return clamp(origin: rawCandidates[0], size: pillSize, within: visible)
    }

    static func collidesWithExternalPopup(frame: NSRect, ownPanelNumber: Int?) -> Bool {
        let screen = screenContaining(point: NSPoint(x: frame.midX, y: frame.midY)) ?? NSScreen.main
        let obstacles = externalFloatingRects(ownPanelNumber: ownPanelNumber, screenFrame: screen?.frame)
        let inflated = frame.insetBy(dx: -6, dy: -6)
        return obstacles.contains { $0.intersects(inflated) }
    }

    // MARK: - CGWindowList Discovery

    private static func externalFloatingRects(ownPanelNumber: Int?, screenFrame: NSRect?) -> [NSRect] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        guard primaryHeight > 0,
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

            // Floating selection menus/popovers are compact (<= 680 x 220 pt).
            guard cgRect.width >= 24, cgRect.width <= 680,
                  cgRect.height >= 16, cgRect.height <= 220 else {
                continue
            }

            let isFloatingLayer = (layer > 0 && layer < 1000)
            let isCompactOverlayWindow = (layer == 0 && cgRect.width <= 420 && cgRect.height <= 96)
            guard isFloatingLayer || isCompactOverlayWindow else { continue }

            let appKitY = primaryHeight - (cgRect.origin.y + cgRect.size.height)
            let appKitRect = NSRect(
                x: cgRect.origin.x,
                y: appKitY,
                width: cgRect.size.width,
                height: cgRect.size.height
            )

            // Ignore system menu bar items pinned right along the top edge of the screen.
            if let screenFrame, cgRect.height <= 40, abs(appKitRect.maxY - screenFrame.maxY) <= 4 {
                continue
            }

            rects.append(appKitRect)
        }
        return rects
    }

    // MARK: - Screen Helpers

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

    private static func screenContaining(point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }
}
