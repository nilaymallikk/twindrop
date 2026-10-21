package app.twindrop

import android.content.Intent

/**
 * Parsing of ACTION_SEND intents into the small payload that TwinDrop stores.
 * Only `text/*` is supported (docs/06 §1, SHARE-008); nothing is fetched or downloaded.
 */
object ShareIntents {
    sealed class ParseResult {
        data class Ok(val text: String, val subject: String?, val title: String?) : ParseResult()
        data class Unsupported(val reason: String) : ParseResult()
    }

    private val httpUrl = Regex("""https?://[^\s<>"'`]+""", RegexOption.IGNORE_CASE)

    /** First http(s) URL in the text, with sentence punctuation trimmed off the end. */
    fun firstHttpUrl(text: String): String? {
        val match = httpUrl.find(text) ?: return null
        return match.value.trimEnd('.', ',', ';', ':', '!', '?', ')', ']', '}', '>', '"', '\'')
    }

    fun parse(intent: Intent?): ParseResult {
        if (intent == null) return ParseResult.Unsupported("no intent")
        if (intent.action != Intent.ACTION_SEND) {
            return ParseResult.Unsupported("not ACTION_SEND")
        }
        val type = intent.type?.lowercase()
        if (type == null || !type.startsWith("text/")) {
            return ParseResult.Unsupported("mime $type")
        }
        if (intent.hasExtra(Intent.EXTRA_STREAM)) {
            return ParseResult.Unsupported("has stream")
        }
        val raw = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim()
        if (raw.isNullOrEmpty()) return ParseResult.Unsupported("empty text")
        if (raw.toByteArray(Charsets.UTF_8).size > ShareQueueStore.MAX_SHARE_BYTES) {
            return ParseResult.Unsupported("too large")
        }
        val subject = intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString()?.trim()
            ?.takeIf { it.isNotEmpty() }
        val title = intent.getCharSequenceExtra(Intent.EXTRA_TITLE)?.toString()?.trim()
            ?.takeIf { it.isNotEmpty() }
        return ParseResult.Ok(raw, subject, title)
    }

    fun isSupported(intent: Intent?): Boolean = parse(intent) is ParseResult.Ok
}
