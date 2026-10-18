import "server-only";

/**
 * READ-ONLY view of the store plans (monthly / yearly price and trial) for the "Plans & Paywall" page.
 *
 * Prices and trial lengths are owned by Google Play Console / RevenueCat, never by this panel. This module
 * only reads them so staff can see what the paywall will show.
 *
 * !! UNVERIFIED against a real RevenueCat project !!
 * The adapter below calls the RevenueCat REST API v2:
 *     GET https://api.revenuecat.com/v2/projects/{REVENUECAT_PROJECT_ID}/offerings?expand=items.package.product
 *     Authorization: Bearer {REVENUECAT_API_KEY}      (a v2 *secret* API key with read access to the project)
 * It was written from the public API description and never executed here (no RevenueCat account/key).
 * RevenueCat's v2 product objects describe the store product (identifier, type, subscription duration) but
 * may NOT include the localised price or the trial phase, because those come from the store. Every field is
 * therefore optional and the page shows "not provided by the API" instead of guessing. Before relying on
 * this page, run the call above once with your key and compare the response with `parseOfferings()`.
 *
 * The secret key is read ONLY here (server side) and is never sent to the browser.
 */

export interface StorePlan {
  packageId: string;
  title: string | null;
  productId: string | null;
  period: string | null;
  price: string | null;
  trial: string | null;
}

export interface StoreOverview {
  configured: boolean;
  plans: StorePlan[];
  /** Human-readable problem (never contains the key). */
  error?: string;
}

export interface StoreInfoProvider {
  overview(): Promise<StoreOverview>;
}

const asString = (v: unknown): string | null => (typeof v === "string" && v.trim() !== "" ? v.trim().slice(0, 120) : null);
const asRecord = (v: unknown): Record<string, unknown> | null =>
  typeof v === "object" && v !== null && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
const asItems = (v: unknown): unknown[] => {
  const r = asRecord(v);
  return r && Array.isArray(r.items) ? r.items : Array.isArray(v) ? v : [];
};

/** Defensive parser: unknown shapes yield nulls, never throw. Exported for tests. */
export function parseOfferings(json: unknown): StorePlan[] {
  const plans: StorePlan[] = [];
  const root = asRecord(json);
  if (!root) return plans;
  for (const off of asItems(root)) {
    const offering = asRecord(off);
    if (!offering) continue;
    for (const pk of asItems(offering.packages)) {
      const pkg = asRecord(pk);
      if (!pkg) continue;
      const product = asRecord(pkg.product);
      const subscription = asRecord(product?.subscription);
      const price = asRecord(product?.price) ?? asRecord(subscription?.price);
      const amount = typeof price?.amount === "number" ? price.amount : null;
      const currency = asString(price?.currency);
      plans.push({
        packageId: asString(pkg.lookup_key) ?? asString(pkg.id) ?? "package",
        title: asString(pkg.display_name) ?? asString(product?.display_name),
        productId: asString(product?.store_identifier) ?? asString(product?.id),
        period: asString(subscription?.duration) ?? asString(product?.duration),
        price: amount === null ? null : `${amount}${currency ? ` ${currency}` : ""}`,
        trial: asString(subscription?.trial_duration) ?? asString(product?.trial_duration),
      });
    }
  }
  return plans;
}

export function createStoreInfoProvider(
  env: Record<string, string | undefined> = process.env,
  fetchImpl: typeof fetch = fetch,
): StoreInfoProvider {
  const key = env.REVENUECAT_API_KEY;
  const project = env.REVENUECAT_PROJECT_ID;
  const bad = (v?: string) => !v || /[<>]/.test(v) || /^(REPLACE|your[-_ ])/i.test(v);
  return {
    async overview(): Promise<StoreOverview> {
      if (bad(key) || bad(project)) return { configured: false, plans: [] };
      // The project id goes into the URL path: allow only the characters RevenueCat ids use.
      if (!/^[A-Za-z0-9_-]{1,64}$/.test(project as string)) {
        return { configured: true, plans: [], error: "REVENUECAT_PROJECT_ID has an unexpected format" };
      }
      try {
        const res = await fetchImpl(
          `https://api.revenuecat.com/v2/projects/${project}/offerings?expand=items.package.product`,
          {
            headers: { Authorization: `Bearer ${key}`, Accept: "application/json" },
            signal: AbortSignal.timeout(8000),
            cache: "no-store",
          },
        );
        if (!res.ok) return { configured: true, plans: [], error: `RevenueCat answered HTTP ${res.status}` };
        return { configured: true, plans: parseOfferings(await res.json()) };
      } catch {
        return { configured: true, plans: [], error: "Could not reach RevenueCat" };
      }
    },
  };
}
