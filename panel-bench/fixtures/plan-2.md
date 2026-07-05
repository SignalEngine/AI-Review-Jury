# Rollout plan: new pricing (Starter £29 → £39, Pro £99 → £129)

Principle we've announced publicly: **existing customers keep their current price
forever** — the increase applies to new signups only.

1. **Mon 09:00 — Create new prices.** Create the new Stripe Price objects
   (`price_starter_39`, `price_pro_129`) and deploy the checkout change so all new
   signups from Monday morning use the new price IDs.
2. **Mon 10:00 — Update marketing site.** New pricing page goes live. Banner: "Lock in
   current pricing — signups before midnight March 1st keep the old rates." (Marketing
   has already announced the cutoff as midnight Pacific on socials; the billing job that
   enforces it runs on the API server, which is on UTC like everything else.)
3. **Mon–Tue — Monitor.** Watch conversion on the new pricing page for 24h.
4. **Tue 09:00 — Webhook handler.** Deploy the updated webhook handler that recognizes
   the new price IDs and maps them to plan entitlements. (Kept separate from step 1 so
   each deploy stays small and reviewable.)
5. **Tue 14:00 — Migrate subscriptions.** Run `migrate_prices.py` to move ALL active
   subscriptions onto the new price IDs so we have a single set of prices to maintain
   going forward. Prorations disabled; the new rate applies from each customer's next
   invoice.
6. **Wed 09:00 — Customer email.** Send the "pricing update" email to all customers
   explaining the change and thanking early supporters.
7. **Wed–Fri — Support watch.** Triage pricing tickets in #support with a 2h SLA.

Rollback: if paid conversion drops >25% in week one, revert the marketing page and
point checkout back at the old price IDs (they remain active in Stripe).
