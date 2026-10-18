"""Build media_manifest.json from audit/probe_original.json (pre-compression) and
audit/probe.json (shipped). Nothing is marked VERIFIED: the repository holds no
evidence of source or licence for any video."""
import json, os, collections
orig = json.load(open('audit/probe_original.json'))
ship = json.load(open('audit/probe.json'))
demos = json.load(open('assets/exercise_demonstrations.json'))

def ham(a, b): return sum(x != y for x, y in zip(a, b))
by_sha = collections.defaultdict(list)
for f, v in orig.items(): by_sha[v['sha256']].append(f)
fn2ex = {os.path.basename(d['local_bundled_path']): d for d in demos.values()}
near = collections.defaultdict(set)
files = sorted(orig)
for i, a in enumerate(files):
    for b in files[i + 1:]:
        if orig[a]['sha256'] != orig[b]['sha256'] and orig[a]['ahash'] and orig[b]['ahash'] \
           and ham(orig[a]['ahash'], orig[b]['ahash']) <= 2:
            near[a].add(b); near[b].add(a)

SRC = ('UNKNOWN. No acquisition/generation record exists in the repository (no script, README or commit '
       'note). The commit history only says "upgrade all 190 workouts to 3D model videos". '
       'exercise_demonstrations.json self-declares "Free Exercise DB 3D Biomechanics Demonstration" and an '
       'r2.dev video_url; neither claim is backed by evidence here.')
LIC = 'UNVERIFIED. exercise_demonstrations.json says "MIT License" but no licence text, grant or source URL proof exists.'

entries, summary = [], collections.defaultdict(list)
for f in files:
    o, s, d = orig[f], ship.get(f, {}), fn2ex.get(f)
    flags = []
    if d is None: flags.append('not referenced by exercise_demonstrations.json (orphan file)')
    elif d['status'] != 'VERIFIED': flags.append(f'catalogue status={d["status"]}')
    group = [x for x in by_sha[o['sha256']] if x != f]
    if group:
        names = [fn2ex[x]['name'] if x in fn2ex else x + ' (orphan)' for x in group]
        flags.append('byte-identical to: ' + ', '.join(names)); summary['duplicate_hash'].append(f)
    if near[f]: flags.append('near-identical frame to: ' + ', '.join(sorted(near[f]))); summary['near_identical'].append(f)
    if (o.get('duration') or 0) < 3: flags.append('shorter than 3 s'); summary['short'].append(f)
    if not o['has_video']: flags.append('no video stream'); summary['no_video'].append(f)
    if o['has_audio']: flags.append('original had an audio track (stripped in shipped file)'); summary['had_audio'].append(f)
    if (o.get('duration') or 0) > 10: flags.append(f'original {o["duration"]:.1f}s, trimmed to 10 s'); summary['trimmed'].append(f)
    if o.get('width') != o.get('height') and o.get('width') != 1920: summary['odd_resolution'].append(f)
    if o.get('width') == o.get('height'): flags.append('square 480x480 source, different from the rest of the set'); summary['square'].append(f)
    entries.append({
        'exercise_id': d['exercise_id'] if d else None, 'exercise_name': d['name'] if d else None,
        'category': d['muscle_group'] if d else None, 'filename': f,
        'sha256': s.get('sha256'), 'original_sha256': o['sha256'],
        'source': SRC, 'license': LIC,
        'resolution': f'{s.get("width")}x{s.get("height")}', 'original_resolution': f'{o.get("width")}x{o.get("height")}',
        'duration_s': round(s.get('duration', 0), 2), 'original_duration_s': round(o.get('duration', 0), 2),
        'size_bytes': s.get('size'), 'original_size_bytes': o['size'],
        'codec': s.get('codec'), 'has_audio': s.get('has_audio'),
        'status': 'FLAGGED' if flags else 'UNVERIFIED', 'flags': flags})
m = {'generated_by': 'tool/build_manifest.py', 'note': 'No entry is VERIFIED: provenance and licence cannot be proven from this repository. Visual correctness was not judged by tooling.',
     'counts': {'entries': len(entries), 'FLAGGED': sum(e['status'] == 'FLAGGED' for e in entries), 'UNVERIFIED': sum(e['status'] == 'UNVERIFIED' for e in entries)},
     'summary': {k: sorted(v) for k, v in summary.items()},
     'duplicate_groups': [sorted(v) for v in by_sha.values() if len(v) > 1],
     'videos': entries}
json.dump(m, open('media_manifest.json', 'w'), indent=1)
print(m['counts'], {k: len(v) for k, v in summary.items()}, len(m['duplicate_groups']), 'dup groups')
