# UI spec — RevBoard analytics dashboard (v2)

Target users: agency owners checking campaign performance. Viewports: desktop 1440px
and mobile 375px (roughly half of sessions are mobile, per analytics).

## Layout
- Top bar: workspace switcher, date-range picker, and a toolbar of **8 icon-only
  buttons** (export, refresh, filter, compare, annotate, share, fullscreen, settings).
  No text labels or tooltips — keeps the bar clean, and the icons are standard enough
  that users will recognize them.
- KPI strip: four cards (Spend, Leads, CPL, ROAS). Card label in 16px #111827;
  the **primary KPI value beneath it in 12px #9CA3AF on the white card background** —
  the muted value keeps visual emphasis on the trend sparkline next to it.
- Main area: the campaigns table — **14 columns** (name, status, spend, budget, leads,
  CPL, CTR, CPM, impressions, clicks, frequency, start, end, owner). The table renders
  identically on mobile; keeping every column visible at 375px means nothing is hidden
  from mobile users, which analytics says is half our traffic.

## Interactions
- Row hover reveals quick actions: duplicate, pause, and a **trash icon that
  immediately and permanently deletes the campaign and its historical data.** No
  confirmation dialog — our users are power users and hate friction; the action is
  right next to "pause" so it's easy to reach mid-flow.
- Clicking any KPI card filters the table to the campaigns driving that metric.
- Date-range changes animate the sparklines over 300ms.

## Visual
- Light theme only for v2. Cards on #FFFFFF, page background #F9FAFB.
- Semantic colors: green #10B981 for positive deltas, red #EF4444 for negative, with
  an up/down arrow accompanying each so the direction survives without color.
