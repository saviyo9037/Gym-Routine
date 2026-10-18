"use server";

import { runMutation, ActionError, type ActionResult } from "@/lib/action";
import { announcementSchema, parseOrThrow, uuidSchema } from "@/lib/validation";

/** Create (id = null) or update an announcement. Owner or support. */
export async function saveAnnouncement(id: unknown, input: unknown): Promise<ActionResult<{ id: string }>> {
  return runMutation<{ id: string }>(["owner", "support"], async ({ db, user }) => {
    const v = parseOrThrow(announcementSchema, input);
    const row = {
      title: v.title,
      body: v.body,
      level: v.level,
      starts_at: (v.starts_at ?? new Date()).toISOString(),
      ends_at: v.ends_at ? v.ends_at.toISOString() : null,
      active: v.active,
    };
    if (id === null || id === undefined || id === "") {
      const { data, error } = await db
        .from("announcements")
        .insert({ ...row, created_by: user.id })
        .select("id")
        .single();
      if (error || !data) throw new ActionError("Could not create the announcement");
      const newId = data.id as string;
      return { audit: { action: "announcement.create", target_type: "announcement", target_id: newId, metadata: { level: v.level, active: v.active } }, data: { id: newId } };
    }
    const target = parseOrThrow(uuidSchema, id);
    const { error } = await db.from("announcements").update(row).eq("id", target);
    if (error) throw new ActionError("Could not update the announcement");
    return { audit: { action: "announcement.update", target_type: "announcement", target_id: target, metadata: { level: v.level, active: v.active } }, data: { id: target } };
  });
}

export async function setAnnouncementActive(id: unknown, active: unknown): Promise<ActionResult> {
  return runMutation(["owner", "support"], async ({ db }) => {
    const target = parseOrThrow(uuidSchema, id);
    const on = active === true || active === "true";
    const { error } = await db.from("announcements").update({ active: on }).eq("id", target);
    if (error) throw new ActionError("Could not change the announcement");
    return { audit: { action: on ? "announcement.activate" : "announcement.deactivate", target_type: "announcement", target_id: target } };
  });
}

export async function deleteAnnouncement(id: unknown): Promise<ActionResult> {
  return runMutation(["owner", "support"], async ({ db }) => {
    const target = parseOrThrow(uuidSchema, id);
    const { error } = await db.from("announcements").delete().eq("id", target);
    if (error) throw new ActionError("Could not delete the announcement");
    return { audit: { action: "announcement.delete", target_type: "announcement", target_id: target } };
  });
}
