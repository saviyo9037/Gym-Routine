"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { createExercise, updateExercise } from "@/lib/actions/catalogue";
import { DIFFICULTIES, MUSCLE_GROUPS, STATUSES } from "@/lib/validation";

export interface ExerciseDefaults {
  id?: number;
  name?: string;
  primary_muscle_group?: string;
  secondary_muscles?: string | null;
  target?: string | null;
  description?: string | null;
  starting_position?: string | null;
  instructions?: string | null;
  breathing_guidance?: string | null;
  beginner_modification?: string | null;
  equipment?: string | null;
  difficulty?: string;
  suggested_sets_reps?: string | null;
  common_mistakes?: string | null;
  default_sets?: number;
  default_reps?: number;
  default_weight_kg?: number;
  rest_seconds?: number;
  is_compound?: boolean;
  is_recommended?: boolean;
  status?: string;
}

const EQUIPMENT = ["Bodyweight", "Dumbbells", "Barbell", "Cable", "Machine", "Kettlebell", "Bands", "Plate", "Specialty", "None"];

export function ExerciseForm({ defaults, mode }: { defaults: ExerciseDefaults; mode: "create" | "update" }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string[]>>({});

  function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const input: Record<string, unknown> = Object.fromEntries(fd.entries());
    input.is_compound = fd.get("is_compound") === "on";
    input.is_recommended = fd.get("is_recommended") === "on";
    if (mode === "update") input.id = defaults.id;
    setError(null);
    setFieldErrors({});
    start(async () => {
      const r = await (mode === "create" ? createExercise(input) : updateExercise(input));
      if (r.ok) {
        router.push(`/catalogue/${r.data?.id ?? ""}`);
        router.refresh();
      } else {
        setError(r.error === "validation" ? "Please fix the highlighted fields." : r.error);
        setFieldErrors(r.fieldErrors ?? {});
      }
    });
  }

  const err = (k: string) => (fieldErrors[k] ? <p className="mt-1 text-xs text-danger">{fieldErrors[k].join(", ")}</p> : null);
  const text = (k: keyof ExerciseDefaults, label: string, opts: { area?: boolean; required?: boolean } = {}) => (
    <div className={opts.area ? "md:col-span-2" : ""}>
      <label className="label" htmlFor={k}>
        {label}
      </label>
      {opts.area ? (
        <textarea id={k} name={k} rows={3} defaultValue={(defaults[k] as string) ?? ""} className="input" />
      ) : (
        <input id={k} name={k} defaultValue={(defaults[k] as string) ?? ""} required={opts.required} className="input" />
      )}
      {err(k)}
    </div>
  );
  const num = (k: keyof ExerciseDefaults, label: string, dflt: number, step = "1") => (
    <div>
      <label className="label" htmlFor={k}>
        {label}
      </label>
      <input id={k} name={k} type="number" step={step} min={0} defaultValue={(defaults[k] as number) ?? dflt} className="input" required />
      {err(k)}
    </div>
  );

  return (
    <form onSubmit={submit} className="card grid gap-4 md:grid-cols-2">
      <div>
        <label className="label" htmlFor="id">
          Exercise id (stable, integer)
        </label>
        <input id="id" name="id" type="number" min={1} defaultValue={defaults.id ?? ""} readOnly={mode === "update"} required className="input" />
        {err("id")}
      </div>
      {text("name", "Name", { required: true })}
      <div>
        <label className="label" htmlFor="primary_muscle_group">
          Primary muscle group
        </label>
        <select id="primary_muscle_group" name="primary_muscle_group" defaultValue={defaults.primary_muscle_group ?? ""} required className="input">
          <option value="" disabled>
            Select...
          </option>
          {MUSCLE_GROUPS.map((m) => (
            <option key={m}>{m}</option>
          ))}
        </select>
        {err("primary_muscle_group")}
      </div>
      <div>
        <label className="label" htmlFor="equipment">
          Equipment
        </label>
        <input id="equipment" name="equipment" list="equipment-list" defaultValue={defaults.equipment ?? ""} required className="input" />
        <datalist id="equipment-list">
          {EQUIPMENT.map((x) => (
            <option key={x} value={x} />
          ))}
        </datalist>
        {err("equipment")}
      </div>
      <div>
        <label className="label" htmlFor="difficulty">
          Difficulty
        </label>
        <select id="difficulty" name="difficulty" defaultValue={defaults.difficulty ?? "Intermediate"} className="input">
          {DIFFICULTIES.map((d) => (
            <option key={d}>{d}</option>
          ))}
        </select>
        {err("difficulty")}
      </div>
      <div>
        <label className="label" htmlFor="status">
          Status
        </label>
        <select id="status" name="status" defaultValue={defaults.status ?? "draft"} className="input">
          {STATUSES.map((d) => (
            <option key={d}>{d}</option>
          ))}
        </select>
      </div>
      {text("secondary_muscles", "Secondary muscles")}
      {text("target", "Target")}
      {text("suggested_sets_reps", "Suggested sets/reps")}
      {num("default_sets", "Default sets", 3)}
      {num("default_reps", "Default reps", 10)}
      {num("default_weight_kg", "Default weight (kg)", 15, "0.5")}
      {num("rest_seconds", "Rest (seconds)", 90)}
      {text("description", "Description", { area: true })}
      {text("starting_position", "Starting position", { area: true })}
      {text("instructions", "Instructions", { area: true })}
      {text("breathing_guidance", "Breathing guidance", { area: true })}
      {text("beginner_modification", "Beginner modification", { area: true })}
      {text("common_mistakes", "Common mistakes", { area: true })}
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" name="is_compound" defaultChecked={defaults.is_compound ?? false} /> Compound lift
      </label>
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" name="is_recommended" defaultChecked={defaults.is_recommended ?? true} /> Recommended
      </label>
      <div className="md:col-span-2">
        {error ? (
          <p role="alert" className="mb-2 text-sm text-danger">
            {error}
          </p>
        ) : null}
        <button className="btn" disabled={pending}>
          {pending ? "Saving..." : mode === "create" ? "Create exercise" : "Save changes"}
        </button>
      </div>
    </form>
  );
}
