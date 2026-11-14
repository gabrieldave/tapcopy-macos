import AppKit
import ApplicationServices

/// Accessibility (TCC) state. The polling timer stops the instant access is
/// granted, so TapCopy idles at 0.0% CPU while waiting, and refreshes live
/// whenever a selection gesture occurs.
final class PermissionManager {

    static let shared = PermissionManager()

    private var timer: Timer?
    private(set) var isTrusted: Bool = AXIsProcessTrusted()
    var onChange: (() -> Void)?

    private init() {}

    // MARK: - Public API

    func requestIfNeeded() {
        if refresh() { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let prompted = AXIsProcessTrustedWithOptions(options)
        TapLog.log("Accessibility prompt requested (trusted=\(prompted))")
        startPolling()
    }

    func startPolling() {
        guard timer == nil, !isTrusted else { return }
        let newTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            _ = self?.refresh()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    @discardableResult
    func refresh() -> Bool {
        let trusted = AXIsProcessTrusted()
        let changed = (trusted != isTrusted)
        isTrusted = trusted
        if trusted {
            stopPolling()
        } else if timer == nil {
            startPolling()
        }
        if changed {
            TapLog.log("Accessibility permission changed: \(trusted)")
            if Thread.isMainThread {
                onChange?()
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.onChange?()
                }
            }
        }
        return trusted
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    var statusTextES: String {
        isTrusted ? "Permiso de Accesibilidad: Concedido" : "Permiso de Accesibilidad: Pendiente"
    }

    var statusTextEN: String {
        isTrusted ? "Accessibility Permission: Granted" : "Accessibility Permission: Pending"
    }
}
