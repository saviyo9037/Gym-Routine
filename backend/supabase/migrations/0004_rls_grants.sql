-- 0004: Row Level Security + explicit grants (least privilege).

alter table public.profiles enable row level security;
alter table public.admins enable row level security;
alter table public.catalogue_versions enable row level security;
alter table public.exercises_catalog enable row level security;
alter table public.exercise_media enable row level security;
alter table public.template_plans enable row level security;
alter table public.user_exercises enable row level security;
alter table public.workout_plans enable row level security;
alter table public.workout_plan_exercises enable row level security;
alter table public.workout_sessions enable row level security;
alter table public.session_sets enable row level security;
alter table public.routines enable row level security;
alter table public.routine_completions enable row level security;
alter table public.entitlements enable row level security;
alter table public.revenuecat_events enable row level security;
alter table public.audit_log enable row level security;

-- Start from nothing, then grant narrowly.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
grant all on all tables in schema public to service_role;
grant usage on schema public to anon, authenticated, service_role;
grant all on all functions in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

-- Functions callable by signed-in users / policies.
grant execute on function public.is_valid_muscle_group(text) to anon, authenticated;
grant execute on function public.is_admin(text) to authenticated;
grant execute on function public.has_admin_role(text[]) to authenticated;
grant execute on function public.current_admin_role() to authenticated;
grant execute on function public.is_active_user() to authenticated;
grant execute on function public.delete_my_account_data() to authenticated;
-- publish_catalogue, apply_revenuecat_event, revenue_summary, dashboard_stats: service_role only.

-- ---------- profiles ----------
grant select on public.profiles to authenticated;
grant update (display_name, settings, last_sync_at, last_seen_at) on public.profiles to authenticated;
create policy profiles_select_own on public.profiles for select to authenticated
  using (id = auth.uid());
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid() and public.is_active_user())
  with check (id = auth.uid());

-- ---------- admins ----------
grant select on public.admins to authenticated;
create policy admins_select_self on public.admins for select to authenticated
  using (user_id = auth.uid());
-- no insert/update/delete policies: service role only.

-- ---------- catalogue: read-only ----------
grant select on public.catalogue_versions, public.exercises_catalog,
  public.exercise_media, public.template_plans to anon, authenticated;
create policy catalogue_versions_read on public.catalogue_versions for select
  to anon, authenticated using (true);
create policy exercises_catalog_read on public.exercises_catalog for select
  to anon, authenticated using (status in ('published','archived') and catalogue_version is not null);
create policy exercise_media_read on public.exercise_media for select
  to anon, authenticated using (status = 'published');
create policy template_plans_read on public.template_plans for select
  to anon, authenticated using (status = 'published');

-- ---------- user-owned tables ----------
do $$
declare t text;
begin
  foreach t in array array['user_exercises','workout_plans','workout_plan_exercises',
    'workout_sessions','session_sets','routines','routine_completions'] loop
    execute format('grant select, insert, update on public.%I to authenticated', t);
    execute format('create policy %I on public.%I for select to authenticated using (user_id = auth.uid())',
      t || '_select_own', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (user_id = auth.uid() and public.is_active_user())',
      t || '_insert_own', t);
    execute format('create policy %I on public.%I for update to authenticated using (user_id = auth.uid() and public.is_active_user()) with check (user_id = auth.uid())',
      t || '_update_own', t);
    -- No delete grant/policy: clients soft-delete via deleted_at.
  end loop;
end $$;

-- ---------- entitlements: owner reads only; writes via service role ----------
grant select on public.entitlements to authenticated;
create policy entitlements_select_own on public.entitlements for select to authenticated
  using (user_id = auth.uid());

-- revenuecat_events, audit_log: RLS on, no policies => only service role (bypasses RLS).
