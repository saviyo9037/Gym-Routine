/**
 * Pure validation of the Supabase env vars, shared by the proxy and publicEnv().
 * Returns a human readable list of problems (never echoes secret values).
 */
export function envProblems(
  url: string | undefined,
  anon: string | undefined,
): string[] {
  const problems: string[] = [];
  const looksPlaceholder = (v: string) => /[<>]/.test(v) || /^your[-_ ]/i.test(v);

  if (!url) {
    problems.push("NEXT_PUBLIC_SUPABASE_URL is not set");
  } else if (looksPlaceholder(url)) {
    problems.push(
      "NEXT_PUBLIC_SUPABASE_URL still contains the placeholder from .env.example - paste your real project URL (https://<project-ref>.supabase.co)",
    );
  } else {
    try {
      const u = new URL(url);
      if (u.protocol !== "https:" && u.protocol !== "http:") {
        problems.push("NEXT_PUBLIC_SUPABASE_URL must start with https:// (or http:// for a local stack)");
      }
    } catch {
      problems.push("NEXT_PUBLIC_SUPABASE_URL is not a valid URL (expected https://<project-ref>.supabase.co)");
    }
  }

  if (!anon) {
    problems.push("NEXT_PUBLIC_SUPABASE_ANON_KEY is not set");
  } else if (looksPlaceholder(anon)) {
    problems.push(
      "NEXT_PUBLIC_SUPABASE_ANON_KEY still contains the placeholder from .env.example - paste your real anon/publishable key",
    );
  }
  return problems;
}

export function serviceKeyProblem(key: string | undefined, name: string): string | null {
  if (!key) return `${name} is not set`;
  if (/[<>]/.test(key) || /^your[-_ ]/i.test(key)) {
    return `${name} still contains the placeholder from .env.example`;
  }
  return null;
}
