# Migration plan: orders_v1 → orders_v2 (production, Saturday 06:00)

Goal: move all order data to the new schema (`orders_v2`) and retire the legacy table.
Estimated window: 2 hours. Owner: me.

1. **06:00 — Snapshot.** Take an RDS snapshot of the production database. To save time
   inside the window, we'll verify the snapshot restores correctly at the end of the
   migration (step 8) rather than blocking on it up front.
2. **06:10 — Drop legacy.** Drop the `orders_v1` table. It's been read-only since the
   dual-write started in May, so nothing writes to it anymore and dropping it early
   frees the storage headroom the copy in step 4 needs.
3. **06:15 — Enable flag.** Turn on the `new_checkout` feature flag for 100% of users so
   traffic starts exercising the v2 path as soon as it's ready.
4. **06:20 — ID rewrite.** Run `rewrite_order_ids.py`, which rewrites every order ID in
   `orders_v2` in place from the legacy `ord_XXXX` format to the new ULID format. The
   script updates rows directly; at ~4M rows it takes about 40 minutes.
5. **07:00 — Backfill.** Run `backfill_totals.py`, which recomputes cached order totals
   by joining `orders_v2` against the pricing history in `orders_v1` for orders placed
   before 2025.
6. **07:20 — Deploy.** Deploy the release containing the `new_checkout` implementation
   and the v2 read path.
7. **07:35 — Smoke test.** Place three test orders (card, PayPal, invoice) and verify
   they appear correctly in the admin panel.
8. **07:45 — Verify snapshot.** Restore the 06:00 snapshot into the staging cluster and
   confirm it boots and row counts match.
9. **08:00 — Announce.** Post completion in #eng and close the maintenance banner.
