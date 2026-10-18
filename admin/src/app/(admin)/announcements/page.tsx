import { pageGuard } from "@/lib/page-guard";
import { Empty, ErrorBox, PageHeader, fmtDate } from "@/components/ui";
import { ActionButton } from "@/components/action-button";
import { AnnouncementForm } from "@/components/config-forms";
import { deleteAnnouncement, setAnnouncementActive } from "@/lib/actions/announcements";

const localInput = (iso: string | null): string => (iso ? new Date(iso).toISOString().slice(0, 16) : "");

export default async function AnnouncementsPage() {
  const { db } = await pageGuard(["owner", "support"]);
  const { data, error } = await db
    .from("announcements")
    .select("id, title, body, level, starts_at, ends_at, active, created_at")
    .order("created_at", { ascending: false })
    .limit(100);

  return (
    <>
      <PageHeader title="Announcements" subtitle="Short messages shown inside the app while active and inside their window." />
      <div className="space-y-4">
        <AnnouncementForm />
        {error ? (
          <ErrorBox message="Could not load announcements." />
        ) : !data?.length ? (
          <Empty title="No announcements yet" />
        ) : (
          data.map((a) => (
            <div key={a.id as string} className="space-y-3">
              <div className="card text-sm">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <p className="font-medium">
                    {a.title as string} <span className={a.level === "warning" ? "text-danger" : "text-muted"}>({a.level as string})</span>
                  </p>
                  <div className="flex gap-2">
                    <ActionButton
                      action={setAnnouncementActive.bind(null, a.id, !a.active)}
                      label={a.active ? "Deactivate" : "Activate"}
                    />
                    <ActionButton
                      action={deleteAnnouncement.bind(null, a.id)}
                      label="Delete"
                      variant="danger"
                      confirmText="Delete this announcement?"
                    />
                  </div>
                </div>
                <p className="mt-1 text-muted">
                  {a.active ? "Active" : "Inactive"} - from {fmtDate(a.starts_at as string)} to {a.ends_at ? fmtDate(a.ends_at as string) : "no end"}
                </p>
              </div>
              <AnnouncementForm
                announcement={{
                  id: a.id as string,
                  title: a.title as string,
                  body: a.body as string,
                  level: a.level as string,
                  starts: localInput(a.starts_at as string),
                  ends: localInput(a.ends_at as string | null),
                  active: a.active as boolean,
                }}
              />
            </div>
          ))
        )}
      </div>
    </>
  );
}
