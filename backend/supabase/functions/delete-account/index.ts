// Supabase Edge Function (Deno). UNVERIFIED: not executed locally (no Deno installed).
// Deletes the caller's cloud data (via the delete_my_account_data RPC, run AS the user)
// and then deletes the auth user with the service role. The service-role key never
// leaves this function.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, content-type, apikey, x-client-info",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json(405, { error: "method not allowed" });

  const authHeader = req.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) return json(401, { error: "missing bearer token" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: u, error: uErr } = await asUser.auth.getUser();
  if (uErr || !u.user) return json(401, { error: "invalid token" });
  const userId = u.user.id;

  // 1. Remove the user's rows (RLS-safe: SECURITY DEFINER function keyed on auth.uid()).
  const { error: rpcErr } = await asUser.rpc("delete_my_account_data");
  if (rpcErr) {
    console.error("delete_my_account_data failed", rpcErr.message);
    return json(500, { error: "data deletion failed" });
  }

  // 2. Remove the auth user (cascades to profiles and any remaining FK rows).
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { error: delErr } = await admin.auth.admin.deleteUser(userId);
  if (delErr) {
    console.error("deleteUser failed", delErr.message);
    return json(500, { error: "auth user deletion failed; data already removed, retry" });
  }
  await admin.from("audit_log").insert({
    actor_id: userId, actor_role: "user", action: "account.deleted", target_type: "user", target_id: userId,
  });
  return json(200, { deleted: true });
});
