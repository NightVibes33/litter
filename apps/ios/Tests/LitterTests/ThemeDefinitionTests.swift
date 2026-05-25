import XCTest
@testable import Litter

final class ThemeDefinitionTests: XCTestCase {
    func testThemeDefinitionIgnoresNullAndNonStringColorEntries() throws {
        let data = Data(
            """
            {
              "name": "night-owl",
              "type": "dark",
              "colors": {
                "editor.background": "#011627",
                "editor.findRangeHighlightBackground": null,
                "editor.foreground": "#d6deeb",
                "symbolIcon.constantForeground": ["#79c0ff", "#d2a8ff"]
              }
            }
            """.utf8
        )

        let theme = try JSONDecoder().decode(ThemeDefinition.self, from: data)

        XCTAssertEqual(theme.colors["editor.background"], "#011627")
        XCTAssertEqual(theme.colors["editor.foreground"], "#d6deeb")
        XCTAssertNil(theme.colors["editor.findRangeHighlightBackground"])
        XCTAssertNil(theme.colors["symbolIcon.constantForeground"])
    }

    func testThemeDefinitionStripsAlphaFromEightDigitHex() throws {
        let data = Data(
            """
            {
              "name": "alpha-theme",
              "type": "dark",
              "colors": {
                "button.background": "#7e57c2cc",
                "editor.background": "#011627"
              }
            }
            """.utf8
        )

        let theme = try JSONDecoder().decode(ThemeDefinition.self, from: data)

        // 8-digit #RRGGBBAA is sanitized to 6-digit #RRGGBB at decode time
        // so downstream color helpers see a well-formed RGB string.
        XCTAssertEqual(theme.colors["button.background"], "#7e57c2")
        XCTAssertEqual(theme.colors["editor.background"], "#011627")
    }
}
