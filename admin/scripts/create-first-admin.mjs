// Creates (or promotes) the first OWNER of the admin panel.
//
//   cd admin
//   node scripts/create-first-admin.mjs you@example.com            # generates a password and prints it ONCE
//   node scripts/create-first-admin.mjs you@example.com "MyPass!"  # or use a password you choose
//
// Needs admin/.env.local with your REAL NEXT_PUBLIC_SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY, and the backend migrations already applied (public.admins must exist).
// The password is never written to any file. The service-role key is only read locally by this script.
import { createClient } from "@supabase/supabase-js";
import { randomBytes } from "node:crypto";
import { readFileSync, existsSync } from "node:fs";

function loadEnvLocal() {
  const file = new URL("../.env.local", import.meta.url);
  if (!existsSync(file)) return;
  for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/.exec(line);
    if (m && !line.trim().startsWith("#") && process.env[m[1]] === undefined) {
      process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
    }
  }
}
loadEnvLocal();

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const email = (process.argv[2] ?? "").trim().toLowerCase();
const givenPassword = process.argv[3];

const bad = (v) => !v || /[<>]/.test(v) || /^REPLACE|^your[-_ ]/i.test(v);
if (bad(url) || bad(serviceKey) || !/^https?:\/\//.test(url ?? "")) {
  console.error("admin/.env.local must contain your real NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY first.");
  process.exit(1);
}
if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
  console.error("Usage: node scripts/create-first-admin.mjs <email> [password]");
  process.exit(1);
}
if (givenPassword !== undefined && givenPassword.length < 12) {
  console.error("Password must be at least 12 characters.");
  process.exit(1);
}

const password = givenPassword ?? randomBytes(15).toString("base64url");
const sb = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

let userId;
const created = await sb.auth.admin.createUser({ email, password, email_confirm: true });
let passwordIsNew = true;
if (created.error) {
  // Already registered: look the user up and promote it (password stays as it is).
  const { data, error } = await sb.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (error) {
    console.error("Could not create or find the user:", created.error.message);
    process.exit(1);
  }
  const existing = data.users.find((u) => (u.email ?? "").toLowerCase() === email);
  if (!existing) {
    console.error("Could not create the user:", created.error.message);
    process.exit(1);
  }
  userId = existing.id;
  passwordIsNew = false;
} else {
  userId = created.data.user.id;
}

const { error: adminError } = await sb
  .from("admins")
  .upsert({ user_id: userId, role: "owner", updated_at: new Date().toISOString() }, { onConflict: "user_id" });
if (adminError) {
  console.error("User exists but could not be made an owner (are the migrations applied?):", adminError.message);
  process.exit(1);
}

console.log(`\nOwner ready: ${email}`);
if (passwordIsNew) {
  console.log(`Password (shown once, store it in a password manager): ${password}`);
} else {
  console.log("This email already had an account: its password was NOT changed.");
}
console.log("Next: open the admin panel, sign in, and enrol your authenticator app (TOTP) when asked.");
