// Pure logic of the `video-url` Edge Function: request validation, rate limiting and the
// authenticate -> authorise -> sign pipeline with injected dependencies. No I/O and no
// runtime-specific imports, so it runs under Deno (the function) and Node >= 22 (tests).
//
// Contract
//   POST { "exercise_id": <integer> }   with   Authorization: Bearer <user JWT>
//   200 { url, expires_in }            short-lived signed URL for the private bucket
//   400 bad request | 401 invalid/missing token | 403 not entitled or trial_locked | 404 no video for that exercise
//   405 wrong method | 429 too many requests | 502 signing failed | 500 server error
// Entitlement is decided SERVER-SIDE by public.video_access() (migrations 0008-0010). Store TRIALS are refused
// (403 trial_locked) unless the function env TRIAL_VIDEOS_LOCKED is "false"; paid, comp and billing-grace
// entitlements get a URL. The client's own
// idea of "premium" is never trusted. Tokens are never logged or echoed.

export const SIGNED_URL_TTL_SECONDS = 300;
export const MAX_EXERCISE_ID = 1_000_000;

export type AccessResult =
  | { allowed: true; storage_path: string; mime_type?: string }
  | { allowed: false; reason: "not_entitled" | "no_video" | "bad_request" | string };

export interface VideoDeps {
  /** Resolves the Supabase auth user id for the bearer token, or null if invalid. */
  getUserId(authorization: string): Promise<string | null>;
  /** Calls public.video_access(user, exercise, requireVerified) with the service role. */
  access(userId: string, exerciseId: number, requireVerified: boolean, allowTrial: boolean): Promise<AccessResult>;
  /** Creates a signed URL for an object of the private bucket. Null on failure. */
  sign(storagePath: string, ttlSeconds: number): Promise<string | null>;
  now(): number;
}

export interface VideoOptions {
  /** Serve videos whose licence is not verified (development only). Default false. */
  allowUnverified?: boolean;
  /** Serve videos to store-trial users too (TRIAL_VIDEOS_LOCKED=false). Default false: trials are refused. */
  allowTrial?: boolean;
}

export interface HttpResult {
  status: number;
  body: Record<string, unknown>;
  headers?: Record<string, string>;
}

export function parseVideoRequest(body: unknown): { exerciseId: number } | { error: string } {
  if (typeof body !== "object" || body === null) return { error: "body must be an object" };
  const id = (body as { exercise_id?: unknown }).exercise_id;
  if (typeof id !== "number" || !Number.isInteger(id)) return { error: "exercise_id must be an integer" };
  if (id < 1 || id > MAX_EXERCISE_ID) return { error: "exercise_id out of range" };
  return { exerciseId: id };
}

/** Sliding-window limiter, per user. In-memory: per function instance (documented limitation). */
export function createRateLimiter(maxPerWindow: number, windowMs: number) {
  const hits = new Map<string, number[]>();
  return {
    /** Returns the seconds to wait when limited, or 0 when the call is allowed (and counted). */
    take(key: string, nowMs: number): number {
      const recent = (hits.get(key) ?? []).filter((t) => nowMs - t < windowMs);
      if (recent.length >= maxPerWindow) {
        hits.set(key, recent);
        return Math.max(1, Math.ceil((windowMs - (nowMs - recent[0])) / 1000));
      }
      recent.push(nowMs);
      hits.set(key, recent);
      if (hits.size > 5000) for (const [k, v] of hits) if (v.every((t) => nowMs - t >= windowMs)) hits.delete(k);
      return 0;
    },
  };
}

export interface VideoInput {
  method: string;
  authorization: string | null;
  body: unknown;
}

export async function handleVideoUrl(
  input: VideoInput,
  deps: VideoDeps,
  limiter: { take(key: string, nowMs: number): number },
  opts: VideoOptions = {},
): Promise<HttpResult> {
  if (input.method !== "POST") return { status: 405, body: { error: "method not allowed" } };
  const auth = input.authorization;
  if (!auth || !/^Bearer\s+\S+$/i.test(auth)) return { status: 401, body: { error: "missing bearer token" } };

  let userId: string | null;
  try {
    userId = await deps.getUserId(auth);
  } catch {
    return { status: 500, body: { error: "server error" } };
  }
  if (!userId) return { status: 401, body: { error: "invalid token" } };

  const wait = limiter.take(userId, deps.now());
  if (wait > 0) return { status: 429, body: { error: "too many requests" }, headers: { "retry-after": String(wait) } };

  const parsed = parseVideoRequest(input.body);
  if ("error" in parsed) return { status: 400, body: { error: parsed.error } };

  let access: AccessResult;
  try {
    access = await deps.access(userId, parsed.exerciseId, !opts.allowUnverified, opts.allowTrial === true);
  } catch {
    return { status: 500, body: { error: "server error" } };
  }
  if (!access.allowed) {
    switch (access.reason) {
      case "not_entitled":
        return { status: 403, body: { error: "not_entitled" } };
      case "trial_locked":
        return { status: 403, body: { error: "trial_locked" } };
      case "no_video":
        return { status: 404, body: { error: "no_video" } };
      case "bad_request":
        return { status: 400, body: { error: "bad request" } };
      default:
        return { status: 403, body: { error: "denied" } };
    }
  }

  let url: string | null;
  try {
    url = await deps.sign(access.storage_path, SIGNED_URL_TTL_SECONDS);
  } catch {
    url = null;
  }
  if (!url) return { status: 502, body: { error: "could not sign url" } };
  return { status: 200, body: { url, expires_in: SIGNED_URL_TTL_SECONDS } };
}
