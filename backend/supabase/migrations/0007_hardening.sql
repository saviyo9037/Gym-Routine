-- 0007: hardening found while re-reading the RLS policies and the sync client.
--  * server_time(): lets clients measure their clock skew (sync normalises timestamps to it)
--  * clamp_client_updated_at: a client can never stamp a row further than 5 minutes in the
--    future (a phone with a wrong clock could otherwise win last-write-wins forever)
--  * enforce_same_owner: a child row may only reference a parent owned by the same user
--    (RLS alone only checked the child's own user_id)
--  * exercise_sync_id: stable cross-device reference to a CUSTOM exercise (local integer ids
--    differ per device)
--  * merge_favourites(): per-exercise last-write-wins merge of catalogue favourites in
--    profiles.settings->'favourites'

-- ---------- server time ----------
create or replace function public.server_time()
returns timestamptz language sql stable as $$ select now() $$;
revoke all on function public.server_time() from public, anon;
grant execute on function public.server_time() to authenticated, service_role;

-- ---------- clamp future client timestamps ----------
create or replace function public.clamp_client_updated_at()
returns trigger language plpgsql as $$
begin
  new.client_updated_at := least(coalesce(new.client_updated_at, now()), now() + interval '5 minutes');
  return new;
end $$;
revoke all on function public.clamp_client_updated_at() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['user_exercises','workout_plans','workout_plan_exercises',
    'workout_sessions','session_sets','routines','routine_completions',
    'training_plans','training_plan_days','training_plan_day_exercises'] loop
    execute format('create trigger %I before insert or update on public.%I for each row execute function public.clamp_client_updated_at()',
      t || '_clamp_client_ts', t);
  end loop;
end $$;

-- ---------- parent must belong to the same user ----------
create or replace function public.enforce_same_owner()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  fk uuid;
  parent_user uuid;
begin
  execute format('select ($1).%I', tg_argv[1]) into fk using new;
  if fk is null then
    return new;
  end if;
  execute format('select user_id from public.%I where id = $1', tg_argv[0]) into parent_user using fk;
  -- A missing parent is reported by the foreign key itself.
  if parent_user is not null and parent_user is distinct from new.user_id then
    raise exception 'parent row belongs to another user' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.enforce_same_owner() from public, anon, authenticated;

create trigger workout_plan_exercises_same_owner before insert or update on public.workout_plan_exercises
  for each row execute function public.enforce_same_owner('workout_plans', 'plan_id');
create trigger session_sets_same_owner before insert or update on public.session_sets
  for each row execute function public.enforce_same_owner('workout_sessions', 'session_id');
create trigger workout_sessions_same_owner before insert or update on public.workout_sessions
  for each row execute function public.enforce_same_owner('workout_plans', 'plan_id');
create trigger routine_completions_same_owner before insert or update on public.routine_completions
  for each row execute function public.enforce_same_owner('routines', 'routine_id');
create trigger training_plan_days_same_owner before insert or update on public.training_plan_days
  for each row execute function public.enforce_same_owner('training_plans', 'plan_id');
create trigger training_plan_day_exercises_same_owner before insert or update on public.training_plan_day_exercises
  for each row execute function public.enforce_same_owner('training_plan_days', 'day_id');

-- ---------- custom exercise references ----------
alter table public.workout_plan_exercises add column if not exists exercise_sync_id uuid;
alter table public.training_plan_day_exercises add column if not exists exercise_sync_id uuid;
alter table public.session_sets add column if not exists exercise_sync_id uuid;

-- ---------- catalogue favourites ----------
-- settings->'favourites' = { "<exerciseId>": {"f": bool, "t": "<iso timestamp>"} }
create or replace function public.merge_favourites(p_items jsonb)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  cur jsonb;
  merged jsonb;
  k text;
  item jsonb;
  ts timestamptz;
  n integer := 0;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'object' then
    raise exception 'favourites must be a json object' using errcode = '22023';
  end if;
  select coalesce(settings -> 'favourites', '{}'::jsonb) into cur from public.profiles where id = auth.uid();
  merged := coalesce(cur, '{}'::jsonb);
  for k, item in select * from jsonb_each(p_items) loop
    n := n + 1;
    exit when n > 2000;                                   -- bounded work / size
    continue when k !~ '^[0-9]{1,9}$';
    continue when jsonb_typeof(item -> 'f') is distinct from 'boolean';
    begin
      ts := (item ->> 't')::timestamptz;
    exception when others then
      continue;
    end;
    ts := least(ts, now() + interval '5 minutes');
    if not (merged ? k) or ts > ((merged -> k) ->> 't')::timestamptz then
      merged := jsonb_set(merged, array[k], jsonb_build_object('f', item -> 'f', 't', to_jsonb(ts)));
    end if;
  end loop;
  update public.profiles
     set settings = jsonb_set(coalesce(settings, '{}'::jsonb), '{favourites}', merged)
   where id = auth.uid();
  return merged;
end $$;
revoke all on function public.merge_favourites(jsonb) from public, anon;
grant execute on function public.merge_favourites(jsonb) to authenticated, service_role;
