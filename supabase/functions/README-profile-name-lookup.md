# NextGen verified Profile/Page Name lookup

This is a secure backend starting point for looking up the **actual** profile/page name. It intentionally never derives the name from a handle.

## Important status

- The Edge Function source has been added at `supabase/functions/channel-profile-lookup/index.ts`.
- It is **not deployed yet** and the Channels page does not call it yet.
- YouTube lookup is implemented in the function when a YouTube Data API key is configured.
- Facebook, Instagram and Threads lookup requires the user to authorize the relevant account and provide a short-lived/current provider access token to the function. The function does not store tokens.
- Do not call this production-ready until the OAuth consent flows, permissions and error cases are tested for each platform.

## Deploy from a computer with Supabase CLI

1. Install the Supabase CLI and sign in: `supabase login`.
2. In the repository root, link the project: `supabase link --project-ref vexntvbufnawtxszslsz`.
3. Set the YouTube key as a server-side secret (never in HTML/JavaScript):
   `supabase secrets set YOUTUBE_DATA_API_KEY=YOUR_KEY`
4. Deploy:
   `supabase functions deploy channel-profile-lookup`
5. Keep JWT verification enabled. The function requires a signed-in NextGen user and checks their Supabase session.
6. Test with an authenticated session and verify returned `verified_by_platform: true` before using the name in the UI.

## YouTube API key

Create/enable YouTube Data API v3 in Google Cloud Console and restrict the key to YouTube Data API v3 where possible. Add it only as a Supabase Function secret.

## Facebook / Instagram / Threads

The function expects an access token only after a proper OAuth connection is implemented. Do not paste tokens into chat or commit them to GitHub. For Facebook, the token must have permission to read the selected Page. Instagram needs an eligible professional account and the correct Instagram API permissions. Threads needs a Threads user authorization token. Provider APIs and permissions can change, so verify each flow against current Meta/Google developer documentation before production.

## Security and behavior

- The endpoint requires a valid signed-in Supabase user.
- Provider access tokens are used only for the request and are not written to the database or logs.
- The UI should display the returned `display_name` only when `verified_by_platform` is true.
- If authorization/API lookup is missing or fails, leave the Profile/Page Name empty and show a clear message; never guess from the username.
- This lookup endpoint does not connect publishing, scheduling, comments or background automation.
