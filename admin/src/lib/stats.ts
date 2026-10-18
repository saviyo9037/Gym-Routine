const DAY = 86400000;

export function sinceIso(days: number, now: number = Date.now()): string {
  return new Date(now - days * DAY).toISOString();
}

/** Buckets created_at timestamps into per-day counts (UTC) for the last `days` days. */
export function signupSeries(rows: { created_at: string }[], days = 14, now: number = Date.now()) {
  const series: { day: string; n: number }[] = [];
  for (let i = days - 1; i >= 0; i--) series.push({ day: new Date(now - i * DAY).toISOString().slice(0, 10), n: 0 });
  for (const r of rows) {
    const d = series.find((x) => x.day === r.created_at.slice(0, 10));
    if (d) d.n++;
  }
  return series;
}

/** Lifecycle of a comp grant (pure; the clock is a parameter so pages stay free of impure calls). */
export function grantState(
  g: { revoked_at: string | null; expires_at: string | null },
  now: number = Date.now(),
): "Revoked" | "Expired" | "Active" {
  if (g.revoked_at) return "Revoked";
  if (g.expires_at && new Date(g.expires_at).getTime() <= now) return "Expired";
  return "Active";
}
