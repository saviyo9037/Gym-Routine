-- 0002: tables. Local SQLite integer ids are kept in local_id where a user row
-- maps to a local row; cloud ids are client-generated uuids (last-write-wins sync).

-- ---------- identity / admin ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  disabled boolean not null default false,
  last_sync_at timestamptz,
  last_seen_at timestamptz,
  settings jsonb not null default '{}'::jsonb,   -- mirrors user_settings key/value
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','support','content')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- catalogue (read-only to app users) ----------
create table public.catalogue_versions (
  version integer primary key,
  published_at timestamptz not null default now(),
  published_by uuid references auth.users(id) on delete set null,
  notes text,
  exercise_count integer not null default 0
);

create table public.exercises_catalog (
  id integer primary key,                           -- stable integer exercise id (== local exercises.id)
  name text not null check (length(btrim(name)) > 0),
  primary_muscle_group text not null check (public.is_valid_muscle_group(primary_muscle_group)),
  secondary_muscles text,
  target text,
  description text,
  starting_position text,
  instructions text,
  breathing_guidance text,
  beginner_modification text,
  equipment text,
  difficulty text not null default 'Intermediate'
    check (difficulty in ('Beginner','Intermediate','Advanced')),
  suggested_sets_reps text,
  common_mistakes text,
  default_sets integer not null default 3 check (default_sets > 0),
  default_reps integer not null default 10 check (default_reps > 0),
  default_weight_kg numeric not null default 15 check (default_weight_kg >= 0),
  rest_seconds integer not null default 90 check (rest_seconds >= 0),
  is_compound boolean not null default false,
  is_recommended boolean not null default true,
  status text not null default 'draft' check (status in ('draft','published','archived')),
  needs_publish boolean not null default true,
  catalogue_version integer references public.catalogue_versions(version),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.exercises_catalog (catalogue_version);
create index on public.exercises_catalog (primary_muscle_group);

create table public.exercise_media (
  id uuid primary key default gen_random_uuid(),
  exercise_id integer not null references public.exercises_catalog(id) on delete cascade,
  media_type text not null check (media_type in ('video','image')),
  mime_type text not null check (mime_type in ('video/mp4','image/jpeg','image/png','image/webp')),
  storage_path text not null,
  thumbnail_path text,
  size_bytes bigint not null check (size_bytes > 0),
  duration_seconds integer,
  -- Licence/provenance is mandatory and never auto-claimed.
  license text not null check (length(btrim(license)) > 0),
  attribution text not null check (length(btrim(attribution)) > 0),
  source_url text,
  license_verified boolean not null default false,
  status text not null default 'draft' check (status in ('draft','published','archived')),
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.exercise_media (exercise_id);

-- Admin-curated template plans / routines (not user-owned; read-only to app).
create table public.template_plans (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('plan','routine')),
  title text not null check (length(btrim(title)) > 0),
  description text,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft','published','archived')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- user-owned (sync) tables ----------
-- Common columns: id uuid (client generated), user_id, client_updated_at,
-- created_at, updated_at (server-authoritative), deleted_at (soft delete).

create table public.user_exercises (            -- custom exercises (exercises.is_custom = 1)
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  local_id integer,
  name text not null check (length(btrim(name)) > 0),
  primary_muscle_group text not null check (public.is_valid_muscle_group(primary_muscle_group)),
  secondary_muscles text, target text, description text, starting_position text,
  instructions text, breathing_guidance text, beginner_modification text,
  equipment text,
  difficulty text not null default 'Intermediate'
    check (difficulty in ('Beginner','Intermediate','Advanced')),
  suggested_sets_reps text, common_mistakes text,
  default_sets integer not null default 3,
  default_reps integer not null default 10,
  default_weight_kg numeric not null default 15,
  rest_seconds integer not null default 90,
  personal_notes text, trainer_instructions text,
  is_compound boolean not null default false,
  is_favourite boolean not null default false,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.workout_plans (             -- workout_plans (one per date)
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  local_id integer,
  plan_date date not null,
  primary_muscle_id integer, primary_muscle_name text,
  secondary_muscle_id integer, secondary_muscle_name text,
  notes text, trainer_instructions text,
  is_completed boolean not null default false,
  is_rest_day boolean not null default false,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create unique index workout_plans_user_date_uq
  on public.workout_plans (user_id, plan_date) where deleted_at is null;

create table public.workout_plan_exercises (    -- planned_exercises
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public.workout_plans(id) on delete cascade,
  local_id integer,
  exercise_id integer,                          -- catalogue id (nullable for custom)
  user_exercise_id uuid references public.user_exercises(id) on delete set null,
  exercise_name text not null,
  muscle_group_name text,
  exercise_order integer not null default 0,
  target_sets integer not null default 3,
  target_reps integer not null default 10,
  target_weight_kg numeric not null default 15,
  rest_seconds integer not null default 90,
  notes text,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.workout_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  local_id integer,
  plan_id uuid references public.workout_plans(id) on delete set null,
  session_date date not null,
  start_time timestamptz not null,
  end_time timestamptz,
  duration_seconds integer not null default 0,
  primary_muscle text not null,
  secondary_muscle text,
  notes text,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.session_sets (              -- workout_sets
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null references public.workout_sessions(id) on delete cascade,
  local_id integer,
  exercise_id integer,
  user_exercise_id uuid references public.user_exercises(id) on delete set null,
  exercise_name text not null,
  set_number integer not null,
  reps integer not null,
  weight_kg numeric not null,
  is_completed boolean not null default true,
  completed_at timestamptz not null,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.routines (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  local_id integer,
  title text not null,
  category text not null,
  start_time text not null,
  end_time text not null,
  repeat_days text not null,
  notes text, food_details text,
  is_reminder_enabled boolean not null default true,
  reminder_minutes_before integer not null default 10,
  alarm_type text not null default 'notification',
  is_alarm_enabled boolean not null default true,
  sound_name text not null default 'Digital Beep',
  is_vibration_enabled boolean not null default true,
  snooze_minutes integer not null default 10,
  is_enabled boolean not null default true,
  color_hex text,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.routine_completions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  routine_id uuid not null references public.routines(id) on delete cascade,
  local_id integer,
  completion_date date not null,
  status text not null,
  notes text,
  completed_at timestamptz not null,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create unique index routine_completions_uq
  on public.routine_completions (user_id, routine_id, completion_date) where deleted_at is null;

do $$
declare t text;
begin
  foreach t in array array['user_exercises','workout_plans','workout_plan_exercises',
    'workout_sessions','session_sets','routines','routine_completions'] loop
    execute format('create index on public.%I (user_id, updated_at)', t);
  end loop;
end $$;

-- ---------- billing / ops ----------
create table public.entitlements (
  user_id uuid not null references auth.users(id) on delete cascade,
  entitlement_id text not null default 'premium',
  is_active boolean not null default false,
  product_id text,
  store text,
  period_type text,
  purchased_at timestamptz,
  expires_at timestamptz,
  will_renew boolean not null default false,
  billing_issue_detected_at timestamptz,
  unsubscribe_detected_at timestamptz,
  last_event_timestamp_ms bigint not null default 0,   -- stale-event guard
  updated_at timestamptz not null default now(),
  primary key (user_id, entitlement_id)
);

create table public.revenuecat_events (
  event_id text primary key,                     -- RevenueCat event.id: idempotency key
  app_user_id text,
  user_id uuid,                                  -- resolved auth user (no FK: keep financial history)
  type text not null,
  event_timestamp_ms bigint not null,
  product_id text,
  store text,
  environment text,
  period_type text,
  price numeric,                                 -- USD price as sent by RevenueCat
  currency text,
  purchased_at_ms bigint,
  expiration_at_ms bigint,
  raw jsonb not null,
  received_at timestamptz not null default now()
);
create index on public.revenuecat_events (user_id);
create index on public.revenuecat_events (type, event_timestamp_ms);

create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid,
  actor_role text,
  action text not null,
  target_type text,
  target_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index on public.audit_log (created_at desc);
