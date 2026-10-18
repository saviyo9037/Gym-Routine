"use server";

import type { SupabaseClient } from "@supabase/supabase-js";
import { runMutation, ActionError, type ActionResult } from "@/lib/action";
import { adminRoleSchema, parseOrThrow, uuidSchema } from "@/lib/validation";

async function ownerCount(db: SupabaseClient): Promise<number> {
  const { count, error } = await db.from("admins").select("user_id", { count: "exact", head: true }).eq("role", "owner");
  if (error) throw new Error(error.message);
  return count ?? 0;
}

/** Grants a role to an EXISTING user (looked up by profile email). Owner only. */
export async function addAdmin(input: unknown): Promise<ActionResult> {
  return runMutation(["owner"], async ({ db, user }) => {
    const { email, role } = parseOrThrow(adminRoleSchema, input);
    // Exact match (the schema lower-cases the address). ilike would treat "_" and "%" in an
    // address as wildcards and could grant admin to a different, similar-looking user.
    const { data: p, error: pErr } = await db.from("profiles").select("id").eq("email", email).maybeSingle();
    if (pErr) throw new Error(pErr.message);
    if (!p) throw new ActionError("No user with that email. They must sign up in the app first.");
    const { error } = await db.from("admins").upsert({ user_id: p.id, role, created_by: user.id });
    if (error) throw new Error(error.message);
    return { audit: { action: "admin.grant", target_type: "user", target_id: p.id as string, metadata: { role } } };
  });
}

export async function changeAdminRole(userId: unknown, role: unknown): Promise<ActionResult> {
  return runMutation(["owner"], async ({ db }) => {
    const id = parseOrThrow(uuidSchema, userId);
    const r = parseOrThrow(adminRoleSchema.shape.role, role);
    const { data: cur } = await db.from("admins").select("role").eq("user_id", id).maybeSingle();
    if (!cur) throw new ActionError("Admin not found");
    if (cur.role === "owner" && r !== "owner" && (await ownerCount(db)) <= 1) {
      throw new ActionError("Cannot demote the last owner");
    }
    const { error } = await db.from("admins").update({ role: r }).eq("user_id", id);
    if (error) throw new Error(error.message);
    return { audit: { action: "admin.role_change", target_type: "user", target_id: id, metadata: { from: cur.role, to: r } } };
  });
}

export async function removeAdmin(userId: unknown): Promise<ActionResult> {
  return runMutation(["owner"], async ({ db }) => {
    const id = parseOrThrow(uuidSchema, userId);
    const { data: cur } = await db.from("admins").select("role").eq("user_id", id).maybeSingle();
    if (!cur) throw new ActionError("Admin not found");
    if (cur.role === "owner" && (await ownerCount(db)) <= 1) throw new ActionError("Cannot remove the last owner");
    const { error } = await db.from("admins").delete().eq("user_id", id);
    if (error) throw new Error(error.message);
    return { audit: { action: "admin.revoke", target_type: "user", target_id: id, metadata: { role: cur.role } } };
  });
}
