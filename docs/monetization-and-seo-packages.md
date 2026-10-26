# NextGen — Commercial Packages & SEO Entitlements
Last updated: 2026-10-26

## Owner requirement (confirmed)
When NextGen is sold as a one-time purchase or offered through paid subscriptions, advanced/full SEO must be a paid premium entitlement. A customer paying ₹499 must NOT receive the Full SEO package. Full SEO should be available only from a package priced at ₹1,499 or higher.

These are the owner's requested minimum price points, not a live billing configuration. Do not advertise or charge customers until the pricing model, billing period, taxes, cancellation/refund rules and package entitlements are finalized.

## Suggested package structure (for product planning)
- **Basic — ₹499 tier:** Core dashboard and basic content drafts; basic metadata/caption/hashtags; manual review checklist. Excludes Full SEO, premium keyword research, advanced competitor research and premium SEO scoring.
- **Full SEO — ₹1,499 minimum tier:** All eligible Basic features plus the Full SEO entitlement: connected live keyword research where supported, related keyword/competition research, title/description/tag optimization, SEO checklist/scoring, competitor insights where available, and post-publication SEO performance review where authorized data is available.
- **Optional premium add-ons:** Extra channel capacity, additional team seats, advanced analytics, and future publishing/comment automation can be separate add-ons or higher tiers. Define pricing and entitlement details before launch.

## Enforcement requirements
1. Enforce package access on the server/backend, not only by hiding buttons in the browser.
2. Store plan and entitlements per account; verify subscription/payment status server-side.
3. If an account is on ₹499 or lower, do not expose Full SEO API calls or premium results.
4. Full SEO is available only when the account has an active eligible plan priced at ₹1,499 or higher, or a one-time purchase that explicitly includes the same entitlement.
5. Keep account-level usage limits, API cost limits, audit logs and clear upgrade prompts.
6. Never put vidIQ/TubeBuddy credentials, API keys or payment secrets in client-side HTML/JavaScript.
7. Use only officially permitted APIs/integrations and respect each provider's terms. Do not claim TubeBuddy or vidIQ features are connected until tested.
8. Keep Manual Approval ON by default. SEO generation must not publish or schedule content without explicit user approval.

## Current implementation status
- This document records the product requirement only.
- Package UI, account plans, payment checkout, server-side entitlement enforcement, and Full SEO provider integrations are NOT implemented yet.
- The existing GitHub Pages prototype is a demo and must not be treated as a production subscription/billing system.
