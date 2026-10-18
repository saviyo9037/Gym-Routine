import Link from "next/link";

export function PageHeader({ title, subtitle, children }: { title: string; subtitle?: string; children?: React.ReactNode }) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 className="text-2xl font-semibold">{title}</h1>
        {subtitle ? <p className="mt-1 text-sm text-muted">{subtitle}</p> : null}
      </div>
      <div className="flex gap-2">{children}</div>
    </div>
  );
}

export function Empty({ title, hint }: { title: string; hint?: string }) {
  return (
    <div className="card text-center">
      <p className="font-medium">{title}</p>
      {hint ? <p className="mt-1 text-sm text-muted">{hint}</p> : null}
    </div>
  );
}

export function ErrorBox({ message }: { message: string }) {
  return (
    <div role="alert" className="rounded-xl border border-danger/50 bg-danger/10 p-4 text-sm text-danger">
      {message}
    </div>
  );
}

export function Stat({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="card">
      <p className="text-xs uppercase tracking-wide text-muted">{label}</p>
      <p className="mt-2 text-3xl font-semibold text-accent">{value}</p>
      {hint ? <p className="mt-1 text-xs text-muted">{hint}</p> : null}
    </div>
  );
}

export const PAGE_SIZE = 20;

export function Pagination({
  page,
  total,
  basePath,
  params = {},
}: {
  page: number;
  total: number;
  basePath: string;
  params?: Record<string, string | undefined>;
}) {
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const href = (p: number) => {
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) if (v) q.set(k, v);
    q.set("page", String(p));
    return `${basePath}?${q.toString()}`;
  };
  return (
    <div className="mt-4 flex items-center justify-between text-sm text-muted">
      <span>
        {total} result{total === 1 ? "" : "s"} - page {Math.min(page, pages)} of {pages}
      </span>
      <div className="flex gap-2">
        {page > 1 ? (
          <Link className="btn-ghost" href={href(page - 1)}>
            Previous
          </Link>
        ) : null}
        {page < pages ? (
          <Link className="btn-ghost" href={href(page + 1)}>
            Next
          </Link>
        ) : null}
      </div>
    </div>
  );
}

export function fmtDate(v: string | null | undefined): string {
  if (!v) return "-";
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? "-" : d.toISOString().replace("T", " ").slice(0, 16) + " UTC";
}
