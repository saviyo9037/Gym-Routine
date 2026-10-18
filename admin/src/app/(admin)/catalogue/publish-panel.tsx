"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { publishCatalogue } from "@/lib/actions/catalogue";

export function PublishPanel({ currentVersion, pendingCount }: { currentVersion: number | null; pendingCount: number }) {
  const router = useRouter();
  const [notes, setNotes] = useState("");
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  return (
    <div className="card flex flex-wrap items-end gap-3">
      <div className="text-sm">
        <p>
          Live catalogue version: <span className="text-accent">{currentVersion ?? "none published yet"}</span>
        </p>
        <p className="text-muted">{pendingCount} exercise(s) with unpublished changes</p>
      </div>
      <input value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Release notes (optional)" className="input max-w-xs" />
      <button
        className="btn"
        disabled={pending || pendingCount === 0}
        onClick={() =>
          start(async () => {
            const r = await publishCatalogue(notes || undefined);
            setMsg(r.ok ? { ok: true, text: `Published version ${r.data?.version}` } : { ok: false, text: r.error });
            if (r.ok) {
              setNotes("");
              router.refresh();
            }
          })
        }
      >
        {pending ? "Publishing..." : "Publish catalogue"}
      </button>
      {msg ? (
        <span role="status" className={msg.ok ? "text-sm text-ok" : "text-sm text-danger"}>
          {msg.text}
        </span>
      ) : null}
    </div>
  );
}
