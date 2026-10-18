import { beforeEach, describe, expect, it } from "vitest";
import { setUserDisabled, deleteUser } from "@/lib/actions/users";
import { archiveExercise, createExercise, publishCatalogue, updateExercise } from "@/lib/actions/catalogue";
import { deleteMedia, setMediaStatus, uploadMedia, verifyMediaLicense } from "@/lib/actions/media";
import { deleteTemplate, saveTemplate } from "@/lib/actions/templates";
import { addAdmin, changeAdminRole, removeAdmin } from "@/lib/actions/admins";
import { loadUserWorkouts } from "@/lib/queries/user-workouts";
import { GuardError } from "@/lib/guard";
import { auditEntries, mutations, OTHER_ID, reset, state, type Call, type Resp } from "./helpers/mock";

beforeEach(reset);

const UUID = OTHER_ID;
const validExercise = {
  id: 7,
  name: "Test Press",
  primary_muscle_group: "Chest",
  equipment: "Barbell",
  difficulty: "Beginner",
  default_sets: 3,
  default_reps: 10,
  default_weight_kg: 20,
  rest_seconds: 90,
};
// 8-byte PNG signature + padding
const png = () => new File([new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0])], "a.png", { type: "image/png" });
const mediaForm = (over: Record<string, string | File> = {}) => {
  const fd = new FormData();
  const base: Record<string, string | File> = { exercise_id: "1", license: "CC-BY 4.0 (checked)", attribution: "Jane Doe", source_url: "", file: png() };
  for (const [k, v] of Object.entries({ ...base, ...over })) fd.set(k, v);
  return fd;
};
const adminTarget = (role: string) => (c: Call): Resp | undefined =>
  c.table === "admins" && c.op === "select" && c.filters.some(([k, v]) => k === "eq:user_id" && v[0] === UUID) ? { data: [{ role }] } : undefined;

type Role = "owner" | "support" | "content";
interface Case {
  name: string;
  run: () => Promise<{ ok: boolean; error?: string }>;
  allowed: Role[];
  action: string;
  respond?: (c: Call) => Resp | undefined;
}
const cases: Case[] = [
  { name: "setUserDisabled", run: () => setUserDisabled(UUID, true), allowed: ["owner", "support"], action: "user.disable" },
  { name: "deleteUser", run: () => deleteUser(UUID), allowed: ["owner"], action: "user.delete" },
  { name: "createExercise", run: () => createExercise(validExercise), allowed: ["owner", "content"], action: "exercise.create" },
  { name: "updateExercise", run: () => updateExercise(validExercise), allowed: ["owner", "content"], action: "exercise.update" },
  { name: "archiveExercise", run: () => archiveExercise(7), allowed: ["owner", "content"], action: "exercise.archive" },
  { name: "publishCatalogue", run: () => publishCatalogue("notes"), allowed: ["owner", "content"], action: "catalogue.publish" },
  { name: "uploadMedia", run: () => uploadMedia(mediaForm()), allowed: ["owner", "content"], action: "media.upload" },
  { name: "verifyMediaLicense", run: () => verifyMediaLicense(UUID), allowed: ["owner", "content"], action: "media.license_verified" },
  { name: "setMediaStatus", run: () => setMediaStatus(UUID, "published"), allowed: ["owner", "content"], action: "media.status" },
  { name: "deleteMedia", run: () => deleteMedia(UUID), allowed: ["owner", "content"], action: "media.delete" },
  { name: "saveTemplate", run: () => saveTemplate(null, { kind: "plan", title: "Push day" }), allowed: ["owner", "content"], action: "template.create" },
  { name: "deleteTemplate", run: () => deleteTemplate(UUID), allowed: ["owner", "content"], action: "template.delete" },
  { name: "addAdmin", run: () => addAdmin({ email: "x@example.test", role: "support" }), allowed: ["owner"], action: "admin.grant" },
  { name: "changeAdminRole", run: () => changeAdminRole(UUID, "support"), allowed: ["owner"], action: "admin.role_change", respond: adminTarget("content") },
  { name: "removeAdmin", run: () => removeAdmin(UUID), allowed: ["owner"], action: "admin.revoke", respond: adminTarget("content") },
];

describe("role enforcement on every mutating action", () => {
  for (const c of cases) {
    for (const role of ["owner", "support", "content"] as Role[]) {
      const allowed = c.allowed.includes(role);
      it(`${c.name} as ${role} -> ${allowed ? "allowed + audited" : "forbidden, no writes"}`, async () => {
        state.adminRole = role;
        state.respond = c.respond;
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
    it(`${c.name} without MFA (aal1) -> mfa_required, no writes`, async () => {
      state.aal = "aal1";
      const r = await c.run();
      expect(r).toMatchObject({ ok: false, error: "mfa_required" });
      expect(mutations()).toHaveLength(0);
    });
    it(`${c.name} without a session -> unauthenticated, no writes`, async () => {
      state.user = null;
      const r = await c.run();
      expect(r).toMatchObject({ ok: false, error: "unauthenticated" });
      expect(mutations()).toHaveLength(0);
    });
  }
});

describe("audit is mandatory", () => {
  it("surfaces failure when the audit write fails", async () => {
    state.auditError = true;
    const r = await createExercise(validExercise);
    expect(r.ok).toBe(false);
  });
});

describe("catalogue validation (same rules as the app)", () => {
  it("rejects an empty name and writes nothing", async () => {
    const r = await createExercise({ ...validExercise, name: "   " });
    expect(r).toMatchObject({ ok: false, error: "validation" });
    expect(mutations()).toHaveLength(0);
  });
  it("rejects a muscle group outside the 15 categories", async () => {
    const r = await createExercise({ ...validExercise, primary_muscle_group: "Neck" });
    expect(r).toMatchObject({ ok: false, error: "validation" });
    expect(mutations()).toHaveLength(0);
  });
  it("rejects missing equipment and bad difficulty", async () => {
    expect((await createExercise({ ...validExercise, equipment: "" })).ok).toBe(false);
    expect((await createExercise({ ...validExercise, difficulty: "Expert" })).ok).toBe(false);
    expect(mutations()).toHaveLength(0);
  });
  it("accepts every one of the 15 categories", async () => {
    for (const m of ["Chest", "Back", "Lats", "Upper Back and Traps", "Shoulders", "Biceps", "Triceps", "Forearms", "Quadriceps", "Hamstrings", "Glutes", "Calves", "Abs and Core", "Full Body", "Cardio"]) {
      expect((await createExercise({ ...validExercise, primary_muscle_group: m })).ok, m).toBe(true);
    }
  });
  it("publish goes through the publish_catalogue RPC", async () => {
    const r = await publishCatalogue("v2");
    expect(r).toMatchObject({ ok: true, data: { version: 2 } });
    expect(state.calls.some((c) => c.table === "rpc:publish_catalogue")).toBe(true);
  });
  it("reports 'nothing to publish' cleanly", async () => {
    state.respond = (c) => (c.op === "rpc" ? { data: null, error: { message: "nothing to publish" } } : undefined);
    expect(await publishCatalogue(undefined)).toMatchObject({ ok: false, error: "Nothing to publish" });
  });
});

describe("media upload", () => {
  it("stores a draft with licence UNVERIFIED (never auto-claims a licence)", async () => {
    const r = await uploadMedia(mediaForm());
    expect(r.ok).toBe(true);
    const ins = state.calls.find((c) => c.table === "exercise_media" && c.op === "insert")!;
    expect(ins.payload).toMatchObject({ license_verified: false, status: "draft", exercise_id: 1, media_type: "image", license: "CC-BY 4.0 (checked)" });
  });
  it("requires licence and attribution", async () => {
    expect((await uploadMedia(mediaForm({ license: "" }))).ok).toBe(false);
    expect((await uploadMedia(mediaForm({ attribution: " " }))).ok).toBe(false);
    expect(mutations()).toHaveLength(0);
  });
  it("rejects disallowed types", async () => {
    const r = await uploadMedia(mediaForm({ file: new File([new Uint8Array(10)], "a.gif", { type: "image/gif" }) }));
    expect(r.ok).toBe(false);
    expect(mutations()).toHaveLength(0);
  });
  it("rejects a mismatched extension/mime", async () => {
    const r = await uploadMedia(mediaForm({ file: new File([new Uint8Array(10)], "a.exe", { type: "image/png" }) }));
    expect(r.ok).toBe(false);
  });
  it("rejects oversized images (>5MB)", async () => {
    const big = new File([new Uint8Array(5 * 1024 * 1024 + 1)], "a.png", { type: "image/png" });
    const r = await uploadMedia(mediaForm({ file: big }));
    expect(r).toMatchObject({ ok: false });
    expect(mutations()).toHaveLength(0);
  });
  it("rejects a file whose bytes are not the claimed type", async () => {
    const fake = new File([new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9])], "a.png", { type: "image/png" });
    const r = await uploadMedia(mediaForm({ file: fake }));
    expect(r).toMatchObject({ ok: false, error: "File content does not match its type" });
    expect(mutations()).toHaveLength(0);
  });
  it("refuses to publish media whose licence is not verified", async () => {
    state.respond = (c) => (c.table === "exercise_media" && c.op === "select" ? { data: [{ license_verified: false }] } : undefined);
    const r = await setMediaStatus(UUID, "published");
    expect(r).toMatchObject({ ok: false, error: "Verify the licence before publishing" });
    expect(mutations()).toHaveLength(0);
  });
});

describe("user safety rails", () => {
  it("cannot disable or delete yourself", async () => {
    expect(await setUserDisabled(state.user!.id, true)).toMatchObject({ ok: false });
    expect(await deleteUser(state.user!.id)).toMatchObject({ ok: false });
    expect(mutations()).toHaveLength(0);
  });
  it("cannot delete another admin directly", async () => {
    state.respond = adminTarget("support");
    expect(await deleteUser(UUID)).toMatchObject({ ok: false });
    expect(mutations()).toHaveLength(0);
  });
  it("rejects a non-uuid user id", async () => {
    expect(await deleteUser("not-a-uuid")).toMatchObject({ ok: false, error: "validation" });
  });
});

describe("admin management", () => {
  it("cannot demote or remove the last owner", async () => {
    state.respond = (c) => {
      if (c.table === "admins" && c.op === "select" && c.head) return { count: 1 };
      return adminTarget("owner")(c);
    };
    expect(await changeAdminRole(UUID, "support")).toMatchObject({ ok: false, error: "Cannot demote the last owner" });
    expect(await removeAdmin(UUID)).toMatchObject({ ok: false, error: "Cannot remove the last owner" });
    expect(mutations()).toHaveLength(0);
  });
  it("validates role and email", async () => {
    expect(await addAdmin({ email: "nope", role: "support" })).toMatchObject({ ok: false, error: "validation" });
    expect(await addAdmin({ email: "a@example.test", role: "god" })).toMatchObject({ ok: false, error: "validation" });
  });
});

describe("viewing a user's workout data", () => {
  it.each(["owner", "support"] as const)("%s may view, and the view is audited before data is read", async (role) => {
    state.adminRole = role;
    await loadUserWorkouts(UUID);
    const idxAudit = state.calls.findIndex((c) => c.table === "audit_log");
    const idxRead = state.calls.findIndex((c) => c.table === "workout_sessions");
    expect(idxAudit).toBeGreaterThanOrEqual(0);
    expect(idxRead).toBeGreaterThan(idxAudit);
    expect(auditEntries()[0]).toMatchObject({ action: "user.view_workouts", target_id: UUID, actor_role: role });
  });
  it("content role is denied and nothing is read", async () => {
    state.adminRole = "content";
    await expect(loadUserWorkouts(UUID)).rejects.toBeInstanceOf(GuardError);
    expect(state.calls.some((c) => c.table === "workout_sessions")).toBe(false);
  });
  it("is denied without MFA", async () => {
    state.aal = "aal1";
    await expect(loadUserWorkouts(UUID)).rejects.toMatchObject({ code: "mfa_required" });
  });
});
