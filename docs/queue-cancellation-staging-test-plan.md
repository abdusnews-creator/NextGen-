# Queue Cancellation — Staging Validation Plan

**Status:** Isolated PostgreSQL CI passed for cancellation, approval/rejection, RPC schema hardening, concurrent cancellation, and concurrent cancel-then-reschedule scenarios. Full Supabase staging validation remains pending.

## Current safety boundary

- The Supabase project currently exposes only the production `main` branch; no development/staging branch is available.
- The cancellation migration `20261031130000_add_audited_queue_cancellation.sql` and RPC-hardening migration `20261031140000_move_privileged_nextgen_rpcs_to_private_schema.sql` are present in the repository but have **not** been applied to production.
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
| Schedule vs cancellation | Cancellation locks and restores content while a new schedule RPC waits on the same content row | Cancellation commits first; waiting schedule then succeeds; old job stays cancelled, new job remains queued, and content reflects the new schedule |

## Release gate

- All cases above pass on staging.
- Inspect resulting rows and audit events directly on staging.
- Confirm existing review and scheduling RPC behavior remains unchanged.
- Re-run security advisors.
- Review the final PR diff; merge only after explicit release approval.
- Apply the migration to production only as a separately approved deployment step, after staging passes.

## Current result

**Expanded isolated PostgreSQL CI — PASSED (2026-10-31):** GitHub Actions [Run #39](https://github.com/nextgen-i/NextGen/actions/runs/41184528360), commit `c2b7cce95b94802dfba7137f967f87decccc6787`. The workflow applied the cancellation migration and the existing approval/scheduling migration to a disposable PostgreSQL 17 service, then ran the following tests successfully:

- Cancellation authorization and state transitions: owner, cross-owner, unauthenticated, queued/processing/published/already-cancelled states, active-job protection, newer schedule preservation, and 1,000-character audit-note bound.
- Approval/rejection RPC regression using test-only snapshots of the current production `SECURITY DEFINER` RPC definitions: owner approval, owner rejection, audit events, bounded rejection reason, cross-owner rejection, repeated-decision rejection, invalid-action rejection, and unauthenticated rejection.
- RPC schema hardening: the three public RPC endpoints are `SECURITY INVOKER` wrappers; privileged implementations remain `SECURITY DEFINER` in the non-exposed `nextgen_private` schema; `anon` and `PUBLIC` have no private-schema usage or public-wrapper execution.
- Two-session concurrent cancellation: one request commits, the competing request receives SQLSTATE `55000`; exactly one cancellation audit event is written.
- Concurrent cancel-then-reschedule: the scheduling RPC waits for cancellation to commit, then succeeds; the old job remains cancelled, the new schedule is the only queued job, and the new timestamp remains on the content item.

**Important limitation:** This is an isolated PostgreSQL fixture test, not a Supabase staging environment. It validates the RPC and trigger logic but does not reproduce the live Supabase project's full RLS policies, API gateway behavior, or Security Advisor. Full staging verification is still required.

No production schema or data was changed. The cancellation migration remains undeployed to production.

## Read-only preflight review (2026-10-31)

- The live production migration ledger still contains exactly 11 migrations and ends at `20261031065025_restrict_nextgen_browser_table_privileges`. The cancellation migration is not deployed.
- The current production Security Advisor reports two warnings for authenticated `SECURITY DEFINER` RPCs (`review_content_item` and `schedule_approved_content`) and one warning for leaked-password protection disabled. The proposed RPC-hardening migration moves the privileged implementations into `nextgen_private` and leaves stable `SECURITY INVOKER` wrappers in `public`; this is expected to address the two function-exposure warnings after deployment, but must be verified with the live Security Advisor in staging.
- The proposed cancellation RPC is also moved into `nextgen_private` by the RPC-hardening migration, with a public `SECURITY INVOKER` wrapper. Verify that the live Advisor no longer reports any of the three public RPCs after the staging migration.
- Static source review confirms the cancellation routine checks `auth.uid()`, scopes the job and content to the owner, locks the content before the job, accepts only `queued` jobs, restores content only when the exact schedule/channel still match and no other active job exists, and writes an audit event.
- Static source review is not a runtime test. In particular, the eventual publishing worker must use a compatible content-then-job lock order (or an explicitly tested concurrency strategy) to avoid lock-order deadlocks.
- The existing `guard_publishing_job_status` trigger is intended to allow only queued-to-cancelled browser updates while preserving immutable job fields. Verify this trigger interaction in staging along with the RPC and audit insert.

**Preflight result:** Read-only production inspection only. The expanded isolated PostgreSQL CI suite, RPC schema/privilege assertions, approval/rejection regression, two-session cancellation race, and schedule-vs-cancellation regression all passed; no production writes or migration deployment occurred, and full Supabase staging runtime tests remain outstanding.
