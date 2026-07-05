# UI spec — Kerbside account settings page

Target users: solo business owners, often on mobile between jobs. Viewports: desktop
1440px, mobile 375px.

## Layout
- Desktop: two-column — left nav (Profile, Business, Payments, Notifications, Danger
  zone), right content pane. Mobile: the nav collapses to a segmented control above a
  single stacked column; sections render one at a time.
- Every form field has a visible text label above it plus helper text where the field
  isn't self-explanatory (e.g. "Deposit percentage — taken at booking, refunded if you
  cancel"). Placeholder text is never used as the only label.

## Forms & feedback
- Fields save per-section via an explicit "Save changes" button that activates only
  when the section is dirty; a saved confirmation toast appears for 4s and is also
  announced via aria-live.
- Validation errors render inline below the field in 14px #B91C1C with an error icon,
  and the field border thickens — color is never the only signal.
- All controls are keyboard-reachable in DOM order with a visible 2px focus ring
  (brand blue on light surfaces, meeting 3:1 contrast against adjacent colors).

## Text & contrast
- Body text 16px #1F2937 on #FFFFFF; secondary text 14px #4B5563 — both clear WCAG AA.
- Touch targets minimum 44×44px on mobile; primary buttons full-width on mobile.

## Danger zone
- "Delete account" sits in its own section, styled as a bordered card, and requires
  typing the business name to confirm inside a dialog that spells out what is deleted
  and that exports remain available for 30 days. The confirm button stays disabled
  until the typed name matches.
