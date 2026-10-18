// MOCK-ONLY: dependencies (JWT lookup, SQL decision, URL signing) are fakes. The real SQL decision is covered by
// backend/supabase/tests/video_access.test.sql. Runs under `deno test` and `node --test` (Node >= 22.6).
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  createRateLimiter,
  handleVideoUrl,
  MAX_EXERCISE_ID,
  parseVideoRequest,
  SIGNED_URL_TTL_SECONDS,
  type AccessResult,
  type VideoDeps,
} from "./video_url.ts";

const USER = "aaaaaaaa-0000-4000-8000-000000000001";
const OK = { allowed: true, storage_path: "videos/12.mp4", mime_type: "video/mp4" } as const;

function deps(over: Partial<VideoDeps> & { access?: VideoDeps["access"] } = {}) {
  const calls = { access: [] as unknown[][], sign: [] as unknown[][], getUser: 0 };
  const d: VideoDeps = {
    async getUserId(auth) {
      calls.getUser++;
      return auth === "Bearer good" ? USER : null;
    },
    async access(u, e, v, t) {
      calls.access.push([u, e, v, t]);
      return OK;
    },
    async sign(p, ttl) {
      calls.sign.push([p, ttl]);
      return `https://signed.invalid/${p}?token=T&ttl=${ttl}`;
    },
    now: () => 1_000_000,
    ...over,
  };
  return { d, calls };
}
const call = (d: VideoDeps, o: Record<string, unknown> = {}, lim = createRateLimiter(60, 60_000), opts = {}) =>
  handleVideoUrl({ method: "POST", authorization: "Bearer good", body: { exercise_id: 12 }, ...o } as never, d, lim, opts);

test("entitled user gets a short-lived signed URL", async () => {
  const { d, calls } = deps();
  const r = await call(d);
  assert.equal(r.status, 200);
  assert.equal(r.body.expires_in, SIGNED_URL_TTL_SECONDS);
  assert.ok(SIGNED_URL_TTL_SECONDS <= 600, "URL lifetime must stay short");
  assert.match(String(r.body.url), /videos\/12\.mp4/);
  assert.deepEqual(calls.sign[0], ["videos/12.mp4", SIGNED_URL_TTL_SECONDS]);
  assert.deepEqual(calls.access[0], [USER, 12, true, false], "licence must be verified and trials refused by default");
});

test("NON-ENTITLED user is rejected with 403 and never gets a URL", async () => {
  const { d, calls } = deps({ access: async () => ({ allowed: false, reason: "not_entitled" }) });
  const r = await call(d);
  assert.equal(r.status, 403);
  assert.deepEqual(r.body, { error: "not_entitled" });
  assert.equal(calls.sign.length, 0, "signing must not be reached");
  assert.equal(JSON.stringify(r).includes("http"), false);
});

test("refunded / expired / unknown-state denials are all 403 without a URL", async () => {
  for (const reason of ["not_entitled", "something_new"]) {
    const { d, calls } = deps({ access: async () => ({ allowed: false, reason }) });
    assert.equal((await call(d)).status, 403);
    assert.equal(calls.sign.length, 0);
  }
});

test("unknown exercise / NO_VIDEO is rejected with 404", async () => {
  const { d, calls } = deps({ access: async () => ({ allowed: false, reason: "no_video" }) });
  const r = await call(d, { body: { exercise_id: 7 } });
  assert.equal(r.status, 404);
  assert.equal(calls.sign.length, 0);
});

test("missing, malformed or invalid token is 401 and never reaches the database", async () => {
  for (const authorization of [null, "", "Bearer", "Basic abc", "Bearer bad"]) {
    const { d, calls } = deps();
    const r = await call(d, { authorization });
    assert.equal(r.status, 401, String(authorization));
    assert.equal(calls.access.length, 0);
    assert.equal(calls.sign.length, 0);
  }
});

test("method must be POST", async () => {
  const { d } = deps();
  assert.equal((await call(d, { method: "GET" })).status, 405);
});

test("input is clamped and validated", async () => {
  for (const body of [null, "x", {}, { exercise_id: "12" }, { exercise_id: 1.5 }, { exercise_id: 0 },
    { exercise_id: -3 }, { exercise_id: MAX_EXERCISE_ID + 1 }, { exercise_id: null }, { exercise_id: [12] }]) {
    const { d, calls } = deps();
    const r = await call(d, { body });
    assert.equal(r.status, 400, JSON.stringify(body));
    assert.equal(calls.access.length, 0);
  }
  assert.ok("exerciseId" in parseVideoRequest({ exercise_id: MAX_EXERCISE_ID }));
});

test("rate limit is per user and answers 429 with Retry-After", async () => {
  const lim = createRateLimiter(3, 60_000);
  const { d } = deps();
  for (let i = 0; i < 3; i++) assert.equal((await call(d, {}, lim)).status, 200);
  const r = await call(d, {}, lim);
  assert.equal(r.status, 429);
  assert.ok(Number(r.headers?.["retry-after"]) >= 1);
  // a different user is unaffected
  const other = deps({ getUserId: async () => "bbbbbbbb-0000-4000-8000-000000000002" });
  assert.equal((await call(other.d, {}, lim)).status, 200);
});

test("rate limiter window slides", () => {
  const lim = createRateLimiter(2, 1000);
  assert.equal(lim.take("u", 0), 0);
  assert.equal(lim.take("u", 10), 0);
  assert.ok(lim.take("u", 20) > 0);
  assert.equal(lim.take("u", 1100), 0);
});

test("unlicensed videos are only served when the dev switch is on", async () => {
  const a = deps();
  await call(a.d, {}, createRateLimiter(60, 60_000), { allowUnverified: true });
  assert.equal(a.calls.access[0][2], false);
});

test("backend failures are generic 5xx and leak nothing", async () => {
  const boom = deps({ access: async (): Promise<AccessResult> => { throw new Error("secret detail token=abc"); } });
  const r = await call(boom.d);
  assert.equal(r.status, 500);
  assert.equal(JSON.stringify(r).includes("secret"), false);
  const nosign = deps({ sign: async () => null });
  assert.equal((await call(nosign.d)).status, 502);
  const authBoom = deps({ getUserId: async () => { throw new Error("x"); } });
  assert.equal((await call(authBoom.d)).status, 500);
});

test("the bearer token is never echoed in any response", async () => {
  const { d } = deps();
  for (const r of [await call(d), await call(d, { authorization: "Bearer bad-token-123" })]) {
    assert.equal(JSON.stringify(r).includes("token-123"), false);
  }
});

// A fake of public.video_access(): trial users are refused unless allowTrial is passed.
const asked: boolean[] = [];
const tierAccess = (tier: "none" | "trial" | "full"): VideoDeps["access"] => async (_u, _e, _v, allowTrial) => {
  asked.push(allowTrial);
  if (tier === "none") return { allowed: false, reason: "not_entitled" };
  if (tier === "trial" && !allowTrial) return { allowed: false, reason: "trial_locked" };
  return OK;
};

test("TRIAL user is refused with 403 trial_locked and never gets a URL", async () => {
  const { d, calls } = deps({ access: tierAccess("trial") });
  const r = await call(d);
  assert.equal(r.status, 403);
  assert.deepEqual(r.body, { error: "trial_locked" });
  assert.equal(calls.sign.length, 0, "signing must not be reached for a trial");
  assert.equal(JSON.stringify(r).includes("http"), false);
  assert.equal(asked.at(-1), false, "the function asks the database with allowTrial=false by default");
  assert.equal(calls.access.length, 0);
});

test("full (paid, comp, grace) users still get a URL when trials are locked", async () => {
  const { d, calls } = deps({ access: tierAccess("full") });
  const r = await call(d);
  assert.equal(r.status, 200);
  assert.equal(calls.sign.length, 1);
});

test("TRIAL_VIDEOS_LOCKED=false (allowTrial) opens videos for trials without code changes", async () => {
  const { d } = deps({ access: tierAccess("trial") });
  const r = await call(d, {}, createRateLimiter(60, 60_000), { allowTrial: true });
  assert.equal(r.status, 200);
  assert.equal(asked.at(-1), true);
  const none = deps({ access: tierAccess("none") });
  assert.equal((await call(none.d, {}, createRateLimiter(60, 60_000), { allowTrial: true })).status, 403, "allowTrial never opens videos to non-entitled users");
});

test("only the exact string 'false' opens trials (function env wiring)", () => {
  const open = (v: string | undefined) => v === "false";
  assert.equal(open(undefined), false);
  assert.equal(open(""), false);
  assert.equal(open("0"), false);
  assert.equal(open("FALSE"), false);
  assert.equal(open("false"), true);
});
