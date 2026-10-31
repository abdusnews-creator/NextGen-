# Connect NextGen to Supabase

## Current project status

The connected NextGen Supabase project is active. Its live database currently has the core workspace tables, owner-scoped RLS, audited approval/scheduling RPCs, and server-only publishing-state guards.

**Do not run `database/schema.sql` against the current NextGen project.** That file is an older draft schema using `content_drafts` and `user_id`; the current app uses `content_items` and `owner_id`. Applying the legacy script to a fresh or existing project would not reproduce the current app schema.

The live Supabase migration history includes three baseline migrations that are not currently present in this repository:
- `20261027094432_create_nextgen_core_workspace_schema`
- `20261027095520_enforce_content_channel_owner_match`
- `20261027223652_add_platform_connections_secure`

Restore those source files before attempting a clean-room database setup. The later migrations in `supabase/migrations/` are incremental and assume those baseline tables already exist.

## 1. Browser configuration

The browser uses `supabase-config.js` with the project URL and a Supabase publishable key. A publishable key is expected to be visible in browser code; it is safe only when Row Level Security and grants are configured correctly.

Never put a `service_role` key, Supabase secret key, database password, OAuth client secret, or provider access/refresh token in HTML, JavaScript, GitHub, or chat.

## 2. Authentication settings

In Supabase Authentication settings:
- Configure the site URL to include `https://nextgen-i.github.io`.
- Add `https://nextgen-i.github.io/NextGen/login.html` as an allowed redirect URL.
- Enable leaked-password protection for password sign-in.
- Confirm email delivery and email confirmation settings before testing new accounts.

## 3. Edge Function secrets and deployment

The `channel-profile-lookup` function requires a valid signed-in NextGen user. YouTube profile lookup additionally requires the server-side `YOUTUBE_DATA_API_KEY` secret. Meta and Threads profile lookup still require proper provider OAuth authorization and permissions; those OAuth flows are not implemented by this function.

The `platform-connection-status` endpoint stores only unverified connection metadata. It deliberately cannot mark an account as `connected`; that state must come from a future server-side OAuth callback after the provider token and scopes have been verified.

To deploy functions through GitHub Actions, configure `SUPABASE_ACCESS_TOKEN` as a repository Actions secret. Do not put the token in the repository or send it through chat.

## 4. Background automation and publishing

There is currently no deployed publishing worker and no `pg_cron` scheduler in the connected database. The active Edge Functions are not a 24/7 publishing worker. Queue rows are only scheduled records; no social platform post is sent.

Manual approval remains the default. Auto Approval is a user preference only; no automatic approval worker is active. Background mode must remain disabled until a real server-side worker is deployed, monitored, and verified.

Before production publishing, implement and test provider OAuth, encrypted token storage/refresh, a leased and idempotent worker, retry/backoff and dead-letter handling, observability, and platform-specific permission checks.
