import AppKit

final class AboutWindowController: NSObject {

    static let shared = AboutWindowController()

    private enum Language: Int {
        case english = 0
        case spanish = 1
    }

    private var window: NSWindow?
    private var language: Language = .spanish

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(labelWithString: "")
    private let chipLabel = NSTextField(labelWithString: "")
    private let signatureLabel = NSTextField(labelWithString: "")
    private let permissionLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "")

    private let testPillButton = NSButton(title: "", target: nil, action: nil)
    private let permissionButton = NSButton(title: "", target: nil, action: nil)
    private let copyButton = NSButton(title: "", target: nil, action: nil)
    private let languageControl = NSSegmentedControl(labels: ["EN", "ES"], trackingMode: .selectOne, target: nil, action: nil)

    private var copyResetWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
    }

    // MARK: - Presentation

    func show() {
        if window == nil {
            buildWindow()
        }
        _ = PermissionManager.shared.refresh()
        applyLanguage()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshIfVisible() {
        guard let window, window.isVisible else { return }
        applyLanguage()
    }

    // MARK: - Window

    private func buildWindow() {
        let contentRect = NSRect(x: 0, y: 0, width: 460, height: 470)
        let panel = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "TapCopy"
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let container = NSView(frame: contentRect)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        iconView.image = NSApplication.shared.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 72).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 72).isActive = true
        stack.addArrangedSubview(iconView)
        stack.setCustomSpacing(14, after: iconView)

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .labelColor
        stack.addArrangedSubview(titleLabel)
        stack.setCustomSpacing(2, after: titleLabel)

        versionLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(versionLabel)
        stack.setCustomSpacing(16, after: versionLabel)

        for label in [stateLabel, chipLabel, signatureLabel, permissionLabel] {
            label.font = .systemFont(ofSize: 12, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byWordWrapping
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 390).isActive = true
            stack.addArrangedSubview(label)
        }

        stack.setCustomSpacing(18, after: permissionLabel)

        languageControl.target = self
        languageControl.action = #selector(languageChanged(_:))
        languageControl.selectedSegment = Language.spanish.rawValue
        languageControl.segmentStyle = .rounded
        stack.addArrangedSubview(languageControl)
        stack.setCustomSpacing(14, after: languageControl)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        testPillButton.target = self
        testPillButton.action = #selector(triggerDemoPill(_:))
        testPillButton.bezelStyle = .rounded
        buttonRow.addArrangedSubview(testPillButton)

        permissionButton.target = self
        permissionButton.action = #selector(openAccessibility(_:))
        permissionButton.bezelStyle = .rounded
        buttonRow.addArrangedSubview(permissionButton)

        copyButton.target = self
        copyButton.action = #selector(copyDiagnostics(_:))
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"
        buttonRow.addArrangedSubview(copyButton)

        stack.addArrangedSubview(buttonRow)

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24)
        ])

        panel.contentView = container
        window = panel
    }

    // MARK: - Language

    @objc private func languageChanged(_ sender: NSSegmentedControl) {
        language = Language(rawValue: sender.selectedSegment) ?? .spanish
        applyLanguage()
    }

    private func applyLanguage() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.2"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "3"

        let signature = SignatureVerifier.shared.result
        let granted = PermissionManager.shared.isTrusted
        let enabled = SelectionMonitor.shared.isEnabled

        switch language {
        case .spanish:
            titleLabel.stringValue = "TapCopy"
            versionLabel.stringValue = "Versión \(version) (build \(build))"
            stateLabel.stringValue = enabled ? "Estado: Activo y escuchando selecciones" : "Estado: Apagado"
            chipLabel.stringValue = "Chip: \(SignatureVerifier.hardwareDescription)"
            signatureLabel.stringValue = signature.isValid
                ? "Firma: Developer ID \(SignatureVerifier.expectedTeamIdentifier) ✓"
                : "Firma: sin verificar · Team \(signature.teamIdentifier ?? "—")"
            permissionLabel.stringValue = PermissionManager.shared.statusTextES
            testPillButton.title = "Probar píldora"
            permissionButton.title = "Abrir Accesibilidad"
            copyButton.title = "Copiar diagnóstico"
            languageControl.selectedSegment = Language.spanish.rawValue

        case .english:
            titleLabel.stringValue = "TapCopy"
            versionLabel.stringValue = "Version \(version) (build \(build))"
            stateLabel.stringValue = enabled ? "Status: Active and watching selections" : "Status: Off"
            chipLabel.stringValue = "Chip: \(SignatureVerifier.hardwareDescription)"
            signatureLabel.stringValue = signature.isValid
                ? "Signature: Developer ID \(SignatureVerifier.expectedTeamIdentifier) ✓"
                : "Signature: unverified · Team \(signature.teamIdentifier ?? "—")"
            permissionLabel.stringValue = PermissionManager.shared.statusTextEN
            testPillButton.title = "Test Pill"
            permissionButton.title = "Open Accessibility"
            copyButton.title = "Copy Diagnostics"
            languageControl.selectedSegment = Language.english.rawValue
        }

        stateLabel.textColor = enabled ? .systemGreen : .systemOrange
        permissionLabel.textColor = granted ? .systemGreen : .systemOrange
        signatureLabel.textColor = signature.isValid ? .secondaryLabelColor : .systemOrange
        permissionButton.isHidden = granted

        copyResetWorkItem?.cancel()
        copyResetWorkItem = nil
        copyButton.contentTintColor = nil
    }

    // MARK: - Actions

    @objc private func triggerDemoPill(_ sender: Any?) {
        guard let window else { return }
        let centerTop = NSPoint(x: window.frame.midX - 48, y: window.frame.midY + 60)
        TapCopyPanelController.shared.show(
            near: centerTop,
            fallbackText: "TapCopy funcionando",
            force: true
        )
    }

    @objc private func openAccessibility(_ sender: Any?) {
        PermissionManager.shared.openSystemSettings()
    }

    private func diagnosticsText() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let signature = SignatureVerifier.shared.result
        let granted = PermissionManager.shared.isTrusted
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let dockHidden = UserDefaults.standard.bool(forKey: "hideDockIcon")

        return """
        TapCopy \(version) (\(build))
        Bundle: \(Bundle.main.bundleIdentifier ?? "?")
        Path: \(Bundle.main.bundlePath)
        macOS: \(os)
        Chip: \(SignatureVerifier.hardwareDescription)
        Signature valid: \(signature.isValid)
        Team ID: \(signature.teamIdentifier ?? "none")
        Signing ID: \(signature.signingIdentifier ?? "none")
        Accessibility: \(granted ? "granted" : "pending")
        Enabled: \(SelectionMonitor.shared.isEnabled)
        Dock icon hidden: \(dockHidden)
        """
    }

    @objc private func copyDiagnostics(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticsText(), forType: .string)

        copyResetWorkItem?.cancel()
        let original = copyButton.title
        copyButton.title = (language == .spanish) ? "✓ Diagnóstico copiado" : "✓ Diagnostics copied"

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.copyButton.title = original
        }
        copyResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}
