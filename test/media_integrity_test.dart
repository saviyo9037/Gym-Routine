import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/data/seed_data.dart';

/// Checks the demonstration-video bookkeeping (videos are NOT bundled: encoded files live in
/// media_src/encoded, uploaded to a private bucket) against the real catalogue
/// (SeedData.exercises) and media_manifest.json. These tests do NOT judge
/// whether a video shows the right movement; that needs human review of
/// audit/frames/.
void main() {
  late List<Map<String, dynamic>> manifest;
  late Map<String, dynamic> demos;

  setUpAll(() {
    final m = json.decode(
      File('media_manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    manifest = (m['videos'] as List).cast<Map<String, dynamic>>();
    demos = json.decode(
      File('assets/exercise_demonstrations.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  test('exact per-category counts come from the real catalogue', () {
    final counts = <String, int>{};
    for (final e in SeedData.exercises) {
      counts[e.muscleGroupName] = (counts[e.muscleGroupName] ?? 0) + 1;
    }
    expect(counts, {
      'Chest': 22,
      'Back': 10,
      'Lats': 9,
      'Upper Back and Traps': 10,
      'Shoulders': 17,
      'Biceps': 22,
      'Triceps': 19,
      'Forearms': 9,
      'Quadriceps': 16,
      'Hamstrings': 11,
      'Glutes': 9,
      'Calves': 7,
      'Abs and Core': 20,
      'Full Body': 9,
      'Cardio': 11,
    });
    expect(SeedData.exercises.length, 201);
    // The manifest must agree with the catalogue per category.
    final manifestCounts = <String, int>{};
    for (final v in manifest.where((v) => v['category'] != null)) {
      manifestCounts[v['category'] as String] =
          (manifestCounts[v['category'] as String] ?? 0) + 1;
    }
    expect(manifestCounts, counts);
    expect(manifest.where((v) => v['status'] == 'NO_VIDEO').length, 78);
    expect(manifest.where((v) => v['status'] != 'NO_VIDEO').length, 123);
    expect(manifest.where((v) => v['status'] == 'NO_VIDEO').length, 78);
    expect(manifest.where((v) => v['status'] != 'NO_VIDEO').length, 123);
  });

  test(
    'every exercise has a manifest entry that matches the demonstrations json',
    () {
      final byId = {
        for (final v in manifest.where((v) => v['exercise_id'] != null))
          v['exercise_id'] as int: v,
      };
      for (final e in SeedData.exercises) {
        final entry = byId[e.id];
        expect(
          entry,
          isNotNull,
          reason: 'No manifest entry for ${e.name} (#${e.id})',
        );
        expect(entry!['exercise_name'], e.name);
        final demo = demos[e.name] as Map<String, dynamic>?;
        expect(
          demo,
          isNotNull,
          reason: '${e.name} missing from demonstrations',
        );
        // Nothing is bundled any more, for any exercise.
        expect(demo!['local_bundled_path'], isNull, reason: e.name);
        expect(
          demo['video_url'],
          isNull,
          reason: '${e.name}: no third-party stream URL',
        );
        if (entry['status'] == 'NO_VIDEO') {
          expect(entry['filename'], isNull, reason: e.name);
          expect(entry['storage_path'], isNull, reason: e.name);
          expect(demo['has_video'], false, reason: e.name);
          expect(demo['storage_path'], isNull, reason: e.name);
        } else {
          expect(entry['storage_path'], 'videos/${e.id}.mp4', reason: e.name);
          expect(demo['storage_path'], entry['storage_path'], reason: e.name);
          expect(demo['has_video'], true, reason: e.name);
        }
      }
    },
  );

  test('NO video file or video path is part of the Flutter asset list', () {
    // pubspec.yaml assets
    final lines = File('pubspec.yaml').readAsLinesSync();
    var inAssets = false;
    final declared = <String>[];
    for (final raw in lines) {
      final t = raw.trim();
      if (t.startsWith('assets:')) {
        inAssets = true;
        continue;
      }
      if (inAssets && t.startsWith('- ')) {
        declared.add(t.substring(2).trim());
      } else if (inAssets && t.isNotEmpty && !t.startsWith('#')) {
        inAssets = false;
      }
    }
    expect(declared, isNotEmpty);
    for (final d in declared) {
      expect(
        d.toLowerCase().contains('video'),
        isFalse,
        reason: 'pubspec bundles $d',
      );
      expect(d.toLowerCase().endsWith('.mp4'), isFalse, reason: d);
    }
    // ... and no video file exists anywhere under assets/ (so none could be bundled).
    const videoExt = ['.mp4', '.mov', '.webm', '.mkv', '.m4v', '.avi'];
    final offenders = Directory('assets')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => videoExt.any((x) => f.path.toLowerCase().endsWith(x)))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty, reason: 'videos inside app assets: $offenders');
    expect(Directory('assets/videos').existsSync(), isFalse);
  });

  test(
    'encoded videos (when media_src is present locally) match the manifest',
    () {
      final dir = Directory('media_src/encoded');
      if (!dir.existsSync()) {
        // media_src is gitignored: nothing to verify on a fresh clone.
        return;
      }
      final listed = <String>{};
      for (final v in manifest.where((v) => v['status'] != 'NO_VIDEO')) {
        listed.add(v['filename'] as String);
        final f = File('media_src/encoded/${v['filename']}');
        expect(f.existsSync(), isTrue, reason: 'Missing ${f.path}');
        final len = f.lengthSync();
        expect(len, greaterThan(1024), reason: '${f.path} is too small');
        expect(
          len,
          v['size_bytes'],
          reason: 'Manifest size is stale for ${f.path}',
        );
        final head = f.openSync()..setPositionSync(4);
        final tag = String.fromCharCodes(head.readSync(4));
        head.closeSync();
        expect(
          tag,
          'ftyp',
          reason: '${f.path} is not a readable MP4 container',
        );
      }
      final onDisk = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
      expect(onDisk, listed, reason: 'encoded files differ from the manifest');
    },
  );

  test(
    'no duplicate video content across different exercises (local encoded set)',
    () {
      final dir = Directory('media_src/encoded');
      if (!dir.existsSync()) return;
      final byLength = <int, List<String>>{};
      for (final v in manifest.where((v) => v['status'] != 'NO_VIDEO')) {
        final path = 'media_src/encoded/${v['filename']}';
        byLength.putIfAbsent(File(path).lengthSync(), () => []).add(path);
      }
      final duplicates = <String>[];
      for (final group in byLength.values.where((g) => g.length > 1)) {
        final bytes = {for (final p in group) p: File(p).readAsBytesSync()};
        for (var i = 0; i < group.length; i++) {
          for (var j = i + 1; j < group.length; j++) {
            if (listEquals(bytes[group[i]], bytes[group[j]])) {
              duplicates.add('${group[i]} == ${group[j]}');
            }
          }
        }
      }
      expect(
        duplicates,
        isEmpty,
        reason: 'Identical videos reused: $duplicates',
      );
    },
  );

  test('manifest never claims VERIFIED without provenance evidence', () {
    for (final v in manifest) {
      expect(v['status'], isNot('VERIFIED'), reason: '${v['exercise_name']}');
    }
  });
}
