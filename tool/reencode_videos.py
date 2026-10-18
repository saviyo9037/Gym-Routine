"""Re-encode videos from media_src/ into media_src/encoded/: <=540p, H.264, no audio,
CRF 28, max 10 s, +faststart. Originals stay in media_src/ (gitignored)."""
import os, subprocess, imageio_ffmpeg
FF = imageio_ffmpeg.get_ffmpeg_exe()
src, dst = 'media_src', 'media_src/encoded'
for f in sorted(os.listdir(src)):
    if not f.endswith('.mp4'): continue
    r = subprocess.run([FF, '-v', 'error', '-y', '-i', os.path.join(src, f), '-t', '10', '-an',
        '-vf', "scale='min(960,iw)':'min(540,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
        '-c:v', 'libx264', '-preset', 'slow', '-crf', '28', '-pix_fmt', 'yuv420p',
        '-movflags', '+faststart', os.path.join(dst, f)], capture_output=True, text=True)
    if r.returncode: print('FAIL', f, r.stderr[:200])
