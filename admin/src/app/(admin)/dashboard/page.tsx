import { pageGuard } from "@/lib/page-guard";
import { signupSeries, sinceIso } from "@/lib/stats";
import { Empty, ErrorBox, PageHeader, Stat } from "@/components/ui";

export default async function DashboardPage() {
  const { db } = await pageGuard(["owner", "support"]);
  const since = sinceIso(14);
  const [stats, rev, recent] = await Promise.all([
    db.rpc("dashboard_stats"),
    db.rpc("revenue_summary"),
    db.from("profiles").select("created_at").is("deleted_at", null).gte("created_at", since).limit(10000),
  ]);
  if (stats.error || rev.error) {
    return (
      <>
        <PageHeader title="Dashboard" />
        <ErrorBox message="Could not load dashboard figures. Check that the backend migrations are applied." />
      </>
    );
  }
  const s = (stats.data as { total_users: number; signups_7d: number; signups_30d: number; dau: number }[])?.[0];
  const r = (rev.data as { active_subscribers: number; mrr_usd: number }[])?.[0];

  const days = signupSeries((recent.data ?? []) as { created_at: string }[], 14);
  const max = Math.max(1, ...days.map((d) => d.n));

  if (!s || s.total_users === 0) {
    return (
      <>
        <PageHeader title="Dashboard" />
        <Empty title="No users yet" hint="Figures appear once people sign up in the app." />
      </>
    );
  }
  return (
    <>
      <PageHeader title="Dashboard" subtitle="Live queries against the database. Nothing is estimated." />
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Stat label="Total users" value={String(s.total_users)} />
        <Stat label="Active subscribers" value={String(r?.active_subscribers ?? 0)} hint="premium entitlement, not expired" />
        <Stat
          label="MRR (USD)"
          value={`$${Number(r?.mrr_usd ?? 0).toFixed(2)}`}
          hint="latest paid production event per auto-renewing subscriber; trials and sandbox excluded"
        />
        <Stat label="DAU" value={String(s.dau)} hint="distinct users seen in the last 24h" />
        <Stat label="Signups (7d)" value={String(s.signups_7d)} />
        <Stat label="Signups (30d)" value={String(s.signups_30d)} />
      </div>
      <div className="card mt-6">
        <p className="mb-3 text-sm font-medium">Signups, last 14 days</p>
        {days.every((d) => d.n === 0) ? (
          <p className="text-sm text-muted">No signups in this period.</p>
        ) : (
          <div className="flex h-32 items-end gap-1" role="img" aria-label="Signups per day">
            {days.map((d) => (
              <div key={d.day} className="flex flex-1 flex-col items-center justify-end" title={`${d.day}: ${d.n}`}>
                <div className="w-full rounded-t bg-accent" style={{ height: `${(d.n / max) * 100}%`, minHeight: d.n ? 2 : 0 }} />
                <span className="mt-1 text-[10px] text-muted">{d.day.slice(8)}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </>
  );
}
