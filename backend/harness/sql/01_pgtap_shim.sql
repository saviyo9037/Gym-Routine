-- TEST-ONLY minimal subset of pgTAP (plan/ok/is/isnt/throws_ok/lives_ok/finish)
-- so the pgTAP-style test files can run in PGlite, which has no pgTAP extension.
-- Real runs should use `supabase test db` with real pgTAP.
create schema tap;
grant usage on schema tap to public;

create function tap.plan(n int) returns text language plpgsql as $$
begin
  perform set_config('tap.n', '0', false);
  perform set_config('tap.fail', '0', false);
  perform set_config('tap.plan', n::text, false);
  return '1..' || n;
end $$;

create function tap.ok(p boolean, descr text default '') returns text language plpgsql as $$
declare n int := coalesce(nullif(current_setting('tap.n', true), ''), '0')::int + 1;
begin
  perform set_config('tap.n', n::text, false);
  if p is true then return 'ok ' || n || ' - ' || descr; end if;
  perform set_config('tap.fail', (coalesce(nullif(current_setting('tap.fail', true), ''), '0')::int + 1)::text, false);
  return 'not ok ' || n || ' - ' || descr;
end $$;

create function tap.is(a anyelement, b anyelement, descr text default '') returns text language plpgsql as $$
begin
  return tap.ok(a is not distinct from b, descr || coalesce(' (got ' || a::text || ', want ' || b::text || ')', ' (got NULL)'));
end $$;

create function tap.isnt(a anyelement, b anyelement, descr text default '') returns text language plpgsql as $$
begin return tap.ok(a is distinct from b, descr); end $$;

create function tap.throws_ok(q text, code text, descr text default '') returns text language plpgsql as $$
begin
  begin
    execute q;
  exception when others then
    return tap.ok(sqlstate = code, descr || ' (sqlstate ' || sqlstate || ', want ' || code || ')');
  end;
  return tap.ok(false, descr || ' (no error raised)');
end $$;

create function tap.lives_ok(q text, descr text default '') returns text language plpgsql as $$
begin
  begin
    execute q;
  exception when others then
    return tap.ok(false, descr || ' (raised ' || sqlstate || ': ' || sqlerrm || ')');
  end;
  return tap.ok(true, descr);
end $$;

create function tap.finish() returns text language plpgsql as $$
begin
  return case when current_setting('tap.fail', true)::int > 0
              or current_setting('tap.n', true)::int <> current_setting('tap.plan', true)::int
    then 'not ok - plan/finish mismatch or failures' else '# finished ok' end;
end $$;
grant execute on all functions in schema tap to public;
