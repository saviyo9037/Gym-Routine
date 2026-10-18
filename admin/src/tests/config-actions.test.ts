import { beforeEach, describe, expect, it } from "vitest";
import { saveAccessModel, saveOperationalConfig, savePaywallCopy } from "@/lib/actions/app-config";
import { deleteAnnouncement, saveAnnouncement, setAnnouncementActive } from "@/lib/actions/announcements";
import { grantPremium, revokePremium } from "@/lib/actions/premium";
import { auditEntries, mutations, OTHER_ID, reset, state, type Call, type Resp } from "./helpers/mock";

// MOCK-ONLY: every test here runs against a mocked Supabase client (no database, no network). They prove the
// role matrix, validation and audit behaviour of the server actions, not the database. The database side
// (constraints, RLS, entitlement merge) is covered by backend/supabase/tests/app_config.test.sql.

beforeEach(reset);

const UUID = OTHER_ID;
const inDays = (n: number) => new Date(Date.now() + n * 86_400_000).toISOString();

type Role = "owner" | "support" | "content";
interface Case {
  name: string;
  run: () => Promise<{ ok: boolean; error?: string }>;
  allowed: Role[];
  action: string;
}
const cases: Case[] = [
  { name: "savePaywallCopy", run: () => savePaywallCopy({ paywall_title: "Get RepTrack", paywall_benefits: "A\nB" }), allowed: ["owner"], action: "app_config.paywall_copy" },
  { name: "saveOperationalConfig", run: () => saveOperationalConfig({ maintenance_mode: "", min_app_version: "1.2.0" }), allowed: ["owner", "support"], action: "app_config.operational" },
  { name: "saveAccessModel", run: () => saveAccessModel({ access_model_override: "freemium" }), allowed: ["owner"], action: "app_config.access_model" },
  { name: "saveAnnouncement(create)", run: () => saveAnnouncement(null, { title: "Hi", body: "Hello", level: "info" }), allowed: ["owner", "support"], action: "announcement.create" },
  { name: "saveAnnouncement(update)", run: () => saveAnnouncement(UUID, { title: "Hi", body: "Hello", level: "warning" }), allowed: ["owner", "support"], action: "announcement.update" },
  { name: "setAnnouncementActive", run: () => setAnnouncementActive(UUID, true), allowed: ["owner", "support"], action: "announcement.activate" },
  { name: "deleteAnnouncement", run: () => deleteAnnouncement(UUID), allowed: ["owner", "support"], action: "announcement.delete" },
  { name: "grantPremium", run: () => grantPremium({ email: "user@example.test", reason: "Goodwill", expires_at: inDays(7) }), allowed: ["owner", "support"], action: "premium.grant" },
  { name: "revokePremium", run: () => revokePremium(UUID), allowed: ["owner", "support"], action: "premium.revoke" },
];

describe("MOCK-ONLY role enforcement on the new admin actions", () => {
  for (const c of cases) {
    for (const role of ["owner", "support", "content"] as Role[]) {
      const allowed = c.allowed.includes(role);
      it(`${c.name} as ${role} -> ${allowed ? "allowed + audited" : "forbidden, no writes"}`, async () => {
        state.adminRole = role;
        const r = await c.run();
        if (allowed) {
          expect(r.ok, JSON.stringify(r)).toBe(true);
          const audits = auditEntries();
          expect(audits).toHaveLength(1);
          expect(audits[0]).toMatchObject({ action: c.action, actor_id: state.user!.id, actor_role: role });
        } else {
          expect(r).toMatchObject({ ok: false, error: "forbidden" });
          expect(mutations()).toHaveLength(0);
          expect(auditEntries()).toHaveLength(0);
        }
      });
    }
    it(`${c.name} without MFA -> mfa_required, no writes`, async () => {
      state.aal = "aal1";
      expect(await c.run()).toMatchObject({ ok: false, error: "mfa_required" });
      expect(mutations()).toHaveLength(0);
    });
    it(`${c.name} without a session -> unauthenticated, no writes`, async () => {
      state.user = null;
      expect(await c.run()).toMatchObject({ ok: false, error: "unauthenticated" });
      expect(mutations()).toHaveLength(0);
    });
    it(`${c.name} from a foreign origin (CSRF) -> forbidden, no writes`, async () => {
      state.requestHeaders = { origin: "https://evil.example", host: "admin.example" };
      expect(await c.run()).toMatchObject({ ok: false, error: "forbidden" });
      expect(mutations()).toHaveLength(0);
    });
  }
});

const lastUpdate = () => state.calls.filter((c) => c.op === "update" && c.table === "app_config").at(-1)?.payload as Record<string, unknown>;

describe("MOCK-ONLY paywall copy validation", () => {
  it("accepts empty fields as 'use the built-in default' and stores nulls", async () => {
    expect((await savePaywallCopy({})).ok).toBe(true);
    expect(lastUpdate()).toMatchObject({ paywall_title: null, paywall_subtitle: null, paywall_benefits: [], plan_badges: {}, promo_text: null });
  });
  it("stores benefits one per line and badges for monthly/yearly only", async () => {
    await savePaywallCopy({ paywall_benefits: " Track every set \n\n Offline first ", badge_yearly: "Best value" });
    expect(lastUpdate()).toMatchObject({ paywall_benefits: ["Track every set", "Offline first"], plan_badges: { yearly: "Best value" } });
  });
  const bad: [string, Record<string, unknown>][] = [
    ["title over 80", { paywall_title: "x".repeat(81) }],
    ["subtitle over 200", { paywall_subtitle: "x".repeat(201) }],
    ["markup in title", { paywall_title: "<b>Buy</b>" }],
    ["markup in a benefit", { paywall_benefits: "ok\n<script>alert(1)</script>" }],
    ["more than 8 benefits", { paywall_benefits: ["1", "2", "3", "4", "5", "6", "7", "8", "9"] }],
    ["a benefit over 120", { paywall_benefits: ["x".repeat(121)] }],
    ["badge over 24", { badge_yearly: "x".repeat(25) }],
    ["promo over 200", { promo_text: "x".repeat(201) }],
  ];
  for (const [name, input] of bad) {
    it(`rejects ${name} and writes nothing`, async () => {
      expect(await savePaywallCopy(input)).toMatchObject({ ok: false, error: "validation" });
      expect(mutations()).toHaveLength(0);
    });
  }
  it("surfaces a database rejection without leaking details", async () => {
    state.respond = (c: Call): Resp | undefined => (c.table === "app_config" && c.op === "update" ? { error: { message: "violates check constraint secret_name" } } : undefined);
    const r = await savePaywallCopy({ paywall_title: "ok" });
    expect(r).toEqual({ ok: false, error: "Could not save the paywall copy" });
    expect(auditEntries()).toHaveLength(0);
  });
});

describe("MOCK-ONLY operational config + access model validation", () => {
  for (const v of ["1.2", "v1.2.3", "1.2.3.4", "latest", "1.2.3-beta", "12345.0.0"]) {
    it(`rejects min version "${v}"`, async () => {
      expect(await saveOperationalConfig({ min_app_version: v })).toMatchObject({ ok: false, error: "validation" });
      expect(mutations()).toHaveLength(0);
    });
  }
  it("accepts x.y.z, x.y.z+build and empty (no minimum)", async () => {
    expect((await saveOperationalConfig({ min_app_version: "1.2.3" })).ok).toBe(true);
    expect((await saveOperationalConfig({ min_app_version: "1.2.3+4" })).ok).toBe(true);
    expect((await saveOperationalConfig({ min_app_version: "" })).ok).toBe(true);
    expect(lastUpdate()).toMatchObject({ min_app_version: null });
  });
  it("maintenance on needs a message", async () => {
    expect(await saveOperationalConfig({ maintenance_mode: "true", maintenance_message: "" })).toMatchObject({
      ok: false,
      error: "Write the message users will see during maintenance",
    });
    expect(mutations()).toHaveLength(0);
    expect((await saveOperationalConfig({ maintenance_mode: "true", maintenance_message: "Back at 10:00" })).ok).toBe(true);
  });
  it("rejects markup and over-long maintenance messages", async () => {
    expect((await saveOperationalConfig({ maintenance_mode: "true", maintenance_message: "<a href=x>hi</a>" })).ok).toBe(false);
    expect((await saveOperationalConfig({ maintenance_mode: "true", maintenance_message: "x".repeat(301) })).ok).toBe(false);
    expect(mutations()).toHaveLength(0);
  });
  it("access model: unknown rejected, 'default' clears the override", async () => {
    expect(await saveAccessModel({ access_model_override: "free" })).toMatchObject({ ok: false, error: "validation" });
    expect(mutations()).toHaveLength(0);
    await saveAccessModel({ access_model_override: "default" });
    expect(lastUpdate()).toMatchObject({ access_model_override: null });
    await saveAccessModel({ access_model_override: "subscription_required" });
    expect(lastUpdate()).toMatchObject({ access_model_override: "subscription_required" });
  });
});

describe("MOCK-ONLY announcements validation", () => {
  const ok = { title: "Hi", body: "Hello", level: "info" };
  it("rejects bad level, empty title/body, markup, over-long text and reversed dates", async () => {
    const bad = [
      { ...ok, level: "critical" },
      { ...ok, title: "  " },
      { ...ok, body: "" },
      { ...ok, title: "<img src=x>" },
      { ...ok, body: "x".repeat(501) },
      { ...ok, starts_at: "2026-02-01T10:00", ends_at: "2026-01-01T10:00" },
      { ...ok, starts_at: "not a date" },
    ];
    for (const b of bad) expect(await saveAnnouncement(null, b), JSON.stringify(b)).toMatchObject({ ok: false, error: "validation" });
    expect(mutations()).toHaveLength(0);
  });
  it("rejects an invalid id on update/delete/toggle", async () => {
    expect(await saveAnnouncement("nope", ok)).toMatchObject({ ok: false, error: "validation" });
    expect(await deleteAnnouncement("nope")).toMatchObject({ ok: false, error: "validation" });
    expect(await setAnnouncementActive("nope", true)).toMatchObject({ ok: false, error: "validation" });
    expect(mutations()).toHaveLength(0);
  });
  it("defaults the start to now and records created_by", async () => {
    await saveAnnouncement(null, ok);
    const ins = state.calls.find((c) => c.table === "announcements" && c.op === "insert")!.payload as Record<string, unknown>;
    expect(ins.created_by).toBe(state.user!.id);
    expect(typeof ins.starts_at).toBe("string");
    expect(ins.ends_at).toBeNull();
  });
});

describe("MOCK-ONLY manual premium rules", () => {
  const base = { email: "user@example.test", reason: "Goodwill after a bug" };
  const insertPayload = () => state.calls.find((c) => c.table === "manual_premium_grants" && c.op === "insert")?.payload as Record<string, unknown> | undefined;

  it("requires a reason, a target and an expiry (or an explicit owner no-expiry)", async () => {
    const bad = [
      { ...base, reason: "", expires_at: inDays(5) },
      { ...base, reason: "ab", expires_at: inDays(5) },
      { reason: "Goodwill", expires_at: inDays(5) },
      { ...base, user_id: UUID, expires_at: inDays(5) },
      { ...base },
      { ...base, expires_at: inDays(5), no_expiry: "true" },
      { ...base, expires_at: "garbage" },
      { ...base, reason: "<script>x</script>", expires_at: inDays(5) },
    ];
    for (const b of bad) expect(await grantPremium(b), JSON.stringify(b)).toMatchObject({ ok: false, error: "validation" });
    expect(mutations()).toHaveLength(0);
  });
  it("support is limited to 90 days and cannot grant open-ended access", async () => {
    state.adminRole = "support";
    expect(await grantPremium({ ...base, no_expiry: "true" })).toMatchObject({ ok: false, error: "Only owners can grant open-ended access" });
    expect(await grantPremium({ ...base, expires_at: inDays(100) })).toMatchObject({ ok: false });
    expect(mutations()).toHaveLength(0);
    expect((await grantPremium({ ...base, expires_at: inDays(60) })).ok).toBe(true);
  });
  it("owner may grant up to 10 years or no expiry (stored as null)", async () => {
    expect((await grantPremium({ ...base, expires_at: inDays(400) })).ok).toBe(true);
    expect(await grantPremium({ ...base, expires_at: inDays(4000) })).toMatchObject({ ok: false });
    reset();
    expect((await grantPremium({ ...base, no_expiry: "true" })).ok).toBe(true);
    expect(insertPayload()).toMatchObject({ expires_at: null, reason: base.reason, granted_by: state.user!.id });
  });
  it("an expiry in the past (or within a minute) is refused", async () => {
    expect(await grantPremium({ ...base, expires_at: inDays(-1) })).toMatchObject({ ok: false, error: "The expiry must be in the future" });
    expect(mutations()).toHaveLength(0);
  });
  it("unknown user -> clear error, nothing written", async () => {
    state.respond = (c) => (c.table === "profiles" && c.op === "select" ? { data: [] } : undefined);
    expect(await grantPremium({ ...base, expires_at: inDays(5) })).toMatchObject({ ok: false });
    expect(mutations()).toHaveLength(0);
  });
  it("audit entry records the reason, the target and the grant id", async () => {
    await grantPremium({ ...base, expires_at: inDays(5) });
    const a = auditEntries()[0] as { action: string; target_type: string; metadata: Record<string, unknown> };
    expect(a.action).toBe("premium.grant");
    expect(a.target_type).toBe("user");
    expect(a.metadata).toMatchObject({ reason: base.reason, no_expiry: false });
    expect(a.metadata.grant_id).toBeTruthy();
  });
  it("revoking something already revoked / missing is reported", async () => {
    state.respond = (c) => (c.table === "manual_premium_grants" && c.op === "update" ? { data: [] } : undefined);
    expect(await revokePremium(UUID)).toMatchObject({ ok: false, error: "Grant not found or already revoked" });
    expect(auditEntries()).toHaveLength(0);
  });
  it("revoke rejects a non-uuid id", async () => {
    expect(await revokePremium("1; drop table")).toMatchObject({ ok: false, error: "validation" });
    expect(mutations()).toHaveLength(0);
  });
});
