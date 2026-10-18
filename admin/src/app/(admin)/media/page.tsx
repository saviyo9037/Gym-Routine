import Link from "next/link";
import { pageGuard } from "@/lib/page-guard";
import { Empty, ErrorBox, PageHeader, PAGE_SIZE, Pagination } from "@/components/ui";
import { MediaTable, type MediaRow } from "@/components/media-table";
import { pageSchema } from "@/lib/validation";

export default async function MediaPage({ searchParams }: { searchParams: Promise<{ page?: string; filter?: string }> }) {
  const { db } = await pageGuard(["owner", "content"]);
  const sp = await searchParams;
  const page = pageSchema.parse(sp.page);
  const unverified = sp.filter === "unverified";
  let q = db
    .from("exercise_media")
    .select("id, exercise_id, media_type, storage_path, size_bytes, license, attribution, license_verified, status", { count: "exact" })
    .order("created_at", { ascending: false })
    .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1);
  if (unverified) q = q.eq("license_verified", false);
  const { data, error, count } = await q;
  return (
    <>
      <PageHeader title="Media" subtitle="Upload media from an exercise's page so it is mapped to the right exercise id.">
        <Link className="btn-ghost" href={unverified ? "/media" : "/media?filter=unverified"}>
          {unverified ? "Show all" : "Only unverified licences"}
        </Link>
      </PageHeader>
      {error ? <ErrorBox message="Could not load media." /> : !data?.length ? <Empty title="No media" /> : <MediaTable showExercise rows={data as MediaRow[]} />}
      <Pagination page={page} total={count ?? 0} basePath="/media" params={{ filter: unverified ? "unverified" : undefined }} />
    </>
  );
}
