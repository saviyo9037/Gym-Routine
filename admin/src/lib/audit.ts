import "server-only";
import type { AdminContext } from "@/lib/guard";

export interface AuditEntry {
  action: string;
  target_type?: string;
  target_id?: string | number | null;
  metadata?: Record<string, unknown>;
}

/** Appends to audit_log. Throws if the write fails so a mutation is never silently unaudited. */
export async function writeAudit(ctx: Pick<AdminContext, "db" | "user" | "role">, entry: AuditEntry): Promise<void> {
  const { error } = await ctx.db.from("audit_log").insert({
    actor_id: ctx.user.id,
    actor_role: ctx.role,
    action: entry.action,
    target_type: entry.target_type ?? null,
    target_id: entry.target_id == null ? null : String(entry.target_id),
    metadata: entry.metadata ?? {},
  });
  if (error) throw new Error(`audit_log write failed: ${error.message}`);
}
