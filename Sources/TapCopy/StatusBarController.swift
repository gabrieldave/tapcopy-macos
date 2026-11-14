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
        let symbol = enabled ? "doc.on.clipboard.fill" : "doc.on.clipboard"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "TapCopy")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !enabled
    }

    // MARK: - Click handling

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            // One-click power toggle straight from the menu bar.
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
        let enabled = isEnabled()
        let granted = isAccessibilityGranted()

        let stateItem = NSMenuItem(
            title: enabled ? "TapCopy activo · selecciona y copia" : "TapCopy apagado",
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

        let permissionTitle = granted
            ? "Permiso de Accesibilidad: Concedido"
            : "Permiso de Accesibilidad: Pendiente…"
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

    @objc private func toggleDockIcon() {
        toggleDock()
    }

    @objc private func openPermission() {
        openAccessibilitySettings()
    }

    @objc private func showAbout() {
        AboutWindowController.shared.show()
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
