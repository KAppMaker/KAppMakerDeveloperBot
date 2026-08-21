# Store compliance — walk this before the FIRST production publish

A store rejection costs days of review-queue round-trips; this checklist costs minutes. Walk every
item before the first production submission of an app (App Store review or Play production track)
and report failures to the owner **inside the publish confirmation message** — the owner decides
whether to fix first or submit anyway. Later releases only need re-checking for items whose inputs
changed (new SDK, new data collected, paywall edits).

This is a publish-time gate, not a loop lane: nothing here iterates.

## Apple — the rejections that actually happen

- **3.1.1 In-app purchase.** Every digital good or subscription is bought through StoreKit/IAP —
  no external checkout links, no "visit our website to subscribe", no copy steering users to buy
  outside the app. (Physical goods and the limited reader/external-link entitlements are the
  exceptions; if the app qualifies, say so in the report.)
- **Paywall disclosure (3.1.2 + review guidance).** On the paywall itself, before purchase: price
  and billing period; what the trial converts to and when ("3 days free, then $6.99/week" — never
  just "Try free"); a functional link to Terms of Use and Privacy Policy; restore-purchases
  reachable. Auto-renewal stated.
- **5.1.1 Data collection & storage.** The app requests permissions only when needed and explains
  why; sign-in is required only for features that need it; **if the app supports accounts, in-app
  account deletion exists** (hard requirement since 2022, common rejection).
- **2.1 Completeness.** No placeholder screens, lorem ipsum, dead buttons, or crash on the review
  path; demo credentials supplied in review notes if sign-in gates content.
- **Privacy nutrition label** (App Store Connect) matches what the SDKs actually collect —
  Firebase Analytics/Crashlytics, RevenueCat/Adapty, and AdMob all collect identifiers; declaring
  "no data collected" while shipping them is a rejection and a trust flag.

## Google Play — the traps

- **Data safety form matches reality.** Cross-check the form against the SDKs actually in the
  build (`enable-ads`, analytics, subscription providers). Play scans binaries; a mismatch triggers
  a policy strike, not a polite email.
- **Billing.** Digital goods through Play Billing only; same no-steering rule as Apple.
- **Subscription transparency.** Price, period and trial-conversion terms visible before purchase;
  cancel path not obscured.
- **Permissions.** Every dangerous permission in the manifest is used by a visible feature;
  unused ones removed (background location and QUERY_ALL_PACKAGES draw special scrutiny and
  declaration forms).
- **Account deletion.** If the app has accounts, Play requires a deletion path in-app *and* a web
  deletion URL on the store listing.
- **Target API level** current per Play's rolling requirement (the boilerplate stays current;
  verify after long-lived projects).

## Both stores

- **Privacy policy URL** reachable (not localhost, not a 404), and its content actually describes
  what this app collects. Terms URL likewise if referenced.
- **No test artifacts in the release build**: test ad-unit IDs swapped for production, sandbox
  flags off, debug menus stripped, `local.properties` placeholders replaced (a green build with
  `testValue` keys ships broken sign-in silently).
- **Paywall copy honesty**: no fake scarcity, no "limited offer" that never ends — both stores
  reject deceptive monetization, and CONVERSION_PLAYBOOK §6 already forbids it.
- **Screenshots/metadata truthfulness**: store screenshots show real app UI, not mockups of
  features that do not exist.

## Reporting format

In the publish confirmation message, one line per failed item: `guideline — what fails — where`
(e.g. `Apple 5.1.1 — no account deletion in app — Settings screen`). If everything passes, one
line saying the compliance walk passed. Never block the publish yourself — surface, recommend,
and let the owner decide.
