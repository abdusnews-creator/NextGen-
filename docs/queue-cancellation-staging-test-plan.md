# Queue Cancellation — Staging Validation Plan

**Status:** Latest isolated PostgreSQL CI passed (2026-10-31; Run #54), including audited-cancellation bypass prevention, private-function privilege, owner, and empty-search-path assertions. Full Supabase staging validation remains pending.

## Current safety boundary

- A fresh branch listing confirms the Supabase project currently has only the production `main` branch; no separate staging branch is available.
- The cancellation migration `20261031130000_add_audited_queue_cancellation.sql` and RPC-hardening migration `20261031140000_move_privileged_nextgen_rpcs_to_private_schema.sql` are present in the repository but have **not** been applied to production.
- Pull request #9 remains a draft and must not be merged or deployed until the checks below pass.
- Do not test cancellation against production data.

## Preconditions

1. Provision or identify an isolated Supabase staging branch/project.
2. Confirm the staging database is disposable and contains no production user data.
3. Apply both queue-cancellation and private-RPC-hardening migrations to staging only, in timestamp order.
4. Confirm the RPC endpoints and private implementation grants are limited to the intended `authenticated` role (with `PUBLIC` and `anon` revoked).
5. Confirm authenticated browser clients have no direct `UPDATE` privilege or queued-cancellation RLS policy on `publishing_jobs`; cancellation must go through the audited RPC.
6. Confirm `nextgen_private` is not included in the project's exposed Data API schemas.
7. Run Supabase security advisors and inspect any new findings.

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
| Direct browser bypass | Authenticated owner attempts a direct `UPDATE` setting a queued job to `cancelled` | Permission denied; job remains queued and no cancellation audit event is created |
| Repeat / race | Two requests attempt to cancel the same queued job | At most one successful cancellation; no duplicate or inconsistent restoration |
| Schedule vs cancellation | Cancellation locks and restores content while a new schedule RPC waits on the same content row | Cancellation commits first; waiting schedule then succeeds; old job stays cancelled, new job remains queued, and content reflects the new schedule |

## Release gate

- All cases above pass on staging.
- Inspect resulting rows and audit events directly on staging.
- Confirm existing review and scheduling RPC behavior remains unchanged.
- Confirm direct browser table updates cannot bypass audited cancellation.
- Confirm the private schema is not exposed through PostgREST/Data API.
- Re-run security advisors.
- Review the final PR diff; merge only after explicit release approval.
- Apply the migration to production only as a separately approved deployment step, after staging passes.

## Current result

**Latest isolated PostgreSQL CI — PASSED (2026-10-31):** GitHub Actions [Run #54 (41185769813)](https://github.com/nextgen-i/NextGen/actions/runs/41185769813), commit `7c16f43f8a39a4759cecf84a8d5d05f8e0d038b7`. All workflow checks completed successfully on a disposable PostgreSQL 17 service.

Successful checks include:

- Cancellation authorization and state transitions: owner, cross-owner, unauthenticated, queued/processing/published/already-cancelled states, active-job protection, newer schedule preservation, and 1,000-character audit-note bound.
- Approval/rejection RPC regression using test-only snapshots of the current production `SECURITY DEFINER` RPC definitions: owner approval, owner rejection, audit events, bounded rejection reason, cross-owner rejection, repeated-decision rejection, invalid-action rejection, and unauthenticated rejection.
- RPC schema hardening: all three public RPC endpoints are `SECURITY INVOKER` wrappers; privileged implementations remain `SECURITY DEFINER` in the non-exposed `nextgen_private` schema.
- Private permission assertions: `authenticated` has the required schema USAGE and EXECUTE rights on the three private implementations; `anon` and `PUBLIC` do not have private-schema access or EXECUTE on those implementations; `anon` cannot execute the public wrappers.
- Direct browser cancellation bypass is blocked: the migration removes the legacy queued-to-cancelled RLS policy and revokes `UPDATE` on `publishing_jobs` from `PUBLIC`, `anon`, and `authenticated`; the regression test confirms the owner cannot directly cancel or omit the audit event.
- Function hardening assertions: all six public wrappers/private implementations pin an empty `search_path`; the three private privileged implementations retain `postgres` ownership.
- Two-session concurrent cancellation: one request commits, the competing request is rejected; exactly one cancellation audit event is written.
- Concurrent cancel-then-reschedule: the scheduling RPC waits for cancellation to commit, then succeeds; the old job remains cancelled, the new schedule is the only queued job, and the new timestamp remains on the content item.

**Important limitation:** This is an isolated PostgreSQL fixture test, not a Supabase staging environment. It validates RPC and trigger logic and privilege boundaries in the test fixture, but does not reproduce the live Supabase project's full RLS policies, API gateway behavior, Data API exposed-schema configuration, or Security Advisor. Full staging verification is still required.

No production schema or data was changed. The cancellation and RPC-hardening migrations remain undeployed to production.

## Production RLS inventory (read-only, 2026-10-31)

- All 10 NextGen application tables inspected in the public schema have RLS enabled.
- Policy counts: `content_items` 4; `platform_connections` 3; `publishing_jobs` 2; each of the other seven tables has 1.
- Policies target `authenticated` and use `auth.uid() = owner_id` ownership checks. The content update policy has both `USING` and `WITH CHECK`; browser content inserts are restricted to unapproved states; approval events are SELECT-only. At audit time, before the proposed hardening migration, publishing jobs exposed owner SELECT and queued-to-cancelled UPDATE; the proposed migration removes that direct UPDATE path.
- These tables do not have FORCE ROW LEVEL SECURITY. That is not a substitute for runtime testing: table owners and privileged functions can bypass RLS. The application Data API roles remain subject to RLS, but real Supabase staging tests are still required.
- This was a read-only catalog inspection of production. No policy, grant, row, or schema was changed.

## Read-only preflight review (2026-10-31)

- The live production migration ledger still contains exactly 11 migrations and ends at `20261031065025_restrict_nextgen_browser_table_privileges`. The cancellation and private-schema hardening migrations are not deployed.
- A fresh live Security Advisor check at 2026-10-31 08:31 UTC still reports exactly two public `SECURITY DEFINER` RPC warnings (`review_content_item` and `schedule_approved_content`) plus the separate leaked-password protection warning. This is expected before the private-schema migration is deployed; it is not evidence that the proposed migration has been validated.
- The proposed RPC-hardening migration moves the privileged implementations into `nextgen_private` and leaves stable `SECURITY INVOKER` wrappers in `public`; verify that the live Advisor no longer reports any of the three public RPCs after the staging migration.
- Static source review confirms the cancellation routine checks `auth.uid()`, scopes the job and content to the owner, locks the content before the job, accepts only `queued` jobs, restores content only when the exact schedule/channel still match and no other active job exists, and writes an audit event.
- Static source review confirms all application relations and auth helpers in the privileged RPC bodies are schema-qualified before the migration pins an empty `search_path`.
- Static source review is not a runtime test. In particular, the eventual publishing worker must use a compatible content-then-job lock order (or an explicitly tested concurrency strategy) to avoid lock-order deadlocks.
- Before the proposed hardening migration, `guard_publishing_job_status` allowed queued-to-cancelled browser updates while preserving immutable job fields. The proposed migration revokes that browser UPDATE privilege and drops its RLS policy so the audited RPC is the only client cancellation path. Verify this in staging.

**Preflight result:** Read-only production inspection only. Latest expanded isolated PostgreSQL CI passed, including private implementation grants, owner checks, empty search paths, public wrapper boundaries, approval/rejection regression, cancellation race, and schedule-vs-cancellation regression. No production writes or migration deployment occurred; full Supabase staging runtime tests remain outstanding.
