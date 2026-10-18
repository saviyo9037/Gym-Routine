import Link from "next/link";
import { notFound } from "next/navigation";
import { pageGuard } from "@/lib/page-guard";
import { ErrorBox, PageHeader, fmtDate } from "@/components/ui";
import { ActionButton } from "@/components/action-button";
import { setUserDisabled, deleteUser } from "@/lib/actions/users";
import { revokePremium } from "@/lib/actions/premium";
import { PremiumGrantForm } from "@/components/config-forms";
import { uuidSchema } from "@/lib/validation";

export default async function UserDetail({ params }: { params: Promise<{ id: string }> }) {
  const { role, db } = await pageGuard(["owner", "support"]);
  const { id } = await params;
  if (!uuidSchema.safeParse(id).success) notFound();

  const [profile, ent, comp, grants] = await Promise.all([
    db.from("profiles").select("*").eq("id", id).maybeSingle(),
    db.from("entitlements").select("*").eq("user_id", id).eq("entitlement_id", "premium").maybeSingle(),
    db.from("entitlements").select("is_active, expires_at").eq("user_id", id).eq("entitlement_id", "premium_comp").maybeSingle(),
    db
      .from("manual_premium_grants")
      .select("id, reason, granted_at, expires_at, revoked_at")
      .eq("user_id", id)
      .order("granted_at", { ascending: false })
      .limit(20),
  ]);
  if (profile.error) return <ErrorBox message="Could not load user." />;
  if (!profile.data) notFound();
  const p = profile.data;
  const e = ent.data;
  const subActive = !!e?.is_active && (!e.expires_at || new Date(e.expires_at) > new Date());
  const c = comp.data;
  const compActive = !!c?.is_active && (!c.expires_at || new Date(c.expires_at as string) > new Date());

  return (
    <>
      <PageHeader title={p.email ?? "(email removed)"} subtitle={p.id}>
        <ActionButton
          action={setUserDisabled.bind(null, id, !p.disabled)}
          label={p.disabled ? "Enable user" : "Disable user"}
          confirmText={p.disabled ? "Re-enable this user?" : "Disable this user? They will be unable to sign in."}
        />
        {role === "owner" ? (
          <ActionButton
            action={deleteUser.bind(null, id)}
            label="Delete user"
            variant="danger"
            confirmText="Permanently delete this user and all their data? This cannot be undone."
            redirectTo="/users"
          />
        ) : null}
      </PageHeader>
      <div className="grid gap-4 md:grid-cols-2">
        <div className="card space-y-1 text-sm">
          <p className="mb-2 font-medium">Profile</p>
          <p>Name: {p.display_name ?? "-"}</p>
          <p>Status: {p.disabled ? "Disabled" : "Active"}</p>
          <p>Signed up: {fmtDate(p.created_at)}</p>
          <p>Last seen: {fmtDate(p.last_seen_at)}</p>
          <p>Last sync: {fmtDate(p.last_sync_at)}</p>
        </div>
        <div className="card space-y-1 text-sm">
          <p className="mb-2 font-medium">Subscription</p>
          {e ? (
            <>
              <p>Premium: {subActive ? <span className="text-ok">Active</span> : "Inactive"}</p>
              <p>Product: {e.product_id ?? "-"}</p>
              <p>Store: {e.store ?? "-"}</p>
              <p>Expires: {fmtDate(e.expires_at)}</p>
              <p>Auto-renew: {e.will_renew ? "Yes" : "No"}</p>
              {e.billing_issue_detected_at ? <p className="text-danger">Billing issue since {fmtDate(e.billing_issue_detected_at)}</p> : null}
            </>
          ) : (
            <p className="text-muted">No subscription records.</p>
          )}
          <p className="pt-2">
            Comp access: {compActive ? <span className="text-ok">Active</span> : "None"}
            {compActive && c?.expires_at ? ` until ${fmtDate(c.expires_at as string)}` : compActive ? " (no expiry)" : ""}
          </p>
        </div>
      </div>
      <div className="mt-4 space-y-3">
        <PremiumGrantForm role={role} presetUserId={id} />
        {grants.data?.length ? (
          <div className="card text-sm">
            <p className="mb-2 font-medium">Comp grants</p>
            {grants.data.map((g) => {
              const live = !g.revoked_at && (!g.expires_at || new Date(g.expires_at as string) > new Date());
              return (
                <div key={g.id as string} className="flex flex-wrap items-center justify-between gap-2 border-t border-line py-2">
                  <span>
                    {g.reason as string} - {fmtDate(g.granted_at as string)} to {g.expires_at ? fmtDate(g.expires_at as string) : "no expiry"} (
                    {g.revoked_at ? "revoked" : live ? "active" : "expired"})
                  </span>
                  {live ? (
                    <ActionButton action={revokePremium.bind(null, g.id)} label="Revoke" variant="danger" confirmText="Revoke this comp access now?" />
                  ) : null}
                </div>
              );
            })}
          </div>
        ) : null}
      </div>
      <div className="card mt-4 text-sm">
        <p className="font-medium">Workout data</p>
        <p className="mt-1 text-muted">Viewing is restricted to owner/support and every view is written to the audit log.</p>
        <Link className="btn-ghost mt-3" href={`/users/${id}/workouts`}>
          View workout data (logged)
        </Link>
      </div>
    </>
  );
}
