# NextGen Live Backend Audit — 2026-10-31

> Audit note only. This is a read-only inventory reconstructed from the live Supabase catalog and deployed Edge Function sources. It is **not** a Supabase migration and must never be copied into `supabase/migrations/` or replayed as SQL.

## Scope and change status

- Supabase project: `vexntvbufnawtxszslsz`
- GitHub repository: `nextgen-i/NextGen`
- Live database inspected read-only; no SQL/DDL changes made during this audit.
- No content was published and no publishing worker was deployed.
- No UI files or design were changed.

## Live Supabase migration history

The live database reports these 11 applied migrations:

1. `20261027094432_create_nextgen_core_workspace_schema`
2. `20261027095520_enforce_content_channel_owner_match`
3. `20261027223652_add_platform_connections_secure`
4. `20261030092814_expand_nextgen_content_publishing_analytics_schema`
5. `20261030092835_harden_nextgen_owner_policies_and_fk_indexes`
6. `20261030093128_add_nextgen_audited_approval_and_safe_scheduling`
7. `20261030093508_harden_nextgen_updated_at_function_search_path`
8. `20261030093539_restrict_publishing_job_execution_to_server_worker`
9. `20261030093647_block_client_side_published_content_and_jobs`
10. `20261031064935_harden_nextgen_approval_queue_and_connection_state`
11. `20261031065025_restrict_nextgen_browser_table_privileges`

The first three migration filenames are present in the live migration history but were not found in the GitHub default-branch code search during this audit. Their original SQL has **not** been recreated or guessed. Resolve this source-control gap from verified historical sources before attempting migration repair or replay.

## Verified database safeguards

- Owner-scoped RLS policies exist for channels, content items, platform connections, automation settings, analytics, notifications/preferences, activity logs, and approval-event reads.
- Authenticated users can insert content only in `draft` or `pending_approval` state, with approval metadata empty.
- Authenticated users can update/delete only unapproved content states; approval is performed through the audited review RPC.
- Approval events are read-only to authenticated owners.
- Authenticated users can read publishing jobs and cancel queued jobs; they cannot freely alter job execution state.
- A publishing-job insert requires content already explicitly approved, a valid unpaused owner channel, and matching content/channel platforms.
- Client-side callers cannot mark content as `published`; only a service-role worker can do so.
- Client-side callers cannot mark a platform connection as `connected`; only a verified server-side OAuth flow can do so.
- Background mode is blocked for non-service-role callers until a server-side worker is deployed and verified.
- `review_content_item` verifies `auth.uid()`, ownership, allowed review actions, and eligible content states before recording the decision.
- `schedule_approved_content` verifies `auth.uid()`, ownership, future schedule time, approved content, active owner channel, and matching platform. It creates a NextGen queue entry only; its return message explicitly says no platform publishing was performed.
- Trigger functions use pinned `search_path` settings. The two audited SECURITY DEFINER RPCs pin `search_path` to `public, pg_temp`.

## Current automation defaults observed

- Approval mode: `manual`
- Auto approval: `false`
- Background mode: `false`
- Timezone: `Asia/Kolkata`
- Daily idea times: `08:00`, `14:00`, `18:00`

## Deployed Edge Functions observed

- `super-handler` v2 — generic handler; not a publishing worker.
- `channel-profile-lookup` v2
- `draft-idea-queue` v3 — authenticated draft-queue insertion; does not publish or schedule.
- `platform-connection-status` v3 — authenticated connection-status endpoint; refuses client-side verification of a connected OAuth state.

All four were observed with JWT verification enabled.

## Open security / readiness items

1. Supabase Security Advisor reports leaked-password protection disabled. Enable it in Supabase Auth settings.
2. Security Advisor warns that authenticated users can execute the two SECURITY DEFINER RPCs:
   - `public.review_content_item(uuid, text, text)`
   - `public.schedule_approved_content(uuid, uuid, timestamptz)`

   Their current definitions include explicit `auth.uid()` checks, owner scoping, state validation, and pinned search paths. Do not blindly revoke EXECUTE or change them to SECURITY INVOKER: that may break the intended approval/scheduling workflow or conflict with current RLS. Review with an authenticated test matrix before changing grants or function security.
3. No `pg_cron` extension or verified background publishing worker was observed. Continuous background automation and real social-platform publishing remain unimplemented.
4. The first three live migrations are missing from the GitHub default-branch code search. Recover exact originals from verified commit/backup sources; do not synthesize migrations from the current live schema.

## Safe next steps

1. Recover and verify the three missing migration source files, preserving their original version numbers and SQL.
2. Compare the recovered SQL with the live catalog and repository history; do not reapply already-recorded migrations.
3. Enable leaked-password protection in Supabase Auth settings.
4. Test review/scheduling RPCs with owner, non-owner, unauthenticated, wrong-platform, paused-channel, and unapproved-content cases before any permission change.
5. Implement OAuth verification and a server-side worker with retry/idempotency and monitoring before enabling Background Mode. Keep Manual Approval ON by default and require explicit approval before scheduling/publishing unless the user deliberately changes the mode under the established safety rules.


## Additional recovery investigation (2026-10-31)

- Searched GitHub code and commit indexes for all three missing migration identifiers; no exact source files or matching migration commits were returned.
- Checked the repository branches available to the linked GitHub connection; the three exact migration paths were not present on `main` or the other inspected branches.
- An older commit titled “Add initial secured database schema for NextGen” (`96438ecb71d3218d9c940c7d38377cb8da9a5023`) contains a prototype schema using `content_drafts` and `draft_reviews`. This does **not** match the current live schema built around `content_items`, `approval_events`, and owner-scoped composite foreign keys. It is not a valid replacement for the missing applied migration.
- A separate historical content/publishing expansion commit (`ee8487bdaca1c30815ed65a9aea5ce25f321b433`) is an additive migration for a later schema and does not recover the three missing initial migrations.
- Therefore, no guessed or reconstructed SQL was added under `supabase/migrations/`. The live schema and applied migration ledger remain unchanged.
