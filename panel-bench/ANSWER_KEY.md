# Panel benchmark — planted-flaw answer key (NEVER include in model prompts)

Each flawed fixture has exactly 4 planted flaws. Clean fixtures (`*-0-clean.md`) have
none planted — the correct review is "fundamentally sound" (minor suggestions OK).

## idea-1 (LeadPolish)
- **I1.1 unit economics:** £9/mo with 20% monthly churn → LTV = 9/0.20 = £45 vs £120 CAC.
  LTV < CAC; the claimed "payback inside 3 months" is impossible (3 months revenue = £27,
  and 20% churn means expected lifetime is only 5 months).
- **I1.2 contradiction:** "fully self-serve, zero-touch onboarding … no human involvement"
  directly contradicts "every new customer gets a 45-minute white-glove onboarding call".
- **I1.3 regulatory:** scraping LinkedIn profiles of UK/EU individuals and auto cold-emailing
  them = GDPR/PECR problem (plus LinkedIn ToS violation). Stated as the core growth loop.
- **I1.4 market math:** "UK has around 2 million letting agencies" — real figure is roughly
  15–20k. The 20,000-customer "1%" target would be >100% of the actual market.

## idea-2 (PlateSwap)
- **I2.1 arithmetic:** 15% of £20 = £3, not £6. All downstream revenue (£6k/day, £2M+/yr)
  is 2x overstated.
- **I2.2 cold start:** "launch with 10,000 home cooks and matching demand from day one,
  supply and demand arrive together" — no mechanism given; classic marketplace chicken-egg
  hand-waved as "inherently viral".
- **I2.3 platform dependency:** distribution runs 100% through auto-posting listings via
  "the TikTok API" — single-platform dependency, and TikTok's API does not permit automated
  template-video posting at this scale (spam policy).
- **I2.4 regulatory:** selling home-cooked food to the public in the UK requires food
  business registration with the local authority (FSA) + hygiene inspection; the spec's
  trust mechanism is ratings and photos only, food-safety law never addressed.

## idea-3 (FocusBrick)
- **I3.1 margin math:** £29 − £11 COGS − £4.50 shipping − £4.35 Amazon fee = £9.15 ≈ 31%
  gross margin, not "around 70%".
- **I3.2 fake moat:** "competitors can copy the hardware but can't copy the prompt" — a
  prompt is trivially replicable and not defensible.
- **I3.3 channel conflict:** retailers stock at RRP £29 with 40% margin while the brand's
  own site runs a permanent 40%-off promo (£17.40) — permanently undercutting the retail
  channel it's courting.
- **I3.4 shipping/regulatory:** device contains a lithium battery but plan is "worldwide
  standard untracked letter post" — lithium batteries are restricted/prohibited in
  untracked international letter post.

## plan-1 (orders migration)
- **P1.1 read-after-drop:** step 2 drops `orders_v1`; step 5's backfill joins against
  `orders_v1` pricing history. The backfill cannot run.
- **P1.2 backup verified too late:** snapshot taken at step 1 but only verified at step 8,
  after the destructive drop (step 2) and irreversible rewrite (step 4). If the snapshot is
  bad you find out after the data is gone.
- **P1.3 flag before code:** step 3 enables `new_checkout` for 100% of users; the code
  implementing it deploys at step 6, ~65 minutes later.
- **P1.4 irreversible, no rollback:** step 4 rewrites 4M order IDs in place with no
  rollback path (and the only backup is the unverified snapshot — distinct from P1.2:
  even with a good snapshot there's no plan-level rollback for a partial failure at 07:00).

## plan-2 (pricing rollout)
- **P2.1 grandfather contradiction:** "existing customers keep their current price forever"
  vs step 5 migrating ALL active subscriptions to the new (higher) price IDs with the new
  rate applying from next invoice.
- **P2.2 webhook gap:** checkout sells new price IDs from Mon 09:00 (step 1) but the
  webhook handler that maps those IDs to entitlements deploys Tue 09:00 (step 4) — a full
  day of paying signups with unrecognized prices/broken entitlements.
- **P2.3 cutoff timezone conflict:** marketing announced "midnight Pacific"; the enforcing
  job runs on UTC. Midnight UTC is 8 hours before midnight Pacific — customers promised the
  old rate will be charged the new one.
- **P2.4 charge-before-comms:** subscriptions migrate Tue 14:00 (step 5); the customer
  email goes out Wed 09:00 (step 6) — customers can be re-priced before being told.

## plan-3 (permissions rollout)
- **P3.1 stale JWT privileges:** the 41 revoked admins keep admin via the role claim baked
  into JWTs with 30-day expiry; no session/token invalidation step. A security revocation
  that can take up to 30 days to bite.
- **P3.2 rollout math:** 10% + 30% + 40% = 80% — the staged enable never reaches the
  promised "full coverage".
- **P3.3 dependency ordering:** step 3 (Day 3) has the middleware calling
  `permissions-service`, which is only deployed to production on Day 7 (step 6).
- **P3.4 key rotation outage:** production signing key rotated at 12:00 with the old key
  deleted immediately — every existing session becomes invalid instantly (mass midday
  logout), contradicting the stated "zero user impact". No dual-key overlap window.

## copy-1 (JobFlow lander)
- **C1.1 contradiction:** hero says "Start free — no credit card required"; pricing says
  "All plans require a card to start your 14-day trial".
- **C1.2 legal risk:** "We guarantee you'll 3x your booked revenue within 90 days or it's
  free. No terms, no fine print" — unsubstantiated earnings guarantee (ASA/FTC problem).
- **C1.3 CTA mismatch:** button copy "Start your free trial" but (per context note) it
  opens the book-a-demo calendar — bait-and-switch CTA.
- **C1.4 audience mismatch:** the three headline benefits (RBAC, SSO/SAML, SOC 2) are
  enterprise-procurement points, pitched at 1–5-person plumbing/electrical firms.

## copy-2 (Draftly pricing page)
- **C2.1 social-proof contradiction:** "Trusted by 2,000+ agencies" (header) vs "be one of
  our first 100 customers" (footer).
- **C2.2 tier inversion:** Starter (£29) includes "up to 10 users"; Pro (£99) includes
  "up to 5 users" — the cheaper plan has the higher user limit.
- **C2.3 discount math:** "Save 20% with annual billing: £99/mo billed annually at £1,069"
  — £99×12 = £1,188; 20% off = £950.40. £1,069 is ~10% off, not 20%.
- **C2.4 expired urgency:** "founding-member pricing ends March 31, 2026" on a page
  stamped "Last updated June 2026" — the deadline is already past.

## copy-3 (Meridian cold email)
- **C3.1 compliance:** cold email to a purchased list with NO unsubscribe/opt-out
  mechanism (UK PECR/GDPR requirement), plus a deceptive "Re:" subject implying a prior
  thread.
- **C3.2 false familiarity:** "Great meeting you at DentalExpo last week" mail-merged to
  5,000 strangers — a fabricated personal claim that destroys trust (and is deceptive).
- **C3.3 oversized ask:** first-touch CTA is a 60-minute strategy session — far too big
  for a cold first email.
- **C3.4 merge-field bug:** "{{firstName}}" used in subject and body with no fallback
  configured → recipients with missing names get "Quick question, ".

## design-1 (RevBoard dashboard)
- **D1.1 contrast/size:** primary KPI values in 12px #9CA3AF on white — fails WCAG AA
  contrast (~2.5:1) at a tiny size, for the single most important data on the page.
- **D1.2 icon-only toolbar:** 8 icon-only buttons with no labels or tooltips —
  unlearnable and inaccessible (no accessible names mentioned).
- **D1.3 mobile table:** a 14-column table "renders identically" at 375px — unusable
  without a responsive strategy (priority columns, cards, horizontal scroll affordance).
- **D1.4 destructive without confirm:** trash icon immediately and permanently deletes a
  campaign and its history, no confirmation/undo, placed adjacent to "pause".

## design-2 (Northstar onboarding)
- **D2.1 field overload:** 11 required fields before any product value; Continue disabled
  until all are valid.
- **D2.2 modal-in-modal:** plan picker opens as a second modal stacked on the signup
  modal.
- **D2.3 no progress indicator:** 6-step flow deliberately hides step count/progress —
  rationalized, but users need location/orientation in multi-step flows.
- **D2.4 inverted CTA hierarchy:** "Skip" is the large filled primary button; "Continue"
  is a small text link — visual weight steers every user to skip setup.

## design-3 (Draftly pricing page spec)
- **D3.1 color-only state:** available vs unavailable = same checkmark in green vs red —
  colorblind users can't distinguish; state carried by color alone.
- **D3.2 broken toggle:** billing toggle animates but prices only update after a page
  reload — the control visibly does nothing, worst kind of UI lie.
- **D3.3 overload above the fold:** six tiers + 45-row matrix all above the fold,
  including on 375px mobile — physically impossible/cognitive overload.
- **D3.4 illegible type:** 11px Helvetica Light for body and a 45-row data matrix —
  below readable minimums, light weight worsens it.

## Scoring
- **CAUGHT:** the model identifies the planted flaw (same underlying issue; wording may
  differ; partial credit NO — the core mechanism must be named).
- **FP:** a concrete claim of a flaw that is not planted and not actually true of the
  fixture. Judgment calls / soft advice / style notes are NOT FPs — only wrong factual
  claims or invented problems presented as defects.
- **BONUS (track separately, doesn't affect recall):** a real un-planted flaw. Fixtures
  are dense; models may find real issues we didn't plant.
- **Clean fixture verdict:** SOUND (says it's fundamentally sound) / NOISY (invents
  defects). Suggestions without invented defects still count as SOUND.
