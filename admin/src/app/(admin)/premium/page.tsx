import Link from "next/link";
import { pageGuard } from "@/lib/page-guard";
import { Empty, ErrorBox, PageHeader, fmtDate } from "@/components/ui";
import { ActionButton } from "@/components/action-button";
import { PremiumGrantForm } from "@/components/config-forms";
import { revokePremium } from "@/lib/actions/premium";
import { grantState } from "@/lib/stats";

export default async function ManualPremiumPage() {
  const { role, db } = await pageGuard(["owner", "support"]);
  const { data, error } = await db
    .from("manual_premium_grants")
    .select("id, user_id, reason, granted_at, expires_at, revoked_at")
    .order("granted_at", { ascending: false })
    .limit(100);
  const ids = Array.from(new Set((data ?? []).map((g) => g.user_id as string)));
  const emails = new Map<string, string | null>();
  if (ids.length) {
    const { data: ps } = await db.from("profiles").select("id, email").in("id", ids);
    for (const p of ps ?? []) emails.set(p.id as string, p.email as string | null);
  }
  return (
    <>
      <PageHeader title="Manual premium" subtitle="Comp access (free) with a reason and an expiry. Every grant and revoke is audit-logged." />
      <PremiumGrantForm role={role} />
      <div className="mt-6">
        {error ? (
          <ErrorBox message="Could not load grants." />
        ) : !data?.length ? (
          <Empty title="No grants yet" />
        ) : (
          <div className="card overflow-x-auto p-0">
            <table className="w-full">
              <thead>
                <tr>
                  <th className="th">User</th>
                  <th className="th">Reason</th>
                  <th className="th">Granted</th>
                  <th className="th">Expires</th>
                  <th className="th">State</th>
                  <th className="th" />
                </tr>
              </thead>
              <tbody>
                {data.map((g) => {
                  const s = grantState(g as { revoked_at: string | null; expires_at: string | null });
                  return (
                    <tr key={g.id as string}>
                      <td className="td">
                        <Link className="text-accent" href={`/users/${g.user_id as string}`}>
                          {emails.get(g.user_id as string) ?? (g.user_id as string)}
                        </Link>
                      </td>
                      <td className="td">{g.reason as string}</td>
                      <td className="td">{fmtDate(g.granted_at as string)}</td>
                      <td className="td">{g.expires_at ? fmtDate(g.expires_at as string) : "No expiry"}</td>
                      <td className="td">{s}</td>
                      <td className="td">
                        {s === "Active" ? (
                          <ActionButton
                            action={revokePremium.bind(null, g.id)}
                            label="Revoke"
                            variant="danger"
                            confirmText="Revoke this comp access now?"
                          />
                        ) : null}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}
