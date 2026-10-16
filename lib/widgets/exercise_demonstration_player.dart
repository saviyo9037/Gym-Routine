import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/theme.dart';
import '../models/exercise_demonstration.dart';
import '../services/exercise_media_service.dart';
import 'exercise_image_widget.dart';

class ExerciseDemonstrationPlayer extends StatefulWidget {
  final int? exerciseId;
  final String exerciseName;
  final String? fallbackImagePath;
  final String? personalPhotoPath;
  final double height;
  final BorderRadius? borderRadius;
  final bool autoPlay;

  const ExerciseDemonstrationPlayer({
    super.key,
    this.exerciseId,
    required this.exerciseName,
    this.fallbackImagePath,
    this.personalPhotoPath,
    this.height = 260,
    this.borderRadius,
    this.autoPlay = false,
  });

  @override
  State<ExerciseDemonstrationPlayer> createState() =>
      _ExerciseDemonstrationPlayerState();
}

class _ExerciseDemonstrationPlayerState
    extends State<ExerciseDemonstrationPlayer>
    with WidgetsBindingObserver {
  final ExerciseMediaService _mediaService = ExerciseMediaService.instance;

  VideoPlayerController? _controller;
  DemonstrationMediaSource? _mediaSource;
  ExerciseDemonstration? _demonstration;

  int _initToken = 0;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;

  bool _isMuted = true; // Strict requirement: muted by default for gym use
  bool _showControls = true;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePlayer();
  }

  @override
  void didUpdateWidget(covariant ExerciseDemonstrationPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exerciseId != widget.exerciseId ||
        oldWidget.exerciseName != widget.exerciseName) {
      _initToken++;
      _disposeController();
      _initializePlayer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Pause playback when app is backgrounded
      if (_controller != null && _controller!.value.isPlaying) {
        _controller!.pause();
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _initializePlayer() async {
    final currentToken = ++_initToken;
    _disposeController();

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
      _controller = null;
    });

    try {
      await _mediaService.initialize();
      if (!mounted || currentToken != _initToken) return;

      ExerciseDemonstration? demo;
      if (widget.exerciseName.isNotEmpty) {
        demo = _mediaService.getDemonstration(widget.exerciseName);
      }
      if (demo == null && widget.exerciseId != null && widget.exerciseId! > 0) {
        demo = _mediaService.getDemonstrationById(widget.exerciseId!);
      }
      _demonstration = demo;

      final source = await _mediaService.resolveMediaSource(
        widget.exerciseName,
        exerciseId: widget.exerciseId,
        fallbackImagePath: widget.fallbackImagePath,
      );

      if (!mounted || currentToken != _initToken) return;
      _mediaSource = source;

      if (source.type == DemonstrationSourceType.photoFallback) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      VideoPlayerController controller;
      switch (source.type) {
        case DemonstrationSourceType.bundledAsset:
          controller = VideoPlayerController.asset(source.uri);
          break;
        case DemonstrationSourceType.downloadedFile:
          controller = VideoPlayerController.file(File(source.uri));
          break;
        case DemonstrationSourceType.remoteNetwork:
          controller = VideoPlayerController.networkUrl(Uri.parse(source.uri));
          break;
        case DemonstrationSourceType.photoFallback:
          return;
      }

      await controller.initialize();
      if (!mounted || currentToken != _initToken) {
        controller.dispose();
        return;
      }

      await controller.setVolume(_isMuted ? 0.0 : 1.0);
      await controller.setLooping(false);

      if (widget.autoPlay) {
        await controller.play();
      }

      controller.addListener(_videoListener);

      if (mounted && currentToken == _initToken) {
        setState(() {
          _controller = controller;
          _isLoading = false;
        });
      } else {
        controller.removeListener(_videoListener);
        controller.dispose();
      }
    } catch (e) {
      if (mounted && currentToken == _initToken) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Could not load demonstration video';
          _isLoading = false;
        });
      }
    }
  }

  void _videoListener() {
    if (mounted) {
      setState(() {});
    }
  }

  void _disposeController() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _initToken++;
    WidgetsBinding.instance.removeObserver(this);
    _disposeController();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      // If at end, seek to start before playing
      if (_controller!.value.position >= _controller!.value.duration) {
        _controller!.seekTo(Duration.zero);
      }
      _controller!.play();
    }
    setState(() {});
  }

  void _replay() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _controller!.seekTo(Duration.zero);
    _controller!.play();
    setState(() {});
  }

  void _toggleMute() {
    if (_controller == null) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  Future<void> _startDownload() async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      final file = await _mediaService.downloadDemonstration(
        widget.exerciseName,
        exerciseId: widget.exerciseId,
        onProgress: (prog) {
          if (mounted) {
            setState(() {
              _downloadProgress = prog;
            });
          }
        },
      );

      if (mounted && file != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.exerciseName} saved for offline use'),
            backgroundColor: AppColors.cardSurface,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Switch to downloaded controller seamlessly
        _disposeController();
        await _initializePlayer();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _deleteDownloaded() async {
    final deleted = await _mediaService.deleteDownloadedDemonstration(
      widget.exerciseName,
      exerciseId: widget.exerciseId,
    );
    if (deleted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline demonstration removed'),
          backgroundColor: AppColors.cardSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _disposeController();
      await _initializePlayer();
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(16);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        height: widget.height,
        width: double.infinity,
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Base Layer: Authentic Exercise Photo Thumbnail
            ExerciseImageWidget(
              imagePath: widget.fallbackImagePath,
              personalPhotoPath: widget.personalPhotoPath,
              exerciseName: widget.exerciseName,
              borderRadius: BorderRadius.zero,
              fit: BoxFit.cover,
            ),

            // 2. Video Player Layer (if video available and initialized)
            if (_controller != null && _controller!.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),

            // 3. Shading Gradient for Contrast
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),

            // 4. Content / Controls Overlay
            if (_hasError)
              _buildErrorOverlay()
            else if (_mediaSource?.type ==
                DemonstrationSourceType.photoFallback)
              _buildPhotoFallbackOverlay()
            else
              _buildVideoControlsOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoFallbackOverlay() {
    return Positioned(
      bottom: 12,
      left: 14,
      right: 14,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.photo_camera_rounded,
                color: AppColors.primary,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'High-Definition Photo Guide',
                    style: TextStyle(
                      color: AppColors.textMain,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Instructional video in production for next release',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage ?? 'Failed to play demonstration',
              style: const TextStyle(color: AppColors.textMain, fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _initializePlayer,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry Playback'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoControlsOverlay() {
    final controller = _controller;
    final isInitialized = controller != null && controller.value.isInitialized;
    final isPlaying = isInitialized && controller.value.isPlaying;
    final isEnded =
        isInitialized && controller.value.position >= controller.value.duration;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _showControls = !_showControls;
        });
      },
      child: Stack(
        children: [
          // Top Badges and Volume Control
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSourceBadge(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_mediaSource?.type ==
                        DemonstrationSourceType.remoteNetwork)
                      _buildDownloadButton(),
                    if (_mediaSource?.type ==
                        DemonstrationSourceType.downloadedFile)
                      IconButton(
                        tooltip: 'Remove offline file',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.textMuted,
                          size: 18,
                        ),
                        onPressed: _deleteDownloaded,
                      ),
                    const SizedBox(width: 4),
                    // Sound control (muted by default)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: IconButton(
                        icon: Icon(
                          _isMuted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: _isMuted ? Colors.white70 : AppColors.primary,
                          size: 18,
                        ),
                        tooltip: _isMuted ? 'Unmute' : 'Mute',
                        onPressed: _toggleMute,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Center Big Play / Pause / Replay Button
          Center(
            child: _isLoading
                ? const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  )
                : (_showControls || !isPlaying
                      ? AnimatedOpacity(
                          opacity: _showControls || !isPlaying ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary,
                                width: 1.5,
                              ),
                            ),
                            child: IconButton(
                              icon: Icon(
                                isEnded
                                    ? Icons.replay_rounded
                                    : (isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded),
                                color: AppColors.primary,
                                size: 34,
                              ),
                              onPressed: isEnded ? _replay : _togglePlayPause,
                            ),
                          ),
                        )
                      : const SizedBox.shrink()),
          ),

          // Bottom Timeline Scrubber and Controls
          if (isInitialized && (_showControls || !isPlaying))
            Positioned(
              bottom: 8,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // Play/Pause miniature toggle
                        InkWell(
                          onTap: isEnded ? _replay : _togglePlayPause,
                          child: Icon(
                            isEnded
                                ? Icons.replay_rounded
                                : (isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded),
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Duration Scrubber
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3.0,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6.0,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12.0,
                              ),
                              activeTrackColor: AppColors.primary,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: AppColors.primary,
                              overlayColor: AppColors.primary.withValues(
                                alpha: 0.2,
                              ),
                            ),
                            child: Slider(
                              value: controller.value.position.inMilliseconds
                                  .clamp(
                                    0,
                                    controller.value.duration.inMilliseconds,
                                  )
                                  .toDouble(),
                              min: 0.0,
                              max: controller.value.duration.inMilliseconds
                                  .toDouble(),
                              onChanged: (val) {
                                controller.seekTo(
                                  Duration(milliseconds: val.toInt()),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Timing label
                        Text(
                          '${_formatDuration(controller.value.position)} / ${_formatDuration(controller.value.duration)}',
                          style: const TextStyle(
                            color: AppColors.textMain,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSourceBadge() {
    final type = _mediaSource?.type;
    String label;
    IconData icon;
    Color color;

    switch (type) {
      case DemonstrationSourceType.bundledAsset:
        label = '⚡ Bundled Offline';
        icon = Icons.offline_bolt_rounded;
        color = Colors.greenAccent;
        break;
      case DemonstrationSourceType.downloadedFile:
        label = '✓ Offline Download';
        icon = Icons.check_circle_rounded;
        color = Colors.greenAccent;
        break;
      case DemonstrationSourceType.remoteNetwork:
        label = '☁ HD Video Demo';
        icon = Icons.play_circle_outline_rounded;
        color = AppColors.primary;
        break;
      case DemonstrationSourceType.photoFallback:
      default:
        label = 'Photo Reference';
        icon = Icons.photo_library_rounded;
        color = AppColors.textSecondary;
    }

    return Tooltip(
      message: _demonstration?.attribution.isNotEmpty == true
          ? 'License: ${_demonstration!.license} • ${_demonstration!.attribution}'
          : label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadButton() {
    if (_isDownloading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${(_downloadProgress * 100).toInt()}%',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: IconButton(
        icon: const Icon(
          Icons.file_download_outlined,
          color: Colors.white70,
          size: 18,
        ),
        tooltip: 'Download for offline use',
        onPressed: _startDownload,
      ),
    );
  }
}
