import AppKit
import ServiceManagement

final class StatusBarController: NSObject, NSMenuDelegate {

    // MARK: - Callbacks

    private let isEnabled: () -> Bool
    private let toggleEnabled: () -> Void
    private let isDockHidden: () -> Bool
    private let toggleDock: () -> Void
    private let isAccessibilityGranted: () -> Bool
    private let openAccessibilitySettings: () -> Void

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    init(
        isEnabled: @escaping () -> Bool,
        toggleEnabled: @escaping () -> Void,
        isDockHidden: @escaping () -> Bool,
        toggleDock: @escaping () -> Void,
        isAccessibilityGranted: @escaping () -> Bool,
        openAccessibilitySettings: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.toggleEnabled = toggleEnabled
        self.isDockHidden = isDockHidden
        self.toggleDock = toggleDock
        self.isAccessibilityGranted = isAccessibilityGranted
        self.openAccessibilitySettings = openAccessibilitySettings
        super.init()
    }

    // MARK: - Setup

    func install() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "TapCopy"
        menu.delegate = self
        refreshAppearance()
    }

    func refreshAppearance() {
        guard let button = statusItem.button else { return }
        let enabled = isEnabled()
        let granted = isAccessibilityGranted()

        let symbol: String
        if !granted {
            symbol = "exclamationmark.triangle.fill"
        } else {
            symbol = enabled ? "doc.on.clipboard.fill" : "doc.on.clipboard"
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "TapCopy")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !enabled && granted
    }

    // MARK: - Click handling

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            toggleEnabled()
            refreshAppearance()
            return
        }
        statusItem.menu = menu
        menuNeedsUpdate(menu)
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        _ = PermissionManager.shared.refresh()
        let enabled = isEnabled()
        let granted = isAccessibilityGranted()
        let monitor = SelectionMonitor.shared

        let stateTitle: String
        if !granted {
            stateTitle = "Falta permiso de Accesibilidad"
        } else {
            stateTitle = enabled ? "TapCopy activo · Píldora Camaleón" : "TapCopy apagado"
        }

        let stateItem = NSMenuItem(
            title: stateTitle,
            action: nil,
            keyEquivalent: ""
        )
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(
            title: enabled ? "Apagar TapCopy" : "Encender TapCopy",
            action: #selector(toggleTapCopy),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let chameleonItem = NSMenuItem(
            title: "Modo Camaleón (4 funciones)",
            action: #selector(toggleChameleon),
            keyEquivalent: ""
        )
        chameleonItem.target = self
        chameleonItem.state = monitor.isChameleonModeEnabled ? .on : .off
        menu.addItem(chameleonItem)

        if let lastApp = monitor.lastExternalApp {
            let pauseItem = NSMenuItem(
                title: "Pausar en \(lastApp.name)",
                action: #selector(toggleExcludeCurrentApp),
                keyEquivalent: ""
            )
            pauseItem.target = self
            pauseItem.state = monitor.isAppExcluded(bundleID: lastApp.bundleID) ? .on : .off
            menu.addItem(pauseItem)
        }

        let testItem = NSMenuItem(
            title: "Probar píldora ahora",
            action: #selector(testPillNow),
            keyEquivalent: ""
        )
        testItem.target = self
        menu.addItem(testItem)

        let permissionTitle = granted
            ? "Permiso de Accesibilidad: Concedido"
            : "Activar Permiso de Accesibilidad…"
        let permissionItem = NSMenuItem(
            title: permissionTitle,
            action: #selector(openPermission),
            keyEquivalent: ""
        )
        permissionItem.target = self
        permissionItem.image = NSImage(
            systemSymbolName: granted ? "checkmark.shield.fill" : "exclamationmark.shield",
            accessibilityDescription: nil
        )
        menu.addItem(permissionItem)
        menu.addItem(.separator())

        let dockItem = NSMenuItem(
            title: "Ocultar icono del Dock",
            action: #selector(toggleDockIcon),
            keyEquivalent: ""
        )
        dockItem.target = self
        dockItem.state = isDockHidden() ? .on : .off
        menu.addItem(dockItem)

        let loginItem = NSMenuItem(
            title: "Iniciar al encender mi Mac",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "Acerca de TapCopy…",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let licenseTitle = LicenseManager.shared.isLicensed
            ? "Licencia…"
            : (LicenseManager.shared.trialExpired ? "Activar licencia…" : "Licencia… (prueba: \(LicenseManager.shared.trialDaysLeft) días)")
        let licenseItem = NSMenuItem(
            title: licenseTitle,
            action: #selector(showLicense),
            keyEquivalent: ""
        )
        licenseItem.target = self
        menu.addItem(licenseItem)

        let updateItem = NSMenuItem(
            title: "Buscar actualizaciones…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        let quitItem = NSMenuItem(
            title: "Salir de TapCopy",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func toggleTapCopy() {
        toggleEnabled()
        refreshAppearance()
    }

    @objc private func toggleChameleon() {
        SelectionMonitor.shared.toggleChameleonMode()
    }

    @objc private func toggleExcludeCurrentApp() {
        guard let lastApp = SelectionMonitor.shared.lastExternalApp else { return }
        SelectionMonitor.shared.toggleExcludedApp(bundleID: lastApp.bundleID)
    }

    @objc private func testPillNow() {
        let anchor = NSEvent.mouseLocation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            TapCopyPanelController.shared.show(
                near: anchor,
                fallbackText: "145 * 1.16",
                force: true
            )
        }
    }

    @objc private func toggleDockIcon() {
        toggleDock()
    }

    @objc private func openPermission() {
        openAccessibilitySettings()
    }

    @objc private func showAbout() {
        AboutWindowController.shared.show()
    }

    @objc private func showLicense() {
        LicenseWindowController.shared.show(LicenseManager.shared.windowState())
    }

    @objc private func checkForUpdates() {
        AppUpdateChecker.shared.checkInteractively()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Launch at login

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "No se pudo actualizar el inicio automático"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
