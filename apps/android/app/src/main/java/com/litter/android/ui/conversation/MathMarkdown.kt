package com.litter.android.ui.conversation

internal fun normalizeMathMarkdown(markdown: String): String {
    if (!markdown.mayContainMath()) {
        return markdown
    }

    return markdown
        .replaceFencedMathBlocks()
        .replaceDisplayMathDelimiters()
        .replaceInlineParenMathDelimiters()
        .replaceSingleDollarInlineMath()
}

internal fun isMathLanguage(language: String?): Boolean =
    when (language?.trim()?.lowercase()) {
        "math", "latex", "tex" -> true
        else -> false
    }

internal fun mathMarkdownBlock(latex: String): String {
    val trimmed = latex.trim()
    return if (trimmed.isEmpty()) "" else "$MathDelimiter\n$trimmed\n$MathDelimiter"
}

private fun String.mayContainMath(): Boolean =
    contains('$') || contains("\\[") || contains("\\(") || contains("```")

private fun String.replaceFencedMathBlocks(): String =
    FencedMathBlockRegex.replace(this) { match ->
        mathMarkdownBlock(match.groupValues[2])
    }

private fun String.replaceDisplayMathDelimiters(): String =
    DisplayMathRegex.replace(this) { match ->
        mathMarkdownBlock(match.groupValues[1])
    }

private fun String.replaceInlineParenMathDelimiters(): String =
    InlineParenMathRegex.replace(this) { match ->
        "$MathDelimiter${match.groupValues[1].trim()}$MathDelimiter"
    }

private fun String.replaceSingleDollarInlineMath(): String {
    val builder = StringBuilder(length)
    var index = 0
    while (index < length) {
        val start = findSingleDollar(index, opening = true) ?: break
        val end = findSingleDollar(start + 1, opening = false) ?: break
        builder.append(this, index, start)
        builder.append(MathDelimiter)
        builder.append(this, start + 1, end)
        builder.append(MathDelimiter)
        index = end + 1
    }
    if (index == 0) {
        return this
    }
    builder.append(this, index, length)
    return builder.toString()
}

private fun String.findSingleDollar(fromIndex: Int, opening: Boolean): Int? {
    var index = fromIndex
    while (index < length) {
        if (this[index] == '$' && isSingleDollarMathDelimiter(index, opening)) {
            return index
        }
        index += 1
    }
    return null
}

private fun String.isSingleDollarMathDelimiter(index: Int, opening: Boolean): Boolean {
    if (isEscaped(index) || hasAdjacentDollar(index)) {
        return false
    }
    return if (opening) {
        val next = getOrNull(index + 1)
        next != null && !next.isWhitespace() && !next.isDigit()
    } else {
        val previous = getOrNull(index - 1)
        previous != null && !previous.isWhitespace()
    }
}

private fun String.isEscaped(index: Int): Boolean {
    var slashCount = 0
    var cursor = index - 1
    while (cursor >= 0 && this[cursor] == '\\') {
        slashCount += 1
        cursor -= 1
    }
    return slashCount % 2 == 1
}

private fun String.hasAdjacentDollar(index: Int): Boolean =
    getOrNull(index - 1) == '$' || getOrNull(index + 1) == '$'

private const val MathDelimiter = "\$\$"

private val FencedMathBlockRegex = Regex(
    pattern = "(?ms)^```[ \\t]*(math|latex|tex)[^\\n]*\\n(.*?)\\n```[ \\t]*$",
    options = setOf(RegexOption.MULTILINE),
)

private val DisplayMathRegex = Regex(
    pattern = "\\\\\\[(.*?)\\\\\\]",
    options = setOf(RegexOption.DOT_MATCHES_ALL),
)

private val InlineParenMathRegex = Regex(
    pattern = "\\\\\\((.*?)\\\\\\)",
    options = setOf(RegexOption.DOT_MATCHES_ALL),
)
