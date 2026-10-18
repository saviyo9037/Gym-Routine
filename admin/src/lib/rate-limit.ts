/**
 * Small in-memory sliding-window limiter. Best effort ONLY: every server
 * instance has its own memory, so this slows a single instance down but is not
 * a distributed limit. The authoritative limit is Supabase Auth's own sign-in
 * rate limiting (Auth > Rate limits) plus the platform/CDN in front of the
 * admin app; see admin/README.md.
 */
export class SlidingWindowLimiter {
  private hits = new Map<string, number[]>();

  constructor(
    private readonly max: number,
    private readonly windowMs: number,
    private readonly now: () => number = Date.now,
  ) {}

  private prune(key: string): number[] {
    const cutoff = this.now() - this.windowMs;
    const live = (this.hits.get(key) ?? []).filter((t) => t > cutoff);
    if (live.length === 0) this.hits.delete(key);
    else this.hits.set(key, live);
    return live;
  }

  /** True when [key] already used up its attempts inside the window. */
  isLimited(key: string): boolean {
    return this.prune(key).length >= this.max;
  }

  /** Counts one failed attempt. */
  record(key: string): void {
    const live = this.prune(key);
    live.push(this.now());
    this.hits.set(key, live);
    // Bound memory: never track more than 5000 keys.
    if (this.hits.size > 5000) {
      const oldest = this.hits.keys().next().value;
      if (oldest !== undefined) this.hits.delete(oldest);
    }
  }

  reset(key: string): void {
    this.hits.delete(key);
  }
}

/** 5 failed sign-ins per e-mail and 20 per IP in 15 minutes. */
export const loginEmailLimiter = new SlidingWindowLimiter(5, 15 * 60_000);
export const loginIpLimiter = new SlidingWindowLimiter(20, 15 * 60_000);
