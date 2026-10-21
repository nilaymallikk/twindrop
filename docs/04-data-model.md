# 04 — Data Model & Merge Rules

SQLite via drift. UUIDv7 ids (lowercase). Times: epoch ms UTC for wall times; **HLC strings** for ordering. Migrations for every schema change (tested on a copy of the previous schema).

## Hybrid logical clock (HLC)
`hlc = "<wallMs 15-digit>-<counter 5-digit>-<deviceId>"`. On local event: `wall=max(now, lastWall)`; counter++ if equal. On receive: `wall=max(now, lastWall, remoteWall)`, adjust counter. Compare as strings. Tolerates clock skew (SYNC-010). Persist last HLC.

## Tables
**peers** `id PK` (remote deviceId), `name`, `kind` (`phone|desktop`), `role_of_peer` (`host|guest`), `token_hash` (desktop side, for phones), `token_ref` (phone side: key name in secure storage), `cert_fp` (pin), `last_host`, `last_port`, `last_seen`, `remote_seq` (highest peer change seq applied), `acked_seq` (highest of OUR seq the peer acknowledged), `protocol_version`, `revoked_at NULL`, `created_at`.

**categories** `id PK` (Inbox id = `inbox`), `name`, `normalized_name`, `color NULL`, `sort_order`, `is_inbox`, `meta_hlc`, `deleted`.

**items**
- `id PK`, `type` (`message|note`), `kind` (`text|link`), `text`, `title NULL`, `url NULL` (first http/https URL only), `source_app NULL`, `category_id NULL` (notes), `origin_device`, `origin_name`, `source_item_id NULL`, `created_at`
- **content group** (edits to `text/title/url`): `content_hash`, `prev_hash`, `content_hlc`
- **meta group** (`category_id`, `pinned`, `deleted`): `pinned`, `deleted`, `deleted_hlc`, `meta_hlc`
- `restored` (0/1), `is_conflict_copy` (0/1)
- Messages are **immutable** (content never changes); only delete (meta group) applies.

**change_log** `seq INTEGER PK AUTOINCREMENT`, `entity_type` (`item|category`), `entity_id`, `source_peer NULL` (NULL = local origin; else the peer we received it from), `created_at`. Every local write **and** every applied remote write appends a row (so changes can propagate to other peers). Compaction allowed: keep the latest row per entity.

**peer_delivery** `peer_id`, `item_id`, `state` (`queued|sent|delivered`) — local only; drives message tick icons.

**quarantine** `id`, `peer_id`, `entity_type`, `entity_id`, `reason`, `payload_json`, `received_at` — invalid remote changes (never silently dropped; viewable in Settings → Data).

**applied_remote** `peer_id`, `peer_seq` UNIQUE — replay guard (SYNC-003).

**settings** key/value (local only). **items_fts** FTS5 over `title,text,url`.

## Validation (client and host; reject, never truncate)
- Message text: non-empty after trim, ≤ 64 KiB UTF-8. Note text ≤ 256 KiB. Title ≤ 200 chars.
- Category name: trimmed, 1–60 chars, unique case-insensitively among non-deleted.
- `url` accepted only if absolute `http`/`https`; reject `javascript:`, `file:`, `data:`, `intent:`, relative, malformed. The raw text is still stored; just not marked as a link.
- Never auto-fetch URLs. Never strip query params unless setting `clean_links` is on and the host is Instagram (`igsh`, `igshid` only); original is kept in `text`.

## Write path (local)
1. Validate. 2. One transaction: write item/category (+ HLCs, hashes) → append `change_log` → insert `peer_delivery(queued)` for each peer (messages) → update FTS. 3. Commit. 4. Signal sync engine (`notify`). **Nothing leaves the device before step 3 commits.**

## Merge rules (applying a remote item R to local L)
Both sides must compute the **same result** (deterministic).
1. **No L:** insert R.
2. **Content group** (`text/title/url`):
   - `R.content_hash == L.content_hash` → same.
   - `R.prev_hash == L.content_hash` → R is a fast-forward → take R's content.
   - `L.prev_hash == R.content_hash` → R is older → keep L.
   - Otherwise **concurrent edit**: winner = higher `content_hlc`. Take winner as the item's content. If texts differ, create a **conflict copy** of the loser: a new note, same category, title `Conflict copy: <title or first 40 chars>`, `is_conflict_copy=1`, with deterministic id `uuidv5(NS_CONFLICT, itemId + ":" + loserContentHash)` so both devices create the *same* copy and never duplicate it. Title-only/URL-only differences also follow this rule.
3. **Meta group:** per-field last-writer-wins by `meta_hlc` (`category_id`, `pinned`, `deleted`).
4. **Delete vs edit:** if the merged item is `deleted` but the winning `content_hlc` is later than `deleted_hlc` → **restore** (`deleted=0`, `restored=1`). Rule: *never lose content to a concurrent delete*.
5. **Categories:** per-field LWW by `meta_hlc`. If two non-deleted categories share a `normalized_name` (created concurrently), the one with the smaller id wins; the other is tombstoned and its notes are reassigned to the winner (as normal item meta updates).
6. **Category deletion** (user action): in one transaction move its notes to `inbox`, then tombstone the category.
7. **Inbox:** fixed id `inbox`; both sides create it on first run; `deleted` is ignored for it.

## Cursor sync
Each device keeps `peers.remote_seq` (peer's seq applied) and serves its own `change_log`. `pull(after=S)` returns entries with `seq > S`, **excluding entries whose `source_peer` equals the requester** (no echo), plus full entity rows. Receiver applies the page in one transaction: merge rows, append own `change_log` (with `source_peer`), record `applied_remote`, then advance `remote_seq` — **never advance before the page commits**.

## Tombstones
Kept ≥ 30 days **and** until every non-revoked peer has acked a seq ≥ the tombstone's change seq; then GC on app start.

## Integrity rules
- Unknown `entity_type`, schema/protocol version → stop sync and surface "Update needed" (SYNC-007). Don't skip-and-advance.
- Invalid but understood change (bad URL scheme, oversize) → quarantine, advance, surface count in Diagnostics.
- Cursor mismatch or restored DB → **resync**: request full snapshot from the peer and merge with the same rules (nothing is deleted locally).
- WAL mode; foreign-key and `PRAGMA integrity_check` on startup; if corrupt: copy DB to a timestamped backup **before** any recovery, then guide the user.
- No DB inside the AppImage mount; use XDG data dir / platform path provider.
