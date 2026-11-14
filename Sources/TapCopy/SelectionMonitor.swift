import AppKit
import ApplicationServices

/// Watches mouse gestures and pulls the current text selection through the
/// Accessibility API. It never touches the pasteboard while reading and never
/// synthesizes Cmd+C on mouse-up, so the blue selection stays intact.
final class SelectionMonitor {

    static let shared = SelectionMonitor()

    // MARK: - State

    var isEnabled: Bool = true {
        didSet {
            guard isEnabled != oldValue else { return }
            applyEnabledState()
            UserDefaults.standard.set(isEnabled, forKey: "tapCopyEnabled")
        }
    }

    private var monitors: [Any] = []
    private var mouseDownPoint: NSPoint = .zero
    private var maxDragDistance: CGFloat = 0
    private var enhancedPIDs = Set<pid_t>()

    private let discardedRoles: Set<String> = [
        "AXSlider", "AXScrollBar", "AXGrowArea", "AXSplitter", "AXToolbar"
    ]

    private init() {}

    // MARK: - Public helpers

    /// Must be called once at launch: the read-only `isEnabled` default never
    /// fires `didSet`, so monitors are installed explicitly here.
    func activate() {
        applyEnabledState()
    }

    private func applyEnabledState() {
        if isEnabled {
            installMonitors()
        } else {
            removeMonitors()
            TapCopyPanelController.shared.hideImmediately()
        }
    }

    func toggle() {
        isEnabled.toggle()
    }

    func resetApplicationCache() {
        enhancedPIDs.removeAll()
    }

    // MARK: - Event monitors

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        TapLog.log("Event monitors installed")

        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        let dismissEvents: NSEvent.EventTypeMask = [.rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents, handler: { [weak self] event in
            self?.handleMouse(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouseEvents, handler: { [weak self] event in
            self?.handleMouse(event)
            return event
        }) {
            monitors.append(local)
        }
        if let globalDismiss = NSEvent.addGlobalMonitorForEvents(matching: dismissEvents, handler: { [weak self] event in
            self?.handleDismiss(event)
        }) {
            monitors.append(globalDismiss)
        }
        if let localDismiss = NSEvent.addLocalMonitorForEvents(matching: dismissEvents, handler: { [weak self] event in
            self?.handleDismiss(event)
            return event
        }) {
            monitors.append(localDismiss)
        }
    }

    private func removeMonitors() {
        guard !monitors.isEmpty else { return }
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        TapLog.log("Event monitors removed")
    }

    private func handleMouse(_ event: NSEvent) {
        guard isEnabled else { return }
        let mouse = NSEvent.mouseLocation
        let insidePanel = TapCopyPanelController.shared.contains(screenPoint: mouse, toleratedInset: 6)

        switch event.type {
        case .leftMouseDown:
            // A click on the pill must land cleanly on the "Copiar" button.
            if insidePanel { return }
            mouseDownPoint = mouse
            maxDragDistance = 0
            TapCopyPanelController.shared.hideImmediately()

        case .leftMouseDragged:
            let dx = mouse.x - mouseDownPoint.x
            let dy = mouse.y - mouseDownPoint.y
            let distance = sqrt(dx * dx + dy * dy)
            maxDragDistance = max(maxDragDistance, distance)

        case .leftMouseUp:
            if insidePanel { return }
            let wasRealSelection = maxDragDistance >= 5.0 || event.clickCount >= 2
            TapLog.log("MouseUp drag=\(String(format: "%.1f", maxDragDistance)) clicks=\(event.clickCount) real=\(wasRealSelection) trusted=\(PermissionManager.shared.isTrusted)")
            maxDragDistance = 0
            guard wasRealSelection else { return }
            scheduleSelectionRead()

        default:
            break
        }
    }

    private func handleDismiss(_ event: NSEvent) {
        guard isEnabled else { return }
        switch event.type {
        case .keyDown:
            guard event.keyCode == 53 else { return }
        case .rightMouseDown, .otherMouseDown, .scrollWheel:
            break
        default:
            return
        }
        TapCopyPanelController.shared.hideImmediately()
    }

    // MARK: - Selection extraction

    private func scheduleSelectionRead() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075) { [weak self] in
            self?.readFrontmostSelection()
        }
    }

    func debugReadFrontmostSelection() {
        readFrontmostSelection()
    }

    private func readFrontmostSelection() {
        guard isEnabled else { return }
        guard PermissionManager.shared.isTrusted else {
            TapLog.log("Read skipped: no Accessibility permission")
            return
        }
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        let pid = frontApp.processIdentifier
        let mouse = NSEvent.mouseLocation
        TapLog.log("Reading selection from \(frontApp.localizedName ?? "?") [\(pid)]")

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            let text = self.extractSelection(pid: pid, at: mouse)
            guard let selected = text else {
                TapLog.log("No selected text returned for PID \(pid)")
                return
            }
            TapLog.log("Selection captured: \(selected.count) chars")
            DispatchQueue.main.async {
                TapCopyPanelController.shared.show(near: NSEvent.mouseLocation, fallbackText: selected)
            }
        }
    }

    /// Enables the modern web accessibility trees once per process and quits at
    /// the first non-empty selection found. The element under the cursor is the
    /// primary source (it can belong to an app that is not frontmost for a
    /// fraction of a second), with the focused app as fallback.
    private func extractSelection(pid: pid_t, at mouse: NSPoint) -> String? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let underCursor = element(at: mouse)
        let cursorPID = underCursor.flatMap { ownerPID(of: $0) }
        if let cursorPID {
            let name = NSRunningApplication(processIdentifier: cursorPID)?.localizedName ?? "?"
            TapLog.log("Cursor element owner: \(name) [\(cursorPID)]")
        }

        var orderedPIDs: [pid_t] = []
        if let cursorPID, cursorPID != ownPID, cursorPID != pid {
            orderedPIDs.append(cursorPID)
        }
        if pid != ownPID {
            orderedPIDs.append(pid)
        }

        var candidates: [(pid: pid_t, element: AXUIElement)] = []
        if let underCursor, let cursorPID {
            candidates.append((cursorPID, underCursor))
        }

        for targetPID in orderedPIDs {
            let appRef = AXUIElementCreateApplication(targetPID)
            enableModernAccessibility(appRef, pid: targetPID)
            if let focused = copyElement(appRef, attribute: kAXFocusedUIElementAttribute as String) {
                candidates.append((targetPID, focused))
            }
            if let window = copyElement(appRef, attribute: kAXFocusedWindowAttribute as String) {
                candidates.append((targetPID, window))
            }
        }

        for candidate in candidates {
            if let role = role(of: candidate.element), discardedRoles.contains(role) {
                continue
            }
            if let text = extractText(from: candidate.element) {
                return text
            }
        }
        return nil
    }

    private func enableModernAccessibility(_ appRef: AXUIElement, pid: pid_t) {
        guard !enhancedPIDs.contains(pid) else { return }
        AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appRef, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        enhancedPIDs.insert(pid)
        // Give Chromium/WebKit a beat to build its tree on first use.
        usleep(35_000)
    }

    private func extractText(from element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        var level = 0
        while let node = current, level <= 4 {
            if let text = directSelection(in: node) {
                return text
            }
            current = copyElement(node, attribute: kAXParentAttribute as String)
            level += 1
        }
        return nil
    }

    private func directSelection(in element: AXUIElement) -> String? {
        // (a) Plain selected text.
        var selectedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedValue) == .success,
           let raw = selectedValue as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return raw }
        }

        // (b) Text marker range — required for multi-node selections (lists,
        // code blocks) in Chrome, Brave, Arc, Safari and WebKit views.
        var markerValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextMarkerRangeAttribute as CFString, &markerValue) == .success,
           let marker = markerValue {
            var stringValue: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForTextMarkerRangeParameterizedAttribute as CFString,
                marker,
                &stringValue
            ) == .success, let raw = stringValue as? String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return raw }
            }
        }

        return nil
    }

    // MARK: - AX helpers

    private func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func ownerPID(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        return pid
    }

    private func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func element(at screenPoint: NSPoint) -> AXUIElement? {
        // AXUIElementCopyElementAtPosition uses global top-left origin coordinates.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let axX = Float(screenPoint.x)
        let axY = Float(primaryHeight - screenPoint.y)
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, axX, axY, &element) == .success else {
            return nil
        }
        return element
    }
}
