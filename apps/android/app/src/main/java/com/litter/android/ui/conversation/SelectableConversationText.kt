package com.litter.android.ui.conversation

import android.util.TypedValue
import android.text.method.LinkMovementMethod
import android.widget.TextView
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.litter.android.ui.LitterTextStyle
import com.litter.android.ui.LitterTheme
import com.litter.android.ui.LitterThemeManager
import com.litter.android.ui.LocalTextScale
import io.noties.markwon.AbstractMarkwonPlugin
import io.noties.markwon.Markwon
import io.noties.markwon.core.MarkwonTheme
import io.noties.markwon.ext.latex.JLatexMathPlugin
import io.noties.markwon.inlineparser.MarkwonInlineParserPlugin
import io.noties.markwon.syntax.SyntaxHighlightPlugin
import io.noties.prism4j.Prism4j

@Composable
internal fun SelectableConversationText(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    SelectionContainer(modifier = modifier) {
        content()
    }
}

@Composable
internal fun SelectableMarkdownText(
    text: String,
    modifier: Modifier = Modifier,
    bodySize: Float = LitterTextStyle.body,
    usePhysicalDpTextSize: Boolean = false,
    onTextViewReady: ((TextView) -> Unit)? = null,
) {
    val context = LocalContext.current
    val textScale = LocalTextScale.current
    val resolvedTextSize = bodySize * textScale
    val textColor = LitterTheme.textBody.toArgb()
    val useMono = LitterThemeManager.monoFontEnabled
    val typeface = remember(context, useMono) {
        if (useMono) {
            runCatching {
                androidx.core.content.res.ResourcesCompat.getFont(
                    context,
                    com.sigkitten.litter.android.R.font.berkeley_mono_regular,
                )
            }.getOrNull() ?: android.graphics.Typeface.MONOSPACE
        } else {
            android.graphics.Typeface.DEFAULT
        }
    }
    val markdownTextSizePx = remember(context, resolvedTextSize, usePhysicalDpTextSize) {
        resolvedTextSize.toTextSizePx(context, usePhysicalDpTextSize)
    }
    val markwon = rememberConversationMarkwon(
        context = context,
        typeface = typeface,
        markdownTextSizePx = markdownTextSizePx,
        textColor = textColor,
    )
    val markdown = remember(text) { normalizeMathMarkdown(text) }

    AndroidView(
        factory = { ctx ->
            TextView(ctx).apply {
                configureSelectableMarkdownTextView(
                    textView = this,
                    textColor = textColor,
                    linkColor = LitterTheme.accent.toArgb(),
                    textSize = resolvedTextSize,
                    typeface = typeface,
                    usePhysicalDpTextSize = usePhysicalDpTextSize,
                )
                onTextViewReady?.invoke(this)
            }
        },
        update = { tv ->
            configureSelectableMarkdownTextView(
                textView = tv,
                textColor = textColor,
                linkColor = LitterTheme.accent.toArgb(),
                textSize = resolvedTextSize,
                typeface = typeface,
                usePhysicalDpTextSize = usePhysicalDpTextSize,
            )
            markwon.setMarkdown(tv, markdown)
        },
        modifier = modifier,
    )
}

internal fun configureSelectableMarkdownTextView(
    textView: TextView,
    textColor: Int,
    linkColor: Int,
    textSize: Float,
    typeface: android.graphics.Typeface? = null,
    usePhysicalDpTextSize: Boolean = false,
) {
    textView.setTextColor(textColor)
    textView.typeface = typeface
    textView.includeFontPadding = false
    if (usePhysicalDpTextSize) {
        textView.setTextSize(TypedValue.COMPLEX_UNIT_DIP, textSize)
    } else {
        textView.textSize = textSize
    }
    textView.linksClickable = true
    textView.movementMethod = LinkMovementMethod.getInstance()
    textView.setLinkTextColor(linkColor)
    textView.setTextIsSelectable(true)
}

@Composable
private fun rememberConversationMarkwon(
    context: android.content.Context,
    typeface: android.graphics.Typeface?,
    markdownTextSizePx: Float,
    textColor: Int,
): Markwon = remember(context, typeface, markdownTextSizePx, textColor) {
    try {
        val prism4j = Prism4j(com.litter.android.ui.Prism4jGrammarLocator())
        Markwon.builder(context)
            .usePlugin(object : AbstractMarkwonPlugin() {
                override fun configureTheme(builder: MarkwonTheme.Builder) {
                    typeface?.let { builder.codeTypeface(it) }
                }
            })
            .usePlugin(
                SyntaxHighlightPlugin.create(
                    prism4j,
                    io.noties.markwon.syntax.Prism4jThemeDarkula.create(),
                ),
            )
            .usePlugin(MarkwonInlineParserPlugin.create())
            .usePlugin(
                JLatexMathPlugin.create(markdownTextSizePx, markdownTextSizePx * 1.12f) { builder ->
                    builder.inlinesEnabled(true)
                    builder.blocksEnabled(true)
                    builder.theme().textColor(textColor)
                },
            )
            .build()
    } catch (_: Exception) {
        Markwon.create(context)
    }
}

private fun Float.toTextSizePx(
    context: android.content.Context,
    usePhysicalDpTextSize: Boolean,
): Float {
    val unit = if (usePhysicalDpTextSize) {
        TypedValue.COMPLEX_UNIT_DIP
    } else {
        TypedValue.COMPLEX_UNIT_SP
    }
    return TypedValue.applyDimension(unit, this, context.resources.displayMetrics)
}
