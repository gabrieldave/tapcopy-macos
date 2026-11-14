import AppKit
import ApplicationServices

/// Accessibility (TCC) state. The polling timer stops the instant access is
/// granted, so TapCopy idles at 0.0% CPU while waiting.
final class PermissionManager {

    static let shared = PermissionManager()

    private var timer: Timer?
    private(set) var isTrusted: Bool = AXIsProcessTrusted()
    var onChange: (() -> Void)?

    private init() {}

    // MARK: - Public API

    func requestIfNeeded() {
        refresh()
        guard !isTrusted else { return }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didRequestAccessibility") {
            defaults.set(true, forKey: "didRequestAccessibility")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        startPolling()
    }

    func startPolling() {
        guard timer == nil, !isTrusted else { return }
        let newTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        let changed = (trusted != isTrusted)
        isTrusted = trusted
        if trusted {
            stopPolling()
        }
        if changed {
            onChange?()
        }
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
