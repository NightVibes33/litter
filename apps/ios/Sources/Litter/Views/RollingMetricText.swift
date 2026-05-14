import SwiftUI

struct RollingMetricText: View {
    let text: String
    var animation: Animation = .spring(response: 0.35, dampingFraction: 0.6)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: CGFloat = 1.0

    init(_ text: String, animation: Animation = .spring(response: 0.35, dampingFraction: 0.6)) {
        self.text = text
        self.animation = animation
    }

    var body: some View {
        if reduceMotion {
            metricText
        } else {
            metricText
                .contentTransition(.numericText(value: visibleNumericValue))
                .animation(animation, value: text)
                .scaleEffect(pulse)
                .onChange(of: text) { _, _ in
                    // Quick punch up, then a softer spring back to rest so
                    // the digit visibly "thumps" when it changes instead
                    // of just sliding.
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                        pulse = 1.18
                    } completion: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                            pulse = 1.0
                        }
                    }
                }
        }
    }

    private var metricText: Text {
        Text(verbatim: text)
            .monospacedDigit()
    }

    private var visibleNumericValue: Double {
        Self.normalizedNumericValue(from: text) ?? 0
    }

    private static func normalizedNumericValue(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let duration = normalizedDurationValue(from: trimmed) {
            return duration
        }
        guard let range = trimmed.range(
            of: #"[-+]?\d[\d,]*(?:\.\d+)?"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let numberText = trimmed[range].replacingOccurrences(of: ",", with: "")
        guard let number = Double(numberText) else { return nil }
        guard range.upperBound < trimmed.endIndex else { return number }
        switch trimmed[range.upperBound] {
        case "K", "k":
            return number * 1_000
        case "M":
            return number * 1_000_000
        case "B", "b":
            return number * 1_000_000_000
        default:
            return number
        }
    }

    private static func normalizedDurationValue(from text: String) -> Double? {
        let pattern = #"[-+]?\d[\d,]*(?:\.\d+)?\s*[hms]"#
        var searchRange = text.startIndex..<text.endIndex
        var total: Double = 0
        var found = false

        while let range = text.range(of: pattern, options: .regularExpression, range: searchRange) {
            let match = text[range]
            guard let unit = match.last else { break }
            let numberText = match
                .dropLast()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: "")
            if let number = Double(numberText) {
                found = true
                switch unit {
                case "h":
                    total += number * 3_600
                case "m":
                    total += number * 60
                case "s":
                    total += number
                default:
                    break
                }
            }
            searchRange = range.upperBound..<text.endIndex
        }

        return found ? total : nil
    }
}
