"""Extract start/middle/end frames per video and build per-category contact sheets.
Usage: python tool/audit_frames.py [video_dir] [out_dir]  (local only)"""
import sys, os, json, re, subprocess, imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont
FF = imageio_ffmpeg.get_ffmpeg_exe()
vdir = sys.argv[1] if len(sys.argv) > 1 else 'media_src/encoded'
out = sys.argv[2] if len(sys.argv) > 2 else 'audit/frames'
tmp = 'audit/_tmp'; os.makedirs(out, exist_ok=True); os.makedirs(tmp, exist_ok=True)
probe = json.load(open('audit/probe.json'))
demos = json.load(open('assets/exercise_demonstrations.json'))
TW, TH = 213, 120
try: font = ImageFont.truetype('arial.ttf', 12)
except Exception: font = ImageFont.load_default()

def frame(f, t, dest):
    subprocess.run([FF, '-v', 'error', '-y', '-ss', f'{t:.2f}', '-i', f, '-frames:v', '1',
                    '-vf', f'scale={TW}:{TH}:force_original_aspect_ratio=decrease', dest], capture_output=True)

cats = {}
for name, d in demos.items():
    cats.setdefault(d['muscle_group'], []).append(d)
for cat, items in cats.items():
    items.sort(key=lambda d: d['exercise_id'])
    cell_w, cell_h, cols = TW * 3 + 8, TH + 34, 2
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * cell_w, rows * cell_h), (20, 20, 20))
    dr = ImageDraw.Draw(sheet)
    for i, d in enumerate(items):
        fn = os.path.basename(d['local_bundled_path'])
        path = os.path.join(vdir, fn)
        dur = probe.get(fn, {}).get('duration', 0) or 0
        x0, y0 = (i % cols) * cell_w, (i // cols) * cell_h
        for j, t in enumerate([0.0, max(dur / 2, 0), max(dur - 0.15, 0)]):
            tp = os.path.join(tmp, f'{d["exercise_id"]}_{j}.jpg')
            frame(path, t, tp)
            if os.path.exists(tp):
                im = Image.open(tp); sheet.paste(im, (x0 + j * TW + j * 2, y0))
        dr.text((x0 + 2, y0 + TH + 2), f'#{d["exercise_id"]} {d["name"]}', fill=(255, 255, 255), font=font)
        dr.text((x0 + 2, y0 + TH + 17), fn, fill=(150, 150, 150), font=font)
    sheet.save(os.path.join(out, re.sub(r'\W+', '_', cat.lower()) + '.jpg'), quality=82)
    print(cat, len(items))
