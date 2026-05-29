package com.litter.android.ui.conversation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MathMarkdownTest {
    @Test
    fun normalizesCommonInlineDelimiters() {
        val markdown = "Energy is \$E = mc^2\$ and area is \\(a^2\\)."

        assertEquals(
            "Energy is \$\$E = mc^2\$\$ and area is \$\$a^2\$\$.",
            normalizeMathMarkdown(markdown),
        )
    }

    @Test
    fun normalizesDisplayDelimiters() {
        val markdown = "Before\n\\[\n\\int_0^1 x^2 dx\n\\]\nAfter"

        assertEquals(
            "Before\n\$\$\n\\int_0^1 x^2 dx\n\$\$\nAfter",
            normalizeMathMarkdown(markdown),
        )
    }

    @Test
    fun normalizesFencedMathBlocks() {
        val markdown = "```math\n\\frac{1}{3}\n```"

        assertEquals(
            "\$\$\n\\frac{1}{3}\n\$\$",
            normalizeMathMarkdown(markdown),
        )
    }

    @Test
    fun leavesDoubleDollarMathAlone() {
        val markdown = "\$\$\n\\alpha\n\$\$"

        assertEquals(markdown, normalizeMathMarkdown(markdown))
    }

    @Test
    fun ignoresLikelyCurrency() {
        val markdown = "Costs are \$5 and \$6."

        assertEquals(markdown, normalizeMathMarkdown(markdown))
    }

    @Test
    fun detectsMathLanguages() {
        assertTrue(isMathLanguage("math"))
        assertTrue(isMathLanguage(" LaTeX "))
        assertTrue(isMathLanguage("tex"))
        assertFalse(isMathLanguage("kotlin"))
        assertFalse(isMathLanguage(null))
    }
}
