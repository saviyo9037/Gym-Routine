-- 0010: trial tier for protected videos.
-- Tiers: 'none' (no live entitlement), 'trial' (store free trial: premium row with period_type = 'TRIAL'),
-- 'full' (paid premium row, live comp grant, or store billing grace on a paid row).
-- video_access() now serves a signed-URL path only to 'full', unless the caller passes p_allow_trial = true
-- (the Edge Function does that only when its env TRIAL_VIDEOS_LOCKED is "false"). The default is the SAFE
-- value: trials are refused. Additive; is_entitled() is unchanged (trial users still count as entitled for
-- everything except videos).
-- Re-runnable: create or replace / drop if exists.

create or replace function public.entitlement_tier(p_user_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
    when coalesce(bool_or(live and not is_trial), false) then 'full'
    when coalesce(bool_or(live and is_trial), false) then 'trial'
    else 'none'
  end
  from (
    select
      e.is_active and (
        e.expires_at is null
        or e.expires_at > now()
        or (e.entitlement_id = 'premium'
            and e.billing_issue_detected_at is not null
            and e.expires_at > now() - interval '16 days')
      ) as live,
      (e.entitlement_id = 'premium' and upper(coalesce(e.period_type, '')) = 'TRIAL') as is_trial
    from public.entitlements e
    where e.user_id = p_user_id and e.entitlement_id in ('premium', 'premium_comp')
  ) t;
$$;
revoke all on function public.entitlement_tier(uuid) from public, anon, authenticated;
grant execute on function public.entitlement_tier(uuid) to service_role;

-- Replace the 3-argument signature (a second overload would make named-argument calls ambiguous).
drop function if exists public.video_access(uuid, integer, boolean);

create or replace function public.video_access(
  p_user_id uuid,
  p_exercise_id integer,
  p_require_verified boolean default true,
  p_allow_trial boolean default false
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m public.exercise_media%rowtype;
  v_tier text;
begin
  if p_user_id is null or p_exercise_id is null or p_exercise_id < 1 then
    return jsonb_build_object('allowed', false, 'reason', 'bad_request');
  end if;

  v_tier := public.entitlement_tier(p_user_id);
  if v_tier = 'none' then
    return jsonb_build_object('allowed', false, 'reason', 'not_entitled');
  end if;
  if v_tier = 'trial' and not coalesce(p_allow_trial, false) then
    return jsonb_build_object('allowed', false, 'reason', 'trial_locked');
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
revoke all on function public.video_access(uuid, integer, boolean, boolean) from public, anon, authenticated;
grant execute on function public.video_access(uuid, integer, boolean, boolean) to service_role;
