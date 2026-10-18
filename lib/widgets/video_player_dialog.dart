import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/theme.dart';
import '../models/media_attachment.dart';
import '../services/database_service.dart';
import '../services/media_service.dart';

class VideoPlayerDialog extends StatefulWidget {
  final String videoPath;
  final String title;
  final MediaAttachment? attachment;
  final VoidCallback? onUpdated;
  final VoidCallback? onDeleted;

  const VideoPlayerDialog({
    super.key,
    required this.videoPath,
    this.title = 'Workout Form Video',
    this.attachment,
    this.onUpdated,
    this.onDeleted,
  });

  static Future<void> show(
    BuildContext context, {
    required String videoPath,
    String title = 'Workout Form Video',
    MediaAttachment? attachment,
    VoidCallback? onUpdated,
    VoidCallback? onDeleted,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (_) => VideoPlayerDialog(
        videoPath: videoPath,
        title: title,
        attachment: attachment,
        onUpdated: onUpdated,
        onDeleted: onDeleted,
      ),
    );
  }

  @override
  State<VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<VideoPlayerDialog> {
  final MediaService _mediaService = MediaService.instance;
  final DatabaseService _dbService = DatabaseService();

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isEnded = false;
  String _resolvedPath = '';
  MediaAttachment? _attachment;

  @override
  void initState() {
    super.initState();
    _attachment = widget.attachment;
    _initPlayer(widget.videoPath);
  }

  Future<void> _initPlayer(String rawPath) async {
    setState(() {
      _isInitialized = false;
      _hasError = false;
      _isEnded = false;
    });

    try {
      final path = await _mediaService.resolveFilePath(rawPath);
      _resolvedPath = path;

      final file = File(path);
      if (!await file.exists()) {
        setState(() => _hasError = true);
        return;
      }

      await _controller?.dispose();
      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();

      _controller!.addListener(_onControllerUpdate);
      await _controller!.play();

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _onControllerUpdate() {
    if (!mounted || _controller == null) return;

    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;

    if (dur > Duration.zero && pos >= dur) {
      if (!_isEnded) {
        setState(() => _isEnded = true);
      }
    } else {
      if (_isEnded) {
        setState(() => _isEnded = false);
      }
    }
    setState(() {});
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;

    if (_isEnded) {
      _controller!.seekTo(Duration.zero);
      _controller!.play();
      setState(() => _isEnded = false);
    } else if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
  }

  Future<void> _replaceVideo() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(
                Icons.videocam_rounded,
                color: AppColors.primary,
              ),
              title: const Text(
                'Record New Video',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final newPath = await _mediaService.recordVideo();
                if (newPath != null) {
                  await _applyReplacement(newPath);
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.video_library_rounded,
                color: AppColors.primary,
              ),
              title: const Text(
                'Choose from Gallery',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final newPath = await _mediaService.pickVideoFromGallery();
                if (newPath != null) {
                  await _applyReplacement(newPath);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyReplacement(String newPath) async {
    if (_resolvedPath.isNotEmpty && _resolvedPath != newPath) {
      await _mediaService.deleteFile(_resolvedPath);
    }

    if (_attachment != null && _attachment!.id != null) {
      final updated = _attachment!.copyWith(filePath: newPath);
      await _dbService.updateMediaAttachment(updated);
      _attachment = updated;
    }

    widget.onUpdated?.call();
    await _initPlayer(newPath);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video replaced successfully'),
          backgroundColor: AppColors.successDark,
        ),
      );
    }
  }

  Future<void> _deleteVideo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text(
          'Delete Video?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this workout video? This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (_attachment != null && _attachment!.id != null) {
        await _dbService.deleteMediaAttachment(_attachment!.id!);
      }
      await _mediaService.deleteFile(_resolvedPath);
      widget.onDeleted?.call();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video deleted'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Player Area
          if (_hasError)
            Container(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.error,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Video file could not be loaded or is missing',
                    style: TextStyle(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _resolvedPath,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.sync_rounded, color: Colors.black),
                    label: const Text(
                      'Replace Video',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    onPressed: _replaceVideo,
                  ),
                ],
              ),
            )
          else if (!_isInitialized || _controller == null)
            const Padding(
              padding: EdgeInsets.all(56.0),
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          else
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio > 0
                        ? _controller!.value.aspectRatio
                        : 16 / 9,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(_controller!),
                        GestureDetector(
                          onTap: _togglePlayPause,
                          child: Container(
                            color: Colors.transparent,
                            child: AnimatedOpacity(
                              opacity:
                                  (_isEnded || !_controller!.value.isPlaying)
                                  ? 1.0
                                  : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isEnded
                                      ? Icons.replay_rounded
                                      : (_controller!.value.isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow_rounded),
                                  color: AppColors.primary,
                                  size: 48,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Progress Scrubber
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        trackHeight: 3,
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: AppColors.border,
                        thumbColor: AppColors.primary,
                      ),
                      child: Slider(
                        value: _controller!.value.position.inMilliseconds
                            .clamp(
                              0,
                              _controller!.value.duration.inMilliseconds > 0
                                  ? _controller!.value.duration.inMilliseconds
                                  : 1,
                            )
                            .toDouble(),
                        min: 0,
                        max: _controller!.value.duration.inMilliseconds > 0
                            ? _controller!.value.duration.inMilliseconds
                                  .toDouble()
                            : 1.0,
                        onChanged: (val) {
                          _controller!.seekTo(
                            Duration(milliseconds: val.toInt()),
                          );
                        },
                      ),
                    ),
                  ),

                  // Timers
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_controller!.value.position),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _formatDuration(_controller!.value.duration),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Actions row: Replace and Delete
                  const Divider(color: AppColors.border, height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        TextButton.icon(
                          icon: const Icon(
                            Icons.sync_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          label: const Text(
                            'Replace',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: _replaceVideo,
                        ),
                        TextButton.icon(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.redAccent,
                            size: 18,
                          ),
                          label: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                          onPressed: _deleteVideo,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
