"use server";

import { runMutation, ActionError, type ActionResult } from "@/lib/action";
import { accessModelSchema, operationalConfigSchema, paywallCopySchema, parseOrThrow } from "@/lib/validation";

/**
 * app_config is one row (id = 1). The database re-validates every value (CHECK constraints), and the app
 * re-validates what it downloads, so an admin typo can never break the app: it either fails here or falls
 * back to the built-in defaults in the app.
 */

/** Paywall copy (title, subtitle, benefits, plan badges, promo). Pricing copy => OWNER ONLY. */
export async function savePaywallCopy(input: unknown): Promise<ActionResult> {
  return runMutation(["owner"], async ({ db, user }) => {
    const v = parseOrThrow(paywallCopySchema, input);
    const badges: Record<string, string> = {};
    if (v.badge_monthly) badges.monthly = v.badge_monthly;
    if (v.badge_yearly) badges.yearly = v.badge_yearly;
    const { error } = await db
      .from("app_config")
      .update({
        paywall_title: v.paywall_title,
        paywall_subtitle: v.paywall_subtitle,
        paywall_benefits: v.paywall_benefits,
        plan_badges: badges,
        promo_text: v.promo_text,
        updated_by: user.id,
      })
      .eq("id", 1);
    if (error) throw new ActionError("Could not save the paywall copy");
    return {
      audit: {
        action: "app_config.paywall_copy",
        target_type: "app_config",
        target_id: 1,
        metadata: {
          title_set: v.paywall_title !== null,
          subtitle_set: v.paywall_subtitle !== null,
          benefits: v.paywall_benefits.length,
          badges: Object.keys(badges),
          promo_set: v.promo_text !== null,
        },
      },
    };
  });
}

/** Maintenance mode + minimum app version. Owner or support (support may need to react to an incident). */
export async function saveOperationalConfig(input: unknown): Promise<ActionResult> {
  return runMutation(["owner", "support"], async ({ db, user }) => {
    const v = parseOrThrow(operationalConfigSchema, input);
    if (v.maintenance_mode && !v.maintenance_message) {
      throw new ActionError("Write the message users will see during maintenance");
    }
    const { error } = await db
      .from("app_config")
      .update({
        maintenance_mode: v.maintenance_mode,
        maintenance_message: v.maintenance_message,
        min_app_version: v.min_app_version,
        updated_by: user.id,
      })
      .eq("id", 1);
    if (error) throw new ActionError("Could not save the app config");
    return {
      audit: {
        action: "app_config.operational",
        target_type: "app_config",
        target_id: 1,
        metadata: { maintenance_mode: v.maintenance_mode, min_app_version: v.min_app_version },
      },
    };
  });
}

/** Remote ACCESS_MODEL override (null = use the build's value). OWNER ONLY. */
export async function saveAccessModel(input: unknown): Promise<ActionResult> {
  return runMutation(["owner"], async ({ db, user }) => {
    const v = parseOrThrow(accessModelSchema, input);
    const { error } = await db
      .from("app_config")
      .update({ access_model_override: v.access_model_override, updated_by: user.id })
      .eq("id", 1);
    if (error) throw new ActionError("Could not save the access model");
    return {
      audit: {
        action: "app_config.access_model",
        target_type: "app_config",
        target_id: 1,
        metadata: { access_model_override: v.access_model_override },
      },
    };
  });
}
