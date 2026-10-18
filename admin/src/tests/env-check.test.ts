import { describe, expect, it } from "vitest";
import { envProblems, serviceKeyProblem } from "@/lib/env-check";

describe("envProblems", () => {
  it("accepts a normal https URL and a key", () => {
    expect(envProblems("https://abc.supabase.co", "eyJhbGciOi")).toEqual([]);
    expect(envProblems("http://127.0.0.1:54321", "k")).toEqual([]);
  });
  it("reports missing values", () => {
    expect(envProblems(undefined, undefined)).toHaveLength(2);
  });
  it("detects the angle-bracket placeholder copied from the old example", () => {
    const p = envProblems("<your-supabase-project-url>", "<your-supabase-anon-key>");
    expect(p).toHaveLength(2);
    expect(p[0]).toMatch(/placeholder/);
  });
  it("detects REPLACE-style text as an invalid URL, not a crash", () => {
    const p = envProblems("REPLACE-WITH-YOUR-PROJECT-REF", "REPLACE-WITH-YOUR-ANON-KEY");
    expect(p.join(" ")).toMatch(/not a valid URL/);
  });
  it("rejects non-http protocols", () => {
    expect(envProblems("ftp://x.supabase.co", "k")[0]).toMatch(/https/);
  });
  it("never echoes the secret values", () => {
    const secret = "supersecret<token>";
    expect(envProblems("https://a.b", secret).join(" ")).not.toContain("supersecret");
  });
});

describe("serviceKeyProblem", () => {
  it("flags missing and placeholder keys", () => {
    expect(serviceKeyProblem(undefined, "K")).toMatch(/not set/);
    expect(serviceKeyProblem("<your-key>", "K")).toMatch(/placeholder/);
    expect(serviceKeyProblem("a-real-looking-key", "K")).toBeNull();
  });
});
