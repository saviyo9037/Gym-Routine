import { pageGuard } from "@/lib/page-guard";
import { Empty, ErrorBox, PageHeader, fmtDate } from "@/components/ui";
import { ActionButton } from "@/components/action-button";
import { AddAdminForm, RoleSelect } from "@/components/admin-forms";
import { removeAdmin } from "@/lib/actions/admins";

export default async function AdminsPage() {
  const { db, user } = await pageGuard(["owner"]);
  const { data, error } = await db.from("admins").select("user_id, role, created_at").order("created_at", { ascending: true });
  const ids = (data ?? []).map((a) => a.user_id as string);
  const emails = new Map<string, string | null>();
  if (ids.length) {
    const { data: ps } = await db.from("profiles").select("id, email").in("id", ids);
    for (const p of ps ?? []) emails.set(p.id as string, p.email as string | null);
  }
  return (
    <>
      <PageHeader title="Admins" subtitle="Owner only. Admins must also enrol TOTP two-factor to sign in." />
      <AddAdminForm />
      <div className="mt-6">
        {error ? (
          <ErrorBox message="Could not load admins." />
        ) : !data?.length ? (
          <Empty title="No admins" />
        ) : (
          <div className="card overflow-x-auto p-0">
            <table className="w-full">
              <thead>
                <tr>
                  <th className="th">User</th>
                  <th className="th">Role</th>
                  <th className="th">Since</th>
                  <th className="th" />
                </tr>
              </thead>
              <tbody>
                {data.map((a) => (
                  <tr key={a.user_id}>
                    <td className="td">{emails.get(a.user_id) ?? a.user_id}</td>
                    <td className="td">
                      <RoleSelect userId={a.user_id} role={a.role} />
                    </td>
                    <td className="td">{fmtDate(a.created_at)}</td>
                    <td className="td">
                      {a.user_id !== user.id ? (
                        <ActionButton action={removeAdmin.bind(null, a.user_id)} label="Remove" variant="danger" confirmText="Remove this admin's access?" />
                      ) : (
                        <span className="text-xs text-muted">you</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}
