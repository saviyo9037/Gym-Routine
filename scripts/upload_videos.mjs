// Uploads the encoded exercise videos (media_src/encoded/*.mp4) to the PRIVATE Supabase bucket
// "exercise-videos" at the storage_path listed in media_manifest.json (videos/<exercise_id>.mp4).
//
//   node scripts/upload_videos.mjs --dry-run                       # show what would happen, no network
//   node scripts/upload_videos.mjs                                 # upload VERIFIED videos only
//   node scripts/upload_videos.mjs --include-unverified --rows     # test uploads (rows stay DRAFT + unverified)
//   node scripts/upload_videos.mjs --only 12,15 --force            # re-upload specific exercises
//
// Safety rules:
//  * Only manifest entries with status VERIFIED are uploaded unless --include-unverified is given
//    (never publish footage whose licence is unproven).
//  * Objects that already exist with the same size are skipped (use --force to replace).
//  * --rows creates a DRAFT exercise_media row (license_verified=false) if none points at the path. It never
//    verifies or publishes: a human does that in the admin panel after checking the licence/evidence.
//  * The service-role key is read from the environment or admin/.env.local, used only here, never written anywhere.
import { createRequire } from "node:module";
import { readFileSync, existsSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const BUCKET = "exercise-videos";
const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const only = (() => {
  const i = args.indexOf("--only");
  return i >= 0 ? new Set(args[i + 1].split(",").map((x) => Number(x.trim()))) : null;
})();
const dryRun = flag("--dry-run");

function loadEnvLocal() {
  const file = join(root, "admin", ".env.local");
  if (!existsSync(file)) return;
  for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/.exec(line);
    if (m && !line.trim().startsWith("#") && process.env[m[1]] === undefined) {
      process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
    }
  }
}

const manifest = JSON.parse(readFileSync(join(root, "media_manifest.json"), "utf8"));
const wanted = manifest.videos.filter((e) => e.filename && e.storage_path && e.status !== "NO_VIDEO")
  .filter((e) => !only || only.has(e.exercise_id));

const plan = [];
for (const e of wanted) {
  const local = join(root, "media_src", "encoded", e.filename);
  if (e.status !== "VERIFIED" && !flag("--include-unverified")) {
    plan.push({ e, action: "skip", why: `status ${e.status} (not VERIFIED; use --include-unverified for test uploads only)` });
  } else if (!existsSync(local)) {
    plan.push({ e, action: "skip", why: `local file missing: ${local}` });
  } else {
    plan.push({ e, local, action: "upload", size: statSync(local).size });
  }
}

if (dryRun) {
  for (const p of plan) console.log(`${p.action.toUpperCase().padEnd(6)} #${p.e.exercise_id} ${p.e.storage_path}${p.why ? "  - " + p.why : ""}`);
  const n = plan.filter((p) => p.action === "upload").length;
  console.log(`\n${n} would be uploaded, ${plan.length - n} skipped (dry run, nothing sent).`);
  process.exit(0);
}

loadEnvLocal();
const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const bad = (v) => !v || /[<>]/.test(v) || /^REPLACE|^your[-_ ]/i.test(v);
if (bad(url) || bad(key) || !/^https?:\/\//.test(url ?? "")) {
  console.error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (environment or admin/.env.local) to your REAL values first.");
  process.exit(1);
}
const require = createRequire(join(root, "admin", "package.json"));
const { createClient } = require("@supabase/supabase-js");
const sb = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

let uploaded = 0, skipped = 0, failed = 0;
for (const p of plan) {
  const tag = `#${p.e.exercise_id} ${p.e.storage_path}`;
  if (p.action === "skip") { console.log(`SKIP   ${tag} - ${p.why}`); skipped++; continue; }

  const dir = p.e.storage_path.split("/").slice(0, -1).join("/");
  const name = p.e.storage_path.split("/").pop();
  const { data: listing, error: listErr } = await sb.storage.from(BUCKET).list(dir, { search: name });
  if (listErr) { console.error(`FAIL   ${tag} - cannot list bucket: ${listErr.message}`); failed++; continue; }
  const existing = (listing ?? []).find((o) => o.name === name);
  if (existing && Number(existing.metadata?.size) === p.size && !flag("--force")) {
    console.log(`SAME   ${tag} (already uploaded, same size)`);
    skipped++;
  } else {
    const bytes = readFileSync(p.local);
    const { error } = await sb.storage.from(BUCKET).upload(p.e.storage_path, bytes, {
      contentType: "video/mp4",
      cacheControl: "3600",
      upsert: Boolean(existing),
    });
    if (error) { console.error(`FAIL   ${tag} - ${error.message}`); failed++; continue; }
    const sha = createHash("sha256").update(bytes).digest("hex").slice(0, 12);
    console.log(`OK     ${tag} (${p.size} bytes, sha256 ${sha}...)`);
    uploaded++;
  }

  if (flag("--rows")) {
    const { data: rows, error: rowErr } = await sb.from("exercise_media").select("id").eq("storage_path", p.e.storage_path).limit(1);
    if (rowErr) { console.error(`FAIL   ${tag} - row lookup: ${rowErr.message}`); failed++; continue; }
    if (!rows?.length) {
      const { error } = await sb.from("exercise_media").insert({
        exercise_id: p.e.exercise_id,
        media_type: "video",
        mime_type: "video/mp4",
        storage_path: p.e.storage_path,
        size_bytes: p.size,
        duration_seconds: Math.round(p.e.duration_s ?? 0) || null,
        license: String(p.e.license ?? "UNVERIFIED").slice(0, 200),
        attribution: "UNVERIFIED - see media_manifest.json",
        license_verified: false,
        status: "draft",
      });
      if (error) console.error(`ROW    ${tag} - not created (is the exercise seeded in exercises_catalog?): ${error.message}`);
      else console.log(`ROW    ${tag} draft row created (verify the licence and publish in the admin panel)`);
    }
  }
}
console.log(`\nuploaded ${uploaded}, skipped ${skipped}, failed ${failed}`);
process.exit(failed ? 1 : 0);
