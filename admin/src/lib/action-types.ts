// Client-safe type (no server-only imports). Mirrors ActionResult in action.ts.
export type ActionResult<T = undefined> =
  | { ok: true; data?: T }
  | { ok: false; error: string; fieldErrors?: Record<string, string[]> };
