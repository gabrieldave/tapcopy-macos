import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController?
    private var reminderTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard

        // One-time self-heal: v1.0.1 saved `tapCopyEnabled = false` on every quit/reboot.
        if !defaults.bool(forKey: "didFixTerminationState_v102") {
            defaults.set(true, forKey: "didFixTerminationState_v102")
            defaults.set(true, forKey: "tapCopyEnabled")
        }

        let hideDock = defaults.bool(forKey: "hideDockIcon")
        NSApp.setActivationPolicy(hideDock ? .accessory : .regular)

        buildMainMenu()

        let signature = SignatureVerifier.shared.result

        // Layer 1 — a modified or re-signed .app must never reach the monitors.
        if Bundle.main.bundleURL.pathExtension == "app" && !signature.isValid {
            TapLog.log("Signature gate blocked launch: team=\(signature.teamIdentifier ?? "none") id=\(signature.signingIdentifier ?? "none")")
            let spanish = Locale.preferredLanguages.first?.hasPrefix("es") ?? true
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = spanish ? "Firma de TapCopy no válida" : "Invalid TapCopy signature"
            alert.informativeText = spanish
                ? "La firma oficial de TapCopy (YH6W55MP95) no es válida. La app pudo haber sido alterada o re-firmada fuera del equipo autorizado. Descarga una copia oficial desde tapcopy.iareal.net."
                : "The official TapCopy signature (YH6W55MP95) is not valid. The app may have been altered or re-signed outside the authorized team. Download an official copy from tapcopy.iareal.net."
            alert.addButton(withTitle: spanish ? "Salir" : "Quit")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let monitor = SelectionMonitor.shared
        let saved = defaults.object(forKey: "tapCopyEnabled") as? Bool
        monitor.configureAtLaunch(enabled: saved ?? true)

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
            if PermissionManager.shared.isTrusted && SelectionMonitor.shared.isEnabled {
                SelectionMonitor.shared.reinstallMonitors()
            }
            self?.statusBarController?.refreshAppearance()
            AboutWindowController.shared.refreshIfVisible()
        }
        PermissionManager.shared.requestIfNeeded()

        // Licensing: localized window, expired-state gate (C once per session) and
        // the gentle day 11-14 reminder that only fires after 2 s of real idle.
        LicenseWindowController.shared.isSpanish = Locale.preferredLanguages.first?.hasPrefix("es") ?? true
        LicenseWindowController.shared.onQuit = { NSApp.terminate(nil) }

        LicenseManager.shared.startClock()
        if !LicenseManager.shared.canUseApp {
            let state = LicenseManager.shared.windowState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                LicenseWindowController.shared.show(state)
            }
        }

        let reminderTimer = Timer(timeInterval: 1.0, repeats: true) { _ in
            guard SelectionMonitor.shared.secondsSinceLastActivity >= 2.0,
                  !TapCopyPanelController.shared.isVisible else { return }
            LicenseManager.shared.showReminderIfDue(isIdle: true)
        }
        RunLoop.main.add(reminderTimer, forMode: .common)
        self.reminderTimer = reminderTimer

        AppUpdateChecker.shared.checkSilentlyIfDue()
        LicenseManager.shared.syncTrialIfNeeded()

        if !hideDock {
            NSApp.activate(ignoringOtherApps: true)
        }

        let wsCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            wsCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                 object: nil, queue: .main) { notification in
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    SelectionMonitor.shared.noteActivatedApplication(app)
                }
            }
        )
        workspaceObservers.append(
            wsCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                 object: nil, queue: .main) { _ in
                SelectionMonitor.shared.resetApplicationCache()
            }
        )
        workspaceObservers.append(
            wsCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                 object: nil, queue: .main) { [weak self] _ in
                TapLog.log("System woke from sleep — refreshing TCC and event monitors")
                _ = PermissionManager.shared.refresh()
                SelectionMonitor.shared.reinstallMonitors()
                LicenseManager.shared.handleWake()
                self?.statusBarController?.refreshAppearance()
            }
        )

        appObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in
                TapCopyPanelController.shared.hideImmediately()
            }
        )

        NSLog("TapCopy %@ (%@) — signature valid: %@, team: %@",
              Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
              Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
              signature.isValid ? "yes" : "no",
              signature.teamIdentifier ?? "unsigned")

        TapLog.log("Launch \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?") — accessibilityTrusted=\(PermissionManager.shared.isTrusted) enabled=\(SelectionMonitor.shared.isEnabled)")

        if CommandLine.arguments.contains("--demo-pill") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                TapCopyPanelController.shared.show(
                    near: NSEvent.mouseLocation,
                    fallbackText: "145 * 1.16",
                    force: true
                )
            }
        }

        if CommandLine.arguments.contains("--read-now") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                SelectionMonitor.shared.debugReadFrontmostSelection()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !SelectionMonitor.shared.isEnabled {
            SelectionMonitor.shared.setEnabled(true)
        }
        _ = PermissionManager.shared.refresh()
        statusBarController?.refreshAppearance()
        AboutWindowController.shared.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        reminderTimer?.invalidate()
        reminderTimer = nil
        SelectionMonitor.shared.shutdown()
        PinShelfController.shared.closeAll()

        let wsCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            wsCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        for observer in appObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        appObservers.removeAll()
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
