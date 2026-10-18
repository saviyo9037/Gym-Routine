"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { z } from "zod";
import { ADMIN_ROLES, GuardError, requireAdmin } from "@/lib/guard";
import { createSessionClient } from "@/lib/supabase/server";
import { runMutation, ActionError, type ActionResult } from "@/lib/action";
import { parseOrThrow } from "@/lib/validation";
import { requestIsSameOrigin } from "@/lib/csrf";
import { writeAudit } from "@/lib/audit";
import { loginEmailLimiter, loginIpLimiter } from "@/lib/rate-limit";

const loginSchema = z.object({ email: z.string().trim().toLowerCase().pipe(z.email()), password: z.string().min(1).max(200) });

export interface LoginState {
  error?: string;
}

const GENERIC = "Invalid credentials, or this account is not an admin.";

const TOO_MANY = "Too many attempts. Please wait a few minutes and try again.";

async function clientIp(): Promise<string> {
  const h = await headers();
  return (h.get("x-forwarded-for")?.split(",")[0] ?? h.get("x-real-ip") ?? "unknown").trim() || "unknown";
}

export async function login(_prev: LoginState, formData: FormData): Promise<LoginState> {
  if (!(await requestIsSameOrigin())) return { error: GENERIC };
  const parsed = loginSchema.safeParse({ email: formData.get("email"), password: formData.get("password") });
  if (!parsed.success) return { error: GENERIC };
  const emailKey = parsed.data.email;
  const ipKey = await clientIp();
  // Best-effort throttle (see lib/rate-limit.ts); the real limit is Supabase Auth's.
  if (loginEmailLimiter.isLimited(emailKey) || loginIpLimiter.isLimited(ipKey)) return { error: TOO_MANY };
  const session = await createSessionClient();
  const { error } = await session.auth.signInWithPassword(parsed.data);
  if (error) {
    loginEmailLimiter.record(emailKey);
    loginIpLimiter.record(ipKey);
    return { error: GENERIC };
  }
  try {
    const ctx = await requireAdmin(ADMIN_ROLES, { aal: "aal1" });
    // Sign-ins are recorded (best effort: an audit outage must not lock admins out).
    await writeAudit(ctx, { action: "auth.login", target_type: "user", target_id: ctx.user.id }).catch((e) =>
      console.error("login audit failed", e),
    );
  } catch (e) {
    // A valid password for a non-admin is still a failed admin sign-in.
    loginEmailLimiter.record(emailKey);
    loginIpLimiter.record(ipKey);
    await session.auth.signOut();
    if (e instanceof GuardError) return { error: GENERIC };
    throw e;
  }
  loginEmailLimiter.reset(emailKey);
  redirect("/mfa");
}

export async function logout(): Promise<void> {
  // A cross-site request must not be able to sign the admin out.
  if (!(await requestIsSameOrigin())) redirect("/login");
  const session = await createSessionClient();
  await session.auth.signOut();
  redirect("/login");
}

export interface EnrollData {
  factorId: string;
  qrSvg: string;
  secret: string;
}

/** Starts TOTP enrolment. Refuses when a verified factor exists (prevents adding a second factor with only a password). */
export async function startEnroll(): Promise<ActionResult<EnrollData>> {
  return runMutation(
    ADMIN_ROLES,
    async ({ user }) => {
      const session = await createSessionClient();
      const { data: factors, error: lErr } = await session.auth.mfa.listFactors();
      if (lErr) throw new Error(lErr.message);
      if (factors.totp.length > 0) throw new ActionError("Two-factor authentication is already set up. Enter your code instead.");
      for (const f of factors.all.filter((x) => x.factor_type === "totp" && x.status === "unverified")) {
        await session.auth.mfa.unenroll({ factorId: f.id });
      }
      const { data, error } = await session.auth.mfa.enroll({ factorType: "totp", friendlyName: `admin-${user.id.slice(0, 8)}` });
      if (error || !data) throw new Error(error?.message ?? "enrol failed");
      return {
        data: { factorId: data.id, qrSvg: data.totp.qr_code, secret: data.totp.secret },
        audit: { action: "auth.mfa_enroll_started", target_type: "user", target_id: user.id },
      };
    },
    { aal: "aal1" },
  );
}

/** Verifies a TOTP code (enrolment or login) and upgrades the session to aal2. */
export async function verifyTotp(factorId: unknown, code: unknown): Promise<ActionResult> {
  return runMutation(
    ADMIN_ROLES,
    async ({ user }) => {
      const fid = parseOrThrow(z.uuid(), factorId);
      const c = parseOrThrow(z.string().regex(/^\d{6}$/, "Enter the 6-digit code"), code);
      const session = await createSessionClient();
      const { data: ch, error: chErr } = await session.auth.mfa.challenge({ factorId: fid });
      if (chErr || !ch) throw new ActionError("Could not start verification");
      const { error } = await session.auth.mfa.verify({ factorId: fid, challengeId: ch.id, code: c });
      if (error) throw new ActionError("Invalid code");
      return { audit: { action: "auth.mfa_verified", target_type: "user", target_id: user.id } };
    },
    { aal: "aal1" },
  );
}
