"""Probe bundled exercise videos with ffmpeg (no ffprobe available). Local only.
Usage: python tool/media_probe.py [video_dir] [out_json]"""
import sys, os, re, json, hashlib, subprocess, imageio_ffmpeg
FF = imageio_ffmpeg.get_ffmpeg_exe()
vdir = sys.argv[1] if len(sys.argv) > 1 else 'media_src/encoded'
out = sys.argv[2] if len(sys.argv) > 2 else 'audit/probe.json'

def probe(p):
    r = subprocess.run([FF, '-hide_banner', '-i', p], capture_output=True, text=True, errors='replace')
    t = r.stderr
    info = {'has_video': False, 'has_audio': 'Audio:' in t}
    m = re.search(r'Duration: (\d+):(\d+):([\d.]+)', t)
    if m: info['duration'] = int(m[1]) * 3600 + int(m[2]) * 60 + float(m[3])
    m = re.search(r'Stream #\S+.*?Video: (\w+)[^,]*(?:, [^,]*)*?, (\d{2,5})x(\d{2,5})', t)
    if m:
        info.update(has_video=True, codec=m[1], width=int(m[2]), height=int(m[3]))
    m = re.search(r'(\d+(?:\.\d+)?) fps', t)
    if m: info['fps'] = float(m[1])
    m = re.search(r'bitrate: (\d+) kb/s', t)
    if m: info['bitrate_kbps'] = int(m[1])
    info['probe_ok'] = r.returncode in (0, 1) and 'Duration' in t and 'Invalid data' not in t
    return info

def phash(p):
    # 8x8 grayscale of a frame at 1s, packed as 64-bit average hash
    r = subprocess.run([FF, '-v', 'error', '-ss', '1', '-i', p, '-frames:v', '1', '-vf', 'scale=8:8,format=gray',
                        '-f', 'rawvideo', '-'], capture_output=True)
    b = r.stdout
    if len(b) != 64: return None
    avg = sum(b) / 64
    return ''.join('1' if x > avg else '0' for x in b)

res = {}
for f in sorted(os.listdir(vdir)):
    if not f.endswith('.mp4'): continue
    p = os.path.join(vdir, f)
    d = probe(p)
    d['size'] = os.path.getsize(p)
    d['sha256'] = hashlib.sha256(open(p, 'rb').read()).hexdigest()
    d['ahash'] = phash(p)
    res[f] = d
os.makedirs(os.path.dirname(out), exist_ok=True)
json.dump(res, open(out, 'w'), indent=1)
print(len(res), 'probed')
