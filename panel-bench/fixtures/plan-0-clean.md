# Rollout plan: add composite index to speed up the /reports dashboard

Goal: cut p95 on `GET /reports` from 4.2s to under 500ms by adding a composite index
and switching the dashboard query to use it. Zero downtime required.

1. **Day 1 — Create index concurrently.** `CREATE INDEX CONCURRENTLY idx_events_org_day
   ON events (org_id, day)` on the production replica-aware primary. CONCURRENTLY avoids
   locking writes; expected build time ~25 min at current table size. If the build fails
   or is cancelled it leaves an INVALID index — the runbook step includes checking
   `pg_index.indisvalid` and dropping/retrying if needed.
2. **Day 1 — Verify index health.** Confirm the index is valid and being maintained:
   `indisvalid = true`, size within 10% of the staging estimate (staging carries a
   full-size production clone; the same build was rehearsed there last week).
3. **Day 2 — Deploy the new query behind a flag.** Ship the rewritten dashboard query
   gated by `reports_new_query`, default OFF. The new query is verified against the old
   one in CI with a golden-data test asserting identical results on 40 fixture orgs.
4. **Day 2 — Shadow-read.** Enable shadow mode for 24h: serve the old query, run the new
   one in parallel on 5% of requests, log result mismatches and latency. Alert threshold:
   any mismatch, or new-query p95 above 500ms.
5. **Day 3 — Flip gradually.** No mismatches → enable the flag 10% → 50% → 100% over one
   day, watching the same dashboards at each step.
6. **Day 5 — Cleanup.** Remove the old query path and the flag; keep the shadow-compare
   harness in the repo for the next migration.

Rollback at any step: flip `reports_new_query` OFF (instant, no deploy). The index is
additive and harmless to leave in place; drop it only if write amplification shows up
in `pg_stat_user_tables` (not expected — the table takes ~2 writes/sec).
