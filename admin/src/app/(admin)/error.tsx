"use client";

export default function ErrorPage({ reset }: { error: Error; reset: () => void }) {
  return (
    <div role="alert" className="card">
      <p className="font-medium text-danger">Something went wrong loading this page.</p>
      <p className="mt-1 text-sm text-muted">Details are in the server logs.</p>
      <button className="btn-ghost mt-3" onClick={reset}>
        Try again
      </button>
    </div>
  );
}
