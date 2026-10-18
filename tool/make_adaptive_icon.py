"""Generate adaptive-icon foreground layers from assets/icons/app_icon.png.
The artwork is placed inside the 66% safe zone of the 108dp canvas so no launcher
mask can crop it; the background layer is the app's #0A0A0A."""
import os
from PIL import Image

src = Image.open('assets/icons/app_icon.png').convert('RGBA')
res = 'android/app/src/main/res'
sizes = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
for dpi, px in sizes.items():
    canvas = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    art = int(px * 0.66)
    icon = src.resize((art, art), Image.LANCZOS)
    canvas.paste(icon, ((px - art) // 2, (px - art) // 2), icon)
    d = os.path.join(res, f'mipmap-{dpi}')
    os.makedirs(d, exist_ok=True)
    canvas.save(os.path.join(d, 'ic_launcher_foreground.png'))
os.makedirs(os.path.join(res, 'mipmap-anydpi-v26'), exist_ok=True)
open(os.path.join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/ic_launcher_background"/>\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
    '</adaptive-icon>\n')
open(os.path.join(res, 'values', 'ic_launcher_background.xml'), 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<resources>\n    <color name="ic_launcher_background">#0A0A0A</color>\n</resources>\n')
print('ok')
