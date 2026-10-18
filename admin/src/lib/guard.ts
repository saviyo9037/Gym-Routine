import "server-only";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import { createSessionClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/admin";

export const ADMIN_ROLES = ["owner", "support", "content"] as const;
export type AdminRole = (typeof ADMIN_ROLES)[number];

export type GuardCode = "unauthenticated" | "mfa_required" | "forbidden";

export class GuardError extends Error {
  constructor(public readonly code: GuardCode, message?: string) {
    super(message ?? code);
    this.name = "GuardError";
  }
}

export interface AdminContext {
  user: User;
  role: AdminRole;
  /** Service-role client. Exists only because the caller passed the guard. */
  db: SupabaseClient;
}

export interface GuardOptions {
  /** Default "aal2". Only the MFA enrol/verify actions use "aal1". */
  aal?: "aal1" | "aal2";
}

/**
 * THE single authorisation gate for every page and server action:
 *   1. a valid session (user validated by the Supabase Auth server),
 *   2. MFA assurance level aal2 (TOTP verified in this session),
 *   3. a row in `admins` whose role is in `allowed`.
 * Throws GuardError otherwise. Nothing may touch the service-role client before this passes.
 */
export async function requireAdmin(allowed: readonly AdminRole[], opts: GuardOptions = {}): Promise<AdminContext> {
  const session = await createSessionClient();
  const { data: userData, error: userErr } = await session.auth.getUser();
  if (userErr || !userData?.user) throw new GuardError("unauthenticated");

  const needAal = opts.aal ?? "aal2";
  if (needAal === "aal2") {
    const { data: aal, error: aalErr } = await session.auth.mfa.getAuthenticatorAssuranceLevel();
    if (aalErr || !aal || aal.currentLevel !== "aal2") throw new GuardError("mfa_required");
  }

  const db = createServiceClient();
  const { data: row, error: adminErr } = await db
    .from("admins")
    .select("role")
    .eq("user_id", userData.user.id)
    .maybeSingle();
  if (adminErr) throw new GuardError("forbidden", "admin lookup failed");
  const role = row?.role as AdminRole | undefined;
  if (!role || !(ADMIN_ROLES as readonly string[]).includes(role) || !allowed.includes(role)) {
    throw new GuardError("forbidden");
  }
  return { user: userData.user, role, db };
}
