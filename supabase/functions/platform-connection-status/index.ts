import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://nextgen-i.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "GET" && req.method !== "POST") return json({ error: "GET or POST required." }, 405);

  const authorization = req.headers.get("Authorization") || "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "Sign in to NextGen first." }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anonKey) return json({ error: "Server configuration is incomplete." }, 500);

  const supabase = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: authData, error: authError } = await supabase.auth.getUser();
  const user = authData?.user;
  if (authError || !user) return json({ error: "Session invalid or expired. Sign in again." }, 401);

  if (req.method === "GET") {
    const { data, error } = await supabase
      .from("platform_connections")
      .select("id, platform, platform_user_id, display_name, handle, connection_status, token_expires_at, scopes, last_verified_at, last_error, updated_at")
      .eq("owner_id", user.id)
      .order("platform");
    if (error) return json({ error: "Could not load connection statuses." }, 400);
    return json({ ok: true, connections: data ?? [] });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Send valid JSON." }, 400);
  }

  const platform = typeof body.platform === "string" ? body.platform.trim().toLowerCase() : "";
  const status = typeof body.connection_status === "string" ? body.connection_status.trim() : "pending";
  if (!["youtube", "facebook", "instagram", "threads"].includes(platform)) {
    return json({ error: "Unsupported platform." }, 400);
  }
  if (status === "connected") {
    return json({
      error: "A platform can only be marked connected after server-side OAuth verification. That verification flow is not configured yet.",
      code: "OAUTH_VERIFICATION_REQUIRED",
      platform,
    }, 409);
  }
  if (!["not_connected", "pending", "error"].includes(status)) {
    return json({ error: "Invalid connection status." }, 400);
  }

  const clean = (value: unknown, max = 200) =>
    typeof value === "string" ? value.trim().slice(0, max) || null : null;

  // These are unverified profile details only. A browser request cannot claim
  // scopes, token expiry, or a verified connection.
  const row = {
    owner_id: user.id,
    platform,
    platform_user_id: clean(body.platform_user_id, 250),
    display_name: clean(body.display_name),
    handle: clean(body.handle, 250),
    connection_status: status,
    token_expires_at: null,
    scopes: [],
    last_verified_at: null,
    last_error: status === "error" ? clean(body.last_error, 1000) : null,
    updated_at: new Date().toISOString(),
  };

  let query = supabase.from("platform_connections").select(
    "id, platform, platform_user_id, display_name, handle, connection_status, token_expires_at, scopes, last_verified_at, last_error, updated_at",
  );

  if (row.platform_user_id) {
    const existing = await supabase.from("platform_connections").select("id")
      .eq("owner_id", user.id).eq("platform", platform)
      .eq("platform_user_id", row.platform_user_id).maybeSingle();
    if (existing.error) return json({ error: "Could not verify existing connection." }, 400);
    if (existing.data?.id) {
      const result = await supabase.from("platform_connections").update(row)
        .eq("id", existing.data.id).eq("owner_id", user.id)
        .select("id, platform, platform_user_id, display_name, handle, connection_status, token_expires_at, scopes, last_verified_at, last_error, updated_at")
        .single();
      if (result.error) return json({ error: "Connection status could not be saved." }, 400);
      return json({ ok: true, connection: result.data });
    }
  }

  const result = await supabase.from("platform_connections").insert(row)
    .select("id, platform, platform_user_id, display_name, handle, connection_status, token_expires_at, scopes, last_verified_at, last_error, updated_at")
    .single();
  if (result.error) return json({ error: "Connection status could not be saved." }, 400);
  return json({ ok: true, connection: result.data }, 201);
});
