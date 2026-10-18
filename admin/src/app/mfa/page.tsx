import { redirect } from "next/navigation";
import { ADMIN_ROLES, GuardError, requireAdmin } from "@/lib/guard";
import { createSessionClient } from "@/lib/supabase/server";
import { MfaForm } from "./mfa-form";

export const dynamic = "force-dynamic";

export default async function MfaPage() {
  try {
    await requireAdmin(ADMIN_ROLES); // already aal2 -> go in
    redirect("/dashboard");
  } catch (e) {
    if (e instanceof GuardError) {
      if (e.code === "unauthenticated" || e.code === "forbidden") redirect("/login");
      // mfa_required: fall through to enrol/verify
    } else {
      throw e;
    }
  }
  const session = await createSessionClient();
  const { data } = await session.auth.mfa.listFactors();
  const verified = data?.totp[0]?.id ?? null;
  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center px-4">
      <h1 className="mb-1 text-2xl font-semibold">Two-factor authentication</h1>
      <p className="mb-6 text-sm text-muted">
        {verified ? "Enter the 6-digit code from your authenticator app." : "Set up an authenticator app (TOTP) to continue."}
      </p>
      <MfaForm verifiedFactorId={verified} />
    </main>
  );
}
