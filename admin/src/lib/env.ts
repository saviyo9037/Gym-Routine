import { z } from "zod";
import { envProblems, serviceKeyProblem } from "./env-check";

const publicSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.string().min(1, "NEXT_PUBLIC_SUPABASE_URL is not set"),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1, "NEXT_PUBLIC_SUPABASE_ANON_KEY is not set"),
});

/** Safe to use anywhere (values are public by design). */
export function publicEnv() {
  const problems = envProblems(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  );
  if (problems.length > 0) throw new Error(problems.join("; "));
  // Literal property access so Next can inline NEXT_PUBLIC_* values.
  return publicSchema.parse({
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  });
}

/** Server-only. Imported only by lib/supabase/admin.ts (which imports "server-only"). */
export function serviceRoleKey(): string {
  const k = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const problem = serviceKeyProblem(k, "SUPABASE_SERVICE_ROLE_KEY");
  if (problem) throw new Error(problem);
  return k as string;
}
