# Queue Cancellation — Staging Validation Plan

**Status:** Isolated PostgreSQL CI subset passed; full Supabase staging validation remains pending.

## Current safety boundary

- The Supabase project currently exposes only the production `main` branch; no development/staging branch is available.
- The cancellation migration `20261031130000_add_audited_queue_cancellation.sql` is present in the repository but has **not** been applied to production.
- Pull request #9 remains a draft and must not be merged or deployed until the checks below pass.
- Do not test cancellation against production data.

## Preconditions

1. Provision or identify an isolated Supabase staging branch/project.
2. Confirm the staging database is disposable and contains no production user data.
3. Apply the queue-cancellation migration to staging only.
4. Confirm the function exists and grants are limited to `authenticated` (with `PUBLIC` and `anon` revoked).
5. Run Supabase security advisors and inspect any new findings.

## Required functional and authorization tests

| Case | Setup / action | Expected result |
|---|---|---|
| Owner cancels queued job | Authenticated owner cancels their own `queued` job | Job becomes `cancelled`; an audit event with action `cancelled` is written |
| Exact schedule restoration | Content still matches the cancelled job's channel and scheduled timestamp; no other active job exists | Content returns to `approved`; `scheduled_for` is cleared |
| Other owner's job | A different authenticated user attempts cancellation | Rejected; no job, content, or audit row belonging to the owner is changed |
| Unauthenticated caller | Call RPC without a valid authenticated user | Rejected |
| Non-queued job | Attempt on `processing`, `published`, or already `cancelled` job | Rejected; state remains unchanged |
| Newer content state | Content schedule/channel no longer matches the cancelled job | Job cancellation is recorded, but content is not reset |
| Another active job exists | A second queued/processing job exists for the content | Job cancellation is recorded, but content is not reset |
| Audit note bounds | Supply a long note | Stored note is safely bounded; no unbounded audit payload |
| Repeat / race | Two requests attempt to cancel the same queued job | At most one successful cancellation; no duplicate or inconsistent restoration |

## Release gate

- All cases above pass on staging.
- Inspect resulting rows and audit events directly on staging.
- Confirm existing review and scheduling RPC behavior remains unchanged.
- Re-run security advisors.
- Review the final PR diff; merge only after explicit release approval.
- Apply the migration to production only as a separately approved deployment step, after staging passes.

## Current result

**Isolated PostgreSQL CI — PASSED (2026-10-31):** GitHub Actions run [#6](https://github.com/nextgen-i/NextGen/actions/runs/41183143844), commit `b03f7d60bdf4c1c5ce1c682c2825ee882fcb2bb5`. The fixture loaded, the cancellation migration applied, and the authorization/state-transition test script completed successfully. Covered: owner cancels own queued job with content restoration and audit event; cross-owner cancellation is rejected without changing the other owner's job; another active queued job prevents content restoration; processing jobs cannot be cancelled.

**Not covered by this CI run:** unauthenticated caller, published/already-cancelled jobs, newer content state mismatch, long audit-note bounds, repeated/concurrent cancellation, full existing review/scheduling RPC regression, and Supabase-specific RLS/security-advisor behavior. These remain staging/release-gate items.

This is an isolated PostgreSQL fixture test, not a Supabase staging environment. No production schema or data was changed; the cancellation migration remains undeployed to production.


## Read-only preflight review (2026-10-31)

- The live production migration ledger still contains exactly 11 migrations and ends at `20261031065025_restrict_nextgen_browser_table_privileges`. The cancellation migration is not deployed.
- The current production Security Advisor reports three warnings: two existing authenticated `SECURITY DEFINER` RPC warnings (`review_content_item` and `schedule_approved_content`) and leaked-password protection disabled.
- The proposed cancellation RPC is also `SECURITY DEFINER` in the exposed `public` schema. Expect the Security Advisor to flag it as an additional authenticated `SECURITY DEFINER` function unless its exposure/design is changed. Do not treat that warning as harmless or suppress it without review.
- Static source review confirms the cancellation routine checks `auth.uid()`, scopes the job and content to the owner, locks the content before the job, accepts only `queued` jobs, restores content only when the exact schedule/channel still match and no other active job exists, and writes an audit event.
- Static source review is not a runtime test. In particular, the eventual publishing worker must use a compatible content-then-job lock order (or an explicitly tested concurrency strategy) to avoid lock-order deadlocks.
- The existing `guard_publishing_job_status` trigger is intended to allow only queued-to-cancelled browser updates while preserving immutable job fields. Verify this trigger interaction in staging along with the RPC and audit insert.

**Preflight result:** Read-only production inspection only. The isolated PostgreSQL CI test above passed; no production writes or migration deployment occurred, and full Supabase staging runtime tests remain outstanding.
