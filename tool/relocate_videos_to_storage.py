"""One-off, idempotent: take the videos out of the app bundle.

 * moves assets/videos/exercises/*.mp4 -> media_src/encoded/ (gitignored)
 * exercise_demonstrations.json: bundled path and third-party video_url removed,
   `storage_path` (videos/<exercise_id>.mp4, the object key in the PRIVATE
   Supabase bucket `exercise-videos`) added for every exercise that has a video
 * media_manifest.json: `storage_path` / `encoded_path` added per entry
Nothing is marked VERIFIED. Run from the repo root."""
import json, os, shutil

SRC = 'assets/videos/exercises'
DST = 'media_src/encoded'
os.makedirs(DST, exist_ok=True)

moved = 0
if os.path.isdir(SRC):
    for f in sorted(os.listdir(SRC)):
        if f.endswith('.mp4'):
            target = os.path.join(DST, f)
            if os.path.exists(target):
                os.remove(os.path.join(SRC, f))
            else:
                shutil.move(os.path.join(SRC, f), target)
            moved += 1
    if not os.listdir(SRC):
        os.rmdir(SRC)
    parent = os.path.dirname(SRC)
    if os.path.isdir(parent) and not os.listdir(parent):
        os.rmdir(parent)

demos = json.load(open('assets/exercise_demonstrations.json', encoding='utf-8'))
for d in demos.values():
    if d.get('has_video'):
        d['local_bundled_path'] = None
        d['video_url'] = None
        d['storage_path'] = f"videos/{d['exercise_id']}.mp4"
    else:
        d['storage_path'] = None
json.dump(demos, open('assets/exercise_demonstrations.json', 'w', encoding='utf-8'), indent=2)

man = json.load(open('media_manifest.json', encoding='utf-8'))
for e in man['videos']:
    if e.get('filename'):
        e['storage_path'] = f"videos/{e['exercise_id']}.mp4"
        e['encoded_path'] = f"media_src/encoded/{e['filename']}"
    else:
        e['storage_path'] = None
        e['encoded_path'] = None
man['delivery'] = ('Videos are NOT bundled in the app. Encoded files live in media_src/encoded/ (gitignored) and are '
                   'uploaded to the private Supabase bucket "exercise-videos" at storage_path; the app downloads '
                   'them on demand through the entitlement-checked video-url function.')
json.dump(man, open('media_manifest.json', 'w', encoding='utf-8'), indent=1)
print('moved', moved, 'files')
