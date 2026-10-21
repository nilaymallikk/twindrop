package app.twindrop

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

/**
 * Durable native share queue (docs/06 §1 "Persist locally first").
 *
 * The share receiver commits here before doing anything else. Dart imports the
 * queue into the core database and acks the ids; the import must be idempotent
 * because the same item can be read twice after a process death.
 *
 * Storage: one SharedPreferences file, JSON array. Values are written with
 * `commit()` so the payload is on disk before the panel starts.
 */
object ShareQueueStore {
    private const val FILE = "twindrop_share_queue"
    private const val KEY_QUEUE = "queue"
    private const val KEY_LAST_HASH = "last.hash"
    private const val KEY_LAST_AT = "last.at"
    private const val KEY_LAST_ID = "last.id"

    /** docs/06: identical URL text within 10 s is one item. */
    const val DEDUPE_WINDOW_MS = 10_000L

    /** Notes may be up to 256 KiB (docs/08); refuse bigger shares instead of truncating. */
    const val MAX_SHARE_BYTES = 256 * 1024

    data class ShareItem(
        val shareId: String,
        val text: String,
        val subject: String?,
        val title: String?,
        val sourcePackage: String?,
        val receivedAtMs: Long,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "shareId" to shareId,
            "text" to text,
            "subject" to subject,
            "title" to title,
            "sourcePackage" to sourcePackage,
            "receivedAtMs" to receivedAtMs,
        )

        fun toJson(): JSONObject = JSONObject()
            .put("shareId", shareId)
            .put("text", text)
            .put("subject", subject)
            .put("title", title)
            .put("sourcePackage", sourcePackage)
            .put("receivedAtMs", receivedAtMs)
    }

    data class EnqueueResult(
        val item: ShareItem,
        val duplicate: Boolean,
        val alreadyImported: Boolean,
    )

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** Fingerprint of the URL when the payload is a URL, else of the trimmed text. */
    private fun fingerprint(text: String): String {
        val url = ShareIntents.firstHttpUrl(text) ?: text.trim()
        val digest = MessageDigest.getInstance("SHA-256").digest(url.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    @Synchronized
    fun enqueue(
        context: Context,
        text: String,
        subject: String?,
        title: String?,
        sourcePackage: String?,
    ): EnqueueResult? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null
        val p = prefs(context)
        val now = System.currentTimeMillis()
        val hash = fingerprint(trimmed)
        val lastHash = p.getString(KEY_LAST_HASH, null)
        val lastAt = p.getLong(KEY_LAST_AT, 0L)
        val lastId = p.getString(KEY_LAST_ID, null)

        if (lastHash == hash && lastId != null && lastAt > 0L && now - lastAt in 0..DEDUPE_WINDOW_MS) {
            val pending = readPendingLocked(p).firstOrNull { it.shareId == lastId }
            if (pending != null) {
                return EnqueueResult(pending, duplicate = true, alreadyImported = false)
            }
            // Same payload within the window but the item was already imported/acked.
            val previous = ShareItem(
                shareId = lastId,
                text = trimmed,
                subject = subject?.trim(),
                title = title?.trim(),
                sourcePackage = sourcePackage,
                receivedAtMs = lastAt,
            )
            return EnqueueResult(previous, duplicate = true, alreadyImported = true)
        }

        val item = ShareItem(
            shareId = UUID.randomUUID().toString(),
            text = trimmed,
            subject = subject?.trim()?.takeIf { it.isNotEmpty() },
            title = title?.trim()?.takeIf { it.isNotEmpty() },
            sourcePackage = sourcePackage,
            receivedAtMs = now,
        )
        val queue = readPendingLocked(p).toMutableList()
        queue.add(item)
        p.edit()
            .putString(KEY_QUEUE, JSONArray().apply { queue.forEach { put(it.toJson()) } }.toString())
            .putString(KEY_LAST_HASH, hash)
            .putLong(KEY_LAST_AT, now)
            .putString(KEY_LAST_ID, item.shareId)
            .commit()
        return EnqueueResult(item, duplicate = false, alreadyImported = false)
    }

    @Synchronized
    fun readPending(context: Context): List<ShareItem> = readPendingLocked(prefs(context))

    private fun readPendingLocked(
        p: android.content.SharedPreferences,
    ): List<ShareItem> {
        val raw = p.getString(KEY_QUEUE, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            val items = ArrayList<ShareItem>(array.length())
            for (i in 0 until array.length()) {
                val o = array.optJSONObject(i) ?: continue
                val id = o.optString("shareId", "")
                val text = o.optString("text", "")
                if (id.isEmpty() || text.isEmpty()) continue
                items.add(
                    ShareItem(
                        shareId = id,
                        text = text,
                        subject = o.optString("subject", "").takeIf { it.isNotEmpty() },
                        title = o.optString("title", "").takeIf { it.isNotEmpty() },
                        sourcePackage = o.optString("sourcePackage", "").takeIf { it.isNotEmpty() },
                        receivedAtMs = o.optLong("receivedAtMs", 0L),
                    ),
                )
            }
            items.sortedBy { it.receivedAtMs }
        } catch (_: Exception) {
            // A corrupt queue must not block sharing: drop it, the share that
            // triggered this read is written again by the caller.
            p.edit().remove(KEY_QUEUE).commit()
            emptyList()
        }
    }

    @Synchronized
    fun get(context: Context, shareId: String): ShareItem? =
        readPending(context).firstOrNull { it.shareId == shareId }

    @Synchronized
    fun ack(context: Context, shareIds: Collection<String>) {
        if (shareIds.isEmpty()) return
        val p = prefs(context)
        val ids = shareIds.toSet()
        val remaining = readPendingLocked(p).filterNot { it.shareId in ids }
        p.edit()
            .putString(KEY_QUEUE, JSONArray().apply { remaining.forEach { put(it.toJson()) } }.toString())
            .commit()
    }

    @Synchronized
    fun clear(context: Context) {
        prefs(context).edit().remove(KEY_QUEUE).commit()
    }
}
