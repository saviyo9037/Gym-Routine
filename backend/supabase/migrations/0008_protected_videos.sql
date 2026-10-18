-- 0008: protected exercise videos.
--
-- Videos are a paid feature and are NOT shipped inside the app. They live in a PRIVATE bucket and the
-- app only ever receives a short-lived signed URL from the `video-url` Edge Function, which first asks
-- public.video_access() (service role only) whether the caller is entitled and the video is publishable.
--
-- (Requires Supabase's storage schema, like 0005.)

-- 1) Private bucket: not public, mp4 only, 20 MB per object.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('exercise-videos', 'exercise-videos', false, 20971520, array['video/mp4'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- 2) No direct client access to that bucket, whatever other (permissive) policies exist now or later.
--    Restrictive policies are ANDed with permissive ones. service_role bypasses RLS (uploads + signing).
create policy "exercise-videos: no direct client access" on storage.objects
  as restrictive for all
  to anon, authenticated
  using (bucket_id <> 'exercise-videos')
  with check (bucket_id <> 'exercise-videos');

-- 3) The public catalogue bucket is for images only from now on (videos must not be placed there).
update storage.buckets
   set allowed_mime_types = array['image/jpeg','image/png','image/webp']
 where id = 'exercise-media';

-- 4) Server-side access decision, used only by the Edge Function (service role).
--    Entitlement = the "premium" row is active and not past its expiry. A trial is a normal active
--    entitlement (period_type = 'TRIAL'). A store billing-issue grace period keeps access for at most
--    16 days after expiry (same bound as the app). Refunds/expiry arrive as is_active = false.
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
  ent public.entitlements%rowtype;
  v_entitled boolean := false;
  m public.exercise_media%rowtype;
begin
  if p_user_id is null or p_exercise_id is null or p_exercise_id < 1 then
    return jsonb_build_object('allowed', false, 'reason', 'bad_request');
  end if;

  select * into ent from public.entitlements
   where user_id = p_user_id and entitlement_id = 'premium';

  if found and ent.is_active then
    v_entitled := ent.expires_at is null
      or ent.expires_at > now()
      or (ent.billing_issue_detected_at is not null and ent.expires_at > now() - interval '16 days');
  end if;

  if not v_entitled then
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
    -- Unknown exercise, no video (NO_VIDEO), unpublished, archived or licence not verified.
    return jsonb_build_object('allowed', false, 'reason', 'no_video');
  end if;

  return jsonb_build_object('allowed', true, 'storage_path', m.storage_path, 'mime_type', m.mime_type);
end;
$$;

revoke all on function public.video_access(uuid, integer, boolean) from public, anon, authenticated;
grant execute on function public.video_access(uuid, integer, boolean) to service_role;
