# Connect NextGen to Supabase

This repository is a static GitHub Pages prototype. These steps prepare real authentication and database access, but the connection is not live until you create and configure your own Supabase project.

## 1. Create the project
1. Open https://supabase.com/ and sign in or create an account.
2. Create a new project and keep its database password private.
3. In Project Settings / API (or the Connect dialog), copy the Project URL and the **publishable key** (or legacy anon key).

## 2. Configure the web app
1. Open `supabase-config.js` in this repository.
2. Replace `PASTE_YOUR_SUPABASE_PROJECT_URL_HERE` with your Project URL.
3. Replace `PASTE_YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY_HERE` with the publishable/anon key.
4. Commit the change and wait for GitHub Pages to deploy.

The browser key is not a secret; access must be protected by Row Level Security. **Never paste a service_role key, secret key, database password, or OAuth client secret into browser files or chat.**

## 3. Apply the database schema
1. In the Supabase dashboard, open SQL Editor.
2. Copy the latest contents of `database/schema.sql` into a new query and run it. The script includes an idempotent migration adding `content` and `metadata` to existing `content_drafts` tables; rerun it after schema updates.
3. Check that the tables and RLS policies were created successfully.

## 4. Authentication settings
- In Authentication settings, configure allowed site URLs to include `https://nextgen-i.github.io`.
- Add the sign-in page redirect URL: `https://nextgen-i.github.io/NextGen/login.html`.
- Email confirmation may need to be completed before a new account can sign in.

## Safety and current limitations
- The login page uses Supabase Auth only when valid project settings are present.
- Review Queue can save and load the supported draft fields per signed-in account when Supabase is configured and the latest schema has been applied. The Channels page currently syncs only limited channel state; this is not full production CRUD.
- No social-media publishing, OAuth connections, background worker, or 24/7 automation is active.
- Before commercial use, review the schema, security policies, recovery, logging, billing and privacy requirements.
