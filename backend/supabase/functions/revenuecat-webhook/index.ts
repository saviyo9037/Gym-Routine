// Supabase Edge Function (Deno). UNVERIFIED: not executed locally (no Deno installed).
// RevenueCat webhook -> revenuecat_events (idempotent) + entitlements (stale-safe).
// Secrets: REVENUECAT_WEBHOOK_AUTH (exact Authorization header value configured in the
// RevenueCat dashboard), SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (injected by Supabase).
import { createClient } from "npm:@supabase/supabase-js@2";
import { computeState, parseEvent, verifyAuthHeader } from "../_shared/entitlement.ts";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "method not allowed" });

  const expected = Deno.env.get("REVENUECAT_WEBHOOK_AUTH");
  if (!expected) return json(500, { error: "server misconfigured" }); // fail closed
  if (!verifyAuthHeader(req.headers.get("authorization"), expected)) return json(401, { error: "unauthorized" });

  // A billing event is a few KB; refuse anything absurd before parsing it.
  const length = Number(req.headers.get("content-length") ?? "0");
  if (length > 256 * 1024) return json(413, { error: "payload too large" });

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid json" });
  }
  const parsed = parseEvent(body);
  if ("error" in parsed) return json(400, { error: parsed.error });

  const state = computeState(parsed.event, Date.now());
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  // One transaction in SQL: ON CONFLICT (event_id) DO NOTHING, stale check, upsert.
  const { data, error } = await admin.rpc("apply_revenuecat_event", {
    p_event: parsed.event,
    p_state: state,
  });
  if (error) {
    console.error("apply_revenuecat_event failed", error.message);
    return json(500, { error: "processing failed" }); // non-2xx => RevenueCat retries
  }
  return json(200, { result: data });
});
