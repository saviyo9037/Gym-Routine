import { beforeEach, describe, expect, it } from "vitest";
import { deleteMedia, uploadMedia } from "@/lib/actions/media";
import { reset, state, type Call, type Resp } from "./helpers/mock";

beforeEach(reset);

// MOCK-ONLY: Supabase client is a recording mock.
const png = () => new File([new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0])], "a.png", { type: "image/png" });
// ISO base media header: size, "ftyp", brand.
const mp4 = () =>
  new File([new Uint8Array([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d, 0, 0, 0, 0])], "a.mp4", { type: "video/mp4" });
const form = (file: File) => {
  const fd = new FormData();
  fd.set("exercise_id", "1");
  fd.set("license", "Own footage, shot 2026-11-01 (log kept)");
  fd.set("attribution", "RepTrack owner");
  fd.set("source_url", "");
  fd.set("file", file);
  return fd;
};
const storageCalls = () => state.calls.filter((c: Call) => c.op === "storage");

describe("video protection: bucket selection (MOCK-ONLY)", () => {
  it("uploads videos to the PRIVATE exercise-videos bucket", async () => {
    const r = await uploadMedia(form(mp4()));
    expect(r.ok).toBe(true);
    const uploads = storageCalls();
    expect(uploads).toHaveLength(1);
    expect(uploads[0].table).toBe("storage:exercise-videos");
  });

  it("keeps images in the public exercise-media bucket", async () => {
    const r = await uploadMedia(form(png()));
    expect(r.ok).toBe(true);
    expect(storageCalls()[0].table).toBe("storage:exercise-media");
  });

  it("deleting a video removes the object from the private bucket", async () => {
    state.respond = (c: Call): Resp | undefined =>
      c.table === "exercise_media" && c.op === "select"
        ? { data: [{ id: 1, storage_path: "1/x.mp4", media_type: "video" }] }
        : undefined;
    const r = await deleteMedia("2f1c9a0e-51c3-4f0a-9d65-0c0d9e6a1b11");
    expect(r.ok).toBe(true);
    const rm = storageCalls().find((c: Call) => (c.payload as { remove?: string[] }).remove);
    expect(rm?.table).toBe("storage:exercise-videos");
  });
});
