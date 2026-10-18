"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import type { ActionResult } from "@/lib/action-types";
import { saveAccessModel, saveOperationalConfig, savePaywallCopy } from "@/lib/actions/app-config";
import { saveAnnouncement } from "@/lib/actions/announcements";
import { grantPremium } from "@/lib/actions/premium";

type Submit = (input: Record<string, FormDataEntryValue>) => Promise<ActionResult<unknown>>;

function useSubmit(submit: Submit, resetOnOk = false) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const onSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const form = e.currentTarget;
    const input = Object.fromEntries(new FormData(form).entries());
    // Unchecked checkboxes are absent from FormData: make them explicit.
    for (const el of Array.from(form.elements)) {
      if (el instanceof HTMLInputElement && el.type === "checkbox") input[el.name] = el.checked ? "true" : "";
    }
    setError(null);
    setSaved(false);
    start(async () => {
      const r = await submit(input);
      if (r.ok) {
        setSaved(true);
        if (resetOnOk) form.reset();
        router.refresh();
      } else if (r.error === "validation") {
        const first = r.fieldErrors ? Object.values(r.fieldErrors)[0]?.[0] : null;
        setError(first ?? "Please check the fields");
      } else setError(r.error);
    });
  };
  return { pending, error, saved, onSubmit };
}

function Status({ error, saved }: { error: string | null; saved: boolean }) {
  return (
    <>
      {error ? (
        <p role="alert" className="w-full text-sm text-danger">
          {error}
        </p>
      ) : null}
      {saved ? (
        <p role="status" className="w-full text-sm text-ok">
          Saved.
        </p>
      ) : null}
    </>
  );
}

export interface PaywallCopyValues {
  title: string;
  subtitle: string;
  benefits: string;
  badgeMonthly: string;
  badgeYearly: string;
  promo: string;
}

export function PaywallCopyForm({ initial }: { initial: PaywallCopyValues }) {
  const { pending, error, saved, onSubmit } = useSubmit(savePaywallCopy);
  return (
    <form className="card space-y-3" onSubmit={onSubmit}>
      <p className="font-medium">Paywall copy</p>
      <p className="text-xs text-muted">
        Leave a field empty to use the app&apos;s built-in text. Plain text only. Prices and trial length are NOT set here: they come
        from Google Play / RevenueCat.
      </p>
      <div>
        <label className="label" htmlFor="paywall_title">Title (max 80)</label>
        <input id="paywall_title" name="paywall_title" className="input" maxLength={80} defaultValue={initial.title} />
      </div>
      <div>
        <label className="label" htmlFor="paywall_subtitle">Subtitle (max 200)</label>
        <input id="paywall_subtitle" name="paywall_subtitle" className="input" maxLength={200} defaultValue={initial.subtitle} />
      </div>
      <div>
        <label className="label" htmlFor="paywall_benefits">Benefit bullets (one per line, max 8 lines of 120)</label>
        <textarea id="paywall_benefits" name="paywall_benefits" className="input" rows={5} defaultValue={initial.benefits} />
      </div>
      <div className="grid gap-3 md:grid-cols-2">
        <div>
          <label className="label" htmlFor="badge_monthly">Monthly badge (max 24)</label>
          <input id="badge_monthly" name="badge_monthly" className="input" maxLength={24} defaultValue={initial.badgeMonthly} />
        </div>
        <div>
          <label className="label" htmlFor="badge_yearly">Yearly badge, e.g. Best value (max 24)</label>
          <input id="badge_yearly" name="badge_yearly" className="input" maxLength={24} defaultValue={initial.badgeYearly} />
        </div>
      </div>
      <div>
        <label className="label" htmlFor="promo_text">Promo text (max 200)</label>
        <input id="promo_text" name="promo_text" className="input" maxLength={200} defaultValue={initial.promo} />
      </div>
      <div className="flex flex-wrap items-center gap-3">
        <button className="btn" disabled={pending}>{pending ? "Saving..." : "Save paywall copy"}</button>
        <Status error={error} saved={saved} />
      </div>
    </form>
  );
}

export function OperationalConfigForm({
  initial,
}: {
  initial: { maintenance: boolean; message: string; minVersion: string };
}) {
  const { pending, error, saved, onSubmit } = useSubmit(saveOperationalConfig);
  return (
    <form className="card space-y-3" onSubmit={onSubmit}>
      <p className="font-medium">Maintenance and minimum version</p>
      <label className="flex items-center gap-2 text-sm">
        <input name="maintenance_mode" type="checkbox" defaultChecked={initial.maintenance} />
        Maintenance mode (the app shows the message below; scheduled alarms still ring, local data is untouched)
      </label>
      <div>
        <label className="label" htmlFor="maintenance_message">Maintenance message (max 300)</label>
        <textarea id="maintenance_message" name="maintenance_message" className="input" rows={3} maxLength={300} defaultValue={initial.message} />
      </div>
      <div>
        <label className="label" htmlFor="min_app_version">Minimum app version (x.y.z, empty = none)</label>
        <input id="min_app_version" name="min_app_version" className="input" placeholder="1.2.0" defaultValue={initial.minVersion} />
      </div>
      <div className="flex flex-wrap items-center gap-3">
        <button className="btn" disabled={pending}>{pending ? "Saving..." : "Save"}</button>
        <Status error={error} saved={saved} />
      </div>
    </form>
  );
}

export function AccessModelForm({ current }: { current: string | null }) {
  const { pending, error, saved, onSubmit } = useSubmit(saveAccessModel);
  return (
    <form className="card space-y-3" onSubmit={onSubmit}>
      <p className="font-medium">Access model override (owner only)</p>
      <p className="text-xs text-muted">
        Overrides the model built into the app. It can never open a release build that has no RevenueCat key, and an unknown value makes
        the app require a subscription.
      </p>
      <select name="access_model_override" className="input" defaultValue={current ?? "default"}>
        <option value="default">No override (use the build&apos;s value)</option>
        <option value="subscription_required">subscription_required</option>
        <option value="freemium">freemium</option>
      </select>
      <div className="flex flex-wrap items-center gap-3">
        <button className="btn" disabled={pending}>{pending ? "Saving..." : "Save access model"}</button>
        <Status error={error} saved={saved} />
      </div>
    </form>
  );
}

export function AnnouncementForm({
  announcement,
}: {
  announcement?: { id: string; title: string; body: string; level: string; starts: string; ends: string; active: boolean };
}) {
  const { pending, error, saved, onSubmit } = useSubmit(
    (input) => saveAnnouncement(announcement?.id ?? null, input),
    !announcement,
  );
  return (
    <form className="card space-y-3" onSubmit={onSubmit}>
      <p className="font-medium">{announcement ? "Edit announcement" : "New announcement"}</p>
      <div>
        <label className="label" htmlFor={`t-${announcement?.id ?? "new"}`}>Title (max 80)</label>
        <input id={`t-${announcement?.id ?? "new"}`} name="title" className="input" maxLength={80} required defaultValue={announcement?.title} />
      </div>
      <div>
        <label className="label" htmlFor={`b-${announcement?.id ?? "new"}`}>Message (max 500, plain text)</label>
        <textarea id={`b-${announcement?.id ?? "new"}`} name="body" className="input" rows={3} maxLength={500} required defaultValue={announcement?.body} />
      </div>
      <div className="grid gap-3 md:grid-cols-3">
        <div>
          <label className="label">Level</label>
          <select name="level" className="input" defaultValue={announcement?.level ?? "info"}>
            <option value="info">info</option>
            <option value="warning">warning</option>
          </select>
        </div>
        <div>
          <label className="label">Starts (UTC, empty = now)</label>
          <input name="starts_at" type="datetime-local" className="input" defaultValue={announcement?.starts} />
        </div>
        <div>
          <label className="label">Ends (UTC, empty = no end)</label>
          <input name="ends_at" type="datetime-local" className="input" defaultValue={announcement?.ends} />
        </div>
      </div>
      <label className="flex items-center gap-2 text-sm">
        <input name="active" type="checkbox" defaultChecked={announcement?.active ?? true} /> Active
      </label>
      <div className="flex flex-wrap items-center gap-3">
        <button className="btn" disabled={pending}>{pending ? "Saving..." : announcement ? "Save changes" : "Create announcement"}</button>
        <Status error={error} saved={saved} />
      </div>
    </form>
  );
}

export function PremiumGrantForm({ role, presetUserId }: { role: string; presetUserId?: string }) {
  const { pending, error, saved, onSubmit } = useSubmit(grantPremium, true);
  return (
    <form className="card space-y-3" onSubmit={onSubmit}>
      <p className="font-medium">Grant comp access</p>
      <p className="text-xs text-muted">
        Free access for support/goodwill. A reason is required and is written to the audit log. Support can grant up to 90 days; open-ended
        access is owner-only.
      </p>
      {presetUserId ? (
        <input type="hidden" name="user_id" value={presetUserId} />
      ) : (
        <div>
          <label className="label" htmlFor="grant-email">User email (must already have an account)</label>
          <input id="grant-email" name="email" type="email" required className="input" />
        </div>
      )}
      <div>
        <label className="label" htmlFor="grant-reason">Reason (3-300 chars)</label>
        <input id="grant-reason" name="reason" required minLength={3} maxLength={300} className="input" />
      </div>
      <div className="grid gap-3 md:grid-cols-2">
        <div>
          <label className="label" htmlFor="grant-expiry">Expires (UTC)</label>
          <input id="grant-expiry" name="expires_at" type="datetime-local" className="input" />
        </div>
        {role === "owner" ? (
          <label className="flex items-center gap-2 pt-6 text-sm">
            <input name="no_expiry" type="checkbox" /> No expiry (owner only)
          </label>
        ) : null}
      </div>
      <div className="flex flex-wrap items-center gap-3">
        <button className="btn" disabled={pending}>{pending ? "Granting..." : "Grant access"}</button>
        <Status error={error} saved={saved} />
      </div>
    </form>
  );
}
