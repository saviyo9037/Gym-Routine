import { pageGuard } from "@/lib/page-guard";
import { Empty, ErrorBox, PageHeader, PAGE_SIZE, Pagination, fmtDate } from "@/components/ui";
import { escapeSearch, pageSchema } from "@/lib/validation";

export default async function AuditPage({ searchParams }: { searchParams: Promise<{ page?: string; action?: string }> }) {
  const { db } = await pageGuard(["owner"]);
  const sp = await searchParams;
  const page = pageSchema.parse(sp.page);
  const action = escapeSearch(sp.action ?? "");
  let q = db
    .from("audit_log")
    .select("id, actor_id, actor_role, action, target_type, target_id, metadata, created_at", { count: "exact" })
    .order("id", { ascending: false })
    .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1);
  if (action) q = q.ilike("action", `${action}%`);
  const { data, error, count } = await q;
  return (
    <>
      <PageHeader title="Audit log" subtitle="Append-only record of admin actions." />
      <form className="mb-4 flex gap-2" role="search">
        <input name="action" defaultValue={action} placeholder="Action prefix, e.g. user. or media." className="input max-w-sm" />
        <button className="btn">Filter</button>
      </form>
      {error ? (
        <ErrorBox message="Could not load the audit log." />
      ) : !data?.length ? (
        <Empty title="No audit entries" />
      ) : (
        <div className="card overflow-x-auto p-0">
          <table className="w-full">
            <thead>
              <tr>
                <th className="th">Time</th>
                <th className="th">Actor</th>
                <th className="th">Action</th>
                <th className="th">Target</th>
                <th className="th">Details</th>
              </tr>
            </thead>
            <tbody>
              {data.map((r) => (
                <tr key={r.id}>
                  <td className="td whitespace-nowrap">{fmtDate(r.created_at)}</td>
                  <td className="td">
                    {r.actor_role ?? "-"}
                    <span className="block text-xs text-muted">{r.actor_id ?? ""}</span>
                  </td>
                  <td className="td">{r.action}</td>
                  <td className="td">
                    {r.target_type ?? "-"} {r.target_id ?? ""}
                  </td>
                  <td className="td max-w-xs truncate font-mono text-xs text-muted">{JSON.stringify(r.metadata)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <Pagination page={page} total={count ?? 0} basePath="/audit" params={{ action: action || undefined }} />
    </>
  );
}
