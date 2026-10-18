// Unit tests for the admin hardening: CSRF origin check, login throttle, exact-match
// admin grant, CSP/security headers and the "no raw HTML" rule.
// MOCK-ONLY where noted: the Supabase clients are the in-memory mocks from helpers/mock.ts.
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { beforeEach, describe, expect, it } from "vitest";
import { isSameOrigin } from "@/lib/csrf";
import { SlidingWindowLimiter, loginEmailLimiter, loginIpLimiter } from "@/lib/rate-limit";
import { setUserDisabled } from "@/lib/actions/users";
import { addAdmin } from "@/lib/actions/admins";
import { login } from "@/lib/actions/auth";
import { contentSecurityPolicy } from "../../next.config";
import config from "../../next.config";
import { mutations, OTHER_ID, reset, state, type Call, type Resp } from "./helpers/mock";

beforeEach(reset);

describe("isSameOrigin (pure)", () => {
  const host = "admin.example.test";
  it("accepts the same origin, with or without a forwarded host", () => {
    expect(isSameOrigin({ origin: `https://${host}`, host })).toBe(true);
    expect(isSameOrigin({ origin: `https://${host}`, host: "internal:3000", forwardedHost: host })).toBe(true);
  });
  it("accepts non-browser requests that carry no Origin", () => {
    expect(isSameOrigin({ host })).toBe(true);
  });
  it("rejects another site, the literal null origin and garbage", () => {
    expect(isSameOrigin({ origin: "https://evil.example", host })).toBe(false);
    expect(isSameOrigin({ origin: "null", host })).toBe(false);
    expect(isSameOrigin({ origin: "not a url", host })).toBe(false);
    expect(isSameOrigin({ origin: `https://${host}.evil.example`, host })).toBe(false);
  });
  it("rejects Sec-Fetch-Site cross-site and same-site", () => {
    expect(isSameOrigin({ origin: `https://${host}`, host, fetchSite: "cross-site" })).toBe(false);
    expect(isSameOrigin({ origin: `https://${host}`, host, fetchSite: "same-site" })).toBe(false);
    expect(isSameOrigin({ origin: `https://${host}`, host, fetchSite: "same-origin" })).toBe(true);
  });
});

describe("MOCK-ONLY: CSRF guard in runMutation", () => {
  it("refuses a cross-origin mutation before the guard or any database access", async () => {
    state.requestHeaders = { origin: "https://evil.example", host: "admin.example.test" };
    const res = await setUserDisabled(OTHER_ID, true);
    expect(res).toEqual({ ok: false, error: "forbidden" });
    expect(state.createServiceClient).not.toHaveBeenCalled();
    expect(mutations()).toHaveLength(0);
  });

  it("refuses Sec-Fetch-Site cross-site", async () => {
    state.requestHeaders = { host: "admin.example.test", "sec-fetch-site": "cross-site" };
    expect((await setUserDisabled(OTHER_ID, true)).ok).toBe(false);
    expect(mutations()).toHaveLength(0);
  });

  it("lets a same-origin mutation through (and audits it)", async () => {
    state.requestHeaders = { origin: "https://admin.example.test", host: "admin.example.test", "sec-fetch-site": "same-origin" };
    const res = await setUserDisabled(OTHER_ID, true);
    expect(res.ok).toBe(true);
    expect(state.calls.some((c) => c.table === "audit_log" && c.op === "insert")).toBe(true);
  });
});

describe("SlidingWindowLimiter (pure)", () => {
  it("limits after max failures inside the window and frees up afterwards", () => {
    let t = 1_000_000;
    const l = new SlidingWindowLimiter(3, 60_000, () => t);
    for (let i = 0; i < 3; i++) {
      expect(l.isLimited("a")).toBe(false);
      l.record("a");
    }
    expect(l.isLimited("a")).toBe(true);
    expect(l.isLimited("b")).toBe(false); // keys are independent
    t += 60_001;
    expect(l.isLimited("a")).toBe(false);
  });

  it("reset clears a key", () => {
    const l = new SlidingWindowLimiter(1, 60_000);
    l.record("a");
    expect(l.isLimited("a")).toBe(true);
    l.reset("a");
    expect(l.isLimited("a")).toBe(false);
  });
});

describe("MOCK-ONLY: login throttle and origin check", () => {
  const form = (email: string, password = "pw") => {
    const fd = new FormData();
    fd.set("email", email);
    fd.set("password", password);
    return fd;
  };

  it("blocks the 6th attempt for an e-mail without calling the auth server again", async () => {
    const email = "throttle-1@example.test";
    loginEmailLimiter.reset(email);
    state.signInError = "Invalid login credentials";
    for (let i = 0; i < 5; i++) {
      const r = await login({}, form(email));
      expect(r.error).toMatch(/Invalid credentials/);
    }
    expect(state.signInCalls).toBe(5);
    const blocked = await login({}, form(email));
    expect(blocked.error).toMatch(/Too many attempts/);
    expect(state.signInCalls).toBe(5);
    loginEmailLimiter.reset(email);
    loginIpLimiter.reset("unknown");
  });

  it("a valid password for a NON-admin counts as a failed attempt and signs out", async () => {
    const email = "throttle-2@example.test";
    loginEmailLimiter.reset(email);
    loginIpLimiter.reset("unknown");
    state.adminRole = null; // signs in fine, but is not an admin
    const r = await login({}, form(email));
    expect(r.error).toMatch(/not an admin/);
    expect(loginEmailLimiter.isLimited(email)).toBe(false); // only 1 attempt so far
    for (let i = 0; i < 4; i++) await login({}, form(email));
    expect(loginEmailLimiter.isLimited(email)).toBe(true);
    loginEmailLimiter.reset(email);
    loginIpLimiter.reset("unknown");
  });

  it("refuses a cross-origin login post without touching the auth server", async () => {
    state.requestHeaders = { origin: "https://evil.example", host: "admin.example.test" };
    const r = await login({}, form("csrf@example.test"));
    expect(r.error).toBeDefined();
    expect(state.signInCalls).toBe(0);
  });

  it("a successful admin sign-in resets the e-mail counter", async () => {
    const email = "throttle-3@example.test";
    loginEmailLimiter.reset(email);
    loginIpLimiter.reset("unknown");
    state.signInError = "bad";
    await login({}, form(email));
    await login({}, form(email));
    state.signInError = null;
    await expect(login({}, form(email))).rejects.toBeDefined(); // redirect("/mfa") throws
    expect(loginEmailLimiter.isLimited(email)).toBe(false);
    const audited = state.calls.filter((c) => c.table === "audit_log" && c.op === "insert");
    expect(audited).toHaveLength(1);
    expect((audited[0]!.payload as { action: string }).action).toBe("auth.login");
    loginIpLimiter.reset("unknown");
  });
});

describe("MOCK-ONLY: granting admin uses an exact e-mail match", () => {
  it("never uses ilike (wildcards in an address could pick the wrong user)", async () => {
    let seen: Call | undefined;
    state.respond = (c: Call): Resp | undefined => {
      if (c.table === "profiles" && c.op === "select") {
        seen = c;
        return { data: [{ id: OTHER_ID }] };
      }
      return undefined;
    };
    const res = await addAdmin({ email: "Jo_hn@Example.test", role: "support" });
    expect(res.ok).toBe(true);
    expect(seen).toBeDefined();
    expect(seen!.filters.some(([k]) => k === "ilike")).toBe(false);
    expect(seen!.filters).toContainEqual(["eq:email", ["jo_hn@example.test"]]);
  });
});

describe("security headers", () => {
  it("CSP locks the app down and only allows the configured Supabase origin", () => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://abcd.supabase.co";
    const csp = contentSecurityPolicy();
    expect(csp).toContain("default-src 'self'");
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).toContain("object-src 'none'");
    expect(csp).toContain("base-uri 'self'");
    expect(csp).toContain("form-action 'self'");
    expect(csp).toContain("connect-src 'self' https://abcd.supabase.co wss://abcd.supabase.co");
    expect(csp).not.toMatch(/script-src[^;]*\*/);
    expect(csp).not.toMatch(/default-src[^;]*\*/);
  });

  it("every route gets CSP, HSTS, nosniff, frame deny and a locked-down permissions policy", async () => {
    const rules = await config.headers!();
    const all = rules.find((r) => r.source === "/:path*")!.headers;
    const get = (k: string) => all.find((h) => h.key === k)?.value;
    expect(get("Content-Security-Policy")).toContain("default-src 'self'");
    expect(get("Strict-Transport-Security")).toMatch(/max-age=\d+/);
    expect(get("X-Content-Type-Options")).toBe("nosniff");
    expect(get("X-Frame-Options")).toBe("DENY");
    expect(get("Permissions-Policy")).toContain("camera=()");
    expect(config.poweredByHeader).toBe(false);
  });
});

describe("no raw HTML sinks in the admin source", () => {
  function files(dir: string): string[] {
    return readdirSync(dir).flatMap((n) => {
      const p = path.join(dir, n);
      if (statSync(p).isDirectory()) return n === "tests" ? [] : files(p);
      return /\.(ts|tsx)$/.test(n) ? [p] : [];
    });
  }
  it("never uses dangerouslySetInnerHTML, innerHTML or eval", () => {
    const root = path.resolve(__dirname, "..");
    const bad = files(root).filter((f) => /dangerouslySetInnerHTML|\.innerHTML\s*=|\beval\s*\(|new Function\s*\(/.test(readFileSync(f, "utf8")));
    expect(bad).toEqual([]);
  });
});
