// Minimal chainable mock of the Supabase clients used by the guard and server actions.
import { vi } from "vitest";

export interface Call {
  table: string;
  op: "select" | "insert" | "update" | "delete" | "upsert" | "rpc" | "auth" | "storage";
  payload?: unknown;
  filters: [string, unknown[]][];
  single?: "maybe" | "one";
  head?: boolean;
}
export interface Resp {
  data?: unknown;
  error?: { message: string; code?: string } | null;
  count?: number | null;
}

export const USER_ID = "11111111-1111-4111-8111-111111111111";
export const OTHER_ID = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";

export const state = {
  user: { id: USER_ID, email: "admin@example.test" } as { id: string; email: string } | null,
  aal: "aal2" as "aal1" | "aal2",
  adminRole: "owner" as string | null,
  adminLookupError: false,
  auditError: false,
  calls: [] as Call[],
  respond: undefined as undefined | ((c: Call) => Resp | undefined),
  createServiceClient: vi.fn(),
  requestHeaders: {} as Record<string, string>,
  signInError: null as string | null,
  signInCalls: 0,
};

function defaultRespond(c: Call): Resp {
  if (c.table === "admins" && c.op === "select") {
    if (state.adminLookupError) return { data: null, error: { message: "boom" } };
    const own = c.filters.some(([k, v]) => k === "eq:user_id" && v[0] === state.user?.id);
    if (own) return { data: state.adminRole ? [{ role: state.adminRole }] : [] };
    if (c.head) return { data: null, count: 2 };
    return { data: [] };
  }
  if (c.table === "audit_log" && c.op === "insert") return state.auditError ? { error: { message: "audit down" } } : { data: null };
  if (c.op === "select" && c.head) return { data: null, count: 2 };
  if (c.op === "select") return { data: [{ id: 1, license_verified: true, storage_path: "p/x.png" }] };
  if (c.op === "rpc") return { data: 2 };
  return { data: [{ id: 1 }] };
}

function exec(c: Call): { data: unknown; error: unknown; count?: number | null } {
  state.calls.push(c);
  const r = state.respond?.(c) ?? defaultRespond(c);
  let data = r.data === undefined ? null : r.data;
  if (c.single) data = Array.isArray(data) ? (data[0] ?? null) : data;
  return { data, error: r.error ?? null, count: r.count ?? null };
}

class Query {
  c: Call;
  constructor(table: string) {
    this.c = { table, op: "select", filters: [] };
  }
  private f(name: string) {
    return (...args: unknown[]) => {
      this.c.filters.push([name, args]);
      return this;
    };
  }
  select = (_cols?: string, opts?: { head?: boolean }) => {
    if (opts?.head) this.c.head = true;
    return this;
  };
  insert = (p: unknown) => ((this.c.op = "insert"), (this.c.payload = p), this);
  update = (p: unknown) => ((this.c.op = "update"), (this.c.payload = p), this);
  upsert = (p: unknown) => ((this.c.op = "upsert"), (this.c.payload = p), this);
  delete = () => ((this.c.op = "delete"), this);
  eq = (k: string, v: unknown) => (this.c.filters.push([`eq:${k}`, [v]]), this);
  ilike = this.f("ilike");
  is = this.f("is");
  in = this.f("in");
  or = this.f("or");
  gte = this.f("gte");
  order = this.f("order");
  range = this.f("range");
  limit = this.f("limit");
  maybeSingle = () => ((this.c.single = "maybe"), Promise.resolve(exec(this.c)));
  single = () => ((this.c.single = "one"), Promise.resolve(exec(this.c)));
  then(res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) {
    return Promise.resolve(exec(this.c)).then(res, rej);
  }
}

export function makeDb() {
  return {
    from: (table: string) => new Query(table),
    rpc: (name: string, args: unknown) =>
      Promise.resolve(exec({ table: `rpc:${name}`, op: "rpc", payload: args, filters: [] })),
    auth: {
      admin: {
        updateUserById: (id: string, attrs: unknown) =>
          Promise.resolve(exec({ table: "auth.admin.updateUserById", op: "auth", payload: { id, attrs }, filters: [] })),
        deleteUser: (id: string) =>
          Promise.resolve(exec({ table: "auth.admin.deleteUser", op: "auth", payload: { id }, filters: [] })),
      },
    },
    storage: {
      from: (bucket: string) => ({
        upload: (path: string) =>
          Promise.resolve(exec({ table: `storage:${bucket}`, op: "storage", payload: { upload: path }, filters: [] })),
        remove: (paths: string[]) =>
          Promise.resolve(exec({ table: `storage:${bucket}`, op: "storage", payload: { remove: paths }, filters: [] })),
      }),
    },
  };
}

export function makeSession() {
  return {
    auth: {
      signInWithPassword: async () => {
        state.signInCalls++;
        return state.signInError ? { data: null, error: { message: state.signInError } } : { data: { user: state.user }, error: null };
      },
      signOut: async () => ({ error: null }),
      getUser: async () => (state.user ? { data: { user: state.user }, error: null } : { data: { user: null }, error: { message: "no session" } }),
      mfa: {
        getAuthenticatorAssuranceLevel: async () => ({ data: { currentLevel: state.aal, nextLevel: "aal2" }, error: null }),
      },
    },
  };
}

export function reset() {
  state.user = { id: USER_ID, email: "admin@example.test" };
  state.aal = "aal2";
  state.adminRole = "owner";
  state.adminLookupError = false;
  state.auditError = false;
  state.calls = [];
  state.respond = undefined;
  state.requestHeaders = {};
  state.signInError = null;
  state.signInCalls = 0;
  state.createServiceClient.mockClear();
  state.createServiceClient.mockImplementation(() => makeDb());
}

/** Writes = anything that mutates data, excluding the audit insert. */
export const mutations = () =>
  state.calls.filter(
    (c) => (["insert", "update", "delete", "upsert", "rpc", "auth", "storage"] as string[]).includes(c.op) && c.table !== "audit_log",
  );
export const auditEntries = () =>
  state.calls.filter((c) => c.table === "audit_log" && c.op === "insert").map((c) => c.payload as Record<string, unknown>);
