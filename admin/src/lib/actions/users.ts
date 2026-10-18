"use server";

import { runMutation, ActionError, type ActionResult } from "@/lib/action";
import { parseOrThrow, uuidSchema } from "@/lib/validation";

const BAN_FOREVER = "876000h";

export async function setUserDisabled(userId: string, disabled: boolean): Promise<ActionResult> {
  return runMutation(["owner", "support"], async ({ db, user }) => {
    const id = parseOrThrow(uuidSchema, userId);
    if (id === user.id) throw new ActionError("You cannot disable your own account");
    const { data: isAdmin } = await db.from("admins").select("user_id").eq("user_id", id).maybeSingle();
    if (isAdmin) throw new ActionError("Remove admin access first (owner only)");
    const { error: pErr } = await db.from("profiles").update({ disabled }).eq("id", id);
    if (pErr) throw new Error(pErr.message);
    const { error: aErr } = await db.auth.admin.updateUserById(id, { ban_duration: disabled ? BAN_FOREVER : "none" });
    if (aErr) throw new Error(aErr.message);
    return { audit: { action: disabled ? "user.disable" : "user.enable", target_type: "user", target_id: id } };
  });
}

/** Permanently deletes the auth user; FK cascades remove all of their rows. Owner only. */
export async function deleteUser(userId: string): Promise<ActionResult> {
  return runMutation(["owner"], async ({ db, user }) => {
    const id = parseOrThrow(uuidSchema, userId);
    if (id === user.id) throw new ActionError("You cannot delete your own account");
    const { data: isAdmin } = await db.from("admins").select("user_id").eq("user_id", id).maybeSingle();
    if (isAdmin) throw new ActionError("Remove admin access before deleting this user");
    const { error } = await db.auth.admin.deleteUser(id);
    if (error) throw new Error(error.message);
    return { audit: { action: "user.delete", target_type: "user", target_id: id } };
  });
}
