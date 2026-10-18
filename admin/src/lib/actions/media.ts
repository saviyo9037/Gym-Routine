"use server";

import { randomUUID } from "node:crypto";
import { z } from "zod";
import { runMutation, ActionError, type ActionResult } from "@/lib/action";
import { mediaMetaSchema, parseOrThrow, sniffMedia, uuidSchema, validateMediaFile } from "@/lib/validation";

// Images are public catalogue assets. Videos are a paid feature: they live in a PRIVATE bucket and are only ever
// served through short-lived signed URLs issued by the video-url Edge Function after an entitlement check.
const IMAGE_BUCKET = "exercise-media";
const VIDEO_BUCKET = "exercise-videos";
const bucketFor = (kind: string) => (kind === "video" ? VIDEO_BUCKET : IMAGE_BUCKET);
const MIME_BY_EXT: Record<string, string> = { mp4: "video/mp4", jpg: "image/jpeg", png: "image/png", webp: "image/webp" };

/** Upload is stored as a DRAFT with license_verified=false. A human must verify the licence later. */
export async function uploadMedia(formData: FormData): Promise<ActionResult<{ id: string }>> {
  return runMutation(["owner", "content"], async ({ db, user }) => {
    const meta = parseOrThrow(mediaMetaSchema, {
      exercise_id: formData.get("exercise_id"),
      license: formData.get("license"),
      attribution: formData.get("attribution"),
      source_url: formData.get("source_url") ?? "",
    });
    const file = formData.get("file");
    if (!(file instanceof File)) throw new ActionError("File is required");
    const v = validateMediaFile(file);
    if (!v.ok) throw new ActionError(v.error);
    const mime = MIME_BY_EXT[v.ext];
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (!sniffMedia(bytes, mime)) throw new ActionError("File content does not match its type");

    const { data: ex } = await db.from("exercises_catalog").select("id").eq("id", meta.exercise_id).maybeSingle();
    if (!ex) throw new ActionError("Exercise not found");

    const id = randomUUID();
    const path = `${meta.exercise_id}/${id}.${v.ext}`;
    const bucket = bucketFor(v.kind);
    const { error: upErr } = await db.storage.from(bucket).upload(path, bytes, { contentType: mime, upsert: false });
    if (upErr) throw new Error(upErr.message);
    const { error } = await db.from("exercise_media").insert({
      id,
      exercise_id: meta.exercise_id,
      media_type: v.kind,
      mime_type: mime,
      storage_path: path,
      size_bytes: bytes.byteLength,
      license: meta.license,
      attribution: meta.attribution,
      source_url: meta.source_url,
      license_verified: false,
      status: "draft",
      uploaded_by: user.id,
    });
    if (error) {
      await db.storage.from(bucket).remove([path]);
      throw new Error(error.message);
    }
    return {
      data: { id },
      audit: {
        action: "media.upload",
        target_type: "exercise_media",
        target_id: id,
        metadata: { exercise_id: meta.exercise_id, bytes: bytes.byteLength, license: meta.license },
      },
    };
  });
}

export async function verifyMediaLicense(mediaId: unknown): Promise<ActionResult> {
  return runMutation(["owner", "content"], async ({ db }) => {
    const id = parseOrThrow(uuidSchema, mediaId);
    const { data, error } = await db.from("exercise_media").update({ license_verified: true }).eq("id", id).select("id");
    if (error) throw new Error(error.message);
    if (!data?.length) throw new ActionError("Media not found");
    return { audit: { action: "media.license_verified", target_type: "exercise_media", target_id: id } };
  });
}

export async function setMediaStatus(mediaId: unknown, status: unknown): Promise<ActionResult> {
  return runMutation(["owner", "content"], async ({ db }) => {
    const id = parseOrThrow(uuidSchema, mediaId);
    const st = parseOrThrow(z.enum(["draft", "published", "archived"]), status);
    if (st === "published") {
      const { data: row } = await db.from("exercise_media").select("license_verified").eq("id", id).maybeSingle();
      if (!row) throw new ActionError("Media not found");
      if (!row.license_verified) throw new ActionError("Verify the licence before publishing");
    }
    const { error } = await db.from("exercise_media").update({ status: st }).eq("id", id);
    if (error) throw new Error(error.message);
    return { audit: { action: "media.status", target_type: "exercise_media", target_id: id, metadata: { status: st } } };
  });
}

export async function deleteMedia(mediaId: unknown): Promise<ActionResult> {
  return runMutation(["owner", "content"], async ({ db }) => {
    const id = parseOrThrow(uuidSchema, mediaId);
    const { data: row } = await db.from("exercise_media").select("storage_path, media_type").eq("id", id).maybeSingle();
    if (!row) throw new ActionError("Media not found");
    const { error } = await db.from("exercise_media").delete().eq("id", id);
    if (error) throw new Error(error.message);
    await db.storage.from(bucketFor(String(row.media_type ?? "image"))).remove([row.storage_path as string]);
    return { audit: { action: "media.delete", target_type: "exercise_media", target_id: id } };
  });
}
