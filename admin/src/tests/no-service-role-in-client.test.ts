import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";

const SRC = path.resolve(__dirname, "..");
const ROOT = path.resolve(SRC, "..");

function walk(dir: string, out: string[] = []): string[] {
  for (const e of readdirSync(dir)) {
    const p = path.join(dir, e);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(ts|tsx)$/.test(e)) out.push(p);
  }
  return out;
}
const files = walk(SRC).filter((f) => !f.includes(`${path.sep}tests${path.sep}`));
const text = (f: string) => readFileSync(f, "utf8");
const directive = (src: string) => {
  const m = src.match(/^\s*(?:\/\/[^\n]*\n|\/\*[\s\S]*?\*\/\s*)*["'](use (?:client|server))["']/);
  return m?.[1] ?? null;
};
const rel = (f: string) => path.relative(SRC, f).replaceAll("\\", "/");

/** Modules a client bundle must never reach. */
const SERVER_ONLY = new Set(["lib/supabase/admin.ts", "lib/supabase/server.ts", "lib/guard.ts", "lib/audit.ts", "lib/action.ts", "lib/page-guard.ts", "lib/env.ts", "lib/queries/user-workouts.ts", "lib/revenuecat.ts", "lib/queries/app-config.ts"]);

function resolveImport(from: string, spec: string): string | null {
  let base: string;
  if (spec.startsWith("@/")) base = path.join(SRC, spec.slice(2));
  else if (spec.startsWith(".")) base = path.resolve(path.dirname(from), spec);
  else return null;
  for (const c of [base + ".ts", base + ".tsx", path.join(base, "index.ts"), path.join(base, "index.tsx"), base]) {
    try {
      if (statSync(c).isFile()) return c;
    } catch {
      /* try next */
    }
  }
  return null;
}
function imports(f: string): string[] {
  const out: string[] = [];
  for (const m of text(f).matchAll(/(?:import|export)\s[^;]*?from\s+["']([^"']+)["']|import\s+["']([^"']+)["']/g)) {
    const r = resolveImport(f, m[1] ?? m[2]);
    if (r) out.push(r);
  }
  return out;
}

describe("service-role key stays on the server", () => {
  it("is referenced only by lib/env.ts", () => {
    const offenders = files.filter((f) => /SERVICE_ROLE/.test(text(f)) && rel(f) !== "lib/env.ts");
    expect(offenders.map(rel)).toEqual([]);
  });

  it("the RevenueCat secret key is referenced only by lib/revenuecat.ts, which is server-only", () => {
    const offenders = files.filter((f) => /REVENUECAT_API_KEY/.test(text(f)) && rel(f) !== "lib/revenuecat.ts");
    expect(offenders.map(rel)).toEqual([]);
    expect(text(path.join(SRC, "lib/revenuecat.ts"))).toMatch(/import\s+["']server-only["']/);
    const all = [...files.map(text), text(path.join(ROOT, ".env.example"))].join("\n");
    expect(all).not.toMatch(/NEXT_PUBLIC_[A-Z_]*REVENUECAT/);
  });

  it("is never exposed through a NEXT_PUBLIC_ variable (code, .env.example, next.config)", () => {
    const all = [...files.map(text), text(path.join(ROOT, ".env.example")), text(path.join(ROOT, "next.config.ts"))].join("\n");
    expect(all).not.toMatch(/NEXT_PUBLIC_[A-Z_]*SERVICE/);
  });

  it("supabase/admin.ts and server.ts are marked server-only", () => {
    expect(text(path.join(SRC, "lib/supabase/admin.ts"))).toMatch(/import\s+["']server-only["']/);
    expect(text(path.join(SRC, "lib/supabase/server.ts"))).toMatch(/import\s+["']server-only["']/);
  });

  it("no 'use client' module can reach a server-only module (transitive import check)", () => {
    const clients = files.filter((f) => directive(text(f)) === "use client");
    expect(clients.length).toBeGreaterThan(0);
    const violations: string[] = [];
    for (const c of clients) {
      const seen = new Set<string>();
      const stack = [c];
      while (stack.length) {
        const f = stack.pop()!;
        if (seen.has(f)) continue;
        seen.add(f);
        if (f !== c) {
          if (SERVER_ONLY.has(rel(f))) violations.push(`${rel(c)} -> ${rel(f)}`);
          if (directive(text(f)) === "use server") continue; // compiled to RPC stubs; body never ships to the client
        }
        stack.push(...imports(f));
      }
    }
    expect(violations).toEqual([]);
  });

  it("every file importing lib/supabase/admin is a server module (server action, route handler, or server-only helper)", () => {
    const importers = files.filter((f) => imports(f).some((i) => rel(i) === "lib/supabase/admin.ts"));
    for (const f of importers) expect(directive(text(f)), rel(f)).not.toBe("use client");
    expect(importers.map(rel).sort()).toEqual(["lib/guard.ts"]);
  });
});
