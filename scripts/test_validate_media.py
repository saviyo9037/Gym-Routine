"""Negative tests for validate_media.py using tiny generated fixtures.
Run: python scripts/test_validate_media.py"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

import imageio_ffmpeg

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, 'validate_media.py')
FF = imageio_ffmpeg.get_ffmpeg_exe()


def make_video(path, audio=False, seconds=4, size='320x180'):
    cmd = [FF, '-v', 'error', '-y', '-f', 'lavfi', '-i', f'testsrc=duration={seconds}:size={size}:rate=24']
    if audio:
        cmd += ['-f', 'lavfi', '-i', f'sine=duration={seconds}', '-c:a', 'aac']
    else:
        cmd += ['-an']
    cmd += ['-c:v', 'libx264', '-pix_fmt', 'yuv420p', path]
    subprocess.run(cmd, check=True)


class ValidatorTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.root, 'media_src/encoded'))
        os.makedirs(os.path.join(self.root, 'assets'))
        self.demos = {}
        self.entries = []

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def add(self, eid, name, filename=None, status='UNVERIFIED', **extra):
        key = f'videos/{eid}.mp4' if filename else None
        d = {'exercise_id': eid, 'name': name, 'has_video': bool(filename),
             'local_bundled_path': None, 'video_url': None, 'storage_path': key}
        self.demos[name] = d
        e = {'exercise_id': eid, 'exercise_name': name, 'filename': filename, 'status': status,
             'storage_path': key}
        e.update(extra)
        self.entries.append(e)

    def run_validator(self):
        with open(os.path.join(self.root, 'assets/exercise_demonstrations.json'), 'w') as f:
            json.dump(self.demos, f)
        with open(os.path.join(self.root, 'media_manifest.json'), 'w') as f:
            json.dump({'videos': self.entries}, f)
        r = subprocess.run([sys.executable, SCRIPT, '--root', self.root], capture_output=True, text=True)
        return r.returncode, r.stdout

    def vid(self, name, **kw):
        make_video(os.path.join(self.root, 'media_src/encoded', name), **kw)

    def test_clean_set_passes(self):
        self.vid('a.mp4')
        self.add(1, 'A', 'a.mp4')
        self.add(2, 'B', None, 'NO_VIDEO')
        code, out = self.run_validator()
        self.assertEqual(code, 0, out)

    def test_orphan_file_fails(self):
        self.vid('a.mp4')
        self.vid('orphan.mp4', seconds=5)
        self.add(1, 'A', 'a.mp4')
        code, out = self.run_validator()
        self.assertEqual(code, 1)
        self.assertIn('orphan video file', out)

    def test_duplicate_content_fails(self):
        self.vid('a.mp4')
        shutil.copy(os.path.join(self.root, 'media_src/encoded/a.mp4'),
                    os.path.join(self.root, 'media_src/encoded/b.mp4'))
        self.add(1, 'A', 'a.mp4')
        self.add(2, 'B', 'b.mp4')
        code, out = self.run_validator()
        self.assertEqual(code, 1)
        self.assertIn('identical video content', out)

    def test_missing_file_fails(self):
        self.add(1, 'A', 'gone.mp4')
        code, out = self.run_validator()
        self.assertEqual(code, 1)
        self.assertIn('file missing', out)

    def test_audio_track_fails(self):
        self.vid('a.mp4', audio=True)
        self.add(1, 'A', 'a.mp4')
        code, out = self.run_validator()
        self.assertEqual(code, 1)
        self.assertIn('audio track', out)

    def test_too_long_and_too_big_fail(self):
        self.vid('a.mp4', seconds=12, size='1280x720')
        self.add(1, 'A', 'a.mp4')
        code, out = self.run_validator()
        self.assertEqual(code, 1)
        self.assertIn('duration', out)
        self.assertIn('resolution', out)

    def test_verified_needs_evidence(self):
        self.vid('a.mp4')
        self.add(1, 'A', 'a.mp4', 'VERIFIED', source='UNKNOWN', license='UNVERIFIED')
        code, out = self.run_validator()
        self.assertEqual(code, 1)
        self.assertIn('VERIFIED requires a real source', out)
        self.assertIn('VERIFIED requires a confirmed licence', out)
        self.assertIn('requires non-empty evidence', out)
        self.assertIn('reviewed_by', out)

    def test_verified_with_evidence_passes(self):
        self.vid('a.mp4')
        self.add(1, 'A', 'a.mp4', 'VERIFIED', source='Own shoot 2026-11-01 (log in /evidence/a)',
                 license='Owned by developer', evidence=['shoot-log.pdf'], reviewed_by='J. Doe')
        code, out = self.run_validator()
        self.assertEqual(code, 0, out)

    def test_exercise_without_entry_fails(self):
        self.demos['Z'] = {'exercise_id': 9, 'name': 'Z', 'has_video': False}
        code, out = self.run_validator()
        self.assertEqual(code, 1)
        self.assertIn('no manifest entry', out)

    def test_no_video_must_not_map_a_video(self):
        self.add(1, 'A', None, 'NO_VIDEO')
        self.demos['A']['has_video'] = True
        code, out = self.run_validator()
        self.assertEqual(code, 1)
        self.assertIn('NO_VIDEO but demonstrations json', out)

    def test_video_inside_app_assets_fails(self):
        self.add(1, 'A', None, 'NO_VIDEO')
        os.makedirs(os.path.join(self.root, 'assets/videos'))
        make_video(os.path.join(self.root, 'assets/videos/x.mp4'))
        code, out = self.run_validator()
        self.assertEqual(code, 1)
        self.assertIn('video file inside app assets', out)

    def test_pubspec_bundling_a_video_path_fails(self):
        self.add(1, 'A', None, 'NO_VIDEO')
        with open(os.path.join(self.root, 'pubspec.yaml'), 'w') as f:
            f.write('flutter:\n  assets:\n    - assets/images/\n    - assets/videos/exercises/\n')
        code, out = self.run_validator()
        self.assertEqual(code, 1)
        self.assertIn('pubspec.yaml bundles a video path', out)

    def test_bundled_path_or_third_party_url_fails(self):
        self.vid('a.mp4')
        self.add(1, 'A', 'a.mp4')
        self.demos['A']['local_bundled_path'] = 'media_src/encoded/a.mp4'
        self.demos['A']['video_url'] = 'https://example.invalid/a.mp4'
        code, out = self.run_validator()
        self.assertEqual(code, 1)
        self.assertIn('still bundles', out)
        self.assertIn('third-party video_url', out)

    def test_wrong_storage_path_fails(self):
        self.vid('a.mp4')
        self.add(1, 'A', 'a.mp4')
        self.entries[0]['storage_path'] = 'videos/other.mp4'
        code, out = self.run_validator()
        self.assertEqual(code, 1)
        self.assertIn('manifest storage_path', out)


if __name__ == '__main__':
    unittest.main()
