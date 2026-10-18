import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";

export interface AppConfigRow {
  paywall_title: string | null;
  paywall_subtitle: string | null;
  paywall_benefits: string[];
  plan_badges: { monthly?: string; yearly?: string };
  promo_text: string | null;
  maintenance_mode: boolean;
  maintenance_message: string | null;
  min_app_version: string | null;
  access_model_override: string | null;
  updated_at: string | null;
}

export const EMPTY_CONFIG: AppConfigRow = {
  paywall_title: null,
  paywall_subtitle: null,
  paywall_benefits: [],
  plan_badges: {},
  promo_text: null,
  maintenance_mode: false,
  maintenance_message: null,
  min_app_version: null,
  access_model_override: null,
  updated_at: null,
};

export async function loadAppConfig(db: SupabaseClient): Promise<{ config: AppConfigRow; error: boolean }> {
  const { data, error } = await db.from("app_config").select("*").eq("id", 1).maybeSingle();
  if (error) return { config: EMPTY_CONFIG, error: true };
  if (!data) return { config: EMPTY_CONFIG, error: false };
  const r = data as Record<string, unknown>;
  const benefits = Array.isArray(r.paywall_benefits) ? (r.paywall_benefits as unknown[]).filter((x): x is string => typeof x === "string") : [];
  const badges = (typeof r.plan_badges === "object" && r.plan_badges !== null ? r.plan_badges : {}) as AppConfigRow["plan_badges"];
  return {
    error: false,
    config: {
      paywall_title: (r.paywall_title as string | null) ?? null,
      paywall_subtitle: (r.paywall_subtitle as string | null) ?? null,
      paywall_benefits: benefits,
      plan_badges: badges,
      promo_text: (r.promo_text as string | null) ?? null,
      maintenance_mode: r.maintenance_mode === true,
      maintenance_message: (r.maintenance_message as string | null) ?? null,
      min_app_version: (r.min_app_version as string | null) ?? null,
      access_model_override: (r.access_model_override as string | null) ?? null,
      updated_at: (r.updated_at as string | null) ?? null,
    },
  };
}
