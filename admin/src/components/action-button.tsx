"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import type { ActionResult } from "@/lib/action-types";

export function ActionButton({
  action,
  label,
  confirmText,
  variant = "ghost",
  redirectTo,
}: {
  action: () => Promise<ActionResult<unknown>>;
  label: string;
  confirmText?: string;
  variant?: "ghost" | "danger" | "primary";
  redirectTo?: string;
}) {
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();
  const cls = variant === "danger" ? "btn-danger" : variant === "primary" ? "btn" : "btn-ghost";
  return (
    <span className="inline-flex flex-col gap-1">
      <button
        type="button"
        className={cls}
        disabled={pending}
        onClick={() => {
          if (confirmText && !window.confirm(confirmText)) return;
          setError(null);
          start(async () => {
            const r = await action();
            if (!r.ok) setError(r.error === "validation" ? "Invalid input" : r.error);
            else if (redirectTo) router.push(redirectTo);
            else router.refresh();
          });
        }}
      >
        {pending ? "Working..." : label}
      </button>
      {error ? (
        <span role="alert" className="text-xs text-danger">
          {error}
        </span>
      ) : null}
    </span>
  );
}
