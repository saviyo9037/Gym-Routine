import "server-only";
import { requireAdmin } from "@/lib/guard";
import { writeAudit } from "@/lib/audit";
import { parseOrThrow, uuidSchema } from "@/lib/validation";

/**
 * Workout data is sensitive: only owner/support may read it, and EVERY read is audited
 * (audit is written before any data is returned).
 */
export async function loadUserWorkouts(userId: string) {
  const ctx = await requireAdmin(["owner", "support"]);
  const id = parseOrThrow(uuidSchema, userId);
  await writeAudit(ctx, { action: "user.view_workouts", target_type: "user", target_id: id });
  const { data: sessions, error } = await ctx.db
    .from("workout_sessions")
    .select("id, session_date, primary_muscle, secondary_muscle, duration_seconds, notes")
    .eq("user_id", id)
    .is("deleted_at", null)
    .order("session_date", { ascending: false })
    .limit(30);
  if (error) throw new Error(error.message);
  return sessions ?? [];
}
