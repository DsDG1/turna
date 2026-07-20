# ADR 0024: Team Collaboration Enhancements

## Date
2026-07-20

## Status
Accepted

## Context
The team memo board was a flat append-only JSON file (`.collaboration_memo.json`) with no threading, no edit/delete, no pagination, and no search. It grew unboundedly and had a best-effort race against teammate pushes. The LAN server had no presence indicator (who is connected).

## Decision
1. **Threaded memos**: Memo entries now have `id` (uuid hex 12-char) and `parent_id` fields. Replies are rendered indented under their parent. The reply combo lets users select which message to reply to.

2. **Edit/delete own memos**: Users can edit or delete their own memos (verified by `getpass.getuser()` match). Edited memos record `edited_at`. The `memo_id` is entered via `QInputDialog` (derived from the displayed ID prefix).

3. **Pagination**: Top-level messages are paginated (20 per page) with "上一页/下一页" buttons and a page indicator.

4. **Search**: A search box filters memos by text or user (case-insensitive substring).

5. **Online members**: The LAN server tracks `connected_peers` (IP -> last-seen timestamp). The dialog's `_refresh_peers` method (called every 1s by the log timer) displays active peers, expiring those inactive for 60s.

6. **Activity feed**: The existing `log_queue` (capped at 100 entries) serves as the activity feed, showing connect/push/pull events with timestamps and success/failure indicators.

## Consequences
- Memo threads make conversations scannable.
- Edit/delete reduces noise from outdated messages.
- Pagination prevents performance degradation as the memo grows.
- Online members awareness enables real-time collaboration coordination.
- The memo data structure is backward-compatible (old flat entries get `id=""` and `parent_id=""`, rendered as top-level).
