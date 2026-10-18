import Link from "next/link";
import { pageGuard } from "@/lib/page-guard";
import { Empty, ErrorBox, PageHeader, PAGE_SIZE, Pagination } from "@/components/ui";
import { escapeSearch, MUSCLE_GROUPS, pageSchema } from "@/lib/validation";
import { PublishPanel } from "./publish-panel";

type SP = Promise<{ q?: string; page?: string; muscle?: string; status?: string }>;

export default async function CataloguePage({ searchParams }: { searchParams: SP }) {
  const { db } = await pageGuard(["owner", "content"]);
  const sp = await searchParams;
  const page = pageSchema.parse(sp.page);
  const q = escapeSearch(sp.q ?? "");
  const muscle = (MUSCLE_GROUPS as readonly string[]).includes(sp.muscle ?? "") ? sp.muscle : undefined;
  const status = ["draft", "published", "archived"].includes(sp.status ?? "") ? sp.status : undefined;

  let query = db
    .from("exercises_catalog")
    .select("id, name, primary_muscle_group, equipment, difficulty, status, needs_publish, catalogue_version", { count: "exact" })
    .order("id", { ascending: true })
    .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1);
  if (q) query = query.ilike("name", `%${q}%`);
  if (muscle) query = query.eq("primary_muscle_group", muscle);
  if (status) query = query.eq("status", status);
  const [{ data, error, count }, ver, pending] = await Promise.all([
    query,
    db.from("catalogue_versions").select("version, published_at").order("version", { ascending: false }).limit(1).maybeSingle(),
    db.from("exercises_catalog").select("id", { count: "exact", head: true }).eq("needs_publish", true),
  ]);

  return (
    <>
      <PageHeader title="Exercise catalogue" subtitle="Changes are invisible to the app until published.">
        <Link className="btn" href="/catalogue/new">
          New exercise
        </Link>
      </PageHeader>
      <PublishPanel currentVersion={ver.data?.version ?? null} pendingCount={pending.count ?? 0} />
      <form className="my-4 flex flex-wrap gap-2" role="search">
        <input name="q" defaultValue={q} placeholder="Search name" className="input max-w-xs" />
        <select name="muscle" defaultValue={muscle ?? ""} className="input max-w-xs">
          <option value="">All muscle groups</option>
          {MUSCLE_GROUPS.map((m) => (
            <option key={m}>{m}</option>
          ))}
        </select>
        <select name="status" defaultValue={status ?? ""} className="input max-w-[10rem]">
          <option value="">Any status</option>
          <option>draft</option>
          <option>published</option>
          <option>archived</option>
        </select>
        <button className="btn">Filter</button>
      </form>
      {error ? (
        <ErrorBox message="Could not load the catalogue." />
      ) : !data?.length ? (
        <Empty title="No exercises found" hint="Create one, or seed the catalogue from the app's data." />
      ) : (
        <div className="card overflow-x-auto p-0">
          <table className="w-full">
            <thead>
              <tr>
                <th className="th">ID</th>
                <th className="th">Name</th>
                <th className="th">Muscle</th>
                <th className="th">Equipment</th>
                <th className="th">Difficulty</th>
                <th className="th">Status</th>
              </tr>
            </thead>
            <tbody>
              {data.map((x) => (
                <tr key={x.id}>
                  <td className="td">{x.id}</td>
                  <td className="td">
                    <Link className="text-accent hover:underline" href={`/catalogue/${x.id}`}>
                      {x.name}
                    </Link>
                  </td>
                  <td className="td">{x.primary_muscle_group}</td>
                  <td className="td">{x.equipment ?? "-"}</td>
                  <td className="td">{x.difficulty}</td>
                  <td className="td">
                    {x.status}
                    {x.needs_publish ? <span className="badge ml-2">unpublished changes</span> : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <Pagination page={page} total={count ?? 0} basePath="/catalogue" params={{ q: q || undefined, muscle, status }} />
    </>
  );
}
