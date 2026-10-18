// Applies backend/supabase/migrations to an in-process PGlite (real Postgres, WASM) with
// test-only Supabase stubs + a pgTAP subset, then runs backend/supabase/tests/*.test.sql.
import { PGlite } from '@electric-sql/pglite';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const migDir = join(here, '..', 'supabase', 'migrations');
const testDir = join(here, '..', 'supabase', 'tests');

const db = new PGlite();
const run = async (label, file) => {
  try {
    await db.exec(readFileSync(file, 'utf8'));
    console.log(`applied ${label}`);
  } catch (e) {
    console.error(`FAILED ${label}: ${e.message}`);
    process.exit(2);
  }
};

await run('stubs', join(here, 'sql', '00_supabase_stubs.sql'));
for (const f of readdirSync(migDir).filter((f) => f.endsWith('.sql')).sort()) await run(f, join(migDir, f));
await run('pgtap shim', join(here, 'sql', '01_pgtap_shim.sql'));

let failed = 0, total = 0;
for (const f of readdirSync(testDir).filter((f) => f.endsWith('.test.sql')).sort()) {
  let results;
  try {
    results = await db.exec('set search_path to public, tap;\n' + readFileSync(join(testDir, f), 'utf8'));
  } catch (e) {
    console.error(`ERROR in ${f}: ${e.message}`);
    await db.exec('rollback').catch(() => {});
    failed++;
    continue;
  }
  const lines = results.flatMap((r) => r.rows.map((row) => Object.values(row)[0])).filter((v) => typeof v === 'string');
  for (const l of lines) {
    if (/^(not )?ok /.test(l)) { total++; if (l.startsWith('not ok')) { failed++; console.log(`  ${f}: ${l}`); } }
    else if (/^(1\.\.|# |not ok -)/.test(l) && l.startsWith('not ok')) { failed++; console.log(`  ${f}: ${l}`); }
  }
  console.log(`${f}: ${lines.filter((l) => /^ok /.test(l)).length} ok`);
}
console.log(`\n${total} assertions, ${failed} failure(s)`);
process.exit(failed ? 1 : 0);
