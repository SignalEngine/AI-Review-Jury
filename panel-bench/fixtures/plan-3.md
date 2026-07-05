# Rollout plan: granular permissions (replacing the admin/member binary)

Goal: replace the two-role system with granular permissions, with zero user impact.

1. **Day 1 — Schema.** Add the `permissions` table and backfill: every current `admin`
   gets the full permission set, every `member` gets the read set. The old `role` column
   stays for rollback.
2. **Day 2 — Demote stale admins.** Security asked us to use this migration to revoke
   admin from the 41 accounts flagged as over-privileged. Flip their DB rows to the read
   set as part of the backfill. Our JWTs embed the role claim and have a 30-day expiry,
   so the change takes effect as sessions naturally refresh.
3. **Day 3 — Gate reads.** Deploy the middleware that resolves permissions by calling
   the new `permissions-service` on each request (with a 5-minute in-process cache).
4. **Day 3, later — Staged enable.** Enable the new permission checks for 10% of
   organizations, then 30% the next morning, then the remaining 40% after lunch — full
   coverage by end of Day 4.
5. **Day 5 — Key rotation.** Security also wants the JWT signing key rotated as part of
   this work. Rotate the production signing key at 12:00; from that moment new tokens
   are signed with the new key. Old key is deleted immediately per the security
   checklist. As stated up top, the whole rollout is zero-user-impact.
6. **Day 7 — Deploy permissions-service.** Stand up the new `permissions-service` in
   production (it's been running in staging for two weeks) and remove the legacy role
   checks from the monolith.
7. **Day 10 — Cleanup.** Drop the `role` column once error rates hold flat for 72h.

Rollback: re-enable legacy role checks via the `use_legacy_roles` flag at any point
before Day 10.
