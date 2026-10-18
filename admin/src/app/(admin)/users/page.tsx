import Link from "next/link";
import { pageGuard } from "@/lib/page-guard";
import { Empty, ErrorBox, PageHeader, PAGE_SIZE, Pagination, fmtDate } from "@/components/ui";
import { escapeSearch, pageSchema } from "@/lib/validation";

type SP = Promise<{ q?: string; page?: string }>;

export default async function UsersPage({ searchParams }: { searchParams: SP }) {
  const { db } = await pageGuard(["owner", "support"]);
  const sp = await searchParams;
  const page = pageSchema.parse(sp.page);
  const q = escapeSearch(sp.q ?? "");

  let query = db
    .from("profiles")
    .select("id, email, display_name, disabled, created_at, last_seen_at, last_sync_at", { count: "exact" })
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1);
  if (q) query = query.or(`email.ilike.%${q}%,display_name.ilike.%${q}%`);
  const { data, error, count } = await query;

  return (
    <>
      <PageHeader title="Users" />
      <form className="mb-4 flex gap-2" role="search">
        <input name="q" defaultValue={q} placeholder="Search email or name" className="input max-w-sm" />
        <button className="btn">Search</button>
      </form>
      {error ? (
        <ErrorBox message="Could not load users." />
      ) : !data?.length ? (
        <Empty title={q ? "No users match your search" : "No users yet"} />
      ) : (
        <div className="card overflow-x-auto p-0">
          <table className="w-full">
            <thead>
              <tr>
                <th className="th">Email</th>
                <th className="th">Name</th>
                <th className="th">Signed up</th>
                <th className="th">Last seen</th>
                <th className="th">Status</th>
              </tr>
            </thead>
            <tbody>
              {data.map((u) => (
                <tr key={u.id}>
                  <td className="td">
                    <Link className="text-accent hover:underline" href={`/users/${u.id}`}>
                      {u.email ?? u.id}
                    </Link>
                  </td>
                  <td className="td">{u.display_name ?? "-"}</td>
                  <td className="td">{fmtDate(u.created_at)}</td>
                  <td className="td">{fmtDate(u.last_seen_at)}</td>
                  <td className="td">{u.disabled ? <span className="text-danger">Disabled</span> : "Active"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <Pagination page={page} total={count ?? 0} basePath="/users" params={{ q: q || undefined }} />
    </>
  );
}
