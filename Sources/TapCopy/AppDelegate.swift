import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController?
    private var workspaceObservers: [NSObjectProtocol] = []

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock policy: first launch (hideDockIcon == false) stays .regular so the
        // TCC Accessibility prompt is easy to accept. The toggle switches live.
        let hideDock = UserDefaults.standard.bool(forKey: "hideDockIcon")
        NSApp.setActivationPolicy(hideDock ? .accessory : .regular)

        buildMainMenu()

        // Signature / identity diagnostics (Team ID YH6W55MP95).
        let signature = SignatureVerifier.shared.result

        let monitor = SelectionMonitor.shared
        let saved = UserDefaults.standard.object(forKey: "tapCopyEnabled") as? Bool
        monitor.isEnabled = saved ?? true
        monitor.activate()

        let statusBar = StatusBarController(
            isEnabled: { SelectionMonitor.shared.isEnabled },
            toggleEnabled: { SelectionMonitor.shared.toggle() },
            isDockHidden: { UserDefaults.standard.bool(forKey: "hideDockIcon") },
            toggleDock: { [weak self] in self?.toggleDockIcon() },
            isAccessibilityGranted: { PermissionManager.shared.isTrusted },
            openAccessibilitySettings: { PermissionManager.shared.openSystemSettings() }
        )
        statusBarController = statusBar
        statusBar.install()

        PermissionManager.shared.onChange = { [weak self] in
            self?.statusBarController?.refreshAppearance()
        }
        PermissionManager.shared.requestIfNeeded()

        if !hideDock {
            NSApp.activate(ignoringOtherApps: true)
        }

        let center = NotificationCenter.default
        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                               object: nil, queue: .main) { _ in
                SelectionMonitor.shared.resetApplicationCache()
            }
        )

        NSLog("TapCopy %@ (%@) — signature valid: %@, team: %@",
              Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
              Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
              signature.isValid ? "yes" : "no",
              signature.teamIdentifier ?? "unsigned")

        TapLog.log("Launch \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?") — accessibilityTrusted=\(PermissionManager.shared.isTrusted) enabled=\(SelectionMonitor.shared.isEnabled)")

        // Internal visual smoke test: TapCopy --demo-pill
        if CommandLine.arguments.contains("--demo-pill") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                TapCopyPanelController.shared.show(
                    near: NSEvent.mouseLocation,
                    fallbackText: "Texto de demostración"
                )
            }
        }

        if CommandLine.arguments.contains("--read-now") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                SelectionMonitor.shared.debugReadFrontmostSelection()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SelectionMonitor.shared.isEnabled = false
        for observer in workspaceObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Main menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "TapCopy")

        let aboutItem = NSMenuItem(
            title: "Acerca de TapCopy",
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let hideOthersItem = NSMenuItem(
            title: "Ocultar otros",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(
            title: "Mostrar todo",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(showAllItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Salir de TapCopy",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Standard Edit menu (useful inside the About window for copy/paste).
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edición")
        editMenu.addItem(NSMenuItem(title: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Rehacer", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout(_ sender: Any?) {
        AboutWindowController.shared.show()
    }

    // MARK: - Dock icon toggle

    private func toggleDockIcon() {
        let hidden = UserDefaults.standard.bool(forKey: "hideDockIcon")
        setDockIconHidden(!hidden)
    }

    private func setDockIconHidden(_ hidden: Bool) {
        UserDefaults.standard.set(hidden, forKey: "hideDockIcon")
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
        if !hidden {
            NSApp.activate(ignoringOtherApps: true)
        }
        statusBarController?.refreshAppearance()
    }
}
