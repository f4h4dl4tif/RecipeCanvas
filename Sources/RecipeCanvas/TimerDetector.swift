import Foundation

/// A timer suggested by the wording of a step, e.g. "bake 10–12 minutes" → 10 min.
struct DetectedTimer: Hashable, Identifiable {
    var id: String { "\(label)-\(seconds)" }
    let label: String      // the matched text, e.g. "10–12 minutes"
    let seconds: Int
}

enum TimerDetector {
    private static let regex = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?|½|an?)\s*(?:(?:–|-|to)\s*(\d+(?:[.,]\d+)?)\s*)?(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b"#,
        options: [.caseInsensitive])

    /// Finds durations in a step. Ranges use the lower bound so you check early rather than late.
    static func detect(in text: String) -> [DetectedTimer] {
        let ns = text as NSString
        var result: [DetectedTimer] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let rawNumber = ns.substring(with: match.range(at: 1)).lowercased()
            let unit = ns.substring(with: match.range(at: 3)).lowercased()
            let value: Double
            switch rawNumber {
            case "½": value = 0.5
            case "a", "an": value = 1
            default: value = Double(rawNumber.replacingOccurrences(of: ",", with: ".")) ?? 0
            }
            let multiplier: Double = unit.hasPrefix("h") ? 3600 : (unit.hasPrefix("s") ? 1 : 60)
            // "a" only counts before a spelled-out unit ("an hour"), never "a m".
            if (rawNumber == "a" || rawNumber == "an") && unit.count < 3 { continue }
            let seconds = Int(value * multiplier)
            guard seconds > 0, seconds <= 48 * 3600 else { continue }
            let timer = DetectedTimer(label: ns.substring(with: match.range), seconds: seconds)
            if !result.contains(timer) { result.append(timer) }
        }
        return result
    }

    static func format(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
