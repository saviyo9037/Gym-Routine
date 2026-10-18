import { logout } from "@/lib/actions/auth";

export default function Forbidden() {
  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center px-4 text-center">
      <h1 className="text-2xl font-semibold">Not allowed</h1>
      <p className="mt-2 text-sm text-muted">Your role does not have access to this page.</p>
      <div className="mt-6 flex justify-center gap-3">
        <a className="btn-ghost" href="/dashboard">
          Dashboard
        </a>
        <form action={logout}>
          <button className="btn-ghost">Sign out</button>
        </form>
      </div>
    </main>
  );
}
