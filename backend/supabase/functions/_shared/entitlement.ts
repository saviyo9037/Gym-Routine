// Pure RevenueCat webhook logic. No I/O and no runtime-specific imports, so it runs
// under Deno (Edge Functions) and Node >= 22 (type stripping) alike.

export const ENTITLEMENT_ID = "premium";

export const HANDLED_TYPES = [
  "INITIAL_PURCHASE",
  "RENEWAL",
  "CANCELLATION",
  "EXPIRATION",
  "BILLING_ISSUE",
  "PRODUCT_CHANGE",
  "UNCANCELLATION",
  "NON_RENEWING_PURCHASE",
  "SUBSCRIPTION_PAUSED",
  "SUBSCRIPTION_EXTENDED",
] as const;

export interface RcEvent {
  id: string;
  type: string;
  event_timestamp_ms: number;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  product_id?: string;
  new_product_id?: string;
  store?: string;
  environment?: string;
  period_type?: string;
  price?: number;
  currency?: string;
  purchased_at_ms?: number;
  expiration_at_ms?: number | null;
  grace_period_expiration_at_ms?: number | null;
  entitlement_id?: string | null;
  entitlement_ids?: string[] | null;
  cancel_reason?: string | null;
  [k: string]: unknown;
}

export interface EntitlementState {
  user_id: string | null;
  // Present only when the event changes the "premium" entitlement.
  is_active?: boolean;
  product_id?: string | null;
  store?: string | null;
  period_type?: string | null;
  purchased_at?: string | null;
  expires_at?: string | null;
  will_renew?: boolean;
  billing_issue_detected_at?: string | null;
  unsubscribe_detected_at?: string | null;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Constant-time string compare. Missing/empty expected secret never matches. */
export function verifyAuthHeader(header: string | null | undefined, expected: string | null | undefined): boolean {
  if (!expected || !header) return false;
  const a = new TextEncoder().encode(header);
  const b = new TextEncoder().encode(expected);
  let diff = a.length ^ b.length;
  const n = Math.max(a.length, b.length);
  for (let i = 0; i < n; i++) diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return diff === 0;
}

/** Validates the webhook body and returns the event, or an error string. */
export function parseEvent(body: unknown): { event: RcEvent } | { error: string } {
  if (typeof body !== "object" || body === null) return { error: "body must be an object" };
  const ev = (body as { event?: unknown }).event;
  if (typeof ev !== "object" || ev === null) return { error: "missing event" };
  const e = ev as Record<string, unknown>;
  if (typeof e.id !== "string" || e.id.length === 0) return { error: "event.id required" };
  if (typeof e.type !== "string" || e.type.length === 0) return { error: "event.type required" };
  if (typeof e.event_timestamp_ms !== "number" || !Number.isFinite(e.event_timestamp_ms)) {
    return { error: "event.event_timestamp_ms required" };
  }
  return { event: e as unknown as RcEvent };
}

/** The Supabase auth user id: app_user_id, else a uuid alias / original id. */
export function resolveUserId(e: RcEvent): string | null {
  const candidates = [e.app_user_id, e.original_app_user_id, ...(e.aliases ?? [])];
  for (const c of candidates) if (typeof c === "string" && UUID_RE.test(c)) return c.toLowerCase();
  return null;
}

function appliesToPremium(e: RcEvent): boolean {
  if (Array.isArray(e.entitlement_ids) && e.entitlement_ids.length > 0) return e.entitlement_ids.includes(ENTITLEMENT_ID);
  if (typeof e.entitlement_id === "string" && e.entitlement_id.length > 0) return e.entitlement_id === ENTITLEMENT_ID;
  return true; // RevenueCat omitted the field; the project has a single entitlement.
}

const iso = (ms: number | null | undefined): string | null =>
  typeof ms === "number" && Number.isFinite(ms) ? new Date(ms).toISOString() : null;

/**
 * Staleness rule: an event is stale when the stored entitlement already reflects an
 * event with timestamp >= this event's. (Also enforced atomically in SQL.)
 */
export function isStale(eventTimestampMs: number, lastAppliedTimestampMs: number | null | undefined): boolean {
  return typeof lastAppliedTimestampMs === "number" && lastAppliedTimestampMs >= eventTimestampMs;
}

/**
 * Maps an event to the new premium entitlement state. `nowMs` is injected for testing.
 * Events that are not handled / do not concern "premium" yield only { user_id }.
 */
export function computeState(e: RcEvent, nowMs: number): EntitlementState {
  const user_id = resolveUserId(e);
  if (!(HANDLED_TYPES as readonly string[]).includes(e.type) || !appliesToPremium(e)) return { user_id };

  const exp = e.expiration_at_ms ?? null;
  // Billing-issue grace period keeps access until it ends.
  const accessUntil = Math.max(exp ?? 0, e.grace_period_expiration_at_ms ?? 0);
  const lifetime = exp === null && e.type !== "EXPIRATION";
  const timeActive = lifetime || accessUntil > nowMs;
  const base: EntitlementState = {
    user_id,
    product_id: e.new_product_id ?? e.product_id ?? null,
    store: e.store ?? null,
    period_type: e.period_type ?? null,
    purchased_at: iso(e.purchased_at_ms),
    expires_at: iso(exp),
    billing_issue_detected_at: null,
    unsubscribe_detected_at: null,
  };

  switch (e.type) {
    case "INITIAL_PURCHASE":
    case "RENEWAL":
    case "UNCANCELLATION":
    case "PRODUCT_CHANGE":
    case "SUBSCRIPTION_EXTENDED":
      return { ...base, is_active: timeActive, will_renew: true };
    case "SUBSCRIPTION_PAUSED":
      // Google Play pause: paid access runs to the end of the current period.
      return { ...base, is_active: timeActive, will_renew: false, unsubscribe_detected_at: iso(e.event_timestamp_ms) };
    case "NON_RENEWING_PURCHASE":
      return { ...base, is_active: timeActive, will_renew: false };
    case "CANCELLATION": {
      // Access continues until expiry unless the store already ended it. A refund /
      // support cancellation (cancel_reason CUSTOMER_SUPPORT) revokes access at once,
      // even if the event still carries the original future expiry.
      const revoked = e.cancel_reason === "CUSTOMER_SUPPORT";
      return { ...base, is_active: revoked ? false : timeActive, will_renew: false, unsubscribe_detected_at: iso(e.event_timestamp_ms) };
    }
    case "BILLING_ISSUE":
      return { ...base, is_active: timeActive, will_renew: true, billing_issue_detected_at: iso(e.event_timestamp_ms) };
    case "EXPIRATION":
      return { ...base, is_active: false, will_renew: false };
    default:
      return { user_id };
  }
}
