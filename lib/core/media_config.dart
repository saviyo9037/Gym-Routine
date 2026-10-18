/// Single switch for bundled demonstration videos.
///
/// When `false` every exercise behaves as NO_VIDEO: the photo fallback is
/// shown, no video controller is created and no remote URL is streamed. No
/// video file is deleted, so flipping the flag back restores the videos.
///
/// Default `true` (current behaviour). For a PUBLIC release leave it `false`
/// unless the licence of every bundled video is confirmed (see
/// RELEASE_CHECKLIST.md / MEDIA_GUIDE.md):
///   flutter build appbundle --release --dart-define=BUNDLED_VIDEOS=false
const bool kBundledVideosEnabled = bool.fromEnvironment(
  'BUNDLED_VIDEOS',
  defaultValue: true,
);
