-- 0001: shared helpers. Mirrors lib/data/db_helper.dart (SQLite) entities.
-- Target: Supabase Postgres (auth/storage schemas provided by Supabase).

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- The 15 primary muscle-group categories used by the app catalogue.
create or replace function public.is_valid_muscle_group(p text)
returns boolean language sql immutable as $$
  select p = any (array[
    'Chest','Back','Lats','Upper Back and Traps','Shoulders','Biceps','Triceps',
    'Forearms','Quadriceps','Hamstrings','Glutes','Calves','Abs and Core',
    'Full Body','Cardio'
  ]);
$$;
