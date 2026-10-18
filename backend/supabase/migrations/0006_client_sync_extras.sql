-- 0006: tables/columns the Flutter sync client needs.
--  * weekly training plans (training_plans / _days / _day_exercises)
--  * cardio time/distance columns (local schema v6)
--  * wall-clock HH:mm columns so session times round-trip without timezone drift
--  * delete_my_account_data() also removes the new tables

alter table public.workout_plan_exercises
  add column if not exists target_duration_seconds integer,
  add column if not exists target_distance_km numeric;

alter table public.session_sets
  add column if not exists duration_seconds integer,
  add column if not exists distance_km numeric;

alter table public.workout_sessions
  add column if not exists start_hhmm text,
  add column if not exists end_hhmm text;

create table public.training_plans (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  local_id integer,
  name text not null check (length(btrim(name)) > 0),
  notes text,
  is_active boolean not null default false,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.training_plan_days (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public.training_plans(id) on delete cascade,
  local_id integer,
  weekday integer not null check (weekday between 1 and 7),
  is_rest boolean not null default false,
  title text,
  notes text,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.training_plan_day_exercises (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  day_id uuid not null references public.training_plan_days(id) on delete cascade,
  local_id integer,
  exercise_id integer,
  exercise_name text not null,
  muscle_group_name text,
  exercise_order integer not null default 0,
  target_sets integer not null default 3,
  target_reps integer not null default 10,
  target_weight_kg numeric not null default 0,
  rest_seconds integer not null default 90,
  target_duration_seconds integer,
  target_distance_km numeric,
  notes text,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

do $$
declare t text;
begin
  foreach t in array array['training_plans','training_plan_days','training_plan_day_exercises'] loop
    execute format('create index on public.%I (user_id, updated_at)', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
      t || '_set_updated_at', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('grant select, insert, update on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
    execute format('create policy %I on public.%I for select to authenticated using (user_id = auth.uid())',
      t || '_select_own', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (user_id = auth.uid() and public.is_active_user())',
      t || '_insert_own', t);
    execute format('create policy %I on public.%I for update to authenticated using (user_id = auth.uid() and public.is_active_user()) with check (user_id = auth.uid())',
      t || '_update_own', t);
  end loop;
end $$;

create or replace function public.delete_my_account_data()
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  delete from public.session_sets where user_id = uid;
  delete from public.workout_sessions where user_id = uid;
  delete from public.workout_plan_exercises where user_id = uid;
  delete from public.workout_plans where user_id = uid;
  delete from public.training_plan_day_exercises where user_id = uid;
  delete from public.training_plan_days where user_id = uid;
  delete from public.training_plans where user_id = uid;
  delete from public.routine_completions where user_id = uid;
  delete from public.routines where user_id = uid;
  delete from public.user_exercises where user_id = uid;
  delete from public.entitlements where user_id = uid;
  update public.revenuecat_events set user_id = null where user_id = uid;
  update public.profiles
     set email = null, display_name = null, settings = '{}'::jsonb, deleted_at = now()
   where id = uid;
  insert into public.audit_log (actor_id, actor_role, action, target_type, target_id)
  values (uid, 'user', 'account.data_deleted', 'user', uid::text);
end $$;
