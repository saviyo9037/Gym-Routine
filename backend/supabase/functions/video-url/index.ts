// Supabase Edge Function (Deno). UNVERIFIED: not executed locally (no Deno installed); the pure logic in
// ../_shared/video_url.ts is covered by node tests, the SQL decision by the PGlite harness.
//
// Returns a short-lived signed URL for ONE exercise video in the PRIVATE bucket "exercise-videos" after a
// SERVER-SIDE entitlement check. Secrets (all injected by Supabase): SUPABASE_URL, SUPABASE_ANON_KEY,
// SUPABASE_SERVICE_ROLE_KEY. Optional dev switch: VIDEO_ALLOW_UNVERIFIED=1 serves videos whose licence is not
// verified (never set it in production). TRIAL_VIDEOS_LOCKED=false (`supabase secrets set`) lets store-trial users get
// signed URLs; unset/anything else keeps trials locked (needs migration 0010). Deploy: `supabase functions deploy video-url` (JWT verification stays ON).
import { createClient } from "npm:@supabase/supabase-js@2";
import { createRateLimiter, handleVideoUrl, type AccessResult } from "../_shared/video_url.ts";

const BUCKET = "exercise-videos";
const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, content-type, apikey, x-client-info",
};
const limiter = createRateLimiter(60, 60_000); // 60 URLs per user per minute, per instance

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });

  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) {
    return new Response(JSON.stringify({ error: "server misconfigured" }), {
      status: 500,
      headers: { ...cors, "content-type": "application/json" },
    });
  }
  const admin = createClient(url, service, { auth: { persistSession: false } });

  // A body is {"exercise_id": n}; refuse anything absurd before parsing.
  const length = Number(req.headers.get("content-length") ?? "0");
  let body: unknown = null;
  if (req.method === "POST") {
    if (length > 2048) {
      return new Response(JSON.stringify({ error: "payload too large" }), {
        status: 413,
        headers: { ...cors, "content-type": "application/json" },
      });
    }
    try {
      body = await req.json();
    } catch {
      body = null;
    }
  }

  const result = await handleVideoUrl(
    { method: req.method, authorization: req.headers.get("authorization"), body },
    {
      async getUserId(authorization) {
        const asUser = createClient(url, anon, {
          global: { headers: { Authorization: authorization } },
          auth: { persistSession: false },
        });
        const { data, error } = await asUser.auth.getUser();
        return error || !data.user ? null : data.user.id;
      },
      async access(userId, exerciseId, requireVerified, allowTrial) {
        const { data, error } = await admin.rpc("video_access", {
          p_user_id: userId,
          p_exercise_id: exerciseId,
          p_require_verified: requireVerified,
          p_allow_trial: allowTrial,
        });
        if (error) throw new Error("rpc failed");
        return data as AccessResult;
      },
      async sign(path, ttl) {
        const { data, error } = await admin.storage.from(BUCKET).createSignedUrl(path, ttl);
        return error || !data?.signedUrl ? null : data.signedUrl;
      },
      now: () => Date.now(),
    },
    limiter,
    {
      allowUnverified: Deno.env.get("VIDEO_ALLOW_UNVERIFIED") === "1",
      // Default (unset or anything but "false"): store-trial users get NO signed URL.
      allowTrial: Deno.env.get("TRIAL_VIDEOS_LOCKED") === "false",
    },
  );

  return new Response(JSON.stringify(result.body), {
    status: result.status,
    headers: { ...cors, "content-type": "application/json", "cache-control": "no-store", ...(result.headers ?? {}) },
  });
});
