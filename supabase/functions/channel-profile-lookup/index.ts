// NextGen secure profile-name lookup scaffold.
// Deploy as Supabase Edge Function: channel-profile-lookup
// Never put provider tokens or the YouTube API key in browser code.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://nextgen-i.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function extractHandle(platform: string, rawUrl: string): string {
  const u = new URL(rawUrl);
  const host = u.hostname.toLowerCase().replace(/^www\./, "");
  const parts = u.pathname.split("/").filter(Boolean);
  if (platform === "youtube" && ["youtube.com", "m.youtube.com"].includes(host)) {
    return parts.find((p) => p.startsWith("@")) || "";
  }
  if (platform === "facebook" && ["facebook.com", "m.facebook.com", "fb.com"].includes(host)) {
    return parts[0] || "";
  }
  if (platform === "instagram" && host === "instagram.com") return parts[0] || "";
  if (platform === "threads" && ["threads.net", "threads.com"].includes(host)) return parts[0] || "";
  throw new Error("The link does not match the selected platform.");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) return json({ error: "Supabase function environment is not configured." }, 500);

  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "Sign in to NextGen first." }, 401);
  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) return json({ error: "Your session is invalid or expired. Please sign in again." }, 401);

  try {
    const body = await req.json();
    const platform = String(body.platform || "").toLowerCase();
    const profileUrl = String(body.url || "").trim();
    const accessToken = String(body.access_token || "").trim();
    if (!["youtube", "facebook", "instagram", "threads"].includes(platform)) {
      return json({ error: "Unsupported platform." }, 400);
    }
    const parsed = new URL(profileUrl);
    if (parsed.protocol !== "https:") return json({ error: "Use a valid HTTPS profile link." }, 400);
    const handle = extractHandle(platform, profileUrl);

    let apiUrl = "";
    const headers: Record<string, string> = {};
    if (platform === "youtube") {
      const apiKey = Deno.env.get("YOUTUBE_DATA_API_KEY");
      if (!apiKey) return json({ error: "YouTube API is not configured yet. Add YOUTUBE_DATA_API_KEY to Supabase function secrets." }, 503);
      if (!handle.startsWith("@")) return json({ error: "Use the channel's YouTube handle URL (youtube.com/@handle)." }, 400);
      apiUrl = "https://www.googleapis.com/youtube/v3/channels?part=snippet&forHandle=" + encodeURIComponent(handle) + "&key=" + encodeURIComponent(apiKey);
    } else {
      if (!accessToken) return json({
        error: "Connect and authorize this account first. No username-based name guessing is allowed.",
        code: "OAUTH_REQUIRED",
        platform,
      }, 428);
      headers.Authorization = "Bearer " + accessToken;
      if (platform === "facebook") {
        // Requires an authorized Facebook Page access token and appropriate Graph API permissions.
        apiUrl = "https://graph.facebook.com/v23.0/me?fields=id,name,username";
      } else if (platform === "instagram") {
        // Requires an authorized Instagram professional-account token with profile access.
        apiUrl = "https://graph.instagram.com/v23.0/me?fields=id,username,name";
      } else {
        // Requires a valid Threads user access token.
        apiUrl = "https://graph.threads.net/v1.0/me?fields=id,username,name";
      }
    }

    const response = await fetch(apiUrl, { headers });
    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      return json({
        error: "The platform API rejected the request. Check permissions, token, API access and configured secrets.",
        platform,
        provider_status: response.status,
      }, 502);
    }

    const profile = platform === "youtube" ? result.items?.[0]?.snippet : result;
    const displayName = String(profile?.title || profile?.name || "").trim();
    const returnedHandle = String(profile?.customUrl || profile?.username || handle).trim();
    if (!displayName) return json({ error: "The platform did not return a profile name for this link.", platform }, 404);
    return json({ platform, display_name: displayName, handle: returnedHandle, verified_by_platform: true });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Invalid request." }, 400);
  }
});
