import AppKit
import ApplicationServices

/// Watches mouse/trackpad gestures and pulls the current text selection through
/// the Accessibility API. It never touches the pasteboard while reading and
/// never synthesizes Cmd+C on mouse-up, so the blue selection stays intact.
final class SelectionMonitor {

    static let shared = SelectionMonitor()

    // MARK: - State

    private(set) var isEnabled: Bool = true
    private(set) var isChameleonModeEnabled: Bool = true
    private(set) var lastExternalApp: (name: String, bundleID: String)?

    private var excludedBundleIDs: Set<String> = []
    private var monitors: [Any] = []
    private var isTrackingDrag = false
    private var mouseDownPoint: NSPoint = .zero
    private var maxDragDistance: CGFloat = 0

    private var enhancedPIDs = Set<pid_t>()
    private let pidLock = NSLock()

    private var pendingReadWorkItem: DispatchWorkItem?
    private var readSequence: UInt64 = 0

    private let discardedRoles: Set<String> = [
        "AXSlider", "AXScrollBar", "AXGrowArea", "AXSplitter", "AXToolbar", "AXMenuBar", "AXMenu"
    ]

    private init() {}

    // MARK: - Lifecycle & Power State

    /// Called once at launch without overwriting UserDefaults unless explicitly toggled by the user.
    func configureAtLaunch(enabled: Bool) {
        let defaults = UserDefaults.standard
        if let savedChameleon = defaults.object(forKey: "tapCopyChameleonMode") as? Bool {
            isChameleonModeEnabled = savedChameleon
        } else {
            isChameleonModeEnabled = true
        }
        if let savedExcluded = defaults.stringArray(forKey: "tapCopyExcludedApps") {
            excludedBundleIDs = Set(savedExcluded)
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            noteActivatedApplication(front)
        }

        isEnabled = enabled
        applyEnabledState()
    }

    /// Persists only explicit user power changes (never called by app termination).
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "tapCopyEnabled")
        TapLog.log("User toggled TapCopy enabled=\(enabled)")
        applyEnabledState()
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func toggleChameleonMode() {
        isChameleonModeEnabled.toggle()
        UserDefaults.standard.set(isChameleonModeEnabled, forKey: "tapCopyChameleonMode")
        TapLog.log("Chameleon mode toggled=\(isChameleonModeEnabled)")
    }

    func noteActivatedApplication(_ app: NSRunningApplication) {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = app.bundleIdentifier else {
            return
        }
        let name = app.localizedName ?? bundleID
        lastExternalApp = (name: name, bundleID: bundleID)
    }

    func isAppExcluded(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    func toggleExcludedApp(bundleID: String) {
        if excludedBundleIDs.contains(bundleID) {
            excludedBundleIDs.remove(bundleID)
        } else {
            excludedBundleIDs.insert(bundleID)
            TapCopyPanelController.shared.hideImmediately()
        }
        UserDefaults.standard.set(Array(excludedBundleIDs).sorted(), forKey: "tapCopyExcludedApps")
        TapLog.log("Updated excluded apps: \(excludedBundleIDs)")
    }

    /// Refreshes event monitors after TCC grant, Mac wake, or display reconfiguration.
    func reinstallMonitors() {
        removeMonitors()
        if isEnabled {
            installMonitors()
        }
    }

    /// Clean teardown on app quit/reboot WITHOUT saving `false` into UserDefaults.
    func shutdown() {
        pendingReadWorkItem?.cancel()
        pendingReadWorkItem = nil
        removeMonitors()
        TapCopyPanelController.shared.hideImmediately()
    }

    private func applyEnabledState() {
        if isEnabled {
            installMonitors()
        } else {
            pendingReadWorkItem?.cancel()
            pendingReadWorkItem = nil
            removeMonitors()
            TapCopyPanelController.shared.hideImmediately()
        }
    }

    func resetApplicationCache() {
        pidLock.lock()
        enhancedPIDs.removeAll()
        pidLock.unlock()
    }

    // MARK: - Event monitors

    private func installMonitors() {
        guard monitors.isEmpty else { return }

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

        TapLog.log("Event monitors installed (count=\(monitors.count))")
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
        let insideOwnUI = TapCopyPanelController.shared.contains(screenPoint: mouse, toleratedInset: 4)
            || PinShelfController.shared.contains(screenPoint: mouse)

        switch event.type {
        case .leftMouseDown:
            if insideOwnUI { return }
            pendingReadWorkItem?.cancel()
            pendingReadWorkItem = nil
            isTrackingDrag = true
            mouseDownPoint = mouse
            maxDragDistance = 0
            TapCopyPanelController.shared.hideImmediately()

        case .leftMouseDragged:
            if insideOwnUI { return }
            if !isTrackingDrag {
                isTrackingDrag = true
                mouseDownPoint = NSPoint(x: mouse.x - event.deltaX, y: mouse.y + event.deltaY)
            }
            let dx = mouse.x - mouseDownPoint.x
            let dy = mouse.y - mouseDownPoint.y
            maxDragDistance = max(maxDragDistance, hypot(dx, dy))

        case .leftMouseUp:
            if insideOwnUI { return }
            let shiftClick = event.modifierFlags.contains(.shift)
            let wasRealSelection = maxDragDistance >= 3.5 || event.clickCount >= 2 || shiftClick
            let startPoint = isTrackingDrag ? mouseDownPoint : mouse
            let endPoint = mouse
            TapLog.log("MouseUp drag=\(String(format: "%.1f", maxDragDistance)) clicks=\(event.clickCount) shift=\(shiftClick) real=\(wasRealSelection)")
            isTrackingDrag = false
            maxDragDistance = 0
            guard wasRealSelection else { return }
            scheduleSelectionRead(startPoint: startPoint, endPoint: endPoint)

        default:
            break
        }
    }

    private func handleDismiss(_ event: NSEvent) {
        guard isEnabled else { return }
        switch event.type {
        case .keyDown:
            guard event.keyCode == 53 else { return } // Esc
        case .rightMouseDown, .otherMouseDown, .scrollWheel:
            break
        default:
            return
        }
        TapCopyPanelController.shared.hideImmediately()
    }

    // MARK: - Selection extraction

    private func scheduleSelectionRead(startPoint: NSPoint, endPoint: NSPoint) {
        pendingReadWorkItem?.cancel()
        readSequence &+= 1
        let currentSequence = readSequence

        let work = DispatchWorkItem { [weak self] in
            self?.readFrontmostSelection(
                startPoint: startPoint,
                endPoint: endPoint,
                sequence: currentSequence
            )
        }
        pendingReadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075, execute: work)
    }

    func debugReadFrontmostSelection() {
        let mouse = NSEvent.mouseLocation
        readSequence &+= 1
        readFrontmostSelection(startPoint: mouse, endPoint: mouse, sequence: readSequence)
    }

    private func readFrontmostSelection(startPoint: NSPoint, endPoint: NSPoint, sequence: UInt64) {
        guard isEnabled else { return }
        guard PermissionManager.shared.refresh() else {
            TapLog.log("Read skipped: Accessibility permission not granted")
            return
        }
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        noteActivatedApplication(frontApp)
        if isAppExcluded(bundleID: frontApp.bundleIdentifier) {
            TapLog.log("Read skipped: app excluded (\(frontApp.bundleIdentifier ?? "?"))")
            return
        }

        let pid = frontApp.processIdentifier
        let appName = frontApp.localizedName ?? "?"
        TapLog.log("Reading selection from \(appName) [\(pid)]")

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            var selected = self.extractSelection(
                pid: pid,
                startPoint: startPoint,
                endPoint: endPoint,
                forceReenableAX: false
            )

            // Retry once if Chromium/Electron/WebKit was still building its AX tree or updating selection.
            if selected == nil {
                usleep(130_000)
                selected = self.extractSelection(
                    pid: pid,
                    startPoint: startPoint,
                    endPoint: endPoint,
                    forceReenableAX: true
                )
            }

            guard let finalSelection = selected else {
                TapLog.log("No selected text returned for \(appName) [\(pid)]")
                return
            }

            TapLog.log("Selection captured: \(finalSelection.count) chars from \(appName)")
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isEnabled, self.readSequence == sequence else { return }
                TapCopyPanelController.shared.show(near: NSEvent.mouseLocation, fallbackText: finalSelection)
            }
        }
    }

    private func extractSelection(
        pid: pid_t,
        startPoint: NSPoint,
        endPoint: NSPoint,
        forceReenableAX: Bool
    ) -> String? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var orderedPIDs: [pid_t] = []

        if pid != ownPID {
            let frontAppRef = AXUIElementCreateApplication(pid)
            enableModernAccessibility(frontAppRef, pid: pid, force: forceReenableAX)
            orderedPIDs.append(pid)
        }

        let midPoint = NSPoint(
            x: (startPoint.x + endPoint.x) * 0.5,
            y: (startPoint.y + endPoint.y) * 0.5
        )

        var hitElements: [AXUIElement] = []
        for point in [endPoint, midPoint, startPoint] {
            if let hit = element(at: point), let hitPID = ownerPID(of: hit), hitPID != ownPID {
                if let hitApp = NSRunningApplication(processIdentifier: hitPID),
                   isAppExcluded(bundleID: hitApp.bundleIdentifier) {
                    continue
                }
                if !orderedPIDs.contains(hitPID) {
                    let hitAppRef = AXUIElementCreateApplication(hitPID)
                    enableModernAccessibility(hitAppRef, pid: hitPID, force: forceReenableAX)
                    orderedPIDs.insert(hitPID, at: 0)
                    if let refreshedHit = element(at: point) {
                        hitElements.append(refreshedHit)
                        continue
                    }
                }
                hitElements.append(hit)
            }
        }

        var candidates: [AXUIElement] = []
        for targetPID in orderedPIDs {
            let appRef = AXUIElementCreateApplication(targetPID)
            if let focused = copyElement(appRef, attribute: kAXFocusedUIElementAttribute as String) {
                candidates.append(focused)
            }
        }
        candidates.append(contentsOf: hitElements)

        for candidate in candidates {
            if let role = role(of: candidate), discardedRoles.contains(role) {
                continue
            }
            if let text = extractTextWalkingParents(from: candidate, maxLevels: 20) {
                return text
            }
        }

        // Fallback: search downward inside the focused/main window for AXWebArea or text containers.
        for targetPID in orderedPIDs {
            let appRef = AXUIElementCreateApplication(targetPID)
            let window = copyElement(appRef, attribute: kAXFocusedWindowAttribute as String)
                ?? copyElement(appRef, attribute: kAXMainWindowAttribute as String)
            if let window, let text = extractTextFromWindowSubtree(window: window) {
                return text
            }
        }

        return nil
    }

    private func enableModernAccessibility(_ appRef: AXUIElement, pid: pid_t, force: Bool) {
        pidLock.lock()
        let alreadyEnhanced = enhancedPIDs.contains(pid)
        if !alreadyEnhanced {
            enhancedPIDs.insert(pid)
        }
        pidLock.unlock()

        guard !alreadyEnhanced || force else { return }
        AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appRef, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if !alreadyEnhanced {
            usleep(65_000)
        }
    }

    private func extractTextWalkingParents(from element: AXUIElement, maxLevels: Int) -> String? {
        var current: AXUIElement? = element
        var level = 0
        while let node = current, level <= maxLevels {
            if let currentRole = role(of: node), discardedRoles.contains(currentRole) {
                return nil
            }
            if let text = directSelection(in: node) {
                return text
            }
            current = copyElement(node, attribute: kAXParentAttribute as String)
            level += 1
        }
        return nil
    }

    private func extractTextFromWindowSubtree(window: AXUIElement) -> String? {
        var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
        var index = 0
        let maxVisited = 72
        let maxDepth = 7

        while index < queue.count && index < maxVisited {
            let current = queue[index]
            index += 1

            if let nodeRole = role(of: current.element), discardedRoles.contains(nodeRole) {
                continue
            }
            if let text = directSelection(in: current.element) {
                return text
            }
            guard current.depth < maxDepth else { continue }

            for child in copyChildElements(current.element) {
                queue.append((child, current.depth + 1))
                if queue.count >= maxVisited { break }
            }
        }
        return nil
    }

    private func directSelection(in element: AXUIElement) -> String? {
        // (a) Plain selected text.
        var selectedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedValue) == .success,
           let raw = selectedValue as? String {
            if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return raw
            }
        }

        // (b) Text marker range — Chrome, Brave, Arc, Safari, Electron, and WebKit views.
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
                if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return raw
                }
            }
        }

        // (c) Selected CFRange — Preview/PDFKit, code editors, and custom AppKit views.
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rawRange = rangeRef,
           CFGetTypeID(rawRange) == AXValueGetTypeID() {
            let axValue = rawRange as! AXValue
            var cfRange = CFRange(location: 0, length: 0)
            if AXValueGetValue(axValue, .cfRange, &cfRange), cfRange.length > 0, cfRange.location >= 0 {
                var paramStringRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(
                    element,
                    kAXStringForRangeParameterizedAttribute as CFString,
                    axValue,
                    &paramStringRef
                ) == .success, let raw = paramStringRef as? String {
                    if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return raw
                    }
                }

                var fullValueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &fullValueRef) == .success,
                   let fullString = fullValueRef as? String {
                    let nsString = fullString as NSString
                    if cfRange.location + cfRange.length <= nsString.length {
                        let sub = nsString.substring(with: NSRange(location: cfRange.location, length: cfRange.length))
                        if !sub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return sub
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - AX helpers

    private func copyChildElements(_ element: AXUIElement) -> [AXUIElement] {
        for attr in [kAXChildrenAttribute as String, kAXContentsAttribute as String] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success,
                  let array = value as? NSArray,
                  array.count > 0 else {
                continue
            }
            var children: [AXUIElement] = []
            children.reserveCapacity(array.count)
            for item in array {
                let ref = item as CFTypeRef
                if CFGetTypeID(ref) == AXUIElementGetTypeID() {
                    children.append(ref as! AXUIElement)
                }
            }
            if !children.isEmpty {
                return children
            }
        }
        return []
    }

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
