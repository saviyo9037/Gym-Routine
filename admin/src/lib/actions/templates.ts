"use server";

import { runMutation, ActionError, type ActionResult } from "@/lib/action";
import { parseOrThrow, templateSchema, uuidSchema } from "@/lib/validation";

export async function saveTemplate(id: unknown, input: unknown): Promise<ActionResult<{ id: string }>> {
  return runMutation(["owner", "content"], async ({ db, user }) => {
    const fields = parseOrThrow(templateSchema, input);
    if (id) {
      const tid = parseOrThrow(uuidSchema, id);
      const { data, error } = await db.from("template_plans").update(fields).eq("id", tid).select("id");
      if (error) throw new Error(error.message);
      if (!data?.length) throw new ActionError("Template not found");
      return { data: { id: tid }, audit: { action: "template.update", target_type: "template", target_id: tid } };
    }
    const { data, error } = await db.from("template_plans").insert({ ...fields, created_by: user.id }).select("id").single();
    if (error) throw new Error(error.message);
    return {
      data: { id: data.id as string },
      audit: { action: "template.create", target_type: "template", target_id: data.id as string },
    };
  });
}

export async function deleteTemplate(id: unknown): Promise<ActionResult> {
  return runMutation(["owner", "content"], async ({ db }) => {
    const tid = parseOrThrow(uuidSchema, id);
    const { error } = await db.from("template_plans").delete().eq("id", tid);
    if (error) throw new Error(error.message);
    return { audit: { action: "template.delete", target_type: "template", target_id: tid } };
  });
}
