package app.twindrop

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import android.widget.Toast
/**
 * Share-sheet entry point (docs/06 §1): read the payload, persist it to the durable
 * native queue first, then show the small Flutter panel. Finishing here returns the
 * user to the source app. No network is touched from this activity.
 */
class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The share sheet must not animate: the panel appears over the source
        // app (docs/06 §1).
        window.setWindowAnimations(0)
        if (savedInstanceState != null) {
            finish()
            return
        }
        try {
            handle(intent)
        } catch (_: Exception) {
            Toast.makeText(this, UNSUPPORTED, Toast.LENGTH_SHORT).show()
        } finally {
            finish()
        }
    }

    private fun handle(intent: Intent?) {
        when (val parsed = ShareIntents.parse(intent)) {
            is ShareIntents.ParseResult.Unsupported -> {
                val message = if (parsed.reason == "too large") TOO_LARGE else UNSUPPORTED
                Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
            }

            is ShareIntents.ParseResult.Ok -> {
                val enqueued = ShareQueueStore.enqueue(
                    this,
                    parsed.text,
                    parsed.subject,
                    parsed.title,
                    intent?.`package`,
                )
                if (enqueued == null) {
                    Toast.makeText(this, COULD_NOT_SAVE, Toast.LENGTH_SHORT).show()
                    return
                }
                if (enqueued.alreadyImported) {
                    // Same link inside the dedupe window and it is already saved.
                    Toast.makeText(this, SAVED, Toast.LENGTH_SHORT).show()
                    return
                }
                startPanel(enqueued)
            }
        }
    }

    private fun startPanel(enqueued: ShareQueueStore.EnqueueResult) {
        val panel = Intent(this, SharePanelActivity::class.java).apply {
            putExtra(SharePanelActivity.EXTRA_SHARE_ID, enqueued.item.shareId)
            putExtra(SharePanelActivity.EXTRA_DUPLICATE, enqueued.duplicate)
            addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
        }
        try {
            startActivity(panel)
        } catch (_: Exception) {
            // Engine unavailable (very low memory): the item is already saved.
            Toast.makeText(this, SAVED, Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        const val UNSUPPORTED = "TwinDrop saves text and links only."
        const val TOO_LARGE = "Couldn't save. This share is too large."
        const val COULD_NOT_SAVE = "Couldn't save. Free some space and try again — nothing was sent."
        const val SAVED = "Saved to Inbox."
    }
}
