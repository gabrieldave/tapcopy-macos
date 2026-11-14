// TapCopy v1.1.0 · License / trial window (AppKit, no SwiftUI).
// Layout mirrors docs/licensing/LICENSE_WINDOW_SPEC.md 1:1 (480 × 440 pt) and the
// five states A-E. Esc only closes the window: the NSWindow subclass below
// swallows cancelOperation so it can never trigger "Quit TapCopy" in the expired state.

import AppKit

enum LicenseState: Equatable {
    case trialActive(daysLeft: Int, day: Int)
    case trialEndingSoon(daysLeft: Int, day: Int)
    case trialExpired
    case activating
    case licensed(plan: LicensePlan, maskedKey: String)
}

enum LicensePlan: String { case personal, pro }

enum LicenseError: String, Error {
    case format, invalidKey = "invalid_key", seatLimit = "seat_limit", refunded, network
}

/// Backend seam. OpenCode implements `ActivationService` against /api/license/activate.
protocol ActivationService: AnyObject {
    func activate(key: String, completion: @escaping (Result<(LicensePlan, String), LicenseError>) -> Void)
    func deactivate(completion: @escaping (Bool) -> Void)
}

/// Esc must never reach the "Quit TapCopy" action while the trial is expired.
private final class LicensePanelWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

final class LicenseWindowController: NSObject, NSTextFieldDelegate {

    static let shared = LicenseWindowController()

    var service: ActivationService? = LicenseActivationService()
    var isSpanish = true
    var onQuit: (() -> Void)? = { NSApp.terminate(nil) }

    private enum Palette {
        static let accent = NSColor(srgbRed: 0x38 / 255.0, green: 0xBD / 255.0, blue: 0xF8 / 255.0, alpha: 1)
        static let success = NSColor(srgbRed: 0x10 / 255.0, green: 0xB9 / 255.0, blue: 0x81 / 255.0, alpha: 1)
        static let warning = NSColor.systemOrange
        static let danger = NSColor.systemRed
    }

    private enum M {
        static let size = NSSize(width: 480, height: 440)
        static let side: CGFloat = 28
        static let inner: CGFloat = 424
        static let keyPattern = #"^TCOPY-[A-Z0-9]{4}(-[A-Z0-9]{4}){0,3}$"#
        static let trialDays = 14
    }

    private var window: NSWindow?
    private var state: LicenseState = .trialActive(daysLeft: 14, day: 1)

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "TapCopy")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let card = NSView()
    private let cardLabel = NSTextField(labelWithString: "")
    private let cardValue = NSTextField(labelWithString: "")
    private let track = NSView()
    private let fill = NSView()
    private var fillWidth: NSLayoutConstraint?
    private let sectionLabel = NSTextField(labelWithString: "")
    private let keyField = NSTextField()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let buyButton = NSButton(title: "", target: nil, action: nil)
    private let secondaryButton = NSButton(title: "", target: nil, action: nil)
    private let primaryButton = NSButton(title: "", target: nil, action: nil)
    private let spinner = NSProgressIndicator()

    // MARK: - Public

    func show(_ newState: LicenseState) {
        if window == nil { buildWindow() }
        apply(newState)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        if case .licensed = newState {} else { window?.makeFirstResponder(keyField) }
    }

    static func trialState(firstLaunch: Date, now: Date = Date()) -> LicenseState {
        let elapsed = Calendar.current.dateComponents([.day], from: firstLaunch, to: now).day ?? 0
        let day = min(max(elapsed + 1, 1), M.trialDays)
        let left = M.trialDays - elapsed
        if left <= 0 { return .trialExpired }
        return left <= 3 ? .trialEndingSoon(daysLeft: left, day: day) : .trialActive(daysLeft: left, day: day)
    }

    // MARK: - Build

    private func buildWindow() {
        let win = LicensePanelWindow(contentRect: NSRect(origin: .zero, size: M.size),
                                     styleMask: [.titled, .closable, .fullSizeContentView],
                                     backing: .buffered, defer: false)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.appearance = NSAppearance(named: .darkAqua)
        win.title = t("TapCopy License", "Licencia de TapCopy")

        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: M.size))
        fx.material = .underWindowBackground
        fx.blendingMode = .behindWindow
        fx.state = .active
        win.contentView = fx

        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.alignment = .center

        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        cardLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        cardLabel.textColor = .secondaryLabelColor
        cardValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        cardValue.alignment = .right
        for v in [track, fill] { v.wantsLayer = true; v.layer?.cornerRadius = 3 }
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor

        sectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        keyField.placeholderString = "TCOPY-XXXX"
        keyField.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        keyField.bezelStyle = .roundedBezel
        keyField.focusRingType = .exterior
        keyField.delegate = self
        keyField.setAccessibilityLabel(t("License key", "Clave de licencia"))

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.maximumNumberOfLines = 2

        buyButton.isBordered = false
        buyButton.contentTintColor = Palette.accent
        buyButton.font = .systemFont(ofSize: 13, weight: .medium)
        buyButton.target = self
        buyButton.action = #selector(buyTapped)

        secondaryButton.bezelStyle = .rounded
        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryTapped)
        // Esc must only close the window (never "Quit" in the expired state): handle it with an
        // NSWindow subclass overriding cancelOperation(_:) → close(), not with a keyEquivalent here.

        primaryButton.bezelStyle = .rounded
        primaryButton.keyEquivalent = "\r"
        primaryButton.bezelColor = Palette.accent
        primaryButton.target = self
        primaryButton.action = #selector(primaryTapped)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let views: [NSView] = [iconView, titleLabel, subtitleLabel, card, sectionLabel, keyField,
                               statusLabel, buyButton, secondaryButton, primaryButton, spinner]
        views.forEach { $0.translatesAutoresizingMaskIntoConstraints = false; fx.addSubview($0) }
        [cardLabel, cardValue, track].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; card.addSubview($0) }
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)

        let fw = fill.widthAnchor.constraint(equalToConstant: 0)
        fillWidth = fw
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: fx.topAnchor, constant: 40),
            iconView.centerXAnchor.constraint(equalTo: fx.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: fx.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.centerXAnchor.constraint(equalTo: fx.centerXAnchor),

            card.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 22),
            card.leadingAnchor.constraint(equalTo: fx.leadingAnchor, constant: M.side),
            card.widthAnchor.constraint(equalToConstant: M.inner),
            card.heightAnchor.constraint(equalToConstant: 68),
            cardLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),
            cardLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            cardValue.centerYAnchor.constraint(equalTo: cardLabel.centerYAnchor),
            cardValue.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            track.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            track.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            track.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            track.heightAnchor.constraint(equalToConstant: 6),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fw,

            sectionLabel.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 22),
            sectionLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            keyField.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 8),
            keyField.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            keyField.widthAnchor.constraint(equalToConstant: M.inner),
            keyField.heightAnchor.constraint(equalToConstant: 38),
            statusLabel.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            statusLabel.widthAnchor.constraint(equalToConstant: M.inner),

            primaryButton.trailingAnchor.constraint(equalTo: fx.trailingAnchor, constant: -M.side),
            primaryButton.bottomAnchor.constraint(equalTo: fx.bottomAnchor, constant: -24),
            secondaryButton.trailingAnchor.constraint(equalTo: primaryButton.leadingAnchor, constant: -10),
            secondaryButton.centerYAnchor.constraint(equalTo: primaryButton.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: secondaryButton.leadingAnchor, constant: -10),
            spinner.centerYAnchor.constraint(equalTo: primaryButton.centerYAnchor),
            buyButton.leadingAnchor.constraint(equalTo: fx.leadingAnchor, constant: M.side),
            buyButton.centerYAnchor.constraint(equalTo: primaryButton.centerYAnchor),
        ])
        window = win
    }

    // MARK: - State

    private func apply(_ newState: LicenseState) {
        state = newState
        cardLabel.stringValue = t("FREE TRIAL", "PRUEBA GRATIS")
        sectionLabel.stringValue = t("Activate license", "Activar licencia")
        buyButton.title = t("Buy License ↗", "Comprar licencia ↗")
        statusLabel.stringValue = ""
        spinner.stopAnimation(nil)
        [keyField, secondaryButton, primaryButton, buyButton].forEach { ($0 as? NSControl)?.isEnabled = true }
        [sectionLabel, keyField, buyButton, track].forEach { $0.isHidden = false }

        switch newState {
        case let .trialActive(left, day), let .trialEndingSoon(left, day):
            let soon: Bool = { if case .trialEndingSoon = newState { return true }; return false }()
            subtitleLabel.stringValue = left == 1
                ? t("Free trial · last day", "Prueba gratis · último día")
                : String(format: t("Free trial · %d days left", "Prueba gratis · quedan %d días"), left)
            subtitleLabel.textColor = soon ? Palette.warning : .secondaryLabelColor
            setProgress(day: day, color: soon ? Palette.warning : Palette.accent)
            secondaryButton.title = t("Continue Trial", "Seguir probando")
            primaryButton.title = t("Activate", "Activar")
            validateKey()
        case .trialExpired:
            subtitleLabel.stringValue = t("Your 14-day trial has ended", "Tu prueba de 14 días terminó")
            subtitleLabel.textColor = Palette.danger
            setProgress(day: M.trialDays, color: Palette.danger)
            secondaryButton.title = t("Quit TapCopy", "Salir de TapCopy")
            primaryButton.title = t("Activate", "Activar")
            validateKey()
        case .activating:
            spinner.startAnimation(nil)
            [keyField, secondaryButton, primaryButton, buyButton].forEach { ($0 as? NSControl)?.isEnabled = false }
        case let .licensed(plan, masked):
            subtitleLabel.stringValue = plan == .pro
                ? t("Pro License · up to 3 Macs", "Licencia Pro · hasta 3 Macs")
                : t("Personal License · 1 Mac", "Licencia Personal · 1 Mac")
            subtitleLabel.textColor = Palette.success
            cardLabel.stringValue = t("KEY", "CLAVE")
            cardValue.stringValue = masked
            [sectionLabel, keyField, buyButton, track].forEach { $0.isHidden = true }
            secondaryButton.title = t("Deactivate This Mac", "Desactivar esta Mac")
            primaryButton.title = t("Done", "Listo")
        }
    }

    private func setProgress(day: Int, color: NSColor) {
        cardValue.stringValue = String(format: t("Day %d of 14", "Día %d de 14"), day)
        fill.layer?.backgroundColor = color.cgColor
        fillWidth?.constant = (M.inner - 28) * CGFloat(day) / CGFloat(M.trialDays)
    }

    private func showError(_ error: LicenseError) {
        let copy: [LicenseError: (String, String)] = [
            .format: ("Keys look like TCOPY-XXXX. Check for typos.", "Las claves tienen la forma TCOPY-XXXX. Revisa que esté bien escrita."),
            .invalidKey: ("That key isn't valid. Check it and try again.", "Esa clave no es válida. Revísala e inténtalo de nuevo."),
            .seatLimit: ("This key is already active on its maximum number of Macs.", "Esta clave ya está activa en el máximo de Macs de su plan."),
            .refunded: ("This license was refunded and is no longer active.", "Esta licencia fue reembolsada y ya no está activa."),
            .network: ("Couldn't reach the activation server. Check your connection.", "No pudimos conectar con el servidor de activación. Revisa tu conexión."),
        ]
        statusLabel.stringValue = t(copy[error]!.0, copy[error]!.1)
        statusLabel.textColor = Palette.danger
        shake(keyField)
    }

    private func shake(_ view: NSView) {
        let anim = CAKeyframeAnimation(keyPath: "position.x")
        anim.values = [0, -6, 6, -6, 6, 0].map { view.frame.midX + $0 }
        anim.duration = 0.3
        view.wantsLayer = true
        view.layer?.add(anim, forKey: "shake")
    }

    // MARK: - Key field

    func controlTextDidChange(_ obj: Notification) {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        let cleaned = String(keyField.stringValue.uppercased().unicodeScalars.filter { allowed.contains($0) })
        if cleaned != keyField.stringValue { keyField.stringValue = cleaned }
        statusLabel.stringValue = ""
        validateKey()
    }

    private var keyIsWellFormed: Bool {
        keyField.stringValue.range(of: M.keyPattern, options: .regularExpression) != nil
    }

    private func validateKey() { primaryButton.isEnabled = keyIsWellFormed }

    // MARK: - Actions

    @objc private func primaryTapped() {
        if case .licensed = state { window?.close(); return }
        guard keyIsWellFormed else { showError(.format); return }
        let previous = state
        apply(.activating)
        service?.activate(key: keyField.stringValue) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case let .success((plan, masked)):
                    self.apply(.licensed(plan: plan, maskedKey: masked))
                    self.statusLabel.stringValue = self.t("✓ License activated. Thank you!", "✓ Licencia activada. ¡Gracias!")
                    self.statusLabel.textColor = Palette.success
                case let .failure(error):
                    self.apply(previous)
                    self.showError(error)
                }
            }
        }
    }

    @objc private func secondaryTapped() {
        switch state {
        case .trialExpired: onQuit?()
        case .licensed:
            service?.deactivate { _ in }
            window?.close()
        default: window?.close()
        }
    }

    @objc private func buyTapped() {
        let path = isSpanish ? "https://tapcopy.iareal.net/es/#pricing" : "https://tapcopy.iareal.net/#pricing"
        if let url = URL(string: path) { NSWorkspace.shared.open(url) }
    }

    private func t(_ en: String, _ es: String) -> String { isSpanish ? es : en }
}

// MARK: - Backend seam

/// Bridges the window to LicenseManager (Keychain + Ed25519 + HTTPS).
final class LicenseActivationService: ActivationService {
    func activate(key: String, completion: @escaping (Result<(LicensePlan, String), LicenseError>) -> Void) {
        LicenseManager.shared.activate(key: key, completion: completion)
    }

    func deactivate(completion: @escaping (Bool) -> Void) {
        LicenseManager.shared.deactivate(completion: completion)
    }
}
