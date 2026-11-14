import AppKit
import Foundation

/// Contextual entity detector, safe local math evaluator, text sanitizer, and
/// formatting utilities for TapCopy's Chameleon Pill (100% offline, $0 API cost).
enum ChameleonAnalyzer {

    enum ContextualMatch {
        case url(URL, displayLabel: String)
        case filePath(URL, displayLabel: String)
        case color(swatch: NSColor, convertedValue: String, badgeTitle: String)
        case math(formattedResult: String)
    }

    enum SearchEngine {
        case google
        case github
        case stackOverflow
    }

    enum TextTransformCase {
        case upper
        case lower
        case title
        case snake
        case camel
        case markdownBlock
    }

    // MARK: - Entity Detection

    static func detectContextualMatch(in rawText: String) -> ContextualMatch? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 1024 else { return nil }

        // Single-line checks for paths, URLs, colors, and arithmetic expressions.
        if !trimmed.contains("\n") && !trimmed.contains("\r") {
            if let colorMatch = detectColor(in: trimmed) {
                return colorMatch
            }
            if let pathMatch = detectFilePath(in: trimmed) {
                return pathMatch
            }
            if let urlMatch = detectURL(in: trimmed) {
                return urlMatch
            }
            if let mathMatch = detectMath(in: trimmed) {
                return mathMatch
            }
        }
        return nil
    }

    private static func detectFilePath(in text: String) -> ContextualMatch? {
        let prefixes = ["/Users/", "/Applications/", "/Library/", "/System/", "/Volumes/", "/tmp/", "/var/", "/opt/", "~/"]
        guard prefixes.contains(where: { text.hasPrefix($0) }) else { return nil }
        let expanded = (text as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        let fileURL = URL(fileURLWithPath: expanded)
        return .filePath(fileURL, displayLabel: "Mostrar")
    }

    private static func detectURL(in text: String) -> ContextualMatch? {
        guard !text.contains(" ") else { return nil }

        if text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") {
            if let url = URL(string: text), url.host != nil {
                return .url(url, displayLabel: "Abrir")
            }
        }

        // Bare domain like `findaro.iareal.net` or `github.com/gabrieldave` (avoid version strings like 1.0.2).
        let pattern = #"^(?:[a-zA-Z0-9-]+\.)+([a-zA-Z]{2,12})(?:/[^\s]*)?$"#
        if text.range(of: pattern, options: .regularExpression) != nil,
           let url = URL(string: "https://\(text)"),
           url.host != nil {
            return .url(url, displayLabel: "Abrir")
        }

        return nil
    }

    private static func detectColor(in text: String) -> ContextualMatch? {
        // 1. Hex color: #RGB, #RRGGBB, #RRGGBBAA
        if text.hasPrefix("#") {
            let hex = String(text.dropFirst())
            let validHex = hex.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
            if validHex {
                if hex.count == 3 {
                    let chars = Array(hex)
                    let expanded = String([chars[0], chars[0], chars[1], chars[1], chars[2], chars[2]])
                    if let val = UInt32(expanded, radix: 16) {
                        let r = Int((val >> 16) & 0xFF)
                        let g = Int((val >> 8) & 0xFF)
                        let b = Int(val & 0xFF)
                        let color = NSColor(srgbRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)
                        return .color(swatch: color, convertedValue: "rgb(\(r), \(g), \(b))", badgeTitle: "RGB")
                    }
                } else if hex.count == 6 || hex.count == 8 {
                    let rgbPart = String(hex.prefix(6))
                    if let val = UInt32(rgbPart, radix: 16) {
                        let r = Int((val >> 16) & 0xFF)
                        let g = Int((val >> 8) & 0xFF)
                        let b = Int(val & 0xFF)
                        var alpha: CGFloat = 1.0
                        var converted = "rgb(\(r), \(g), \(b))"
                        if hex.count == 8, let aVal = UInt32(hex.suffix(2), radix: 16) {
                            alpha = CGFloat(aVal) / 255.0
                            converted = String(format: "rgba(%d, %d, %d, %.2f)", r, g, b, alpha)
                        }
                        let color = NSColor(srgbRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: alpha)
                        return .color(swatch: color, convertedValue: converted, badgeTitle: "RGB")
                    }
                }
            }
        }

        // 2. rgb(r, g, b) or rgba(r, g, b, a)
        let lower = text.lowercased()
        if lower.hasPrefix("rgb(") || lower.hasPrefix("rgba("), lower.hasSuffix(")") {
            guard let openIdx = lower.firstIndex(of: "("),
                  let closeIdx = lower.lastIndex(of: ")") else { return nil }
            let inside = lower[lower.index(after: openIdx)..<closeIdx]
            let parts = inside.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 3, parts.count <= 4,
               let r = Int(parts[0]), let g = Int(parts[1]), let b = Int(parts[2]),
               (0...255).contains(r), (0...255).contains(g), (0...255).contains(b) {
                var alpha: CGFloat = 1.0
                if parts.count == 4, let aDouble = Double(parts[3]), (0.0...1.0).contains(aDouble) {
                    alpha = CGFloat(aDouble)
                }
                let color = NSColor(srgbRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: alpha)
                let hexString = String(format: "#%02X%02X%02X", r, g, b)
                return .color(swatch: color, convertedValue: hexString, badgeTitle: hexString)
            }
        }

        return nil
    }

    // MARK: - Safe Arithmetic Evaluator

    private static func detectMath(in text: String) -> ContextualMatch? {
        guard text.count <= 80 else { return nil }

        // Exclude ISO/slash dates (e.g. 2026-11-14, 14/11/2026) and phone numbers (+52 56...).
        if text.range(of: #"^\d{1,4}[-/]\d{1,2}[-/]\d{1,4}$"#, options: .regularExpression) != nil {
            return nil
        }
        if text.range(of: #"^\+\d[\d\s-]{6,}$"#, options: .regularExpression) != nil {
            return nil
        }

        var cleaned = text
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " =?"))

        guard !cleaned.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/%() ")
        guard cleaned.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

        cleaned = cleaned.replacingOccurrences(of: " ", with: "")
        var parser = MathParser(input: Array(cleaned))
        guard let value = parser.parseExpression(),
              parser.isAtEnd,
              parser.binaryOpsCount > 0,
              value.isFinite else {
            return nil
        }

        let formatted: String
        if abs(value.rounded() - value) < 1e-9 && abs(value) < 1e15 {
            formatted = String(format: "%.0f", value.rounded())
        } else {
            var str = String(format: "%.4f", value)
            while str.contains(".") && (str.hasSuffix("0") || str.hasSuffix(".")) {
                let last = str.removeLast()
                if last == "." { break }
            }
            formatted = str
        }

        return .math(formattedResult: formatted)
    }

    private struct MathParser {
        let chars: [Character]
        var pos: Int = 0
        var binaryOpsCount: Int = 0

        init(input: [Character]) {
            self.chars = input
        }

        var isAtEnd: Bool { pos == chars.count }

        mutating func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while pos < chars.count && (chars[pos] == "+" || chars[pos] == "-") {
                let op = chars[pos]
                pos += 1
                guard let rhs = parseTerm() else { return nil }
                binaryOpsCount += 1
                lhs = (op == "+") ? (lhs + rhs) : (lhs - rhs)
            }
            return lhs
        }

        mutating func parseTerm() -> Double? {
            guard var lhs = parseFactor() else { return nil }
            while pos < chars.count && (chars[pos] == "*" || chars[pos] == "/" || chars[pos] == "%") {
                let op = chars[pos]
                pos += 1
                guard let rhs = parseFactor() else { return nil }
                binaryOpsCount += 1
                if op == "*" {
                    lhs *= rhs
                } else if op == "/" {
                    guard abs(rhs) > 1e-12 else { return nil }
                    lhs /= rhs
                } else {
                    guard abs(rhs) > 1e-12 else { return nil }
                    lhs = lhs.truncatingRemainder(dividingBy: rhs)
                }
            }
            return lhs
        }

        mutating func parseFactor() -> Double? {
            guard pos < chars.count else { return nil }
            if chars[pos] == "+" {
                pos += 1
                return parseFactor()
            }
            if chars[pos] == "-" {
                pos += 1
                guard let val = parseFactor() else { return nil }
                return -val
            }
            if chars[pos] == "(" {
                pos += 1
                guard let inner = parseExpression(), pos < chars.count, chars[pos] == ")" else {
                    return nil
                }
                pos += 1
                return inner
            }
            let start = pos
            var dotCount = 0
            while pos < chars.count && (chars[pos].isNumber || chars[pos] == ".") {
                if chars[pos] == "." { dotCount += 1 }
                pos += 1
            }
            guard pos > start, dotCount <= 1 else { return nil }
            return Double(String(chars[start..<pos]))
        }
    }

    // MARK: - Text Sanitation & Transforms

    static func sanitizedPlainText(_ rawText: String) -> String {
        var text = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{00AD}", with: "")

        let lines = text.components(separatedBy: "\n").map { line -> String in
            line.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
        }
        text = lines.joined(separator: "\n")
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func transform(_ rawText: String, mode: TextTransformCase) -> String {
        let clean = sanitizedPlainText(rawText)
        switch mode {
        case .upper:
            return clean.uppercased()
        case .lower:
            return clean.lowercased()
        case .title:
            return clean.localizedCapitalized
        case .snake:
            return splitWords(clean).map { $0.lowercased() }.joined(separator: "_")
        case .camel:
            let words = splitWords(clean)
            guard let first = words.first else { return clean }
            let tail = words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            return first.lowercased() + tail.joined()
        case .markdownBlock:
            if clean.contains("\n") {
                return "```\n\(clean)\n```"
            } else {
                return "`\(clean)`"
            }
        }
    }

    private static func splitWords(_ input: String) -> [String] {
        let spaced = input.replacingOccurrences(
            of: #"([a-z0-9])([A-Z])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        let parts = spaced.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return parts.filter { !$0.isEmpty }
    }

    static func statsLine(for rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let chars = trimmed.count
        let words = trimmed.split { $0.isWhitespace || $0.isNewline }.count
        return "\(words) palabras · \(chars) caracteres"
    }

    static func looksLikeCode(_ rawText: String) -> Bool {
        let markers = ["func ", "let ", "var ", "const ", "import ", "return ", "=>", "->", "{", "}", "def ", "class ", "SELECT ", "#include"]
        return markers.contains { rawText.contains($0) }
    }

    static func searchURL(for rawText: String, engine: SearchEngine) -> URL? {
        let query = String(sanitizedPlainText(rawText).prefix(320))
        guard !query.isEmpty else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#/")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        switch engine {
        case .google:
            return URL(string: "https://www.google.com/search?q=\(encoded)")
        case .github:
            return URL(string: "https://github.com/search?q=\(encoded)&type=code")
        case .stackOverflow:
            return URL(string: "https://stackoverflow.com/search?q=\(encoded)")
        }
    }
}
