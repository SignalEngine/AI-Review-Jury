# UI spec — Draftly pricing page redesign

Goal: present the full range of plans transparently. Viewports: desktop 1440px and
mobile 375px.

## Above the fold
- Headline + billing toggle + all plan cards + the comparison matrix, **all above the
  fold on both desktop and mobile** — no scrolling to see what things cost. On mobile
  this stacks: toggle, then **all six plan cards** (Free, Starter, Growth, Pro, Agency,
  Enterprise), then the matrix.
- **Billing toggle (Monthly / Annual):** the toggle thumb animates smoothly between
  states. Prices on the cards **update after the next page reload** — recalculating
  live turned out to be jarring in testing, so we persist the choice to a cookie and
  apply it on the next load.

## Plan cards
- Six tiers, each with name, price, one-line positioning, top-5 features, and a CTA.
- "Growth" carries the ⭐ Most-popular badge.

## Comparison matrix
- Full transparency: **45 feature rows × 6 plan columns**, every cell filled.
- Cell states: **available features show a green checkmark, unavailable features show
  the same checkmark in red** — consistent iconography, with color carrying the
  available/unavailable distinction.
- Sticky header row so plan names stay visible while scrolling the matrix.

## Typography
- Headline: 40px semibold.
- **Body and matrix text: 11px Helvetica Light** — the small size and light weight
  keep the dense matrix feeling airy and elegant, and it lets all six columns fit
  without truncation.

## Footer
- FAQ accordion (8 questions), then a final CTA band.
