import Foundation

struct BuildArtifact: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case unsignedIPA

        var title: String {
            switch self {
            case .unsignedIPA: return "Unsigned IPA"
            }
        }
    }

    var id: String { path }
    var path: String
    var kind: Kind

    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

enum BuildArtifactDetector {
    private static let ipaPattern = #"(?:^|[\s>])((?:/root|/tmp|/var/tmp|/mnt/apps|/usr/local)[^\s\"'<>|;]*?\.ipa)"#

    static func ipaArtifacts(in text: String?) -> [BuildArtifact] {
        guard let text, !text.isEmpty,
              let regex = try? NSRegularExpression(pattern: ipaPattern) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            let cleaned = stripTrailingPunctuation(String(text[range]))
            guard cleaned.hasSuffix(".ipa"), seen.insert(cleaned).inserted else { return nil }
            return BuildArtifact(path: cleaned, kind: .unsignedIPA)
        }
    }

    private static func stripTrailingPunctuation(_ value: String) -> String {
        var output = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = output.last, [".", ",", ")", "]", "}"].contains(String(last)) {
            output.removeLast()
        }
        return output
    }
}
