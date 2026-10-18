import Link from "next/link";
import { ADMIN_ROLES, type AdminRole } from "@/lib/guard";
import { pageGuard } from "@/lib/page-guard";
import { logout } from "@/lib/actions/auth";

export const dynamic = "force-dynamic";

const NAV: { href: string; label: string; roles: AdminRole[] }[] = [
  { href: "/dashboard", label: "Dashboard", roles: ["owner", "support"] },
  { href: "/users", label: "Users", roles: ["owner", "support"] },
  { href: "/subscriptions", label: "Subscriptions", roles: ["owner", "support"] },
  { href: "/premium", label: "Manual premium", roles: ["owner", "support"] },
  { href: "/paywall", label: "Plans & Paywall", roles: ["owner"] },
  { href: "/app-config", label: "App config", roles: ["owner", "support"] },
  { href: "/announcements", label: "Announcements", roles: ["owner", "support"] },
  { href: "/catalogue", label: "Exercise catalogue", roles: ["owner", "content"] },
  { href: "/media", label: "Media", roles: ["owner", "content"] },
  { href: "/templates", label: "Templates", roles: ["owner", "content"] },
  { href: "/admins", label: "Admins", roles: ["owner"] },
  { href: "/audit", label: "Audit log", roles: ["owner"] },
];

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const ctx = await pageGuard(ADMIN_ROLES);
  return (
    <div className="flex min-h-screen flex-col md:flex-row">
      <aside className="border-b border-line bg-card p-4 md:w-60 md:border-b-0 md:border-r">
        <p className="mb-4 text-lg font-semibold">
          RepTrack <span className="text-accent">Admin</span>
        </p>
        <nav className="flex flex-wrap gap-1 md:flex-col">
          {NAV.filter((n) => n.roles.includes(ctx.role)).map((n) => (
            <Link key={n.href} href={n.href} className="rounded-lg px-3 py-2 text-sm hover:bg-card2 hover:text-accent">
              {n.label}
            </Link>
          ))}
        </nav>
        <div className="mt-6 text-xs text-muted">
          <p className="truncate">{ctx.user.email}</p>
          <p>
            Role: <span className="text-accent">{ctx.role}</span>
          </p>
          <form action={logout} className="mt-2">
            <button className="btn-ghost">Sign out</button>
          </form>
        </div>
      </aside>
      <main className="flex-1 p-4 md:p-8">{children}</main>
    </div>
  );
}
