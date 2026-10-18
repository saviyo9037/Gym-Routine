import { describe, expect, it } from "vitest";
import { escapeSearch, exerciseSchema, MUSCLE_GROUPS, sniffMedia, templateSchema, validateMediaFile } from "@/lib/validation";

describe("validation", () => {
  it("has exactly the 15 categories", () => {
    expect(MUSCLE_GROUPS).toHaveLength(15);
  });
  it("exerciseSchema normalises optional blanks to null", () => {
    const r = exerciseSchema.parse({
      id: "5", name: " X ", primary_muscle_group: "Back", equipment: "Cable", difficulty: "Advanced",
      default_sets: "3", default_reps: "8", default_weight_kg: "0", rest_seconds: "60", description: "  ",
    });
    expect(r.name).toBe("X");
    expect(r.description).toBeNull();
    expect(r.id).toBe(5);
  });
  it("validateMediaFile enforces type and size", () => {
    expect(validateMediaFile({ name: "a.mp4", type: "video/mp4", size: 1000 })).toMatchObject({ ok: true, kind: "video" });
    expect(validateMediaFile({ name: "a.JPEG", type: "image/jpeg", size: 1000 })).toMatchObject({ ok: true, ext: "jpg" });
    expect(validateMediaFile({ name: "a.mp4", type: "video/mp4", size: 51 * 1024 * 1024 }).ok).toBe(false);
    expect(validateMediaFile({ name: "a.webp", type: "image/webp", size: 0 }).ok).toBe(false);
    expect(validateMediaFile({ name: "a.mov", type: "video/quicktime", size: 10 }).ok).toBe(false);
    expect(validateMediaFile({ name: "a.mp4", type: "image/png", size: 10 }).ok).toBe(false);
  });
  it("sniffMedia checks magic bytes", () => {
    expect(sniffMedia(new Uint8Array([0xff, 0xd8, 0xff, 0xe0]), "image/jpeg")).toBe(true);
    expect(sniffMedia(new Uint8Array([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70]), "video/mp4")).toBe(true);
    expect(sniffMedia(new Uint8Array([1, 2, 3, 4]), "image/jpeg")).toBe(false);
    expect(sniffMedia(new Uint8Array([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]), "image/webp")).toBe(true);
  });
  it("templateSchema requires a JSON object payload", () => {
    expect(templateSchema.safeParse({ kind: "plan", title: "t", payload: "[1]" }).success).toBe(false);
    expect(templateSchema.safeParse({ kind: "plan", title: "t", payload: "{bad" }).success).toBe(false);
    expect(templateSchema.safeParse({ kind: "plan", title: "t", payload: '{"a":1}' }).success).toBe(true);
  });
  it("escapeSearch strips PostgREST filter metacharacters", () => {
    expect(escapeSearch("a,b%(c)*")).not.toMatch(/[,%()*]/);
  });
});
