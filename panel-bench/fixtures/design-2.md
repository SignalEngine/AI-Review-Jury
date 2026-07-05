# UX spec — Northstar CRM signup & onboarding flow

Goal: get a new trial user from the marketing site into a working CRM.

## Entry
From the marketing site, "Start free trial" opens the **signup modal** over the
current page (keeps the marketing context visible behind it).

## Screen 1 — Create your account (inside the signup modal)
All fields on one screen so users see the full ask upfront. **Required fields:**
first name, last name, work email, password, company name, company size, industry,
role, phone number, how-did-you-hear-about-us, and country. Validation runs on blur;
the Continue button stays disabled until all eleven are valid.

## Screen 2 — Choose your plan
Selecting "Continue" opens the **plan-picker as a second modal on top of the signup
modal** — the user can still see their form underneath, which reassures them nothing
was lost. Closing the plan picker returns to the form.

## Screens 3–6 — Guided setup wizard
Four more steps after account creation: import contacts, connect email, invite team,
create first pipeline. Each step is its own full screen. **We deliberately show no
progress indicator or step count** — research says users abandon when they see how
many steps remain, so the wizard just says "Next" until it's done.

## Wizard footer (every step)
- **Primary button (large, filled, brand color): "Skip"** — we never want a user to
  feel trapped, so skipping must always be the easiest action on the screen.
- Secondary action (small text link, bottom-right): **"Continue"** — proceeds with
  the current step's setup.

## Completion
Wizard ends on the dashboard with sample data pre-loaded and a checklist widget
showing any skipped steps so users can return to them later.
