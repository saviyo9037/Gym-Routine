"""Validate the encoded exercise videos (media_src/encoded, NOT bundled in the app) against
media_manifest.json and check that no video is bundled in the app assets.

Usage:  python scripts/validate_media.py [--root DIR] [--no-probe] [--strict]
Exit code 0 = no errors, 1 = errors (warnings never fail unless --strict).
Needs: pip install imageio-ffmpeg (bundled ffmpeg, no ffprobe needed).
"""
import hashlib
import json
import os
import re
import subprocess
import sys

VIDEO_DIR = 'media_src/encoded'  # gitignored; uploaded to the private bucket, never bundled
MANIFEST = 'media_manifest.json'
DEMOS = 'assets/exercise_demonstrations.json'
STATUSES = {'VERIFIED', 'UNVERIFIED', 'FLAGGED', 'NO_VIDEO'}
MAX_SECONDS = 10.05
MAX_W, MAX_H = 960, 540

errors, warnings = [], []


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def probe(path):
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    r = subprocess.run([ff, '-hide_banner', '-i', path], capture_output=True,
                       text=True, errors='replace')
    t = r.stderr
    info = {'audio': 'Audio:' in t}
    m = re.search(r'Duration: (\d+):(\d+):([\d.]+)', t)
    info['duration'] = (int(m[1]) * 3600 + int(m[2]) * 60 + float(m[3])) if m else None
    m = re.search(r'Video: (\w+)[^\n]*?, (\d{2,5})x(\d{2,5})', t)
    if m:
        info.update(codec=m[1], w=int(m[2]), h=int(m[3]))
    return info


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def check_not_bundled():
    """Videos must never ship inside the APK/AAB."""
    video_ext = ('.mp4', '.mov', '.webm', '.mkv', '.m4v', '.avi')
    for root, _dirs, files in os.walk('assets'):
        for f in files:
            if f.lower().endswith(video_ext):
                err(f'video file inside app assets: {os.path.join(root, f)}')
    if os.path.isfile('pubspec.yaml'):
        in_assets = False
        for line in open('pubspec.yaml', encoding='utf-8'):
            t = line.strip()
            if t.startswith('assets:'):
                in_assets = True
                continue
            if in_assets and t.startswith('- '):
                if 'video' in t.lower() or t.lower().endswith(video_ext):
                    err(f'pubspec.yaml bundles a video path: {t}')
            elif in_assets and t and not t.startswith('#'):
                in_assets = False


def main():
    if '--root' in sys.argv:
        os.chdir(sys.argv[sys.argv.index('--root') + 1])
    do_probe = '--no-probe' not in sys.argv
    have_files = os.path.isdir(VIDEO_DIR)
    if not have_files:
        warn(f'{VIDEO_DIR} not found (gitignored): file, hash and codec checks are skipped')
    check_not_bundled()
    manifest = json.load(open(MANIFEST, encoding='utf-8'))
    demos = json.load(open(DEMOS, encoding='utf-8'))
    entries = manifest.get('videos', [])

    by_id = {}
    for e in entries:
        eid = e.get('exercise_id')
        if eid is None:
            err(f'manifest entry without exercise_id: {e.get("filename")}')
            continue
        if eid in by_id:
            err(f'duplicate manifest entry for exercise {eid}')
        by_id[eid] = e

    # completeness: every catalogue exercise has an entry
    for name, d in demos.items():
        eid = d.get('exercise_id')
        if eid not in by_id:
            err(f'exercise {eid} "{name}" has no manifest entry')
    for eid, e in by_id.items():
        if e.get('status') not in STATUSES:
            err(f'exercise {eid}: invalid status {e.get("status")!r}')

    on_disk = set(f for f in os.listdir(VIDEO_DIR) if f.lower().endswith('.mp4')) \
        if have_files else set()
    listed = set()
    hashes = {}

    for eid, e in sorted(by_id.items()):
        status = e.get('status')
        fn = e.get('filename')
        name = e.get('exercise_name')
        d = demos.get(name, {})
        tag = f'#{eid} {name}'
        if status == 'NO_VIDEO':
            if fn:
                err(f'{tag}: NO_VIDEO but filename set ({fn})')
            if d.get('has_video') or d.get('local_bundled_path') or d.get('storage_path'):
                err(f'{tag}: NO_VIDEO but demonstrations json still maps a video')
            if e.get('storage_path'):
                err(f'{tag}: NO_VIDEO but manifest has a storage_path')
            continue
        if not fn:
            err(f'{tag}: status {status} but no filename')
            continue
        listed.add(fn)
        expected_key = f'videos/{eid}.mp4'
        if e.get('storage_path') != expected_key:
            err(f'{tag}: manifest storage_path {e.get("storage_path")!r} != {expected_key!r}')
        if d.get('storage_path') != expected_key:
            err(f'{tag}: demonstrations json storage_path {d.get("storage_path")!r} != {expected_key!r}')
        if d.get('local_bundled_path'):
            err(f'{tag}: demonstrations json still bundles {d.get("local_bundled_path")!r}')
        if d.get('video_url'):
            err(f'{tag}: demonstrations json has a third-party video_url (only the protected storage_path is allowed)')
        if not d.get('has_video'):
            err(f'{tag}: manifest lists a video but has_video is false in demonstrations json')
        if not have_files:
            continue
        path = os.path.join(VIDEO_DIR, fn)
        if not os.path.isfile(path):
            err(f'{tag}: file missing on disk: {path}')
            continue
        digest = sha256(path)
        if e.get('sha256') and e['sha256'] != digest:
            err(f'{tag}: sha256 differs from manifest (stale manifest or changed file)')
        if e.get('size_bytes') is not None and e['size_bytes'] != os.path.getsize(path):
            err(f'{tag}: size differs from manifest')
        hashes.setdefault(digest, []).append(tag)

        if do_probe:
            try:
                info = probe(path)
            except Exception as ex:  # noqa: BLE001
                err(f'{tag}: could not probe ({ex})')
                continue
            if info.get('codec') != 'h264':
                err(f'{tag}: codec {info.get("codec")!r}, expected h264')
            if info['audio']:
                err(f'{tag}: has an audio track')
            dur = info.get('duration')
            if dur is None or dur <= 0:
                err(f'{tag}: unreadable duration')
            elif dur > MAX_SECONDS:
                err(f'{tag}: duration {dur:.1f}s > 10s')
            elif dur < 3:
                warn(f'{tag}: very short ({dur:.1f}s)')
            if info.get('w') and (info['w'] > MAX_W or info['h'] > MAX_H):
                err(f'{tag}: resolution {info["w"]}x{info["h"]} > {MAX_W}x{MAX_H}')

        if status == 'VERIFIED':
            src = str(e.get('source') or '')
            lic = str(e.get('license') or '')
            ev = e.get('evidence')
            if not src or src.upper().startswith('UNKNOWN'):
                err(f'{tag}: VERIFIED requires a real source (got {src[:40]!r})')
            if not lic or lic.upper().startswith('UNVERIFIED'):
                err(f'{tag}: VERIFIED requires a confirmed licence (got {lic[:40]!r})')
            if not ev:
                err(f'{tag}: VERIFIED requires non-empty evidence (invoice, licence text/URL, shoot log...)')
            if e.get('reviewed_by') in (None, ''):
                err(f'{tag}: VERIFIED requires reviewed_by (the human who checked the movement)')
        elif '--strict' in sys.argv:
            warn(f'{tag}: {status} (not verified)')

    for digest, tags in hashes.items():
        if len(tags) > 1:
            err('identical video content shared by: ' + ', '.join(tags))

    for fn in sorted(on_disk - listed):
        err(f'orphan video file not in manifest: {fn}')

    verified = sum(1 for e in by_id.values() if e.get('status') == 'VERIFIED')
    unverified = sum(1 for e in by_id.values() if e.get('status') in ('UNVERIFIED', 'FLAGGED') and e.get('filename'))
    nov = sum(1 for e in by_id.values() if e.get('status') == 'NO_VIDEO')
    print(f'exercises in manifest: {len(by_id)}  files on disk: {len(on_disk)}')
    print(f'VERIFIED: {verified}   with video but unverified: {unverified}   NO_VIDEO: {nov}')
    if unverified:
        warn(f'{unverified} videos have no verified licence/source: do not upload them to the bucket or release with BUNDLED_VIDEOS=true until verified')
    for w in warnings[:30]:
        print('WARN ', w)
    if len(warnings) > 30:
        print(f'WARN  ... and {len(warnings) - 30} more')
    for x in errors:
        print('ERROR', x)
    print(f'{len(errors)} error(s), {len(warnings)} warning(s)')
    if errors or ('--strict' in sys.argv and warnings):
        sys.exit(1)


if __name__ == '__main__':
    main()
