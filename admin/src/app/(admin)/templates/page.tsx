import Link from "next/link";
import { pageGuard } from "@/lib/page-guard";
import { Empty, ErrorBox, PageHeader, PAGE_SIZE, Pagination, fmtDate } from "@/components/ui";
import { pageSchema } from "@/lib/validation";

export default async function TemplatesPage({ searchParams }: { searchParams: Promise<{ page?: string }> }) {
  const { db } = await pageGuard(["owner", "content"]);
  const page = pageSchema.parse((await searchParams).page);
  const { data, error, count } = await db
    .from("template_plans")
    .select("id, kind, title, status, updated_at", { count: "exact" })
    .order("updated_at", { ascending: false })
    .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1);
  return (
    <>
      <PageHeader title="Template plans and routines">
        <Link className="btn" href="/templates/new">
          New template
        </Link>
      </PageHeader>
      {error ? (
        <ErrorBox message="Could not load templates." />
      ) : !data?.length ? (
        <Empty title="No templates yet" />
      ) : (
        <div className="card overflow-x-auto p-0">
          <table className="w-full">
            <thead>
              <tr>
                <th className="th">Title</th>
                <th className="th">Kind</th>
                <th className="th">Status</th>
                <th className="th">Updated</th>
              </tr>
            </thead>
            <tbody>
              {data.map((t) => (
                <tr key={t.id}>
                  <td className="td">
                    <Link className="text-accent hover:underline" href={`/templates/${t.id}`}>
                      {t.title}
                    </Link>
                  </td>
                  <td className="td">{t.kind}</td>
                  <td className="td">{t.status}</td>
                  <td className="td">{fmtDate(t.updated_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <Pagination page={page} total={count ?? 0} basePath="/templates" />
    </>
  );
}
