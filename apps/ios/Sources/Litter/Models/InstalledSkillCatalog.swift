import Foundation

enum InstalledSkillCatalog {
    private static let configHeader = "[[skills.config]]"

    static var codexHomeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("codex", isDirectory: true)
    }

    static var skillsURL: URL {
        codexHomeURL.appendingPathComponent("skills", isDirectory: true)
    }

    static var configURL: URL {
        codexHomeURL.appendingPathComponent("config.toml", isDirectory: false)
    }

    static func installedUserSkills() -> [SkillMetadata] {
        let fm = FileManager.default
        try? fm.createDirectory(at: skillsURL, withIntermediateDirectories: true)
        guard let enumerator = fm.enumerator(
            at: skillsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var skills: [SkillMetadata] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == "SKILL.md" else { continue }
            guard !isSystemSkill(fileURL) else { continue }
            guard let skill = skillMetadata(from: fileURL) else { continue }
            skills.append(skill)
        }
        return skills
    }

    static func merge(serverSkills: [SkillMetadata]) -> [SkillMetadata] {
        var merged = serverSkills
        var seen = Set(serverSkills.map { stableIdentity(for: $0) })
        for skill in installedUserSkills() {
            guard seen.insert(stableIdentity(for: skill)).inserted else { continue }
            merged.append(skill)
        }
        return merged.sorted { lhs, rhs in
            let left = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if left == .orderedSame {
                return lhs.path.value.localizedCaseInsensitiveCompare(rhs.path.value) == .orderedAscending
            }
            return left == .orderedAscending
        }
    }



    static func localModelSkillContext(maxSkills: Int = 12, maxCharacters: Int = 24_000) -> String {
        let enabledSkills = installedUserSkills().filter(\.enabled).prefix(maxSkills)
        var sections: [String] = []
        var remaining = maxCharacters
        for skill in enabledSkills where remaining > 0 {
            let body = (try? String(contentsOfFile: skill.path.value, encoding: .utf8)) ?? ""
            let cappedBody = String(body.prefix(max(0, min(remaining, 4_000))))
            let section = """
            --- skill: \(skill.name) ---
            Description: \(skill.description)
            Path: \(skill.path.value)
            Instructions:
            \(cappedBody)
            """
            sections.append(section)
            remaining -= section.count
        }
        return sections.joined(separator: "\n\n")
    }

    static func withEnabled(_ skill: SkillMetadata, enabled: Bool) -> SkillMetadata {
        SkillMetadata(
            name: skill.name,
            description: skill.description,
            shortDescription: skill.shortDescription,
            interface: skill.interface,
            dependencies: skill.dependencies,
            path: skill.path,
            scope: skill.scope,
            enabled: enabled
        )
    }

    static func setEnabled(_ skill: SkillMetadata, enabled: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: codexHomeURL, withIntermediateDirectories: true)
        let path = skill.path.value
        let equivalentPaths = equivalentSkillPaths(for: path)
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let pruned = removeSkillConfigBlocks(
            from: existing,
            matchingPaths: equivalentPaths,
            matchingNames: [skill.name.lowercased()]
        )
        var next = pruned.trimmingCharacters(in: .whitespacesAndNewlines)
        if !next.isEmpty {
            next += "\n\n"
        }
        next += """
        \(configHeader)
        name = \(tomlString(skill.name))
        path = \(tomlString(path))
        enabled = \(enabled ? "true" : "false")

        """
        try next.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func skillMetadata(from fileURL: URL) -> SkillMetadata? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let metadata = frontMatterFields(in: text)
        let fallbackName = fileURL.deletingLastPathComponent().lastPathComponent
        let name = clean(metadata["name"]) ?? fallbackName
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let description = clean(metadata["description"]) ?? fallbackDescription(in: text)
        let enabled = enabledOverride(forName: name, path: fileURL.path) ?? true
        return SkillMetadata(
            name: name,
            description: description,
            shortDescription: nil,
            interface: nil,
            dependencies: nil,
            path: AbsolutePath(value: fileURL.path),
            scope: .user,
            enabled: enabled
        )
    }

    private static func frontMatterFields(in text: String) -> [String: String] {
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return [:]
        }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" { break }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty {
                fields[key] = value
            }
        }
        return fields
    }

    private static func fallbackDescription(in text: String) -> String {
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, line != "---", !line.hasPrefix("#") else { continue }
            return line
        }
        return "Installed user skill"
    }

    private static func clean(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.count >= 2,
           let first = value.first,
           let last = value.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            value.removeFirst()
            value.removeLast()
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func enabledOverride(forName name: String, path: String) -> Bool? {
        let equivalentPaths = equivalentSkillPaths(for: path)
        let normalizedName = name.lowercased()
        let config = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        for block in skillConfigBlocks(in: config) {
            let blockPath = tomlValue(named: "path", in: block)
            let blockName = tomlValue(named: "name", in: block)?.lowercased()
            guard blockPath.map(equivalentPaths.contains) == true || blockName == normalizedName else {
                continue
            }
            guard let enabled = tomlValue(named: "enabled", in: block)?.lowercased() else {
                continue
            }
            if enabled == "true" { return true }
            if enabled == "false" { return false }
        }
        return nil
    }

    private static func removeSkillConfigBlocks(
        from config: String,
        matchingPaths paths: Set<String>,
        matchingNames names: Set<String>
    ) -> String {
        let lines = config.components(separatedBy: "\n")
        var output: [String] = []
        var index = 0
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == configHeader {
                var block: [String] = []
                repeat {
                    block.append(lines[index])
                    index += 1
                } while index < lines.count && !lines[index].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")

                let blockPath = tomlValue(named: "path", in: block)
                let blockName = tomlValue(named: "name", in: block)?.lowercased()
                if blockPath.map(paths.contains) == true || blockName.map(names.contains) == true {
                    continue
                }
                output.append(contentsOf: block)
                continue
            }
            output.append(lines[index])
            index += 1
        }
        return output.joined(separator: "\n")
    }

    private static func skillConfigBlocks(in config: String) -> [[String]] {
        let lines = config.components(separatedBy: "\n")
        var blocks: [[String]] = []
        var index = 0
        while index < lines.count {
            guard lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == configHeader else {
                index += 1
                continue
            }
            var block: [String] = []
            repeat {
                block.append(lines[index])
                index += 1
            } while index < lines.count && !lines[index].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")
            blocks.append(block)
        }
        return blocks
    }

    private static func tomlValue(named key: String, in block: [String]) -> String? {
        for line in block {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines) == key else { continue }
            return clean(String(parts[1]))
        }
        return nil
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }


    private static func equivalentSkillPaths(for path: String) -> Set<String> {
        Set([path, fakefsPathEquivalent(forSkillPath: path), nativePathEquivalent(forSkillPath: path)].compactMap { $0 })
    }

    private static func nativePathEquivalent(forSkillPath path: String) -> String? {
        let fakefsRoot = "/root/.codex/skills"
        guard path == fakefsRoot || path.hasPrefix(fakefsRoot + "/") else { return nil }
        let relative = String(path.dropFirst(fakefsRoot.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return skillsURL.path }
        return skillsURL.appendingPathComponent(relative).path
    }

    private static func fakefsPathEquivalent(forSkillPath path: String) -> String? {
        let root = skillsURL.path
        guard path == root || path.hasPrefix(root + "/") else { return nil }
        let relative = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return "/root/.codex/skills" }
        return "/root/.codex/skills/\(relative)"
    }

    private static func stableIdentity(for skill: SkillMetadata) -> String {
        if let fakefsPath = fakefsPathEquivalent(forSkillPath: skill.path.value) {
            return fakefsPath.lowercased()
        }
        return skill.path.value.lowercased()
    }

    private static func isSystemSkill(_ fileURL: URL) -> Bool {
        fileURL.pathComponents.contains(".system")
    }
}
