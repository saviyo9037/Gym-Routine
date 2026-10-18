# Media guide: adding a verified demonstration video

Videos are a **paid feature and are not shipped inside the app**. Delivery chain:

```
media_src/encoded/<slug>.mp4  (gitignored, your encoded master)
   -> scripts/upload_videos.mjs -> PRIVATE Supabase bucket "exercise-videos"
   -> exercise_media row (admin panel: licence verified + published)
   -> app asks the "video-url" Edge Function -> server checks the subscription
   -> short-lived signed URL (300 s) -> downloaded on demand, ONE exercise at a time,
      into the app's private cache, played from there (offline afterwards)
   -> cache is deleted when the subscription ends
```

`media_manifest.json` is the single source of truth. A video only counts as **VERIFIED** when a
human has confirmed (1) where it came from, (2) that you may ship it, and (3) that it shows the right
movement. Tooling never sets VERIFIED for you, and the server only serves rows whose licence is
verified AND published.

## Switches
* `lib/core/media_config.dart` -> `kBundledVideosEnabled` (default `true`). Build with
  `--dart-define=BUNDLED_VIDEOS=false` to make every exercise NO_VIDEO (photo only, no network call).
  Despite the name it now switches ALL demonstration videos (bundled or protected).
* Server: never set `VIDEO_ALLOW_UNVERIFIED=1` on the `video-url` function in production
  (development switch that serves videos whose licence is not verified).

## Add one video for exercise ID `N`
1. **Get the footage legally.** Shoot it yourself or obtain a written licence that allows shipping in
   a paid app. Keep the evidence (licence text, contract, shoot log) outside the app (`evidence/<N>/`).
2. **Encode** (H.264, no audio, <= 960x540, <= 10 s, faststart) into `media_src/encoded/`:
   ```
   python -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())"   # path to ffmpeg
   ffmpeg -i source.mp4 -t 10 -an -vf "scale='min(960,iw)':'min(540,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2" \
     -c:v libx264 -preset slow -crf 28 -pix_fmt yuv420p -movflags +faststart media_src/encoded/<slug>.mp4
   ```
   One file per exercise: **never reuse a file for another exercise** (validator + tests fail on
   byte-identical files).
3. **Look at it** (`python tool/audit_frames.py`) and confirm it shows exactly this exercise.
4. **Probe + hash**: `python tool/media_probe.py` (writes `audit/probe.json`), then copy `sha256`,
   `size_bytes`, `duration_s`, `resolution`, `codec` into the manifest entry.
5. **Edit `assets/exercise_demonstrations.json`** for that exercise:
   `"has_video": true, "media_type": "video", "storage_path": "videos/<N>.mp4", "status": "UNVERIFIED"`.
   Keep `local_bundled_path` and `video_url` **null** (nothing is bundled; no third-party stream).
6. **Edit `media_manifest.json`** entry: `filename`, `encoded_path` (`media_src/encoded/<slug>.mp4`),
   `storage_path` (`videos/<N>.mp4`), hashes/sizes, and
   - `source`: real description (who shot it / licensor, date) - not "UNKNOWN"
   - `license`: the actual licence/grant - not "UNVERIFIED"
   - `evidence`: list of evidence references
   - `reviewed_by`: the person who confirmed the movement
   - `status`: `VERIFIED` only when all four are real, otherwise `UNVERIFIED`. Replace an old `NO_VIDEO`.
7. **Validate**: `python scripts/validate_media.py` (must print `0 error(s)`; also fails if any video is
   inside `assets/` or listed in `pubspec.yaml`). `python scripts/test_validate_media.py` tests the validator.
8. **Upload the file** (needs your real Supabase project; service-role key from `admin/.env.local` or the
   environment, never committed):
   ```
   node scripts/upload_videos.mjs --dry-run                      # preview, no network
   node scripts/upload_videos.mjs --only <N> --rows              # VERIFIED entries only; creates a DRAFT row
   node scripts/upload_videos.mjs --only <N> --rows --include-unverified   # TEST uploads only
   ```
   Same-size objects are skipped; `--force` replaces. The script never verifies or publishes anything.
9. **Verify + publish in the admin panel** (Media page: licence verified, then status published).
   Until then the function answers "no video" and the app shows the photo.
10. **Test**: `flutter test` (the media tests check the 123/78 split and that nothing is bundled). Update the
    hard-coded counts only after reviewing the new totals.

## What the validator checks
manifest completeness (every exercise id) / demonstrations JSON agrees with the manifest (`storage_path`
= `videos/<id>.mp4`, no `local_bundled_path`, no `video_url`) / NO_VIDEO entries map nothing / **no video file
under `assets/` and none in `pubspec.yaml`** / (when `media_src/encoded` exists) file exists, orphan files,
sha256 + size, no duplicate content, H.264, no audio, <= 10 s, <= 960x540 / VERIFIED requires source,
licence, evidence, reviewed_by.
