"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { saveTemplate } from "@/lib/actions/templates";

export interface TemplateDefaults {
  id?: string;
  kind?: string;
  title?: string;
  description?: string | null;
  payload?: unknown;
  status?: string;
}

export function TemplateForm({ defaults }: { defaults: TemplateDefaults }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [fe, setFe] = useState<Record<string, string[]>>({});

  function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const input = Object.fromEntries(new FormData(e.currentTarget).entries());
    setError(null);
    setFe({});
    start(async () => {
      const r = await saveTemplate(defaults.id ?? null, input);
      if (r.ok) {
        router.push("/templates");
        router.refresh();
      } else {
        setError(r.error === "validation" ? "Please fix the highlighted fields." : r.error);
        setFe(r.fieldErrors ?? {});
      }
    });
  }
  const err = (k: string) => (fe[k] ? <p className="mt-1 text-xs text-danger">{fe[k].join(", ")}</p> : null);

  return (
    <form onSubmit={submit} className="card grid gap-4 md:grid-cols-2">
      <div>
        <label className="label" htmlFor="kind">
          Kind
        </label>
        <select id="kind" name="kind" defaultValue={defaults.kind ?? "plan"} className="input">
          <option value="plan">Workout plan</option>
          <option value="routine">Routine</option>
        </select>
      </div>
      <div>
        <label className="label" htmlFor="status">
          Status
        </label>
        <select id="status" name="status" defaultValue={defaults.status ?? "draft"} className="input">
          <option>draft</option>
          <option>published</option>
          <option>archived</option>
        </select>
      </div>
      <div className="md:col-span-2">
        <label className="label" htmlFor="title">
          Title
        </label>
        <input id="title" name="title" required defaultValue={defaults.title ?? ""} className="input" />
        {err("title")}
      </div>
      <div className="md:col-span-2">
        <label className="label" htmlFor="description">
          Description
        </label>
        <textarea id="description" name="description" rows={2} defaultValue={defaults.description ?? ""} className="input" />
      </div>
      <div className="md:col-span-2">
        <label className="label" htmlFor="payload">
          Content (JSON object)
        </label>
        <textarea
          id="payload"
          name="payload"
          rows={10}
          defaultValue={JSON.stringify(defaults.payload ?? {}, null, 2)}
          className="input font-mono"
        />
        {err("payload")}
      </div>
      <div className="md:col-span-2">
        {error ? (
          <p role="alert" className="mb-2 text-sm text-danger">
            {error}
          </p>
        ) : null}
        <button className="btn" disabled={pending}>
          {pending ? "Saving..." : "Save template"}
        </button>
      </div>
    </form>
  );
}
