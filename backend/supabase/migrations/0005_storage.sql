-- 0005: Storage bucket for catalogue media. Public read, writes service role only.
-- (Requires Supabase's storage schema.)

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('exercise-media', 'exercise-media', true, 52428800,
        array['video/mp4','image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "exercise-media public read" on storage.objects for select
  to anon, authenticated using (bucket_id = 'exercise-media');
-- No insert/update/delete policies: uploads happen server-side with the service role.
