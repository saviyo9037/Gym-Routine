"use server";

import { z } from "zod";
import { runMutation, ActionError, type ActionResult } from "@/lib/action";
import { exerciseSchema, parseOrThrow } from "@/lib/validation";

export async function createExercise(input: unknown): Promise<ActionResult<{ id: number }>> {
  return runMutation(["owner", "content"], async ({ db }) => {
    const ex = parseOrThrow(exerciseSchema, input);
    const { error } = await db.from("exercises_catalog").insert(ex);
    if (error) {
      if (error.code === "23505") throw new ActionError(`Exercise id ${ex.id} already exists`);
      throw new Error(error.message);
    }
    return {
      data: { id: ex.id },
      audit: { action: "exercise.create", target_type: "exercise", target_id: ex.id, metadata: { name: ex.name } },
    };
  });
}

export async function updateExercise(input: unknown): Promise<ActionResult<{ id: number }>> {
  return runMutation(["owner", "content"], async ({ db }) => {
    const { id, ...fields } = parseOrThrow(exerciseSchema, input);
    const { data, error } = await db.from("exercises_catalog").update(fields).eq("id", id).select("id");
    if (error) throw new Error(error.message);
    if (!data || data.length === 0) throw new ActionError("Exercise not found");
    return {
      data: { id },
      audit: { action: "exercise.update", target_type: "exercise", target_id: id, metadata: { name: fields.name, status: fields.status } },
    };
  });
}

/** "Delete" is an archive so the stable integer id is never reused and clients learn of the removal. */
export async function archiveExercise(exerciseId: unknown): Promise<ActionResult> {
  return runMutation(["owner", "content"], async ({ db }) => {
    const id = parseOrThrow(z.coerce.number().int().positive(), exerciseId);
    const { data, error } = await db.from("exercises_catalog").update({ status: "archived" }).eq("id", id).select("id");
    if (error) throw new Error(error.message);
    if (!data || data.length === 0) throw new ActionError("Exercise not found");
    return { audit: { action: "exercise.archive", target_type: "exercise", target_id: id } };
  });
}

/** Stamps all pending changes with a new catalogue_versions row. */
export async function publishCatalogue(notes: unknown): Promise<ActionResult<{ version: number }>> {
  return runMutation(["owner", "content"], async ({ db, user }) => {
    const n = parseOrThrow(z.string().trim().max(500).optional(), notes);
    const { data, error } = await db.rpc("publish_catalogue", { p_actor: user.id, p_notes: n ?? null });
    if (error) {
      if (/nothing to publish/i.test(error.message)) throw new ActionError("Nothing to publish");
      throw new Error(error.message);
    }
    return {
      data: { version: data as number },
      audit: { action: "catalogue.publish", target_type: "catalogue", target_id: String(data), metadata: { notes: n ?? null } },
    };
  });
}
