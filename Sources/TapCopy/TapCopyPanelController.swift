import AppKit

// MARK: - Palette

private enum PillPalette {
    static let carbon = NSColor(srgbRed: 0x1E / 255.0, green: 0x1F / 255.0, blue: 0x22 / 255.0, alpha: 0.96)
    static let hover = NSColor(srgbRed: 0x2B / 255.0, green: 0x2D / 255.0, blue: 0x31 / 255.0, alpha: 0.98)
    static let border = NSColor.white.withAlphaComponent(0.14)
    static let icon = NSColor(srgbRed: 0xE4 / 255.0, green: 0xE4 / 255.0, blue: 0xE7 / 255.0, alpha: 1.0)
    static let label = NSColor(srgbRed: 0xF4 / 255.0, green: 0xF4 / 255.0, blue: 0xF5 / 255.0, alpha: 1.0)
    static let success = NSColor(srgbRed: 0x10 / 255.0, green: 0xB9 / 255.0, blue: 0x81 / 255.0, alpha: 1.0)
}

// MARK: - Panel subclass

final class TapCopyPanel: NSPanel {
    // Never steal focus: the source app keeps its blue selection.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Interactive capsule

final class PillView: NSView {

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "Copiar")
    private var trackingAreaRef: NSTrackingArea?

    var onClick: (() -> Void)?

    private(set) var isCopiedState = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16.0
        layer?.masksToBounds = true
        layer?.backgroundColor = PillPalette.carbon.cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = PillPalette.border.cgColor

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = PillPalette.icon
        iconView.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: "Copiar"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
        )
        addSubview(iconView)

        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = PillPalette.label
        label.alignment = .left
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Interaction

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isCopiedState else { return }
        NSCursor.pointingHand.push()
        applyBackground(PillPalette.hover)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
        guard !isCopiedState else { return }
        applyBackground(PillPalette.carbon)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    private func applyBackground(_ color: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = color.cgColor
        CATransaction.commit()
    }

    // MARK: States

    func setCopied(_ copied: Bool) {
        isCopiedState = copied
        if copied {
            iconView.isHidden = true
            label.stringValue = "✓ Copiado"
            label.textColor = PillPalette.success
            applyBackground(PillPalette.hover)
        } else {
            iconView.isHidden = false
            label.stringValue = "Copiar"
            label.textColor = PillPalette.label
            applyBackground(PillPalette.carbon)
        }
        needsLayout = true
    }

    // MARK: Layout

    static let horizontalPadding: CGFloat = 14.0
    static let iconSpacing: CGFloat = 6.0
    static let iconWidth: CGFloat = 13.0
    static let height: CGFloat = 32.0

    static func size(for text: String, showsIcon: Bool) -> NSSize {
        let font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let iconPart = showsIcon ? (iconWidth + iconSpacing) : 0
        let width = max(96.0, horizontalPadding * 2 + iconPart + textWidth)
        return NSSize(width: ceil(width), height: height)
    }

    override func layout() {
        super.layout()
        let labelSize = label.intrinsicContentSize
        let iconPart = iconView.isHidden ? 0 : (Self.iconWidth + Self.iconSpacing)
        let totalWidth = iconPart + labelSize.width
        var x = (bounds.width - totalWidth) / 2.0

        if !iconView.isHidden {
            iconView.frame = NSRect(x: x, y: (bounds.height - 13.0) / 2.0, width: Self.iconWidth, height: 13.0)
            x += Self.iconWidth + Self.iconSpacing
        } else {
            iconView.frame = .zero
        }

        label.frame = NSRect(
            x: x,
            y: (bounds.height - labelSize.height) / 2.0,
            width: labelSize.width,
            height: labelSize.height
        )
    }
}

// MARK: - Panel controller

final class TapCopyPanelController {

    static let shared = TapCopyPanelController()

    private var panel: TapCopyPanel?
    private var pillView: PillView?
    private var fallbackText: String = ""
    private var autoHideWorkItem: DispatchWorkItem?

    private init() {}

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    var frame: NSRect {
        panel?.frame ?? .zero
    }

    func contains(screenPoint: NSPoint, toleratedInset: CGFloat) -> Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.insetBy(dx: -toleratedInset, dy: -toleratedInset).contains(screenPoint)
    }

    // MARK: Show / hide

    func show(near point: NSPoint, fallbackText: String) {
        guard SelectionMonitor.shared.isEnabled else { return }
        self.fallbackText = fallbackText

        autoHideWorkItem?.cancel()
        let controller = self
        let work = DispatchWorkItem { [weak controller] in
            controller?.fadeOut()
        }
        autoHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)

        let size = PillView.size(for: "Copiar", showsIcon: true)
        let origin = clampedOrigin(anchor: point, size: size)

        let targetPanel = ensurePanel()
        guard let pill = pillView else { return }
        pill.setCopied(false)
        pill.frame = NSRect(origin: .zero, size: size)
        targetPanel.setFrame(NSRect(origin: origin, size: size), display: true)
        pill.needsLayout = true
        pill.layoutSubtreeIfNeeded()

        targetPanel.alphaValue = 0.0
        targetPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            targetPanel.animator().alphaValue = 1.0
        }
    }

    func hideImmediately() {
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
        panel?.orderOut(nil)
        panel?.alphaValue = 1.0
        pillView?.setCopied(false)
    }

    private func fadeOut() {
        autoHideWorkItem = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.alphaValue = 1.0
            self?.pillView?.setCopied(false)
        }
    }

    // MARK: Copy action

    private func performCopy() {
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil

        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount
        sendCommandC()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self else { return }
            if pasteboard.changeCount <= initialChangeCount {
                pasteboard.clearContents()
                pasteboard.setString(self.fallbackText, forType: .string)
            }
            self.showCopiedFeedback()
        }
    }

    private func showCopiedFeedback() {
        guard let panel, let pill = pillView else { return }
        pill.setCopied(true)

        let size = PillView.size(for: "✓ Copiado", showsIcon: false)
        let origin = clampedOrigin(anchor: panel.frame.origin, size: size, isOrigin: true)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        pill.frame = NSRect(origin: .zero, size: size)
        pill.needsLayout = true
        pill.layoutSubtreeIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in
            self?.fadeOut()
        }
    }

    private func sendCommandC() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyCode: CGKeyCode = 0x08 // "c"
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: Geometry

    private func ensurePanel() -> TapCopyPanel {
        if let panel { return panel }
        let rect = NSRect(x: 0, y: 0, width: 96, height: PillView.height)
        let newPanel = TapCopyPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = .popUpMenu
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.hidesOnDeactivate = false
        newPanel.isMovable = false
        newPanel.isMovableByWindowBackground = false
        newPanel.isReleasedWhenClosed = false
        newPanel.animationBehavior = .none
        newPanel.ignoresMouseEvents = false

        let view = PillView(frame: rect)
        view.autoresizingMask = [.width, .height]
        view.onClick = { [weak self] in
            self?.performCopy()
        }
        newPanel.contentView = view

        panel = newPanel
        pillView = view
        return newPanel
    }

    /// Places the pill at (mouse + 12, mouse + 14) and clamps it inside the
    /// visible frame of the screen under the cursor, 8 pt margin on all sides.
    private func clampedOrigin(anchor: NSPoint, size: NSSize, isOrigin: Bool = false) -> NSPoint {
        let primary = NSPoint(x: anchor.x + (isOrigin ? 0 : 12), y: anchor.y + (isOrigin ? 0 : 14))
        let margin: CGFloat = 8.0
        let screen = screenContaining(point: isOrigin ? anchor : NSEvent.mouseLocation) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return primary }

        let lowerX = visible.minX + margin
        let lowerY = visible.minY + margin
        let upperX = Swift.max(lowerX, visible.maxX - size.width - margin)
        let upperY = Swift.max(lowerY, visible.maxY - size.height - margin)
        return NSPoint(
            x: min(Swift.max(primary.x, lowerX), upperX),
            y: min(Swift.max(primary.y, lowerY), upperY)
        )
    }

    private func screenContaining(point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }
}
