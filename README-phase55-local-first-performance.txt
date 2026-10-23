Super Iraq IQ — Phase 55: Local-first storage and smoother sync

Purpose
- Keep routine operations local-first so sales and stock work without a live internet request.
- Make IndexedDB the primary browser-local database.
- Stop writing the entire database JSON into localStorage on every persist. This avoids repeated serialization and localStorage quota pressure.
- On startup, migrate from the legacy localStorage database into IndexedDB and verify the saved record before removing the legacy database key.
- Debounce whole-snapshot cloud sync to 10 seconds after edits; attempt a periodic sync every 60 seconds and on reconnection.
- Prevent concurrent full-snapshot pushes, skip repeated identical snapshots within the current session, and warn if a snapshot is larger than the existing ~780 KB client guard.
- Keep local data when cloud sync fails; the cloud status says sync is pending rather than treating failure as loss of local data.

Important architecture boundaries
- IndexedDB is stored in this browser profile on this computer, not a shared folder or OS-level database. Other devices do not see it unless data is synchronized.
- This phase improves local responsiveness and reduces duplicate storage, but does NOT yet convert the cloud schema to normalized products/sales/stock-movement tables or incremental change-log sync. The current branch snapshot model has a practical payload ceiling and sends a branch snapshot on sync.
- The 780 KB client guard is a warning/protection threshold, not a promise of supported product count. Large branches need the next phase: paginated/transactional tables and incremental sync/outbox by operation ID.
- Do not clear browser data or uninstall/reset the browser before exporting a verified JSON backup. Keep external backups.
- Cloud sync was not tested against a live Supabase instance or multiple real branches in this environment.

Validation performed for this package
- Node syntax check: server/src/server.js — passed.
- Node syntax check: apps/admin-web/cloud-integration.js — passed.
- Extracted inline JavaScript syntax checks from apps/admin-web/index.html — passed.
- ZIP integrity check — performed when packaging.
