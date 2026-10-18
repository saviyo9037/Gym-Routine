import Link from "next/link";
import { pageGuard } from "@/lib/page-guard";
import { Empty, ErrorBox, PageHeader, PAGE_SIZE, Pagination, fmtDate } from "@/components/ui";
import { pageSchema } from "@/lib/validation";

export default async function SubscriptionsPage({ searchParams }: { searchParams: Promise<{ page?: string; show?: string }> }) {
  const { db } = await pageGuard(["owner", "support"]);
  const sp = await searchParams;
  const page = pageSchema.parse(sp.page);
  const onlyActive = sp.show !== "all";

  let q = db
    .from("entitlements")
    .select("user_id, is_active, product_id, store, expires_at, will_renew, billing_issue_detected_at, updated_at", { count: "exact" })
    .eq("entitlement_id", "premium")
    .order("updated_at", { ascending: false })
    .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1);
  if (onlyActive) q = q.eq("is_active", true);
  const { data, error, count } = await q;
  const ids = (data ?? []).map((r) => r.user_id as string);
  const emails = new Map<string, string | null>();
  if (ids.length) {
    const { data: ps } = await db.from("profiles").select("id, email").in("id", ids);
    for (const p of ps ?? []) emails.set(p.id as string, p.email as string | null);
  }
  const { data: events, error: evErr } = await db
    .from("revenuecat_events")
    .select("event_id, type, product_id, price, currency, environment, event_timestamp_ms")
    .order("event_timestamp_ms", { ascending: false })
    .limit(15);

  return (
    <>
      <PageHeader title="Subscriptions">
        <Link className="btn-ghost" href={onlyActive ? "/subscriptions?show=all" : "/subscriptions"}>
          {onlyActive ? "Show all" : "Active only"}
        </Link>
      </PageHeader>
      {error ? (
        <ErrorBox message="Could not load subscriptions." />
      ) : !data?.length ? (
        <Empty title="No subscriptions" hint="Entitlements appear after RevenueCat webhook events arrive." />
      ) : (
        <div className="card overflow-x-auto p-0">
          <table className="w-full">
            <thead>
              <tr>
                <th className="th">User</th>
                <th className="th">Active</th>
                <th className="th">Product</th>
                <th className="th">Store</th>
                <th className="th">Expires</th>
                <th className="th">Renews</th>
              </tr>
            </thead>
            <tbody>
              {data.map((r) => (
                <tr key={r.user_id}>
                  <td className="td">
                    <Link className="text-accent hover:underline" href={`/users/${r.user_id}`}>
                      {emails.get(r.user_id) ?? r.user_id}
                    </Link>
                  </td>
                  <td className="td">{r.is_active ? "Yes" : "No"}</td>
                  <td className="td">{r.product_id ?? "-"}</td>
                  <td className="td">{r.store ?? "-"}</td>
                  <td className="td">{fmtDate(r.expires_at)}</td>
                  <td className="td">{r.will_renew ? "Yes" : "No"}{r.billing_issue_detected_at ? " (billing issue)" : ""}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <Pagination page={page} total={count ?? 0} basePath="/subscriptions" params={{ show: onlyActive ? undefined : "all" }} />

      <h2 className="mb-2 mt-8 text-lg font-medium">Recent RevenueCat events</h2>
      {evErr ? (
        <ErrorBox message="Could not load events." />
      ) : !events?.length ? (
        <Empty title="No events received yet" />
      ) : (
        <div className="card overflow-x-auto p-0">
          <table className="w-full">
            <thead>
              <tr>
                <th className="th">Time</th>
                <th className="th">Type</th>
                <th className="th">Product</th>
                <th className="th">Price</th>
                <th className="th">Env</th>
              </tr>
            </thead>
            <tbody>
              {events.map((e) => (
                <tr key={e.event_id}>
                  <td className="td">{fmtDate(new Date(Number(e.event_timestamp_ms)).toISOString())}</td>
                  <td className="td">{e.type}</td>
                  <td className="td">{e.product_id ?? "-"}</td>
                  <td className="td">{e.price != null ? `${e.price} ${e.currency ?? ""}` : "-"}</td>
                  <td className="td">{e.environment ?? "-"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
