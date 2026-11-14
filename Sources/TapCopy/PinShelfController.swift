import AppKit

/// Function 4 of Chameleon Pill: non-activating floating Micro-Shelf ("Fijar / Pin")
/// that holds text snippets on screen across Spaces without overwriting the main
/// pasteboard until requested.
final class PinShelfController {

    static let shared = PinShelfController()

    private final class ShelfPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class ShelfCardView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private final class ActionChipButton: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private var activePanels: [NSPanel] = []
    private let maxPins = 4

    private init() {}

    func contains(screenPoint: NSPoint) -> Bool {
        activePanels.contains { panel in
            panel.isVisible && panel.frame.insetBy(dx: -4, dy: -4).contains(screenPoint)
        }
    }

    func closeAll() {
        for panel in activePanels {
            panel.orderOut(nil)
        }
        activePanels.removeAll()
    }

    func pin(text: String, near anchor: NSPoint) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if activePanels.count >= maxPins, let oldest = activePanels.first {
            oldest.orderOut(nil)
            activePanels.removeFirst()
        }

        let cardSize = NSSize(width: 244, height: 74)
        let stackOffset = CGFloat(activePanels.count) * 18.0
        let rawAnchor = NSPoint(x: anchor.x + 14 + stackOffset, y: anchor.y - 22 - stackOffset)
        let metrics = WindowCollisionAvoidance.captureScreenMetrics(near: rawAnchor)
        let origin = WindowCollisionAvoidance.bestOrigin(
            anchor: rawAnchor,
            selectionRect: nil,
            pillSize: cardSize,
            targetPID: nil,
            ownPanelNumber: nil,
            metrics: metrics
        )

        let panel = ShelfPanel(
            contentRect: NSRect(origin: origin, size: cardSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false

        let card = ShelfCardView(frame: NSRect(origin: .zero, size: cardSize))
        card.wantsLayer = true
        card.layer?.cornerRadius = 13.0
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = NSColor(srgbRed: 0x18 / 255.0, green: 0x19 / 255.0, blue: 0x1C / 255.0, alpha: 0.96).cgColor
        card.layer?.borderWidth = 1.0
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        let badgeLabel = NSTextField(labelWithString: "📌 Fijado · \(trimmed.count) car")
        badgeLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        badgeLabel.textColor = NSColor(srgbRed: 0xA1 / 255.0, green: 0xA1 / 255.0, blue: 0xAA / 255.0, alpha: 1.0)
        badgeLabel.frame = NSRect(x: 12, y: 48, width: 132, height: 15)
        card.addSubview(badgeLabel)

        let copyBtn = ActionChipButton(frame: NSRect(x: 150, y: 46, width: 58, height: 20))
        copyBtn.title = "Copiar"
        copyBtn.isBordered = false
        copyBtn.wantsLayer = true
        copyBtn.layer?.cornerRadius = 6.0
        copyBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        copyBtn.font = .systemFont(ofSize: 10.5, weight: .medium)
        copyBtn.contentTintColor = .white

        let closeBtn = ActionChipButton(frame: NSRect(x: 214, y: 46, width: 20, height: 20))
        closeBtn.title = "✕"
        closeBtn.isBordered = false
        closeBtn.font = .systemFont(ofSize: 11, weight: .semibold)
        closeBtn.contentTintColor = NSColor.white.withAlphaComponent(0.65)

        let previewString = trimmed.replacingOccurrences(of: "\n", with: " ↵ ")
        let previewLabel = NSTextField(labelWithString: previewString)
        previewLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        previewLabel.textColor = NSColor(srgbRed: 0xF4 / 255.0, green: 0xF4 / 255.0, blue: 0xF5 / 255.0, alpha: 1.0)
        previewLabel.maximumNumberOfLines = 2
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.cell?.wraps = true
        previewLabel.frame = NSRect(x: 12, y: 8, width: 220, height: 34)
        card.addSubview(previewLabel)

        let handler = ShelfActionTarget(
            text: text,
            panel: panel,
            copyButton: copyBtn,
            onClose: { [weak self] closedPanel in
                closedPanel.orderOut(nil)
                self?.activePanels.removeAll { $0 === closedPanel }
            }
        )
        objc_setAssociatedObject(panel, &ShelfActionTarget.assocKey, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        copyBtn.target = handler
        copyBtn.action = #selector(ShelfActionTarget.copyPinned(_:))
        closeBtn.target = handler
        closeBtn.action = #selector(ShelfActionTarget.closePinned(_:))

        card.addSubview(copyBtn)
        card.addSubview(closeBtn)

        panel.contentView = card
        panel.orderFrontRegardless()
        activePanels.append(panel)
    }
}

private final class ShelfActionTarget: NSObject {
    static var assocKey: UInt8 = 0

    let text: String
    weak var panel: NSPanel?
    weak var copyButton: NSButton?
    let onClose: (NSPanel) -> Void

    init(text: String, panel: NSPanel, copyButton: NSButton, onClose: @escaping (NSPanel) -> Void) {
        self.text = text
        self.panel = panel
        self.copyButton = copyButton
        self.onClose = onClose
    }

    @objc func copyPinned(_ sender: Any?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copyButton?.title = "✓ Listo"
        copyButton?.contentTintColor = NSColor(srgbRed: 0x10 / 255.0, green: 0xB9 / 255.0, blue: 0x81 / 255.0, alpha: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.copyButton?.title = "Copiar"
            self?.copyButton?.contentTintColor = .white
        }
    }

    @objc func closePinned(_ sender: Any?) {
        guard let panel else { return }
        onClose(panel)
    }
}
