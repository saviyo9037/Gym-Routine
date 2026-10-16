import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

class MediaService {
  static final MediaService instance = MediaService._internal();
  MediaService._internal() {
    _initAudioListeners();
  }

  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  AudioRecorder get audioRecorder => _audioRecorder;
  AudioPlayer get audioPlayer => _audioPlayer;

  String? _currentlyPlayingPath;
  String? get currentlyPlayingPath => _currentlyPlayingPath;

  PlayerState _playerState = PlayerState.stopped;
  PlayerState get playerState => _playerState;

  void _initAudioListeners() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      _playerState = state;
      if (state == PlayerState.stopped || state == PlayerState.completed) {
        _currentlyPlayingPath = null;
      }
    });
  }

  Stream<PlayerState> get onPlayerStateChanged =>
      _audioPlayer.onPlayerStateChanged;
  Stream<Duration> get onPositionChanged => _audioPlayer.onPositionChanged;
  Stream<Duration> get onDurationChanged => _audioPlayer.onDurationChanged;

  /// Get app-private directory for storing all RepTrack media
  Future<Directory> get _mediaDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(appDir.path, 'reptrack_media'));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir;
  }

  /// Bulletproof path resolver:
  /// Handles absolute paths, relative paths, and Android sandbox migrations across app restarts
  Future<String> resolveFilePath(String? storedPath) async {
    if (storedPath == null || storedPath.trim().isEmpty) return '';

    final path = storedPath.trim();

    // 1. Direct file check
    final direct = File(path);
    if (await direct.exists()) {
      return direct.path;
    }

    // 2. Check if it's an asset path
    if (path.startsWith('assets/')) {
      return path;
    }

    // 3. Resolve by filename in app-private media directory
    final fileName = p.basename(path);
    final mediaDir = await _mediaDirectory;
    final resolvedFile = File(p.join(mediaDir.path, fileName));
    if (await resolvedFile.exists()) {
      return resolvedFile.path;
    }

    // Return original path as fallback
    return path;
  }

  /// Copy any external or temporary file into app-private storage
  Future<String> copyToAppStorage(
    String sourcePath, {
    String prefix = 'media',
  }) async {
    final srcFile = File(sourcePath);
    if (!await srcFile.exists()) {
      throw Exception('Source file does not exist: $sourcePath');
    }

    final targetDir = await _mediaDirectory;

    // If source is already in the media directory, avoid duplicate copies
    if (p.isWithin(targetDir.path, srcFile.path)) {
      return srcFile.path;
    }

    final ext = p.extension(sourcePath);
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}$ext';
    final destinationPath = p.join(targetDir.path, fileName);

    final savedFile = await srcFile.copy(destinationPath);
    return savedFile.path;
  }

  // ------------------- PHOTO CAPTURE & IMPORT -------------------
  Future<String?> capturePhoto() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (photo == null) return null;
      return await copyToAppStorage(photo.path, prefix: 'photo');
    } catch (_) {
      return null;
    }
  }

  Future<String?> pickPhotoFromGallery() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (photo == null) return null;
      return await copyToAppStorage(photo.path, prefix: 'gallery');
    } catch (_) {
      return null;
    }
  }

  // ------------------- VIDEO RECORDING & IMPORT -------------------
  Future<String?> recordVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );
      if (video == null) return null;
      return await copyToAppStorage(video.path, prefix: 'video');
    } catch (_) {
      return null;
    }
  }

  Future<String?> pickVideoFromGallery() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );
      if (video == null) return null;
      return await copyToAppStorage(video.path, prefix: 'video');
    } catch (_) {
      return null;
    }
  }

  // ------------------- AUDIO RECORDING -------------------
  Future<bool> startAudioRecording(String targetFilePath) async {
    try {
      if (await _audioRecorder.hasPermission()) {
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
          path: targetFilePath,
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> stopAudioRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (path != null && await File(path).exists()) {
        return path;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> pauseAudioRecording() async {
    try {
      await _audioRecorder.pause();
    } catch (_) {}
  }

  Future<void> resumeAudioRecording() async {
    try {
      await _audioRecorder.resume();
    } catch (_) {}
  }

  Future<bool> isAudioRecording() async {
    return await _audioRecorder.isRecording();
  }

  Future<String> createAudioFilePath() async {
    final dir = await _mediaDirectory;
    return p.join(
      dir.path,
      'audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
  }

  Future<String?> pickAudioFile() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.audio);
      if (files.isNotEmpty && files.first.path != null) {
        return await copyToAppStorage(
          files.first.path!,
          prefix: 'audio_import',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ------------------- AUDIO PLAYBACK & CONTROL -------------------
  Future<void> playAudio(String filePath) async {
    final resolved = await resolveFilePath(filePath);
    final file = File(resolved);
    if (!await file.exists()) {
      throw Exception('Audio file not found: $filePath');
    }

    if (_currentlyPlayingPath == resolved &&
        _playerState == PlayerState.paused) {
      await _audioPlayer.resume();
      _playerState = PlayerState.playing;
    } else {
      await _audioPlayer.stop();
      _currentlyPlayingPath = resolved;
      await _audioPlayer.play(DeviceFileSource(resolved));
      _playerState = PlayerState.playing;
    }
  }

  Future<void> pauseAudio() async {
    await _audioPlayer.pause();
    _playerState = PlayerState.paused;
  }

  Future<void> resumeAudio() async {
    await _audioPlayer.resume();
    _playerState = PlayerState.playing;
  }

  Future<void> stopAudio() async {
    await _audioPlayer.stop();
    _playerState = PlayerState.stopped;
    _currentlyPlayingPath = null;
  }

  Future<void> seekAudio(Duration position) async {
    await _audioPlayer.seek(position);
  }

  // ------------------- FILE UTILITIES -------------------
  Future<bool> fileExists(String? filePath) async {
    if (filePath == null || filePath.trim().isEmpty) return false;
    final resolved = await resolveFilePath(filePath);
    return await File(resolved).exists();
  }

  Future<void> deleteFile(String? filePath) async {
    if (filePath == null || filePath.trim().isEmpty) return;
    try {
      final resolved = await resolveFilePath(filePath);
      final f = File(resolved);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }

  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
  }
}
