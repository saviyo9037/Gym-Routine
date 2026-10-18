"""Size breakdown of an APK/AAB by top-level category (uncompressed vs compressed bytes)."""
import sys, zipfile, collections
path = sys.argv[1]
z = zipfile.ZipFile(path)
cat = collections.defaultdict(lambda: [0, 0, 0])
big = []
def key(n):
    if n.startswith('lib/'): return 'native libs ' + n.split('/')[1]
    if n.startswith('assets/flutter_assets/assets/videos'): return 'flutter assets: videos'
    if n.startswith('assets/flutter_assets/assets/images'): return 'flutter assets: images'
    if n.startswith('assets/flutter_assets/'):
        if n.endswith('kernel_blob.bin'): return 'flutter kernel_blob.bin (debug Dart code)'
        if n.endswith('.json'): return 'flutter assets: json'
        return 'flutter assets: other (fonts, shaders)'
    if n.startswith('assets/'): return 'other assets'
    if n.endswith('.dex'): return 'dex (Java/Kotlin code)'
    if n.startswith('res/') or n == 'resources.arsc': return 'android resources'
    if n.startswith('META-INF/'): return 'META-INF'
    return 'other'
for i in z.infolist():
    c = cat[key(i.filename)]
    c[0] += 1; c[1] += i.file_size; c[2] += i.compress_size
    big.append((i.compress_size, i.filename))
tot = sum(v[2] for v in cat.values())
import os
print(f'{os.path.basename(path)}: file {os.path.getsize(path)/1e6:.1f} MB, zip entries compressed {tot/1e6:.1f} MB')
for k, v in sorted(cat.items(), key=lambda kv: -kv[1][2]):
    print(f'  {k:46} {v[0]:5} files  {v[1]/1e6:8.1f} MB raw  {v[2]/1e6:8.1f} MB stored')
print('largest entries:')
for s, n in sorted(big, reverse=True)[:8]:
    print(f'  {s/1e6:7.2f} MB  {n}')
