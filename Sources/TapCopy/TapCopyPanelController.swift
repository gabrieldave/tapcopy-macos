import AppKit

// MARK: - Palette

private enum PillPalette {
    static let carbon = NSColor(srgbRed: 0x1E / 255.0, green: 0x1F / 255.0, blue: 0x22 / 255.0, alpha: 0.96)
    static let hover = NSColor(srgbRed: 0x2E / 255.0, green: 0x30 / 255.0, blue: 0x36 / 255.0, alpha: 0.98)
    static let border = NSColor.white.withAlphaComponent(0.15)
    static let divider = NSColor.white.withAlphaComponent(0.10)
    static let icon = NSColor(srgbRed: 0xE4 / 255.0, green: 0xE4 / 255.0, blue: 0xE7 / 255.0, alpha: 1.0)
    static let label = NSColor(srgbRed: 0xF4 / 255.0, green: 0xF4 / 255.0, blue: 0xF5 / 255.0, alpha: 1.0)
    static let accent = NSColor(srgbRed: 0x38 / 255.0, green: 0xBD / 255.0, blue: 0xF8 / 255.0, alpha: 1.0)
    static let success = NSColor(srgbRed: 0x10 / 255.0, green: 0xB9 / 255.0, blue: 0x81 / 255.0, alpha: 1.0)
}

// MARK: - Panel subclass

final class TapCopyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Segment button

private final class PillSegmentView: NSView {

    private let swatchView = NSView()
    private let iconView = NSImageView()
    private let labelField = NSTextField(labelWithString: "")
    private var trackingRef: NSTrackingArea?
    private var didPushCursor = false

    let actionHandler: () -> Void
    let computedWidth: CGFloat

    init(
        title: String?,
        symbolName: String?,
        swatchColor: NSColor? = nil,
        tintColor: NSColor = PillPalette.label,
        toolTipText: String? = nil,
        actionHandler: @escaping () -> Void
    ) {
        self.actionHandler = actionHandler

        let font = NSFont.systemFont(ofSize: 12.0, weight: .medium)
        let textWidth: CGFloat
        if let title, !title.isEmpty {
            textWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        } else {
            textWidth = 0
        }

        let hasSwatch = (swatchColor != nil)
        let hasIcon = (symbolName != nil)
        let hasText = (textWidth > 0)

        var contentW: CGFloat = 0
        if hasSwatch { contentW += 11 }
        if hasSwatch && (hasIcon || hasText) { contentW += 5 }
        if hasIcon { contentW += 13 }
        if hasIcon && hasText { contentW += 5 }
        contentW += textWidth

        let horizontalPad: CGFloat = hasText ? 11.0 : 9.0
        self.computedWidth = max(30.0, ceil(contentW + horizontalPad * 2))

        super.init(frame: NSRect(x: 0, y: 0, width: computedWidth, height: 28.0))

        wantsLayer = true
        layer?.cornerRadius = 13.0
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor
        self.toolTip = toolTipText

        var cursorX = (computedWidth - contentW) / 2.0

        if let swatchColor {
            swatchView.wantsLayer = true
            swatchView.layer?.cornerRadius = 5.5
            swatchView.layer?.backgroundColor = swatchColor.cgColor
            swatchView.layer?.borderWidth = 1.0
            swatchView.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
            swatchView.frame = NSRect(x: cursorX, y: (28.0 - 11.0) / 2.0, width: 11.0, height: 11.0)
            addSubview(swatchView)
            cursorX += 11.0 + ((hasIcon || hasText) ? 5.0 : 0)
        }

        if let symbolName {
            iconView.imageScaling = .scaleProportionallyDown
            iconView.contentTintColor = (tintColor == PillPalette.label) ? PillPalette.icon : tintColor
            iconView.image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: title ?? toolTipText
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
            )
            iconView.frame = NSRect(x: cursorX, y: (28.0 - 13.0) / 2.0, width: 13.0, height: 13.0)
            addSubview(iconView)
            cursorX += 13.0 + (hasText ? 5.0 : 0)
        }

        if let title, !title.isEmpty {
            labelField.stringValue = title
            labelField.font = font
            labelField.textColor = tintColor
            labelField.alignment = .left
            let intrinsic = labelField.intrinsicContentSize
            labelField.frame = NSRect(
                x: cursorX,
                y: (28.0 - intrinsic.height) / 2.0,
                width: textWidth + 4.0,
                height: intrinsic.height
            )
            addSubview(labelField)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingRef = area
    }

    func popCursorIfNeeded() {
        if didPushCursor {
            NSCursor.pop()
            didPushCursor = false
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if !didPushCursor {
            NSCursor.pointingHand.push()
            didPushCursor = true
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = PillPalette.hover.cgColor
        CATransaction.commit()
    }

    override func mouseExited(with event: NSEvent) {
        popCursorIfNeeded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = NSColor.clear.cgColor
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        popCursorIfNeeded()
        actionHandler()
    }
}

// MARK: - Capsule bar container

private final class ChameleonPillView: NSView {

    static let barHeight: CGFloat = 34.0
    private var segments: [PillSegmentView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.barHeight / 2.0
        layer?.masksToBounds = true
        layer?.backgroundColor = PillPalette.carbon.cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = PillPalette.border.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func popAllCursors() {
        for seg in segments {
            seg.popCursorIfNeeded()
        }
    }

    func configure(with items: [PillSegmentView]) -> NSSize {
        popAllCursors()
        subviews.forEach { $0.removeFromSuperview() }
        segments = items

        let outerPad: CGFloat = 4.0
        var cursorX: CGFloat = outerPad

        for (idx, seg) in items.enumerated() {
            if idx > 0 {
                let divider = NSView(frame: NSRect(x: cursorX + 1.0, y: (Self.barHeight - 15.0) / 2.0, width: 1.0, height: 15.0))
                divider.wantsLayer = true
                divider.layer?.backgroundColor = PillPalette.divider.cgColor
                addSubview(divider)
                cursorX += 3.0
            }
            seg.frame = NSRect(x: cursorX, y: (Self.barHeight - 28.0) / 2.0, width: seg.computedWidth, height: 28.0)
            addSubview(seg)
            cursorX += seg.computedWidth
        }

        let totalWidth = max(92.0, ceil(cursorX + outerPad))
        return NSSize(width: totalWidth, height: Self.barHeight)
    }

    func configureSuccessMessage(_ text: String) -> NSSize {
        let badge = PillSegmentView(
            title: "✓ \(text)",
            symbolName: nil,
            tintColor: PillPalette.success,
            actionHandler: {}
        )
        return configure(with: [badge])
    }
}

// MARK: - Panel controller

final class TapCopyPanelController: NSObject {

    static let shared = TapCopyPanelController()

    private var panel: TapCopyPanel?
    private var pillView: ChameleonPillView?
    private var fallbackText: String = ""
    private var lastAnchor: NSPoint = .zero
    private var lastSelectionBounds: NSRect?
    private var lastSourcePID: pid_t?
    private var autoHideWorkItem: DispatchWorkItem?
    private var presentationID: UInt64 = 0
    private var isMenuOpen = false

    private override init() {
        super.init()
    }

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

    // MARK: - Show / Hide

    func show(
        near point: NSPoint,
        fallbackText: String,
        selectionBounds: NSRect? = nil,
        sourcePID: pid_t? = nil,
        force: Bool = false
    ) {
        guard force || SelectionMonitor.shared.isEnabled else { return }
        self.fallbackText = fallbackText
        self.lastAnchor = point
        self.lastSelectionBounds = selectionBounds
        self.lastSourcePID = sourcePID

        presentationID &+= 1
        let currentID = presentationID

        let targetPanel = ensurePanel()
        guard let pill = pillView else { return }

        let segments = buildSegments(for: fallbackText, expectedID: currentID)
        let size = pill.configure(with: segments)
        let metrics = WindowCollisionAvoidance.captureScreenMetrics(near: point)
        let winNum = targetPanel.windowNumber

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let resolvedOrigin = WindowCollisionAvoidance.bestOrigin(
                anchor: point,
                selectionRect: selectionBounds,
                pillSize: size,
                targetPID: sourcePID,
                ownPanelNumber: winNum,
                metrics: metrics
            )

            DispatchQueue.main.async { [weak self] in
                guard let self, self.presentationID == currentID else { return }
                pill.frame = NSRect(origin: .zero, size: size)
                targetPanel.setFrame(NSRect(origin: resolvedOrigin, size: size), display: true)

                self.scheduleAutoHide(after: 5.0, expectedID: currentID)

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.0
                    targetPanel.animator().alphaValue = 0.0
                }
                targetPanel.orderFrontRegardless()

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.08
                    targetPanel.animator().alphaValue = 1.0
                }

                // Re-check at 180ms and 380ms in case Gemini/Notion/PopClip rendered its popup asynchronously.
                for delay in [0.18, 0.38] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.repositionIfOverlapping(expectedID: currentID)
                    }
                }
            }
        }
    }

    func hideImmediately() {
        guard !isMenuOpen else { return }
        presentationID &+= 1
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
        pillView?.popAllCursors()
        panel?.orderOut(nil)
        panel?.alphaValue = 1.0
    }

    private func scheduleAutoHide(after seconds: TimeInterval, expectedID: UInt64) {
        autoHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isMenuOpen else { return }
            self.fadeOut(expectedID: expectedID)
        }
        autoHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func repositionIfOverlapping(expectedID: UInt64) {
        guard presentationID == expectedID, let panel, panel.isVisible else { return }
        let currentFrame = panel.frame
        let anchor = lastAnchor
        let selBounds = lastSelectionBounds
        let pid = lastSourcePID
        let winNum = panel.windowNumber
        let metrics = WindowCollisionAvoidance.captureScreenMetrics(near: anchor)

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard WindowCollisionAvoidance.collidesWithAnyObstacle(
                frame: currentFrame,
                targetPID: pid,
                ownPanelNumber: winNum,
                metrics: metrics
            ) else {
                return
            }

            let newOrigin = WindowCollisionAvoidance.bestOrigin(
                anchor: anchor,
                selectionRect: selBounds,
                pillSize: currentFrame.size,
                targetPID: pid,
                ownPanelNumber: winNum,
                metrics: metrics
            )

            guard hypot(newOrigin.x - currentFrame.origin.x, newOrigin.y - currentFrame.origin.y) >= 4.0 else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.presentationID == expectedID, let panel = self.panel, panel.isVisible else { return }
                TapLog.log("Dodged async UI/DOM popup -> moved pill to (\(Int(newOrigin.x)), \(Int(newOrigin.y)))")
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.10
                    panel.animator().setFrameOrigin(newOrigin)
                }
            }
        }
    }

    private func fadeOut(expectedID: UInt64) {
        guard presentationID == expectedID, let panel, panel.isVisible else { return }
        autoHideWorkItem = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            guard let self, self.presentationID == expectedID else { return }
            self.pillView?.popAllCursors()
            self.panel?.orderOut(nil)
            self.panel?.alphaValue = 1.0
        }
    }

    // MARK: - Chameleon Segments Builder

    private func buildSegments(for text: String, expectedID: UInt64) -> [PillSegmentView] {
        var items: [PillSegmentView] = []

        items.append(
            PillSegmentView(
                title: "Copiar",
                symbolName: "doc.on.doc",
                toolTipText: "Copiar selección",
                actionHandler: { [weak self] in
                    self?.performStandardCopy(expectedID: expectedID)
                }
            )
        )

        guard SelectionMonitor.shared.isChameleonModeEnabled else {
            return items
        }

        let contextual = ChameleonAnalyzer.detectContextualMatch(in: text)
        var hidesWebSearch = false

        if let contextual {
            switch contextual {
            case let .url(url, label):
                hidesWebSearch = true
                items.append(
                    PillSegmentView(
                        title: label,
                        symbolName: "arrow.up.right.square",
                        tintColor: PillPalette.accent,
                        toolTipText: url.absoluteString,
                        actionHandler: { [weak self] in
                            NSWorkspace.shared.open(url)
                            self?.hideImmediately()
                        }
                    )
                )

            case let .filePath(fileURL, label):
                hidesWebSearch = true
                items.append(
                    PillSegmentView(
                        title: label,
                        symbolName: "folder",
                        tintColor: PillPalette.accent,
                        toolTipText: fileURL.path,
                        actionHandler: { [weak self] in
                            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                            self?.hideImmediately()
                        }
                    )
                )

            case let .color(swatch, convertedValue, badgeTitle):
                hidesWebSearch = true
                items.append(
                    PillSegmentView(
                        title: badgeTitle,
                        symbolName: nil,
                        swatchColor: swatch,
                        toolTipText: "Copiar \(convertedValue)",
                        actionHandler: { [weak self] in
                            self?.writeToPasteboard(convertedValue, feedback: convertedValue, expectedID: expectedID)
                        }
                    )
                )

            case let .math(formattedResult):
                items.append(
                    PillSegmentView(
                        title: "= \(formattedResult)",
                        symbolName: nil,
                        tintColor: PillPalette.accent,
                        toolTipText: "Copiar resultado \(formattedResult)",
                        actionHandler: { [weak self] in
                            self?.writeToPasteboard(formattedResult, feedback: formattedResult, expectedID: expectedID)
                        }
                    )
                )
            }
        }

        items.append(
            PillSegmentView(
                title: "Plano",
                symbolName: nil,
                toolTipText: "Copiar como texto plano limpio",
                actionHandler: { [weak self] in
                    guard let self else { return }
                    let clean = ChameleonAnalyzer.sanitizedPlainText(self.fallbackText)
                    self.writeToPasteboard(clean, feedback: "Texto plano", expectedID: expectedID)
                }
            )
        )

        var aaSegmentRef: PillSegmentView?
        let aaSegment = PillSegmentView(
            title: "Aa",
            symbolName: nil,
            toolTipText: "Transformar formato, código y conteo de palabras",
            actionHandler: { [weak self] in
                guard let self, let anchorSeg = aaSegmentRef else { return }
                self.presentTransformMenu(from: anchorSeg, expectedID: expectedID)
            }
        )
        aaSegmentRef = aaSegment
        items.append(aaSegment)

        if !hidesWebSearch {
            items.append(
                PillSegmentView(
                    title: nil,
                    symbolName: "magnifyingglass",
                    toolTipText: "Buscar selección en Google",
                    actionHandler: { [weak self] in
                        guard let self else { return }
                        if let url = ChameleonAnalyzer.searchURL(for: self.fallbackText, engine: .google) {
                            NSWorkspace.shared.open(url)
                        }
                        self.hideImmediately()
                    }
                )
            )
        }

        items.append(
            PillSegmentView(
                title: nil,
                symbolName: "pin",
                toolTipText: "Fijar fragmento en estante flotante",
                actionHandler: { [weak self] in
                    guard let self else { return }
                    let pos = self.panel?.frame.origin ?? NSEvent.mouseLocation
                    self.hideImmediately()
                    PinShelfController.shared.pin(text: self.fallbackText, near: pos)
                }
            )
        )

        return items
    }

    // MARK: - Actions & Transform Menu

    private func presentTransformMenu(from segment: PillSegmentView, expectedID: UInt64) {
        autoHideWorkItem?.cancel()
        isMenuOpen = true

        let menu = NSMenu(title: "Transformar")
        menu.appearance = NSAppearance(named: .darkAqua)

        let statsItem = NSMenuItem(
            title: ChameleonAnalyzer.statsLine(for: fallbackText),
            action: nil,
            keyEquivalent: ""
        )
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        menu.addItem(.separator())

        let transforms: [(String, ChameleonAnalyzer.TextTransformCase)] = [
            ("MAYÚSCULAS", .upper),
            ("minúsculas", .lower),
            ("Tipo Título", .title),
            ("snake_case", .snake),
            ("camelCase", .camel),
            ("Copiar como código Markdown (```)", .markdownBlock)
        ]

        for (index, entry) in transforms.enumerated() {
            let item = NSMenuItem(title: entry.0, action: #selector(applyTransformMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }

        if ChameleonAnalyzer.looksLikeCode(fallbackText) {
            menu.addItem(.separator())
            let ghItem = NSMenuItem(title: "Buscar código en GitHub", action: #selector(searchGitHubMenuItem(_:)), keyEquivalent: "")
            ghItem.target = self
            menu.addItem(ghItem)

            let soItem = NSMenuItem(title: "Buscar en StackOverflow", action: #selector(searchStackOverflowMenuItem(_:)), keyEquivalent: "")
            soItem.target = self
            menu.addItem(soItem)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: segment)
        isMenuOpen = false

        if presentationID == expectedID, panel?.isVisible == true {
            scheduleAutoHide(after: 2.5, expectedID: expectedID)
        }
    }

    @objc private func applyTransformMenuItem(_ sender: NSMenuItem) {
        let modes: [ChameleonAnalyzer.TextTransformCase] = [.upper, .lower, .title, .snake, .camel, .markdownBlock]
        guard sender.tag >= 0, sender.tag < modes.count else { return }
        let transformed = ChameleonAnalyzer.transform(fallbackText, mode: modes[sender.tag])
        isMenuOpen = false
        writeToPasteboard(transformed, feedback: "Copiado", expectedID: presentationID)
    }

    @objc private func searchGitHubMenuItem(_ sender: NSMenuItem) {
        isMenuOpen = false
        if let url = ChameleonAnalyzer.searchURL(for: fallbackText, engine: .github) {
            NSWorkspace.shared.open(url)
        }
        hideImmediately()
    }

    @objc private func searchStackOverflowMenuItem(_ sender: NSMenuItem) {
        isMenuOpen = false
        if let url = ChameleonAnalyzer.searchURL(for: fallbackText, engine: .stackOverflow) {
            NSWorkspace.shared.open(url)
        }
        hideImmediately()
    }

    private func performStandardCopy(expectedID: UInt64) {
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil

        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount
        let source = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        sendCommandC()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.085) { [weak self] in
            guard let self else { return }
            let changed = pasteboard.changeCount > initialChangeCount
            if !changed {
                pasteboard.clearContents()
                pasteboard.setString(self.fallbackText, forType: .string)
            }
            TapLog.log("Copy requested for \(source) — cmdC=\(changed) fallback=\(!changed) chars=\(self.fallbackText.count)")
            self.showSuccessFeedback("Copiado", expectedID: expectedID)
        }
    }

    private func writeToPasteboard(_ string: String, feedback: String, expectedID: UInt64) {
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        showSuccessFeedback(feedback, expectedID: expectedID)
    }

    private func showSuccessFeedback(_ message: String, expectedID: UInt64) {
        guard presentationID == expectedID, let panel, let pill = pillView else { return }
        let newSize = pill.configureSuccessMessage(message)
        let centeredX = panel.frame.midX - (newSize.width / 2.0)
        let screen = NSScreen.screens.first { NSMouseInRect(panel.frame.origin, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let clampedX = min(Swift.max(centeredX, visible.minX + 8.0), Swift.max(visible.minX + 8.0, visible.maxX - newSize.width - 8.0))

        pill.frame = NSRect(origin: .zero, size: newSize)
        panel.setFrame(NSRect(x: clampedX, y: panel.frame.origin.y, width: newSize.width, height: newSize.height), display: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            self?.fadeOut(expectedID: expectedID)
        }
    }

    private func sendCommandC() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyCode: CGKeyCode = 0x08
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Panel Setup

    private func ensurePanel() -> TapCopyPanel {
        if let panel { return panel }
        let rect = NSRect(x: 0, y: 0, width: 120, height: ChameleonPillView.barHeight)
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

        let view = ChameleonPillView(frame: rect)
        view.autoresizingMask = [.width, .height]
        newPanel.contentView = view

        panel = newPanel
        pillView = view
        return newPanel
    }
}
