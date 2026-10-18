import { notFound, redirect } from "next/navigation";
import { GuardError } from "@/lib/guard";
import { loadUserWorkouts } from "@/lib/queries/user-workouts";
import { Empty, PageHeader } from "@/components/ui";
import { uuidSchema } from "@/lib/validation";

export default async function UserWorkouts({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!uuidSchema.safeParse(id).success) notFound();
  let sessions;
  try {
    sessions = await loadUserWorkouts(id); // guard + audit happen inside
  } catch (e) {
    if (e instanceof GuardError) {
      if (e.code === "unauthenticated") redirect("/login");
      if (e.code === "mfa_required") redirect("/mfa");
      redirect("/forbidden");
    }
    throw e;
  }
  return (
    <>
      <PageHeader title="Workout sessions" subtitle={`User ${id} - this view was recorded in the audit log`} />
      {sessions.length === 0 ? (
        <Empty title="No synced workout sessions" />
      ) : (
        <div className="card overflow-x-auto p-0">
          <table className="w-full">
            <thead>
              <tr>
                <th className="th">Date</th>
                <th className="th">Primary</th>
                <th className="th">Secondary</th>
                <th className="th">Minutes</th>
              </tr>
            </thead>
            <tbody>
              {sessions.map((s) => (
                <tr key={s.id}>
                  <td className="td">{s.session_date}</td>
                  <td className="td">{s.primary_muscle}</td>
                  <td className="td">{s.secondary_muscle ?? "-"}</td>
                  <td className="td">{Math.round((s.duration_seconds ?? 0) / 60)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
