import "server-only";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { publicEnv, serviceRoleKey } from "@/lib/env";

/**
 * Service-role client. Bypasses RLS: only ever call it AFTER requireAdmin()
 * (src/lib/guard.ts). This module is server-only and must never be imported from
 * a "use client" file (enforced by src/tests/no-service-role-in-client.test.ts).
 */
export function createServiceClient(): SupabaseClient {
  return createClient(publicEnv().NEXT_PUBLIC_SUPABASE_URL, serviceRoleKey(), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
