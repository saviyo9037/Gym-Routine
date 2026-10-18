import "server-only";
import { redirect } from "next/navigation";
import { GuardError, requireAdmin, type AdminContext, type AdminRole } from "@/lib/guard";

/** Page-level wrapper around the single guard: maps failures to redirects. */
export async function pageGuard(roles: readonly AdminRole[]): Promise<AdminContext> {
  try {
    return await requireAdmin(roles);
  } catch (e) {
    if (e instanceof GuardError) {
      if (e.code === "unauthenticated") redirect("/login");
      if (e.code === "mfa_required") redirect("/mfa");
      redirect("/forbidden");
    }
    throw e;
  }
}
