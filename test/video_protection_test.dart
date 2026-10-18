import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/services/video_access_service.dart';

import 'helpers/video_fakes.dart';

// MOCK-ONLY: signed URLs and downloads are fakes (FakeVideoBackend / FakeVideoDownloader).
// The cache logic itself (private dir, index, atomic files, purge) is the real code.
void main() {
  late VideoTestRig rig;
  setUp(() => rig = VideoTestRig());
  tearDown(() => rig.dispose());

  test('entitled: downloads on demand, one exercise only, then serves from the cache', () async {
    final f = await rig.service.ensureDownloaded(12);
    expect(f.existsSync(), isTrue);
    expect(f.path.startsWith(rig.cacheDir.path), isTrue);
    expect(rig.backend.requested, [12]);
    expect(await rig.service.cachedCount(), 1);
    expect(await rig.service.cachedBytes(), 2048);

    // second call: no new signed URL, no download
    final again = await rig.service.ensureDownloaded(12);
    expect(again.path, f.path);
    expect(rig.backend.requested, [12]);
    expect(rig.downloader.calls, 1);
    expect((await rig.service.cachedFile(12))!.path, f.path);
    expect(
      await rig.service.cachedFile(13),
      isNull,
      reason: 'other exercises are not downloaded',
    );
  });

  test('NOT entitled: refused before any network call', () async {
    rig.entitled = false;
    await expectLater(
      rig.service.ensureDownloaded(12),
      throwsA(
        isA<VideoAccessException>().having(
          (e) => e.kind,
          'kind',
          VideoAccessFailure.notEntitled,
        ),
      ),
    );
    expect(rig.backend.requested, isEmpty);
    expect(rig.downloader.calls, 0);
    expect(await rig.service.cachedFile(12), isNull);
  });

  test(
    'server says not entitled / no video / unavailable: nothing is stored',
    () async {
      for (final k in [
        VideoAccessFailure.notEntitled,
        VideoAccessFailure.noVideo,
        VideoAccessFailure.unavailable,
      ]) {
        rig.backend.fetchFailure = k;
        await expectLater(
          rig.service.ensureDownloaded(20),
          throwsA(isA<VideoAccessException>().having((e) => e.kind, 'kind', k)),
        );
      }
      expect(await rig.service.cachedCount(), 0);
      expect(rig.downloader.calls, 0);
    },
  );

  test('offline and interrupted downloads leave no partial file and can be retried', () async {
    rig.downloader.failWith = VideoAccessFailure.offline;
    await expectLater(
      rig.service.ensureDownloaded(12),
      throwsA(
        isA<VideoAccessException>().having(
          (e) => e.kind,
          'kind',
          VideoAccessFailure.offline,
        ),
      ),
    );
    expect(
      rig.cacheDir.listSync().where((e) => e.path.endsWith('.part')),
      isEmpty,
    );
    expect(await rig.service.cachedCount(), 0);

    rig.downloader.failWith = null;
    final f = await rig.service.ensureDownloaded(12);
    expect(f.existsSync(), isTrue);
  });

  test(
    'concurrent requests for the same exercise share one download',
    () async {
      final a = rig.service.ensureDownloaded(30);
      final b = rig.service.ensureDownloaded(30);
      final files = await Future.wait([a, b]);
      expect(files[0].path, files[1].path);
      expect(rig.downloader.calls, 1);
      expect(rig.backend.requested, [30]);
    },
  );

  test('entitlement ending DELETES the whole cache', () async {
    await rig.service.ensureDownloaded(12);
    await rig.service.ensureDownloaded(13);
    expect(await rig.service.cachedCount(), 2);

    rig.entitled = false;
    await rig.service.onEntitlementChanged(false);
    expect(rig.cacheDir.existsSync() ? rig.cacheDir.listSync() : [], isEmpty);
    rig.entitled = true;
    expect(await rig.service.cachedCount(), 0);
    expect(await rig.service.cachedFile(12), isNull);
  });

  test('entitled stays: onEntitlementChanged(true) and unknown state keep the cache', () async {
    await rig.service.ensureDownloaded(12);
    await rig.service.onEntitlementChanged(true);
    await rig.service.onEntitlementChanged(
      false,
      known: false,
    ); // not determined yet at app start
    expect(await rig.service.cachedCount(), 1);
  });

  test(
    'purgeIfNotEntitled at app start: kept while entitled, wiped when not',
    () async {
      await rig.service.ensureDownloaded(12);
      await rig.service.purgeIfNotEntitled();
      expect(await rig.service.cachedCount(), 1);
      rig.entitled = false;
      await rig.service.purgeIfNotEntitled();
      rig.entitled = true;
      expect(await rig.service.cachedCount(), 0);
    },
  );

  test('entitlement lost WHILE downloading: the file is discarded', () async {
    final slow = _RevokingDownloader(() => rig.entitled = false);
    final service = VideoAccessService(
      canAccessVideos: () => rig.entitled,
      fetchSignedUrl: rig.backend.fetch,
      downloader: slow,
      cacheDirectory: () async => rig.cacheDir,
    );
    await expectLater(
      service.ensureDownloaded(40),
      throwsA(
        isA<VideoAccessException>().having(
          (e) => e.kind,
          'kind',
          VideoAccessFailure.notEntitled,
        ),
      ),
    );
    rig.entitled = true;
    expect(await service.cachedCount(), 0);
    expect(
      rig.cacheDir.listSync().where((e) => e.path.endsWith('.mp4')),
      isEmpty,
    );
  });

  test('a cached file that was truncated/changed is not served', () async {
    final f = await rig.service.ensureDownloaded(12);
    await f.writeAsBytes([1, 2, 3]);
    expect(await rig.service.cachedFile(12), isNull);
    expect(f.existsSync(), isFalse, reason: 'invalid cache entry is removed');
  });

  test('a corrupt index is ignored, never crashes', () async {
    await rig.cacheDir.create(recursive: true);
    await File('${rig.cacheDir.path}/index.json').writeAsString('{broken');
    expect(await rig.service.cachedCount(), 0);
    final f = await rig.service.ensureDownloaded(12);
    expect(f.existsSync(), isTrue);
  });

  test('the cache never leaves the private directory it was given', () async {
    final f = await rig.service.ensureDownloaded(12);
    expect(f.parent.path, rig.cacheDir.path);
    expect(f.path.contains('..'), isFalse);
  });
}

class _RevokingDownloader implements VideoDownloader {
  _RevokingDownloader(this.revoke);
  final void Function() revoke;

  @override
  Future<int> download(
    Uri url,
    File target, {
    void Function(double progress)? onProgress,
  }) async {
    await target.writeAsBytes(List<int>.filled(100, 1));
    revoke(); // subscription ends mid-download
    return 100;
  }
}
