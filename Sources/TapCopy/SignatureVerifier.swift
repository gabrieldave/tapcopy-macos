import Foundation
import Security

/// Verifies the running binary against the BLACK EYE Developer ID Team and
/// reports the real Apple Silicon chip of the host Mac (never hardcoded).
final class SignatureVerifier {

    static let shared = SignatureVerifier()
    static let expectedTeamIdentifier = "YH6W55MP95"

    struct Result {
        let isValid: Bool
        let teamIdentifier: String?
        let signingIdentifier: String?
        let isAdHocOrUnsigned: Bool
    }

    private(set) lazy var result: Result = Self.evaluate()

    // MARK: - Code signature

    private static func evaluate() -> Result {
        var dynamicCode: SecCode?
        let selfStatus = SecCodeCopySelf([], &dynamicCode)
        guard selfStatus == errSecSuccess, let dynamic = dynamicCode else {
            return Result(isValid: false, teamIdentifier: nil, signingIdentifier: nil, isAdHocOrUnsigned: true)
        }

        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(dynamic, [], &staticCode)
        guard staticStatus == errSecSuccess, let code = staticCode else {
            return Result(isValid: false, teamIdentifier: nil, signingIdentifier: nil, isAdHocOrUnsigned: true)
        }

        let flags = SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation)
        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, flags, &information)
        guard infoStatus == errSecSuccess, let info = information as? [String: Any] else {
            return Result(isValid: false, teamIdentifier: nil, signingIdentifier: nil, isAdHocOrUnsigned: true)
        }

        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        let identifier = info[kSecCodeInfoIdentifier as String] as? String
        let flagsValue = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let adHoc = (flagsValue & 0x2) != 0 // CS_ADHOC

        let valid = (team == expectedTeamIdentifier)

        // Full validity check (signature integrity and resources).
        var isValidCode = valid
        if valid {
            let check = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil)
            isValidCode = (check == errSecSuccess)
        }

        return Result(
            isValid: isValidCode,
            teamIdentifier: team,
            signingIdentifier: identifier,
            isAdHocOrUnsigned: adHoc || team == nil
        )
    }

    // MARK: - Hardware

    /// Real chip label, e.g. "Apple M4" — queried from the kernel.
    static var chipName: String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return architecture
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return architecture
        }
        let raw = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? architecture : raw
    }

    /// "arm64" / "x86_64" straight from uname(2).
    static var architecture: String {
        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else { return "unknown" }
        let mirror = Mirror(reflecting: systemInfo.machine)
        let bytes = mirror.children.reduce(into: [CChar]()) { partial, element in
            if let value = element.value as? CChar {
                partial.append(value)
            }
        }
        let terminated = bytes.isEmpty ? [CChar](repeating: 0, count: 1) : bytes
        return String(cString: terminated)
    }

    /// Human friendly hardware line used in the About window and diagnostics.
    static var hardwareDescription: String {
        "\(chipName) · \(architecture)"
    }
}
