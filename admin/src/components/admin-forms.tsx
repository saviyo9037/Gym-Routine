"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { addAdmin, changeAdminRole } from "@/lib/actions/admins";

const ROLES = ["owner", "support", "content"];

export function AddAdminForm() {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  return (
    <form
      className="card flex flex-wrap items-end gap-3"
      onSubmit={(e) => {
        e.preventDefault();
        const form = e.currentTarget;
        const input = Object.fromEntries(new FormData(form).entries());
        setError(null);
        start(async () => {
          const r = await addAdmin(input);
          if (r.ok) {
            form.reset();
            router.refresh();
          } else setError(r.error === "validation" ? "Enter a valid email and role" : r.error);
        });
      }}
    >
      <div>
        <label className="label" htmlFor="email">
          Existing user email
        </label>
        <input id="email" name="email" type="email" required className="input" />
      </div>
      <div>
        <label className="label" htmlFor="role">
          Role
        </label>
        <select id="role" name="role" className="input" defaultValue="support">
          {ROLES.map((r) => (
            <option key={r}>{r}</option>
          ))}
        </select>
      </div>
      <button className="btn" disabled={pending}>
        {pending ? "Saving..." : "Grant access"}
      </button>
      {error ? (
        <p role="alert" className="w-full text-sm text-danger">
          {error}
        </p>
      ) : null}
    </form>
  );
}

export function RoleSelect({ userId, role }: { userId: string; role: string }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  return (
    <span className="inline-flex flex-col">
      <select
        className="input w-32"
        defaultValue={role}
        disabled={pending}
        onChange={(e) =>
          start(async () => {
            const r = await changeAdminRole(userId, e.target.value);
            if (!r.ok) setError(r.error);
            router.refresh();
          })
        }
      >
        {ROLES.map((r) => (
          <option key={r}>{r}</option>
        ))}
      </select>
      {error ? <span className="text-xs text-danger">{error}</span> : null}
    </span>
  );
}
