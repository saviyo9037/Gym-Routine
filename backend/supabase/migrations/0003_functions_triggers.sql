-- 0003: functions and triggers.

-- ---------- updated_at triggers ----------
do $$
declare t text;
begin
  foreach t in array array['profiles','admins','exercises_catalog','exercise_media','template_plans',
    'user_exercises','workout_plans','workout_plan_exercises','workout_sessions','session_sets',
    'routines','routine_completions','entitlements'] loop
    execute format('create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
      t || '_set_updated_at', t);
  end loop;
end $$;

-- ---------- admin helpers ----------
-- is_admin(): caller is any admin. is_admin('owner'): caller has exactly that role.
create or replace function public.is_admin(p_role text default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.admins a
    where a.user_id = auth.uid() and (p_role is null or a.role = p_role)
  );
$$;

create or replace function public.has_admin_role(p_roles text[])
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.admins a
    where a.user_id = auth.uid() and a.role = any (p_roles)
  );
$$;

create or replace function public.current_admin_role()
returns text language sql stable security definer set search_path = public as $$
  select a.role from public.admins a where a.user_id = auth.uid();
$$;

-- Account is usable (profile not disabled/soft-deleted). Missing profile => usable
-- (profile is created by trigger; absence should not lock out the owner of data).
create or replace function public.is_active_user()
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and (p.disabled or p.deleted_at is not null)
  );
$$;

-- ---------- profile bootstrap ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- audit log is append-only ----------
create or replace function public.audit_log_immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'audit_log is append-only';
end $$;

create trigger audit_log_no_update before update or delete on public.audit_log
  for each row execute function public.audit_log_immutable();

-- ---------- catalogue versioning ----------
-- Any change to a catalogue row marks it as needing publication, unless the
-- statement itself sets needs_publish (the publish function does).
create or replace function public.exercises_catalog_mark_dirty()
returns trigger language plpgsql as $$
begin
  if new.needs_publish is not distinct from old.needs_publish then
    new.needs_publish := true;
  end if;
  return new;
end $$;

create trigger exercises_catalog_dirty before update on public.exercises_catalog
  for each row execute function public.exercises_catalog_mark_dirty();

-- Bumps catalogue_versions and stamps all pending rows with the new version.
-- Clients sync rows where catalogue_version > their stored version (archived
-- rows included, so deletions propagate). Service role only.
create or replace function public.publish_catalogue(p_actor uuid default null, p_notes text default null)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v integer;
  n integer;
begin
  perform pg_advisory_xact_lock(hashtext('publish_catalogue'));
  select coalesce(max(version), 0) + 1 into v from public.catalogue_versions;
  select count(*) into n from public.exercises_catalog where needs_publish;
  if n = 0 then
    raise exception 'nothing to publish';
  end if;
  insert into public.catalogue_versions (version, published_by, notes, exercise_count)
  values (v, p_actor, p_notes, (select count(*) from public.exercises_catalog where status = 'published'));
  update public.exercises_catalog
     set catalogue_version = v, needs_publish = false
   where needs_publish;
  return v;
end $$;

-- ---------- RevenueCat apply (atomic + idempotent + stale-safe) ----------
-- Returns 'duplicate' | 'stale' | 'applied' | 'recorded'. Called by the webhook
-- Edge Function with the service role; the pure decision logic lives in
-- functions/_shared/entitlement.ts and is mirrored in p_state.
create or replace function public.apply_revenuecat_event(p_event jsonb, p_state jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare
  inserted integer;
  uid uuid := nullif(p_state->>'user_id', '')::uuid;
  prev bigint;
begin
  insert into public.revenuecat_events (
    event_id, app_user_id, user_id, type, event_timestamp_ms, product_id, store,
    environment, period_type, price, currency, purchased_at_ms, expiration_at_ms, raw)
  values (
    p_event->>'id', p_event->>'app_user_id', uid, p_event->>'type',
    (p_event->>'event_timestamp_ms')::bigint, p_event->>'product_id', p_event->>'store',
    p_event->>'environment', p_event->>'period_type', (p_event->>'price')::numeric,
    p_event->>'currency', (p_event->>'purchased_at_ms')::bigint,
    (p_event->>'expiration_at_ms')::bigint, p_event)
  on conflict (event_id) do nothing;
  get diagnostics inserted = row_count;
  if inserted = 0 then return 'duplicate'; end if;

  if uid is null or not (p_state ? 'is_active') then
    return 'recorded';
  end if;
  if not exists (select 1 from auth.users where id = uid) then
    return 'recorded';
  end if;

  select last_event_timestamp_ms into prev from public.entitlements
   where user_id = uid and entitlement_id = 'premium' for update;
  if found and prev >= (p_event->>'event_timestamp_ms')::bigint then
    return 'stale';
  end if;

  insert into public.entitlements as e (
    user_id, entitlement_id, is_active, product_id, store, period_type, purchased_at,
    expires_at, will_renew, billing_issue_detected_at, unsubscribe_detected_at,
    last_event_timestamp_ms)
  values (
    uid, 'premium', (p_state->>'is_active')::boolean, p_state->>'product_id', p_state->>'store',
    p_state->>'period_type', (p_state->>'purchased_at')::timestamptz,
    (p_state->>'expires_at')::timestamptz, (p_state->>'will_renew')::boolean,
    (p_state->>'billing_issue_detected_at')::timestamptz,
    (p_state->>'unsubscribe_detected_at')::timestamptz,
    (p_event->>'event_timestamp_ms')::bigint)
  on conflict (user_id, entitlement_id) do update set
    is_active = excluded.is_active, product_id = excluded.product_id, store = excluded.store,
    period_type = excluded.period_type, purchased_at = excluded.purchased_at,
    expires_at = excluded.expires_at, will_renew = excluded.will_renew,
    billing_issue_detected_at = excluded.billing_issue_detected_at,
    unsubscribe_detected_at = excluded.unsubscribe_detected_at,
    last_event_timestamp_ms = excluded.last_event_timestamp_ms;
  return 'applied';
end $$;

-- ---------- account data deletion (caller) ----------
-- Hard-deletes everything the caller owns. The auth user itself is removed by
-- the delete-account Edge Function (service role). revenuecat_events are kept
-- as financial records but unlinked from the user id.
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

-- ---------- admin dashboard aggregates (service role only) ----------
-- MRR: for each user with an active, auto-renewing entitlement, take their
-- latest paid PRODUCTION event (price > 0, non-trial) and normalise to a month
-- using the purchased->expiration span. Prices are as reported by RevenueCat
-- (USD). Returns 0 when there is no data; nothing is estimated.
create or replace function public.revenue_summary()
returns table (active_subscribers bigint, mrr_usd numeric)
language sql stable security definer set search_path = public as $$
  with active as (
    select user_id from public.entitlements
     where entitlement_id = 'premium' and is_active
       and (expires_at is null or expires_at > now())
  ),
  latest as (
    select distinct on (e.user_id) e.user_id, e.price,
           greatest(1, round(((e.expiration_at_ms - e.purchased_at_ms) / 86400000.0) / 30.4375)) as months
      from public.revenuecat_events e
      join public.entitlements en
        on en.user_id = e.user_id and en.entitlement_id = 'premium' and en.will_renew
      join active a on a.user_id = e.user_id
     where e.type in ('INITIAL_PURCHASE','RENEWAL','PRODUCT_CHANGE')
       and e.price > 0 and e.environment = 'PRODUCTION'
       and coalesce(e.period_type, 'NORMAL') = 'NORMAL'
       and e.purchased_at_ms is not null and e.expiration_at_ms is not null
     order by e.user_id, e.event_timestamp_ms desc
  )
  select (select count(*) from active)::bigint,
         coalesce((select round(sum(price / months), 2) from latest), 0);
$$;

create or replace function public.dashboard_stats()
returns table (total_users bigint, signups_7d bigint, signups_30d bigint, dau bigint)
language sql stable security definer set search_path = public as $$
  select
    (select count(*) from public.profiles where deleted_at is null),
    (select count(*) from public.profiles where deleted_at is null and created_at >= now() - interval '7 days'),
    (select count(*) from public.profiles where deleted_at is null and created_at >= now() - interval '30 days'),
    (select count(*) from public.profiles where deleted_at is null and last_seen_at >= now() - interval '1 day');
$$;
