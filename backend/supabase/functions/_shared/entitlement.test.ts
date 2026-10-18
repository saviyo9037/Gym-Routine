// Runs under `deno test` and `node --test` (Node >= 22.6 with type stripping).
import { test } from "node:test";
import assert from "node:assert/strict";
import { computeState, isStale, parseEvent, resolveUserId, verifyAuthHeader } from "./entitlement.ts";

const UID = "aaaaaaaa-0000-4000-8000-000000000001";
const NOW = 1_800_000_000_000;
const DAY = 86_400_000;
const ev = (o: Record<string, unknown>) =>
  ({ id: "e1", type: "INITIAL_PURCHASE", event_timestamp_ms: NOW, app_user_id: UID, product_id: "p_month",
     store: "PLAY_STORE", purchased_at_ms: NOW - DAY, expiration_at_ms: NOW + 29 * DAY, ...o }) as never;

test("auth header", () => {
  assert.equal(verifyAuthHeader("Bearer s3cret", "Bearer s3cret"), true);
  assert.equal(verifyAuthHeader("Bearer wrong", "Bearer s3cret"), false);
  assert.equal(verifyAuthHeader("Bearer s3cret", "Bearer s3cret-longer"), false);
  assert.equal(verifyAuthHeader(null, "x"), false);
  assert.equal(verifyAuthHeader("x", undefined), false);
  assert.equal(verifyAuthHeader("", ""), false);
});

test("parseEvent validation", () => {
  assert.ok("error" in parseEvent(null));
  assert.ok("error" in parseEvent({}));
  assert.ok("error" in parseEvent({ event: { type: "X", event_timestamp_ms: 1 } }));
  assert.ok("error" in parseEvent({ event: { id: "a", type: "X" } }));
  assert.ok("event" in parseEvent({ event: { id: "a", type: "X", event_timestamp_ms: 1 } }));
});

test("resolveUserId prefers uuid app_user_id, falls back to aliases, else null", () => {
  assert.equal(resolveUserId(ev({})), UID);
  assert.equal(resolveUserId(ev({ app_user_id: "$RCAnonymousID:abc", aliases: ["$RCAnonymousID:abc", UID] })), UID);
  assert.equal(resolveUserId(ev({ app_user_id: "$RCAnonymousID:abc", aliases: [] })), null);
});

test("purchase / renewal / uncancellation / product change activate", () => {
  for (const type of ["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "PRODUCT_CHANGE"]) {
    const s = computeState(ev({ type }), NOW);
    assert.equal(s.is_active, true, type);
    assert.equal(s.will_renew, true, type);
    assert.equal(s.user_id, UID);
  }
  assert.equal(computeState(ev({ type: "PRODUCT_CHANGE", new_product_id: "p_year" }), NOW).product_id, "p_year");
});

test("non-renewing purchase is active but does not renew", () => {
  const s = computeState(ev({ type: "NON_RENEWING_PURCHASE" }), NOW);
  assert.equal(s.is_active, true);
  assert.equal(s.will_renew, false);
});

test("cancellation keeps access until expiry, flags unsubscribe", () => {
  const s = computeState(ev({ type: "CANCELLATION" }), NOW);
  assert.equal(s.is_active, true);
  assert.equal(s.will_renew, false);
  assert.equal(s.unsubscribe_detected_at, new Date(NOW).toISOString());
});

test("cancellation with an already-passed expiry (refund) is inactive", () => {
  assert.equal(computeState(ev({ type: "CANCELLATION", expiration_at_ms: NOW - 1 }), NOW).is_active, false);
});

test("expiration deactivates", () => {
  const s = computeState(ev({ type: "EXPIRATION", expiration_at_ms: NOW - 1000 }), NOW);
  assert.equal(s.is_active, false);
  assert.equal(s.will_renew, false);
});

test("billing issue stays active through grace period only", () => {
  const inGrace = computeState(ev({ type: "BILLING_ISSUE", expiration_at_ms: NOW - DAY, grace_period_expiration_at_ms: NOW + DAY }), NOW);
  assert.equal(inGrace.is_active, true);
  assert.equal(inGrace.billing_issue_detected_at, new Date(NOW).toISOString());
  const noGrace = computeState(ev({ type: "BILLING_ISSUE", expiration_at_ms: NOW - DAY }), NOW);
  assert.equal(noGrace.is_active, false);
});

test("lifetime (null expiration) purchase is active", () => {
  assert.equal(computeState(ev({ type: "NON_RENEWING_PURCHASE", expiration_at_ms: null }), NOW).is_active, true);
});

test("unhandled types and other entitlements only record", () => {
  assert.deepEqual(computeState(ev({ type: "TEST" }), NOW), { user_id: UID });
  assert.deepEqual(computeState(ev({ entitlement_ids: ["other"] }), NOW), { user_id: UID });
  assert.equal(computeState(ev({ entitlement_ids: ["premium"] }), NOW).is_active, true);
});

test("stale-event rule", () => {
  assert.equal(isStale(100, 100), true);
  assert.equal(isStale(99, 100), true);
  assert.equal(isStale(101, 100), false);
  assert.equal(isStale(1, null), false);
  assert.equal(isStale(1, undefined), false);
});

test("refund via CUSTOMER_SUPPORT revokes immediately even with a future expiry", () => {
  const now = 1_800_000_000_000;
  const s = computeState(
    ev({ type: "CANCELLATION", cancel_reason: "CUSTOMER_SUPPORT", expiration_at_ms: now + 20 * 86_400_000 }),
    now,
  );
  assert.equal(s.is_active, false);
  assert.equal(s.will_renew, false);
});

test("a normal UNSUBSCRIBE cancellation still keeps access until expiry", () => {
  const now = 1_800_000_000_000;
  const s = computeState(
    ev({ type: "CANCELLATION", cancel_reason: "UNSUBSCRIBE", expiration_at_ms: now + 5 * 86_400_000 }),
    now,
  );
  assert.equal(s.is_active, true);
  assert.equal(s.will_renew, false);
});

test("pause keeps access to the end of the period; extension re-activates", () => {
  const now = 1_800_000_000_000;
  const paused = computeState(ev({ type: "SUBSCRIPTION_PAUSED", expiration_at_ms: now + 86_400_000 }), now);
  assert.equal(paused.is_active, true);
  assert.equal(paused.will_renew, false);
  const afterPause = computeState(ev({ type: "SUBSCRIPTION_PAUSED", expiration_at_ms: now - 1 }), now);
  assert.equal(afterPause.is_active, false);
  const extended = computeState(ev({ type: "SUBSCRIPTION_EXTENDED", expiration_at_ms: now + 10 * 86_400_000 }), now);
  assert.equal(extended.is_active, true);
  assert.equal(extended.will_renew, true);
});

test("out-of-order: an old RENEWAL arriving after a newer EXPIRATION is stale", () => {
  assert.equal(isStale(1_000, 2_000), true);
  assert.equal(isStale(2_000, 2_000), true);
  assert.equal(isStale(3_000, 2_000), false);
  assert.equal(isStale(1_000, null), false);
});

test("grace period after a billing issue extends access past the store expiry", () => {
  const now = 1_800_000_000_000;
  const s = computeState(
    ev({ type: "BILLING_ISSUE", expiration_at_ms: now - 1000, grace_period_expiration_at_ms: now + 86_400_000 }),
    now,
  );
  assert.equal(s.is_active, true);
});

test("free trial: INITIAL_PURCHASE with period_type TRIAL is an ACTIVE entitlement until the trial ends", () => {
  const trial = computeState(
    ev({ period_type: "TRIAL", expiration_at_ms: NOW + DAY, purchased_at_ms: NOW }),
    NOW,
  );
  assert.equal(trial.is_active, true);
  assert.equal(trial.period_type, "TRIAL");
  assert.equal(trial.expires_at, new Date(NOW + DAY).toISOString());
});

test("free trial that is not converted: EXPIRATION removes access", () => {
  const ended = computeState(
    ev({ type: "EXPIRATION", period_type: "TRIAL", expiration_at_ms: NOW - 1000 }),
    NOW,
  );
  assert.equal(ended.is_active, false);
});

test("free trial converts to a paid period: RENEWAL (NORMAL) is active", () => {
  const paid = computeState(
    ev({ type: "RENEWAL", period_type: "NORMAL", expiration_at_ms: NOW + 29 * DAY }),
    NOW,
  );
  assert.equal(paid.is_active, true);
  assert.equal(paid.period_type, "NORMAL");
});

test("cancelling during the trial keeps access until the trial ends, a refund revokes at once", () => {
  const cancelled = computeState(
    ev({ type: "CANCELLATION", period_type: "TRIAL", expiration_at_ms: NOW + DAY / 2 }),
    NOW,
  );
  assert.equal(cancelled.is_active, true);
  assert.equal(cancelled.will_renew, false);
  const refunded = computeState(
    ev({ type: "CANCELLATION", period_type: "TRIAL", expiration_at_ms: NOW + DAY / 2, cancel_reason: "CUSTOMER_SUPPORT" }),
    NOW,
  );
  assert.equal(refunded.is_active, false);
});
