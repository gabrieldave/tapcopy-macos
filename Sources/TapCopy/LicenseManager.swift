import AppKit
import CryptoKit
import Foundation
import Security

/// TapCopy v1.1.1 — licensing, 14-day trial clock and seat activation.
///
/// Everything is stored in the Keychain so deleting UserDefaults never resets
/// the trial. Selected text is never part of any request: the only fields that
/// ever leave the Mac are the license key, the device hash and the app version.
///
/// Layer 3: the trial has two locks — a monotonic local anchor (`lastSeen`,
/// NTP tolerance 300 s) and a server-side `hardware_trials` record keyed by the
/// per-Mac device hash. Moving the system clock backwards flips the UI into
/// `.clockTampered` instead of extending the trial.
final class LicenseManager {

    static let shared = LicenseManager()

    // Ed25519 public key of the TapCopy license/update authority (private key never ships).
    static let publicKeyBase64 = "PrRbyej/Mh3eBuWAHeMNNrhzPycyApt/BD7TINebGUg="

    static let trialDays = 14
    static let baseURL = URL(string: "https://tapcopy.iareal.net")!
    static let clockDriftTolerance: TimeInterval = 300

    private enum Keys {
        static let trial = "net.iareal.tapcopy.trial"
        static let license = "net.iareal.tapcopy.license"
        static let trialStartField = "firstLaunch"
        static let lastSeenField = "lastSeen"
        static let remoteSyncField = "lastRemoteSync"
        static let reminder = "net.iareal.tapcopy.reminder"
    }

    static let licenseChanged = Notification.Name("TapCopyLicenseChanged")

    private(set) var storedToken: String?
    private(set) var isClockTampered = false
    private var clockTimer: Timer?

    private init() {
        storedToken = Keychain.string(service: Keys.license, account: "token")
    }

    // MARK: - Device identity

    /// Stable per-Mac identifier: SHA-256(IOPlatformUUID + fixed salt). Never reversible.
    lazy var deviceId: String = {
        let platform = Self.ioPlatformUUID() ?? "unknown"
        let salted = platform + "tapcopy-iareal-2026"
        let digest = SHA256.hash(data: Data(salted.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }()

    private static func ioPlatformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String
        return value
    }

    var macName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    // MARK: - Trial clock (local monotonic anchor)

    /// Installs the 5-minute heartbeat and validates the anchors at launch.
    func startClock() {
        updateTrialAnchors(now: Date())
        guard clockTimer == nil else { return }
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            self?.updateTrialAnchors(now: Date())
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    /// Waking from sleep may jump the clock: re-validate and re-anchor.
    func handleWake() {
        updateTrialAnchors(now: Date())
        syncTrialIfNeeded()
    }

    /// First launch is written to the Keychain on the very first read.
    private func trialStartDate(now: Date = Date()) -> Date {
        if let raw = Keychain.string(service: Keys.trial, account: Keys.trialStartField),
           let timestamp = TimeInterval(raw) {
            return Date(timeIntervalSince1970: timestamp)
        }
        let first = now
        Keychain.set(String(first.timeIntervalSince1970), service: Keys.trial, account: Keys.trialStartField)
        return first
    }

    private var trialStart: Date { trialStartDate() }

    private var storedLastSeen: TimeInterval {
        guard let raw = Keychain.string(service: Keys.trial, account: Keys.lastSeenField),
              let value = TimeInterval(raw) else { return 0 }
        return value
    }

    /// Monotonic guard: a clock that travels backwards more than the NTP
    /// tolerance (300 s) marks the trial as tampered and never rewinds lastSeen.
    private func updateTrialAnchors(now: Date) {
        let first = trialStartDate(now: now).timeIntervalSince1970
        let previous = storedLastSeen
        let current = now.timeIntervalSince1970

        let behindFirst = current < first - Self.clockDriftTolerance
        let behindLast = previous > 0 && current < previous - Self.clockDriftTolerance
        let tampered = behindFirst || behindLast

        if tampered != isClockTampered {
            TapLog.log("Trial clock tamper state: \(tampered)")
        }
        isClockTampered = tampered

        if !tampered {
            let next = max(previous, current)
            Keychain.set(String(next), service: Keys.trial, account: Keys.lastSeenField)
        }
    }

    var trialDay: Int {
        let elapsed = Calendar.current.dateComponents([.day], from: trialStart, to: Date()).day ?? 0
        return min(max(elapsed + 1, 1), Self.trialDays)
    }

    var trialDaysLeft: Int {
        let elapsed = Calendar.current.dateComponents([.day], from: trialStart, to: Date()).day ?? 0
        return max(Self.trialDays - elapsed, 0)
    }

    var trialExpired: Bool { trialDaysLeft <= 0 }

    // MARK: - License state

    struct License {
        let key: String
        let plan: LicensePlan
        let seats: Int
        let issuedAt: Date
    }

    var currentLicense: License? {
        guard let token = storedToken else { return nil }
        return Self.verify(token: token)
    }

    var isLicensed: Bool { currentLicense != nil }

    /// The pill is only allowed while a valid license exists or the trial is
    /// alive and the clock has not been moved backwards.
    var canUseApp: Bool { isLicensed || (!isClockTampered && !trialExpired) }

    var maskedKey: String {
        guard let key = currentLicense?.key else { return "" }
        let tail = key.suffix(4)
        return "TCOPY-••••-••••-\(tail)"
    }

    func windowState() -> LicenseState {
        if let license = currentLicense {
            return .licensed(plan: license.plan, maskedKey: maskedKey)
        }
        if isClockTampered { return .clockTampered }
        if trialExpired { return .trialExpired }
        let left = trialDaysLeft
        return left <= 3
            ? .trialEndingSoon(daysLeft: left, day: trialDay)
            : .trialActive(daysLeft: left, day: trialDay)
    }

    // MARK: - Remote anchor (hardware_trials)

    /// At launch (unlicensed) and at most every 12 h, ask the server for the
    /// first time this device was ever seen. Fail-open on a first offline run.
    func syncTrialIfNeeded() {
        guard !isLicensed else { return }
        let now = Date().timeIntervalSince1970
        let lastSync = TimeInterval(Keychain.string(service: Keys.trial, account: Keys.remoteSyncField) ?? "") ?? 0
        guard now - lastSync > 43_200 else { return }
        Keychain.set(String(now), service: Keys.trial, account: Keys.remoteSyncField)

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/trial/sync"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "deviceId": deviceId,
            "appVersion": Self.localVersion.version,
        ])

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data,
                  let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let serverFirstSeen = Self.epoch(payload["firstSeen"]),
                  let serverNow = Self.epoch(payload["serverNow"]) else {
                return
            }
            DispatchQueue.main.async {
                let localFirst = self.trialStart.timeIntervalSince1970
                let effectiveFirst = min(localFirst, serverFirstSeen)
                Keychain.set(String(effectiveFirst), service: Keys.trial, account: Keys.trialStartField)

                let localLast = self.storedLastSeen
                let nextLast = max(localLast, serverNow)
                Keychain.set(String(nextLast), service: Keys.trial, account: Keys.lastSeenField)

                let current = Date().timeIntervalSince1970
                let tampered = current < effectiveFirst - Self.clockDriftTolerance
                    || current < nextLast - Self.clockDriftTolerance
                if tampered != self.isClockTampered {
                    TapLog.log("Trial clock tamper state after sync: \(tampered)")
                }
                self.isClockTampered = tampered

                TapLog.log("Trial synced: firstSeen=\(Int(effectiveFirst)) serverNow=\(Int(serverNow)) day=\(self.trialDay)")
                NotificationCenter.default.post(name: Self.licenseChanged, object: nil)
                if !self.canUseApp {
                    LicenseWindowController.shared.show(self.windowState())
                }
            }
        }.resume()
    }

    private static func epoch(_ value: Any?) -> TimeInterval? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        if let int = value as? Int { return TimeInterval(int) }
        if let string = value as? String, let double = Double(string) { return double }
        return nil
    }

    // MARK: - Activation

    func activate(key: String, completion: @escaping (Result<(LicensePlan, String), LicenseError>) -> Void) {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.range(of: #"^TCOPY-[A-Z0-9]{4}(-[A-Z0-9]{4}){2}$"#, options: .regularExpression) != nil else {
            completion(.failure(.format))
            return
        }

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/license/activate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "key": normalized,
            "deviceId": deviceId,
            "macName": macName
        ])

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil {
                    completion(.failure(.network))
                    return
                }
                guard let http = response as? HTTPURLResponse, let data else {
                    completion(.failure(.network))
                    return
                }
                let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                guard http.statusCode == 200,
                      let token = payload["token"] as? String,
                      let license = Self.verify(token: token),
                      license.key == normalized else {
                    let serverError = (payload["error"] as? String) ?? ""
                    completion(.failure(LicenseError(rawValue: serverError) ?? .invalidKey))
                    return
                }
                Keychain.set(token, service: Keys.license, account: "token")
                self.storedToken = token
                NotificationCenter.default.post(name: Self.licenseChanged, object: nil)
                completion(.success((license.plan, self.maskedKey)))
            }
        }.resume()
    }

    func deactivate(completion: @escaping (Bool) -> Void) {
        guard let license = currentLicense else {
            clearLocalLicense()
            completion(true)
            return
        }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/license/deactivate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "key": license.key,
            "deviceId": deviceId
        ])

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                let http = response as? HTTPURLResponse
                let ok = error == nil && (http?.statusCode == 200 || http?.statusCode == 404)
                if ok { self?.clearLocalLicense() }
                completion(ok)
            }
        }.resume()
    }

    private func clearLocalLicense() {
        Keychain.remove(service: Keys.license, account: "token")
        storedToken = nil
        NotificationCenter.default.post(name: Self.licenseChanged, object: nil)
    }

    // MARK: - Token verification

    /// Verifies the Ed25519 signature over the server payload and checks the device binding.
    static func verify(token: String) -> License? {
        let parts = token.split(separator: ".")
        guard parts.count == 2,
              let payloadData = Data(base64URLEncoded: String(parts[0])),
              let signatureData = Data(base64URLEncoded: String(parts[1])),
              let publicData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicData),
              publicKey.isValidSignature(signatureData, for: payloadData),
              let payload = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any],
              let key = payload["key"] as? String,
              let planRaw = payload["plan"] as? String,
              let plan = LicensePlan(rawValue: planRaw),
              let seats = payload["seats"] as? Int,
              let device = payload["deviceId"] as? String else {
            return nil
        }
        guard device == LicenseManager.shared.deviceId else { return nil }
        let issued = (payload["iat"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? Date()
        return License(key: key, plan: plan, seats: seats, issuedAt: issued)
    }

    // MARK: - Gentle day 11-14 reminder

    /// Shows the license window at most once per day, only when TapCopy has been
    /// completely idle for at least 2 seconds and no pill is on screen.
    func showReminderIfDue(isIdle: Bool) {
        guard !isLicensed, !isClockTampered, trialDaysLeft <= 3, isIdle,
              !TapCopyPanelController.shared.isVisible else { return }
        let today = ISO8601DateFormatter.string(
            from: Date(),
            timeZone: .current,
            formatOptions: [.withFullDate]
        )
        if Keychain.string(service: Keys.reminder, account: "last") == today { return }
        Keychain.set(today, service: Keys.reminder, account: "last")
        DispatchQueue.main.async {
            LicenseWindowController.shared.show(LicenseManager.shared.windowState())
        }
    }

    // MARK: - Updates

    static var localVersion: (version: String, build: Int) {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = Int(info["CFBundleVersion"] as? String ?? "0") ?? 0
        return (version, build)
    }
}

// MARK: - Keychain helpers

enum Keychain {
    /// `ThisDeviceOnly`: the trial and the license never travel through iCloud
    /// Keychain or an encrypted backup to a different Mac.
    static func set(_ value: String, service: String, account: String) {
        remove(service: service, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Reads legacy entries created by v1.1.0 (any accessibility class): the
    /// next write migrates them to ThisDeviceOnly without losing dates/tokens.
    static func string(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        self.init(base64Encoded: base64)
    }
}
