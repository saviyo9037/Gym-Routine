"use server";

import { runMutation, ActionError, type ActionResult } from "@/lib/action";
import { COMP_MAX_DAYS, parseOrThrow, premiumGrantSchema, uuidSchema } from "@/lib/validation";

const DAY_MS = 86_400_000;

/**
 * Comp ("manual premium") access. Owner and support only.
 *  - a reason is mandatory and is written to the audit log;
 *  - an expiry is mandatory, capped at 90 days for support and 10 years for owners;
 *  - open-ended access ("no expiry") is OWNER ONLY.
 * The database derives the user's 'premium_comp' entitlement from the grant log (migration 0009), so the app
 * and the video-url function both honour it, and an expired or revoked grant stops working.
 */
export async function grantPremium(input: unknown): Promise<ActionResult<{ grantId: string }>> {
  return runMutation<{ grantId: string }>(["owner", "support"], async ({ db, user, role }) => {
    const v = parseOrThrow(premiumGrantSchema, input);

    if (v.no_expiry && role !== "owner") throw new ActionError("Only owners can grant open-ended access");
    if (v.expires_at) {
      const ms = v.expires_at.getTime() - Date.now();
      if (ms < 60_000) throw new ActionError("The expiry must be in the future");
      const maxDays = role === "owner" ? COMP_MAX_DAYS.owner : COMP_MAX_DAYS.support;
      if (ms > maxDays * DAY_MS) throw new ActionError(`The expiry cannot be more than ${maxDays} days away for your role`);
    }

    let targetId: string;
    if (v.user_id) {
      const { data, error } = await db.from("profiles").select("id").eq("id", v.user_id).maybeSingle();
      if (error) throw new Error(error.message);
      if (!data) throw new ActionError("No user with that id");
      targetId = data.id as string;
    } else {
      // Exact match (the schema lower-cases the address); never ilike, "_" and "%" are wildcards there.
      const { data, error } = await db.from("profiles").select("id").eq("email", v.email as string).maybeSingle();
      if (error) throw new Error(error.message);
      if (!data) throw new ActionError("No user with that email. They must sign up in the app first.");
      targetId = data.id as string;
    }

    const { data: row, error } = await db
      .from("manual_premium_grants")
      .insert({
        user_id: targetId,
        reason: v.reason,
        granted_by: user.id,
        expires_at: v.no_expiry ? null : (v.expires_at as Date).toISOString(),
      })
      .select("id")
      .single();
    if (error || !row) throw new ActionError("Could not create the grant");
    const grantId = row.id as string;
    return {
      audit: {
        action: "premium.grant",
        target_type: "user",
        target_id: targetId,
        metadata: { grant_id: grantId, reason: v.reason, expires_at: v.no_expiry ? null : (v.expires_at as Date).toISOString(), no_expiry: v.no_expiry },
      },
      data: { grantId },
    };
  });
}

export async function revokePremium(grantId: unknown): Promise<ActionResult> {
  return runMutation(["owner", "support"], async ({ db, user }) => {
    const id = parseOrThrow(uuidSchema, grantId);
    const { data, error } = await db
      .from("manual_premium_grants")
      .update({ revoked_at: new Date().toISOString(), revoked_by: user.id })
      .eq("id", id)
      .is("revoked_at", null)
      .select("id, user_id");
    if (error) throw new ActionError("Could not revoke the grant");
    const rows = Array.isArray(data) ? data : data ? [data] : [];
    if (rows.length === 0) throw new ActionError("Grant not found or already revoked");
    return { audit: { action: "premium.revoke", target_type: "user", target_id: String((rows[0] as { user_id?: string }).user_id ?? ""), metadata: { grant_id: id } } };
  });
}
