import { describe, expect, it } from "vitest";
import { createStoreInfoProvider, parseOfferings } from "@/lib/revenuecat";

// MOCK-ONLY: the RevenueCat HTTP call is replaced by a fake fetch. The real endpoint/response shape is
// UNVERIFIED (see the header of lib/revenuecat.ts); these tests prove the adapter's behaviour and safety only.

const KEY = "sk_super_secret_value";
const env = { REVENUECAT_API_KEY: KEY, REVENUECAT_PROJECT_ID: "proj123" };
const fakeFetch = (res: Partial<Response> | Error): typeof fetch =>
  (async () => {
    if (res instanceof Error) throw res;
    return res as Response;
  }) as unknown as typeof fetch;

describe("MOCK-ONLY store info adapter", () => {
  it("is 'not configured' without env, with placeholders, or with an empty value", async () => {
    for (const e of [{}, { REVENUECAT_API_KEY: KEY }, { REVENUECAT_API_KEY: "<key>", REVENUECAT_PROJECT_ID: "p" }, { REVENUECAT_API_KEY: "REPLACE-WITH-X", REVENUECAT_PROJECT_ID: "REPLACE-ME" }]) {
      expect(await createStoreInfoProvider(e, fakeFetch(new Error("never called"))).overview()).toEqual({ configured: false, plans: [] });
    }
  });
  it("refuses a project id that could escape the URL path", async () => {
    const r = await createStoreInfoProvider({ ...env, REVENUECAT_PROJECT_ID: "../admin?x=1" }, fakeFetch(new Error("never"))).overview();
    expect(r.configured).toBe(true);
    expect(r.error).toMatch(/unexpected format/);
  });
  it("sends the bearer key only to api.revenuecat.com and never returns it", async () => {
    let seen: { url: string; auth: string | null } | null = null;
    const f = (async (url: string, init: RequestInit) => {
      seen = { url, auth: new Headers(init.headers).get("authorization") };
      return { ok: true, json: async () => ({ items: [] }) } as unknown as Response;
    }) as unknown as typeof fetch;
    const r = await createStoreInfoProvider(env, f).overview();
    expect(seen!.url.startsWith("https://api.revenuecat.com/v2/projects/proj123/")).toBe(true);
    expect(seen!.auth).toBe(`Bearer ${KEY}`);
    expect(JSON.stringify(r)).not.toContain(KEY);
  });
  it("maps HTTP errors and network failures to a short message without the key", async () => {
    const http = await createStoreInfoProvider(env, fakeFetch({ ok: false, status: 401 })).overview();
    expect(http.error).toBe("RevenueCat answered HTTP 401");
    const net = await createStoreInfoProvider(env, fakeFetch(new Error(`boom ${KEY}`))).overview();
    expect(net.error).toBe("Could not reach RevenueCat");
    expect(JSON.stringify([http, net])).not.toContain(KEY);
  });
  it("parses packages defensively and reports unknown fields as null", async () => {
    const body = {
      items: [
        {
          packages: {
            items: [
              { lookup_key: "$rc_monthly", display_name: "Monthly", product: { store_identifier: "reptrack_monthly", subscription: { duration: "P1M" } } },
              { lookup_key: "$rc_annual", product: { store_identifier: "reptrack_yearly", price: { amount: 29.99, currency: "USD" } } },
            ],
          },
        },
      ],
    };
    const r = await createStoreInfoProvider(env, fakeFetch({ ok: true, json: async () => body })).overview();
    expect(r.plans).toEqual([
      { packageId: "$rc_monthly", title: "Monthly", productId: "reptrack_monthly", period: "P1M", price: null, trial: null },
      { packageId: "$rc_annual", title: null, productId: "reptrack_yearly", period: null, price: "29.99 USD", trial: null },
    ]);
  });
  it("never throws on garbage shapes", () => {
    for (const g of [null, undefined, 5, "x", [], {}, { items: 3 }, { items: [null, 1, { packages: "x" }] }, { items: [{ packages: { items: [null, 7] } }] }]) {
      expect(() => parseOfferings(g)).not.toThrow();
      expect(Array.isArray(parseOfferings(g))).toBe(true);
    }
  });
});
