import { beforeEach, describe, expect, it } from "vitest";
import { GuardError, requireAdmin } from "@/lib/guard";
import { reset, state, OTHER_ID } from "./helpers/mock";

beforeEach(reset);

async function code(p: Promise<unknown>) {
  try {
    await p;
    return "ok";
  } catch (e) {
    expect(e).toBeInstanceOf(GuardError);
    return (e as GuardError).code;
  }
}

describe("requireAdmin", () => {
  it("rejects when there is no session, without touching the service client", async () => {
    state.user = null;
    expect(await code(requireAdmin(["owner"]))).toBe("unauthenticated");
    expect(state.createServiceClient).not.toHaveBeenCalled();
  });

  it("requires aal2 by default, without touching the service client", async () => {
    state.aal = "aal1";
    expect(await code(requireAdmin(["owner"]))).toBe("mfa_required");
    expect(state.createServiceClient).not.toHaveBeenCalled();
  });

  it("allows aal1 only when explicitly requested (MFA enrol/verify)", async () => {
    state.aal = "aal1";
    expect(await code(requireAdmin(["owner"], { aal: "aal1" }))).toBe("ok");
  });

  it("rejects signed-in users who are not admins", async () => {
    state.adminRole = null;
    expect(await code(requireAdmin(["owner", "support", "content"]))).toBe("forbidden");
  });

  it("rejects an admin whose role is not in the allowed list", async () => {
    state.adminRole = "content";
    expect(await code(requireAdmin(["owner", "support"]))).toBe("forbidden");
  });

  it("rejects an unknown role value stored in the table", async () => {
    state.adminRole = "superuser";
    expect(await code(requireAdmin(["owner"]))).toBe("forbidden");
  });

  it("fails closed if the admin lookup errors", async () => {
    state.adminLookupError = true;
    expect(await code(requireAdmin(["owner"]))).toBe("forbidden");
  });

  it.each(["owner", "support", "content"] as const)("accepts %s when listed and returns role + service client", async (role) => {
    state.adminRole = role;
    const ctx = await requireAdmin([role]);
    expect(ctx.role).toBe(role);
    expect(ctx.user.id).toBe(state.user!.id);
    expect(ctx.db).toBeDefined();
  });

  it("looks up the role by the authenticated user's id, never a caller-supplied one", async () => {
    await requireAdmin(["owner"]);
    const lookup = state.calls.find((c) => c.table === "admins")!;
    expect(lookup.filters).toContainEqual(["eq:user_id", [state.user!.id]]);
    expect(lookup.filters.some(([, v]) => v[0] === OTHER_ID)).toBe(false);
  });
});
