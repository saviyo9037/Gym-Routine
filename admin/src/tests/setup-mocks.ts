import { vi } from "vitest";
import { makeSession, state } from "./helpers/mock";

vi.mock("@/lib/supabase/server", () => ({ createSessionClient: async () => makeSession() }));
vi.mock("@/lib/supabase/admin", () => ({ createServiceClient: () => state.createServiceClient() }));
// Request headers are controlled per test (default: a same-origin browser request).
vi.mock("next/headers", () => ({
  headers: async () => new Headers(state.requestHeaders),
  cookies: async () => ({ getAll: () => [], set: () => undefined }),
}));
