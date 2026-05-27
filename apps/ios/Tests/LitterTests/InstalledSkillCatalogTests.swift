import XCTest
@testable import Litter

final class InstalledSkillCatalogTests: XCTestCase {
    func testNormalizeInstalledSkillLayoutFlattensCategoryWrappedSkills() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try writeSkill(named: "apple-docs", under: root.appendingPathComponent("agents", isDirectory: true))
        try writeSkill(named: "the-humanizer", under: root.appendingPathComponent("local-codex", isDirectory: true))
        try writeSkill(named: "swiftui-ui-patterns", under: root.appendingPathComponent("plugins/openai-curated", isDirectory: true))
        try writeSkill(named: "skill-installer", under: root.appendingPathComponent("system", isDirectory: true))
        try writeSkill(named: "direct-skill", under: root)

        let moved = try InstalledSkillCatalog.normalizeInstalledSkillLayout(in: root)

        XCTAssertEqual(moved, 4)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("apple-docs/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("the-humanizer/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("swiftui-ui-patterns/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".system/skill-installer/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("direct-skill/SKILL.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("agents/apple-docs/SKILL.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("system/skill-installer/SKILL.md").path))
    }

    func testNormalizeInstalledSkillLayoutMergesOverExistingDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try writeSkill(named: "apple-docs", under: root, body: "old")
        try writeSkill(named: "apple-docs", under: root.appendingPathComponent("agents", isDirectory: true), body: "new")

        let moved = try InstalledSkillCatalog.normalizeInstalledSkillLayout(in: root)

        XCTAssertEqual(moved, 1)
        let skillText = try String(contentsOf: root.appendingPathComponent("apple-docs/SKILL.md"), encoding: .utf8)
        XCTAssertTrue(skillText.contains("new"))
    }

    private func writeSkill(named name: String, under directory: URL, body: String? = nil) throws {
        let skillDirectory = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let text = body ?? """
        ---
        name: \(name)
        description: \(name) test skill
        ---
        Body
        """
        try text.write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}
