import "server-only";
import { GuardError, requireAdmin, type AdminContext, type AdminRole, type GuardOptions } from "@/lib/guard";
import { writeAudit, type AuditEntry } from "@/lib/audit";
import { ValidationError } from "@/lib/validation";
import { requestIsSameOrigin } from "@/lib/csrf";

import type { ActionResult } from "@/lib/action-types";
export type { ActionResult };

export class ActionError extends Error {}

/**
 * Wraps every mutating server action: guard (single gate) -> handler -> mandatory audit_log write.
 * The handler must return the audit entry, so a mutation cannot complete without one.
 */
export async function runMutation<T = undefined>(
  roles: readonly AdminRole[],
  handler: (ctx: AdminContext) => Promise<{ audit: AuditEntry; data?: T }>,
  guardOpts?: GuardOptions,
): Promise<ActionResult<T>> {
  // CSRF defence in depth: refused before the guard or any database access.
  if (!(await requestIsSameOrigin())) return { ok: false, error: "forbidden" };
  let ctx: AdminContext;
  try {
    ctx = await requireAdmin(roles, guardOpts);
  } catch (e) {
    if (e instanceof GuardError) return { ok: false, error: e.code };
    console.error("guard failure", e);
    return { ok: false, error: "forbidden" };
  }
  try {
    const out = await handler(ctx);
    await writeAudit(ctx, out.audit);
    return { ok: true, data: out.data };
  } catch (e) {
    if (e instanceof ValidationError) return { ok: false, error: "validation", fieldErrors: e.fieldErrors };
    if (e instanceof ActionError) return { ok: false, error: e.message };
    console.error("action failed", e);
    return { ok: false, error: "Something went wrong. Check server logs." };
  }
}

/** Pages/queries: guard only (read-only; sensitive reads call writeAudit themselves). */
export async function guardRead(roles: readonly AdminRole[]): Promise<AdminContext> {
  return requireAdmin(roles);
}
