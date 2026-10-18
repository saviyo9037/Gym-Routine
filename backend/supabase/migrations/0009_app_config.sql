-- 0009: remote app config, announcements and manual (comp) premium grants.
--
-- DESIGN
--  * app_config is ONE logical row (id = 1, enforced by a CHECK) with typed, constrained columns instead of
--    free-form key/value rows: every field is validated by the database (length caps, enums, semver) so a
--    bad admin edit is rejected at write time, one UPDATE is atomic, and the app has a fixed schema to
--    validate against. The app still validates again and falls back to built-in defaults.
--  * Everything in app_config / active announcements is NON-SENSITIVE: anon and authenticated may read it,
--    nobody but the service role (the admin panel server) may write it. Owner-only rules (pricing copy,
--    access model) are enforced in the admin app; the database enforces shape, not who may edit.
--  * Comp access ("manual premium"): a log table (manual_premium_grants: reason, expiry, granted_by,
--    revoked) plus ONE derived entitlements row with entitlement_id = 'premium_comp' (store = 'comp').
--    The app reads its own entitlements row through the existing owner-select policy, and the
--    `video-url` decision (video_access) now honours it. 'premium' (RevenueCat) rows are never touched, and
--    revenue_summary() only looks at 'premium', so comp access never counts as revenue.

-- ---------- validators (immutable, used by CHECK constraints) ----------
create or replace function public.is_text_array(p jsonb, p_max_items integer, p_max_len integer)
returns boolean language sql immutable as $$
  select p is not null
     and jsonb_typeof(p) = 'array'
     and jsonb_array_length(p) <= p_max_items
     and not exists (
       select 1 from jsonb_array_elements(p) e
        where jsonb_typeof(e) <> 'string'
           or char_length(e #>> '{}') not between 1 and p_max_len
     );
$$;

create or replace function public.is_plan_badges(p jsonb)
returns boolean language sql immutable as $$
  select p is not null
     and jsonb_typeof(p) = 'object'
     and not exists (
       select 1 from jsonb_each(p) kv
        where kv.key not in ('monthly', 'yearly')
           or jsonb_typeof(kv.value) <> 'string'
           or char_length(kv.value #>> '{}') not between 1 and 24
     );
$$;

create or replace function public.is_semver(p text)
returns boolean language sql immutable as $$
  select p ~ '^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}(\+[0-9]{1,6})?$';
$$;

-- ---------- app_config ----------
create table public.app_config (
  id smallint primary key default 1 check (id = 1),
  paywall_title text check (paywall_title is null or char_length(paywall_title) between 1 and 80),
  paywall_subtitle text check (paywall_subtitle is null or char_length(paywall_subtitle) between 1 and 200),
  paywall_benefits jsonb not null default '[]'::jsonb check (public.is_text_array(paywall_benefits, 8, 120)),
  plan_badges jsonb not null default '{}'::jsonb check (public.is_plan_badges(plan_badges)),
  promo_text text check (promo_text is null or char_length(promo_text) between 1 and 200),
  maintenance_mode boolean not null default false,
  maintenance_message text check (maintenance_message is null or char_length(maintenance_message) between 1 and 300),
  min_app_version text check (min_app_version is null or public.is_semver(min_app_version)),
  access_model_override text check (access_model_override is null
    or access_model_override in ('subscription_required', 'freemium')),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
insert into public.app_config (id) values (1);
create trigger app_config_updated_at before update on public.app_config
  for each row execute function public.set_updated_at();

-- ---------- announcements ----------
create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 80),
  body text not null check (char_length(body) between 1 and 500),
  level text not null default 'info' check (level in ('info', 'warning')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);
create index announcements_window_idx on public.announcements (active, starts_at, ends_at);
create trigger announcements_updated_at before update on public.announcements
  for each row execute function public.set_updated_at();

-- ---------- manual (comp) premium grants ----------
create table public.manual_premium_grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (char_length(btrim(reason)) between 3 and 300),
  granted_by uuid references auth.users(id) on delete set null,
  granted_at timestamptz not null default now(),
  expires_at timestamptz,                 -- null = no expiry (the admin app allows this for owners only)
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  check (expires_at is null or expires_at > granted_at)
);
create index manual_premium_grants_user_idx on public.manual_premium_grants (user_id);

-- Derives the single 'premium_comp' entitlement row from the grant log. Active = at least one grant that
-- is not revoked and not expired. Expiry = the latest expiry among live grants (null if any is open-ended).
create or replace function public.sync_comp_entitlement(p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_live boolean;
  v_open boolean;
  v_expires timestamptz;
begin
  select coalesce(bool_or(revoked_at is null and (expires_at is null or expires_at > now())), false),
         coalesce(bool_or(revoked_at is null and expires_at is null), false),
         max(expires_at) filter (where revoked_at is null)
    into v_live, v_open, v_expires
    from public.manual_premium_grants
   where user_id = p_user;

  insert into public.entitlements as e
    (user_id, entitlement_id, is_active, store, period_type, expires_at, will_renew, updated_at)
  values
    (p_user, 'premium_comp', v_live, 'comp', 'COMP', case when v_open then null else v_expires end, false, now())
  on conflict (user_id, entitlement_id) do update set
    is_active = excluded.is_active,
    expires_at = excluded.expires_at,
    updated_at = now();
end $$;

create or replace function public.manual_premium_grants_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.sync_comp_entitlement(new.user_id);
  return new;
end $$;
create trigger manual_premium_grants_sync after insert or update on public.manual_premium_grants
  for each row execute function public.manual_premium_grants_sync();

-- ---------- one entitlement decision for the server side ----------
-- Paid/trial 'premium' row (same rules as 0008: active, unexpired, or <= 16 days of billing grace) OR a
-- live comp row (active and unexpired; no grace). Refunds/revocations arrive as is_active = false.
create or replace function public.is_entitled(p_user_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select bool_or(
      e.is_active and (
        e.expires_at is null
        or e.expires_at > now()
        or (e.entitlement_id = 'premium'
            and e.billing_issue_detected_at is not null
            and e.expires_at > now() - interval '16 days')
      )
    )
    from public.entitlements e
    where e.user_id = p_user_id and e.entitlement_id in ('premium', 'premium_comp')
  ), false);
$$;
revoke all on function public.is_entitled(uuid) from public, anon, authenticated;
grant execute on function public.is_entitled(uuid) to service_role;

-- video_access now relies on is_entitled() so comp grants work for videos too.
create or replace function public.video_access(
  p_user_id uuid,
  p_exercise_id integer,
  p_require_verified boolean default true
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m public.exercise_media%rowtype;
begin
  if p_user_id is null or p_exercise_id is null or p_exercise_id < 1 then
    return jsonb_build_object('allowed', false, 'reason', 'bad_request');
  end if;

  if not public.is_entitled(p_user_id) then
    return jsonb_build_object('allowed', false, 'reason', 'not_entitled');
  end if;

  select em.* into m
    from public.exercise_media em
    join public.exercises_catalog c on c.id = em.exercise_id
   where em.exercise_id = p_exercise_id
     and em.media_type = 'video'
     and em.status = 'published'
     and c.status = 'published'
     and (em.license_verified or not p_require_verified)
   order by em.updated_at desc
   limit 1;

  if not found then
    return jsonb_build_object('allowed', false, 'reason', 'no_video');
  end if;

  return jsonb_build_object('allowed', true, 'storage_path', m.storage_path, 'mime_type', m.mime_type);
end;
$$;
revoke all on function public.video_access(uuid, integer, boolean) from public, anon, authenticated;
grant execute on function public.video_access(uuid, integer, boolean) to service_role;

-- ---------- DB-level audit trail (in addition to the admin app's own audit_log rows) ----------
-- Records WHAT changed (table, operation, key, changed column names) even when the change did not come
-- through the admin panel. No values are stored (grant reasons / copy may be personal or long).
create or replace function public.audit_config_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_key text;
  v_changed text[];
begin
  if tg_op = 'DELETE' then
    v_key := coalesce(to_jsonb(old) ->> 'id', '');
    insert into public.audit_log (action, target_type, target_id, metadata)
    values ('db.' || tg_table_name || '.delete', tg_table_name, v_key, '{}'::jsonb);
    return old;
  end if;
  v_key := coalesce(to_jsonb(new) ->> 'id', '');
  if tg_op = 'UPDATE' then
    select coalesce(array_agg(n.key order by n.key), '{}') into v_changed
      from jsonb_each(to_jsonb(new)) n
      join jsonb_each(to_jsonb(old)) o on o.key = n.key
     where n.value is distinct from o.value and n.key not in ('updated_at');
  else
    v_changed := '{}';
  end if;
  insert into public.audit_log (action, target_type, target_id, metadata)
  values ('db.' || tg_table_name || '.' || lower(tg_op), tg_table_name, v_key,
          jsonb_build_object('columns', to_jsonb(v_changed)));
  return new;
end $$;
revoke all on function public.audit_config_change() from public, anon, authenticated;

create trigger app_config_audit after update on public.app_config
  for each row execute function public.audit_config_change();
create trigger announcements_audit after insert or update or delete on public.announcements
  for each row execute function public.audit_config_change();
create trigger manual_premium_grants_audit after insert or update on public.manual_premium_grants
  for each row execute function public.audit_config_change();

-- ---------- RLS / grants ----------
alter table public.app_config enable row level security;
alter table public.announcements enable row level security;
alter table public.manual_premium_grants enable row level security;

grant all on public.app_config, public.announcements, public.manual_premium_grants to service_role;
revoke all on public.app_config, public.announcements, public.manual_premium_grants from anon, authenticated;

-- Read-only for the app (non-sensitive by construction).
grant select on public.app_config to anon, authenticated;
create policy app_config_read on public.app_config for select to anon, authenticated using (id = 1);

-- Only announcements that are active and inside their window are visible to the app.
grant select on public.announcements to anon, authenticated;
create policy announcements_read_active on public.announcements for select to anon, authenticated
  using (active and starts_at <= now() and (ends_at is null or ends_at > now()));

-- Grants hold reasons about people: service role only (RLS on, no policies, no grants).

-- The sync helpers must not be callable by API roles.
revoke all on function public.sync_comp_entitlement(uuid) from public, anon, authenticated;
revoke all on function public.manual_premium_grants_sync() from public, anon, authenticated;
grant execute on function public.sync_comp_entitlement(uuid) to service_role;
