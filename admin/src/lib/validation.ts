import { z } from "zod";

/** The 15 primary muscle-group categories used by the app (same rule as the app/DB check). */
export const MUSCLE_GROUPS = [
  "Chest",
  "Back",
  "Lats",
  "Upper Back and Traps",
  "Shoulders",
  "Biceps",
  "Triceps",
  "Forearms",
  "Quadriceps",
  "Hamstrings",
  "Glutes",
  "Calves",
  "Abs and Core",
  "Full Body",
  "Cardio",
] as const;
export const DIFFICULTIES = ["Beginner", "Intermediate", "Advanced"] as const;
export const STATUSES = ["draft", "published", "archived"] as const;

const text = (max: number) => z.string().trim().max(max);
const optText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .transform((v) => (v === "" ? null : v))
    .nullish()
    .transform((v) => v ?? null);

export const exerciseSchema = z.object({
  id: z.coerce.number().int().positive(),
  name: text(120).min(1, "Name is required"),
  primary_muscle_group: z.enum(MUSCLE_GROUPS, { error: "Choose one of the 15 muscle groups" }),
  secondary_muscles: optText(200),
  target: optText(200),
  description: optText(2000),
  starting_position: optText(2000),
  instructions: optText(4000),
  breathing_guidance: optText(1000),
  beginner_modification: optText(1000),
  equipment: text(60).min(1, "Equipment is required"),
  difficulty: z.enum(DIFFICULTIES, { error: "Choose a difficulty" }),
  suggested_sets_reps: optText(100),
  common_mistakes: optText(2000),
  default_sets: z.coerce.number().int().min(1).max(20),
  default_reps: z.coerce.number().int().min(1).max(200),
  default_weight_kg: z.coerce.number().min(0).max(1000),
  rest_seconds: z.coerce.number().int().min(0).max(1800),
  is_compound: z.coerce.boolean().default(false),
  is_recommended: z.coerce.boolean().default(true),
  status: z.enum(STATUSES).default("draft"),
});
export type ExerciseInput = z.infer<typeof exerciseSchema>;

export const MEDIA_LIMITS = {
  video: { mimes: ["video/mp4"], exts: ["mp4"], maxBytes: 50 * 1024 * 1024 },
  image: { mimes: ["image/jpeg", "image/png", "image/webp"], exts: ["jpg", "jpeg", "png", "webp"], maxBytes: 5 * 1024 * 1024 },
} as const;

export const mediaMetaSchema = z.object({
  exercise_id: z.coerce.number().int().positive(),
  // Licence/provenance must be stated by a human; there is deliberately no default.
  license: text(200).min(1, "Licence is required"),
  attribution: text(300).min(1, "Attribution/source credit is required"),
  source_url: optText(500).refine((v) => v === null || /^https?:\/\//i.test(v), "Source URL must be http(s)"),
});

/** Validates file name/mime/size (not content; see sniffMedia). Returns media kind + extension. */
export function validateMediaFile(file: { name: string; type: string; size: number }):
  | { ok: true; kind: "video" | "image"; ext: string }
  | { ok: false; error: string } {
  const ext = file.name.split(".").pop()?.toLowerCase() ?? "";
  for (const kind of ["video", "image"] as const) {
    const lim = MEDIA_LIMITS[kind];
    if ((lim.mimes as readonly string[]).includes(file.type) && (lim.exts as readonly string[]).includes(ext)) {
      if (file.size <= 0) return { ok: false, error: "File is empty" };
      if (file.size > lim.maxBytes) return { ok: false, error: `${kind} exceeds ${lim.maxBytes / 1024 / 1024} MB limit` };
      return { ok: true, kind, ext: ext === "jpeg" ? "jpg" : ext };
    }
  }
  return { ok: false, error: "Unsupported file type (allowed: mp4, jpg, png, webp)" };
}

/** Checks magic bytes so a renamed file cannot masquerade as another type. */
export function sniffMedia(bytes: Uint8Array, mime: string): boolean {
  const eq = (off: number, sig: number[]) => sig.every((b, i) => bytes[off + i] === b);
  switch (mime) {
    case "image/png":
      return eq(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    case "image/jpeg":
      return eq(0, [0xff, 0xd8, 0xff]);
    case "image/webp":
      return eq(0, [0x52, 0x49, 0x46, 0x46]) && eq(8, [0x57, 0x45, 0x42, 0x50]);
    case "video/mp4":
      return eq(4, [0x66, 0x74, 0x79, 0x70]); // "ftyp"
    default:
      return false;
  }
}

export const templateSchema = z.object({
  kind: z.enum(["plan", "routine"]),
  title: text(120).min(1, "Title is required"),
  description: optText(1000),
  payload: z
    .string()
    .trim()
    .default("{}")
    .transform((s, ctx) => {
      try {
        const v = JSON.parse(s === "" ? "{}" : s);
        if (typeof v !== "object" || v === null || Array.isArray(v)) throw new Error("not an object");
        return v as Record<string, unknown>;
      } catch {
        ctx.addIssue({ code: "custom", message: "Payload must be a JSON object" });
        return z.NEVER;
      }
    }),
  status: z.enum(STATUSES).default("draft"),
});

export const adminRoleSchema = z.object({
  email: z.string().trim().toLowerCase().pipe(z.email()),
  role: z.enum(["owner", "support", "content"]),
});

export const uuidSchema = z.uuid();
export const pageSchema = z.coerce.number().int().min(1).max(100000).catch(1);

export class ValidationError extends Error {
  constructor(public readonly fieldErrors: Record<string, string[]>) {
    super("validation failed");
    this.name = "ValidationError";
  }
}

export function parseOrThrow<S extends z.ZodType>(schema: S, input: unknown): z.output<S> {
  const r = schema.safeParse(input);
  if (!r.success) {
    const fe: Record<string, string[]> = {};
    for (const issue of r.error.issues) {
      const k = issue.path.join(".") || "_";
      (fe[k] ??= []).push(issue.message);
    }
    throw new ValidationError(fe);
  }
  return r.data;
}

/** Escapes a user search term for use inside a PostgREST `or`/`ilike` filter. */
export function escapeSearch(q: string): string {
  return q.replace(/[\\%_,()*"']/g, " ").trim().slice(0, 80);
}


// ---------------------------------------------------------------------------------------------
// App config, announcements, manual premium (migration 0009). The same limits are enforced again by
// CHECK constraints in the database and by the Flutter parser, so a bad value is stopped three times.
// ---------------------------------------------------------------------------------------------

/** Plain text only: angle brackets are rejected so no HTML/markup can reach the app. */
const NO_MARKUP = /[<>]/;
const plain = (max: number) =>
  z.string().trim().max(max).refine((v) => !NO_MARKUP.test(v), "Markup characters (< >) are not allowed");
/** Empty string -> null (meaning "use the app's built-in default"). */
const optPlain = (max: number) =>
  plain(max)
    .transform((v) => (v === "" ? null : v))
    .nullish()
    .transform((v) => v ?? null);

export const SEMVER_RE = /^\d{1,4}\.\d{1,4}\.\d{1,4}(\+\d{1,6})?$/;
export const ACCESS_MODELS = ["subscription_required", "freemium"] as const;
export const ANNOUNCEMENT_LEVELS = ["info", "warning"] as const;

const benefitList = z
  .union([z.string(), z.array(z.string())])
  .transform((v) => (Array.isArray(v) ? v : v.split(/\r?\n/)).map((x) => x.trim()).filter((x) => x !== ""))
  .pipe(z.array(plain(120).min(1)).max(8, "At most 8 benefit lines"));

export const paywallCopySchema = z.object({
  paywall_title: optPlain(80),
  paywall_subtitle: optPlain(200),
  paywall_benefits: benefitList.default([]),
  badge_monthly: optPlain(24),
  badge_yearly: optPlain(24),
  promo_text: optPlain(200),
});
export type PaywallCopyInput = z.infer<typeof paywallCopySchema>;

export const operationalConfigSchema = z.object({
  maintenance_mode: z.coerce.boolean().default(false),
  maintenance_message: optPlain(300),
  min_app_version: z
    .string()
    .trim()
    .transform((v) => (v === "" ? null : v))
    .nullish()
    .transform((v) => v ?? null)
    .refine((v) => v === null || SEMVER_RE.test(v), "Use a version like 1.2.3"),
});
export type OperationalConfigInput = z.infer<typeof operationalConfigSchema>;

export const accessModelSchema = z.object({
  access_model_override: z
    .string()
    .trim()
    .transform((v) => (v === "" || v === "default" ? null : v))
    .nullish()
    .transform((v) => v ?? null)
    .refine((v) => v === null || (ACCESS_MODELS as readonly string[]).includes(v), "Unknown access model"),
});

const optDate = z.preprocess(
  (v) => (v === undefined ? null : v),
  z.union([z.string().trim(), z.date(), z.null()]).transform((v, ctx) => {
    if (v === null || v === "") return null;
    const d = v instanceof Date ? v : new Date(v);
    if (Number.isNaN(d.getTime())) {
      ctx.addIssue({ code: "custom", message: "Invalid date" });
      return z.NEVER;
    }
    return d;
  }),
);

export const announcementSchema = z
  .object({
    title: plain(80).min(1, "Title is required"),
    body: plain(500).min(1, "Message is required"),
    level: z.enum(ANNOUNCEMENT_LEVELS, { error: "Choose info or warning" }),
    starts_at: optDate,
    ends_at: optDate,
    active: z.coerce.boolean().default(true),
  })
  .superRefine((v, ctx) => {
    if (v.starts_at && v.ends_at && v.ends_at <= v.starts_at) {
      ctx.addIssue({ code: "custom", path: ["ends_at"], message: "End must be after the start" });
    }
  });
export type AnnouncementInput = z.infer<typeof announcementSchema>;

/** Limits for comp access. Support staff get short grants; open-ended access is owner-only. */
export const COMP_MAX_DAYS = { owner: 3650, support: 90 } as const;

export const premiumGrantSchema = z
  .object({
    user_id: z.uuid().optional(),
    email: z
      .string()
      .trim()
      .toLowerCase()
      .pipe(z.email())
      .optional(),
    reason: plain(300).min(3, "Give a reason (at least 3 characters)"),
    expires_at: optDate,
    no_expiry: z.coerce.boolean().default(false),
  })
  .superRefine((v, ctx) => {
    if (!v.user_id && !v.email) ctx.addIssue({ code: "custom", path: ["email"], message: "Enter the user's email or id" });
    if (v.user_id && v.email) ctx.addIssue({ code: "custom", path: ["email"], message: "Use either the email or the id, not both" });
    if (v.no_expiry && v.expires_at) ctx.addIssue({ code: "custom", path: ["expires_at"], message: "Choose an expiry date OR no expiry" });
    if (!v.no_expiry && !v.expires_at) ctx.addIssue({ code: "custom", path: ["expires_at"], message: "An expiry date is required" });
  });
export type PremiumGrantInput = z.infer<typeof premiumGrantSchema>;

