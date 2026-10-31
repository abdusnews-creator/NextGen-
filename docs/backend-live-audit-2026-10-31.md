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


## Fresh live-schema verification (2026-10-31)

- Rechecked the live public schema with verbose table metadata. Core tables have RLS enabled: `channels`, `content_items`, `approval_events`, `automation_settings`, `platform_connections`, `publishing_jobs`, `channel_analytics_daily`, `content_analytics_daily`, `notification_preferences`, and `activity_logs`.
- Current row counts returned by the schema inventory: one row in `automation_settings`; zero rows in the other listed application tables. No application content or channel records were found in these tables during this check.
- The public schema has no stored access-token, secret, or credential column. The only column matching the token-name scan is `platform_connections.token_expires_at` (expiry timestamp only); OAuth token storage is not implemented in this table.
- Browser grants are narrow: analytics, activity logs, and approval events are SELECT-only; publishing jobs have SELECT and UPDATE only (with RLS/trigger restrictions); platform connections have SELECT/INSERT/UPDATE; channels and content have owner-scoped browser operations.
- The Security Advisor was re-run and still reports the same three warnings: leaked-password protection disabled, plus authenticated EXECUTE access to the two SECURITY DEFINER RPCs. The RPCs are deliberately authenticated entry points for review/scheduling and their definitions include explicit `auth.uid()` and owner/state checks. Keep their current restricted grants; do not remove authenticated EXECUTE without replacing the workflow with a safe alternative.
- The Supabase documentation confirms leaked-password protection is configured in the project's Auth settings and is a Pro-plan-and-above feature. The connected Supabase tools do not expose an Auth password-security setting update action, so this setting cannot be changed through the available integration. Dashboard action remains pending.


## Original migration recovery (2026-10-31)

The original SQL for the three previously missing migrations was recovered directly from the live `supabase_migrations.schema_migrations` ledger (including the stored `statements` arrays), rather than reconstructed from memory or inferred from the current schema. The exact SQL statements were restored as repository files:

- `supabase/migrations/20261027094432_create_nextgen_core_workspace_schema.sql`
- `supabase/migrations/20261027095520_enforce_content_channel_owner_match.sql`
- `supabase/migrations/20261027223652_add_platform_connections_secure.sql`

All three files were fetched back from GitHub after creation to verify that the files exist and contain content. These files are restored source artifacts only; no migration was re-applied to the live database, and no production schema was changed during this recovery step. Before any future deployment, compare the restored files with the live schema and the later hardening migrations, then validate the full migration chain in a disposable/staging database.


## Full migration-chain reconciliation (2026-10-31)

The complete live migration ledger was compared against the repository's `supabase/migrations/` files. All 11 applied migration versions now have corresponding SQL files in the repository. The four missing later migration files were restored from the live ledger, and the two pre-existing files that differed only by blank-line formatting were verified as equivalent to the ledger SQL. The comparison passed for all 11 files when ignoring blank-line formatting; no SQL statement differences were detected.

No production migrations were re-applied as part of this reconciliation. The next safe validation is to replay the chain against a disposable/staging Supabase database, not the live project.


## Static SQL review of all 11 migrations (2026-10-31)

The complete 11-file migration chain was reviewed from the GitHub default branch. This is a source review only: no SQL was executed and no production or staging database was modified. A real migration replay remains pending because Supabase Branching requires the Pro plan.

### Findings

1. **High — cancelled scheduled content can become stuck.** The scheduling RPC changes the content row from `approved` to `scheduled`. The browser update/delete policies only permit `draft`, `pending_approval`, or `rejected` content. The browser may cancel a queued publishing job, but the cancellation policy/trigger changes only the job row; no trigger or RPC restores the associated content item to an editable/approvable state. The scheduling RPC also accepts only `approved` content. Therefore, after cancellation, the content remains `scheduled` and cannot be edited or scheduled again through the current browser/RPC paths. **Recommended fix:** add an owner-checked, audited cancellation RPC that atomically cancels the queued job and restores the content item to `approved` (only when no other active job exists), or provide an equivalent safe reschedule workflow. Test concurrency and audit-event behavior before deployment.

2. **Medium — deleting a channel with existing content may be blocked.** Migration `20261027095520_enforce_content_channel_owner_match` drops the original single-column channel foreign keys (which used `ON DELETE SET NULL`) and replaces them with a composite `(channel_id, owner_id)` foreign key without an `ON DELETE` action. PostgreSQL therefore uses `NO ACTION`; deleting a channel referenced by content rows will fail. **Recommended fix:** decide the intended product behavior. If content should be retained with its channel detached, use a PostgreSQL 17-compatible column-list action such as `ON DELETE SET NULL (channel_id)` on the composite FK, and test it. Otherwise implement a deliberate soft-delete or cascade policy. Do not change this until the desired channel-removal behavior is confirmed.

3. **Medium — Auto Approval is not yet a complete backend workflow.** The schema allows the owner to enable `auto_approval_enabled` and select `approval_mode = 'auto'`, but the reviewed migrations do not implement a trusted automated reviewer that proves spelling, factual, copyright, duplicate, and platform-policy checks passed before approval. The review RPC is an owner-driven approve/reject action, not an automated safety pipeline. Keep Auto Approval OFF until a server-side validator and audited approval path enforce every required check and route uncertain/sensitive content to manual review.

4. **Low — nullable platform identity can permit duplicate pending connection rows.** The unique constraint on `(owner_id, platform, platform_user_id)` does not prevent multiple rows with a NULL `platform_user_id` under PostgreSQL's default NULL-distinct uniqueness behavior. Consider a partial unique index for rows where `platform_user_id IS NULL` if the product intends one pending connection per owner/platform.

### Positive controls confirmed in source

- Owner-scoped RLS and composite owner foreign keys are present across the workspace and analytics relationships.
- Browser content creation is restricted to unapproved states; approval metadata must remain empty on browser writes.
- Approval history is read-only to browser users and written by the owner-checking review RPC.
- Scheduling requires explicitly approved content, a future timestamp, an owner-owned active channel, and matching platforms.
- Browser job updates are limited to cancellation of queued jobs; job payload fields are guarded against mutation.
- Client writes cannot claim a platform connection is verified, mark content published, or enable background mode.
- The default automation settings remain manual approval, auto approval disabled, and background mode disabled.

### Validation boundary

This source review does not prove that the full chain replays successfully on a clean database. It also does not replace authenticated integration tests for owner/non-owner access, approval, scheduling, cancellation, and channel deletion. Do not deploy a corrective migration to production until those tests pass in a disposable staging database.


## Queue cancellation fix prepared (2026-10-31)

A proposed follow-up migration has been added to the repository:

- `supabase/migrations/20261031130000_add_audited_queue_cancellation.sql`

It adds an owner-checked `cancel_scheduled_content` RPC that:
- accepts only a queued job belonging to the authenticated owner;
- locks the associated content and job rows and permits only queued-to-cancelled transitions;
- restores the content to `approved` and clears `scheduled_for` only when the content still matches the exact cancelled schedule and no other queued/processing job exists;
- appends a `cancelled` approval event with a bounded audit note;
- revokes default/public and anon execution and grants the RPC only to authenticated users.

The migration file was fetched back from GitHub and verified after creation. **It has not been applied to Supabase.** Production migration history remains at the existing 11 applied versions. Runtime verification and concurrency/security tests remain pending until a staging or disposable database is available. The frontend must call this RPC for cancellation if/when the migration is approved and deployed; the current direct job-cancel path does not restore content state by itself.
