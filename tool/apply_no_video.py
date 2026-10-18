"""Option A: videos that are byte-identical across exercises are not attributable to any one
exercise, so every file in a duplicate group is unmapped and removed from assets/ (originals stay
in media_src/). Affected exercises fall back to their photo. Local only."""
import json, os, csv
man = json.load(open('media_manifest.json'))
demos = json.load(open('assets/exercise_demonstrations.json'))
dup = {f for g in man['duplicate_groups'] for f in g}
vdir = 'media_src/encoded'
no_video, kept, orphans = [], [], []
for e in man['videos']:
    if e['filename'] not in dup:
        kept.append(e); continue
    if e['exercise_id'] is None:
        orphans.append(e); continue
    d = demos[e['exercise_name']]
    d.update(has_video=False, media_type='image', video_url=None, local_bundled_path=None, status='NO_VIDEO')
    e['removed_filename'] = e.pop('filename')
    e['flags'].append('video removed: byte-identical to other exercises, cannot be attributed (see duplicate_groups)')
    for k in ('sha256', 'size_bytes', 'duration_s', 'resolution', 'codec', 'has_audio'): e[k] = None
    e['filename'] = None; e['status'] = 'NO_VIDEO'
    no_video.append(e)
for f in dup:
    p = os.path.join(vdir, f)
    if os.path.exists(p): os.remove(p)
man['videos'] = sorted(kept + no_video, key=lambda e: e['exercise_id'])
man['removed_orphans'] = [e['filename'] for e in orphans]
man['counts'] = {'entries': len(man['videos']), 'NO_VIDEO': len(no_video),
                 'with_video': len(kept), 'FLAGGED': sum(e['status'] == 'FLAGGED' for e in kept),
                 'UNVERIFIED': sum(e['status'] == 'UNVERIFIED' for e in kept)}
man['note'] += ' Videos shared byte-for-byte by several exercises were removed (NO_VIDEO); remaining videos are unique but still unreviewed.'
man['duplicate_groups_removed'] = man.pop('duplicate_groups')
json.dump(man, open('media_manifest.json', 'w'), indent=1)
json.dump(demos, open('assets/exercise_demonstrations.json', 'w'), indent=2)
with open('audit/needs_video.csv', 'w', newline='') as fh:
    w = csv.writer(fh); w.writerow(['id', 'name', 'category'])
    for e in sorted(no_video, key=lambda e: e['exercise_id']): w.writerow([e['exercise_id'], e['exercise_name'], e['category']])
print(man['counts'], len(orphans), 'orphans removed')
