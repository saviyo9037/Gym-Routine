import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

import '../core/theme.dart';
import '../models/media_attachment.dart';
import '../services/database_service.dart';
import '../services/media_service.dart';
import 'voice_recorder_dialog.dart';

class AudioPlayerCard extends StatefulWidget {
  final MediaAttachment attachment;
  final VoidCallback? onUpdated;
  final VoidCallback? onDeleted;

  const AudioPlayerCard({
    super.key,
    required this.attachment,
    this.onUpdated,
    this.onDeleted,
  });

  @override
  State<AudioPlayerCard> createState() => _AudioPlayerCardState();
}

class _AudioPlayerCardState extends State<AudioPlayerCard> {
  final MediaService _mediaService = MediaService.instance;
  final DatabaseService _dbService = DatabaseService();

  late MediaAttachment _currentAttachment;
  String _resolvedPath = '';
  bool _fileExists = false;
  bool _isPlaying = false;
  bool _isPaused = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;

  @override
  void initState() {
    super.initState();
    _currentAttachment = widget.attachment;
    if (_currentAttachment.durationSeconds != null && _currentAttachment.durationSeconds! > 0) {
      _duration = Duration(seconds: _currentAttachment.durationSeconds!);
    }
    _resolvePath();
    _listenToPlayer();
  }

  Future<void> _resolvePath() async {
    final path = await _mediaService.resolveFilePath(_currentAttachment.filePath);
    final exists = await File(path).exists();
    if (mounted) {
      setState(() {
        _resolvedPath = path;
        _fileExists = exists;
      });
    }
  }

  void _listenToPlayer() {
    _stateSub = _mediaService.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      final isThisAudio = _mediaService.currentlyPlayingPath == _resolvedPath;
      setState(() {
        _isPlaying = isThisAudio && state == PlayerState.playing;
        _isPaused = isThisAudio && state == PlayerState.paused;
        if (state == PlayerState.completed && isThisAudio) {
          _position = Duration.zero;
        }
      });
    });

    _posSub = _mediaService.onPositionChanged.listen((pos) {
      if (!mounted) return;
      if (_mediaService.currentlyPlayingPath == _resolvedPath) {
        setState(() => _position = pos);
      }
    });

    _durSub = _mediaService.onDurationChanged.listen((dur) {
      if (!mounted) return;
      if (_mediaService.currentlyPlayingPath == _resolvedPath && dur > Duration.zero) {
        setState(() => _duration = dur);
      }
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    if (_isPlaying) {
      _mediaService.stopAudio();
    }
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (!_fileExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Audio file not found on device'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      if (_isPlaying) {
        await _mediaService.pauseAudio();
      } else if (_isPaused) {
        await _mediaService.resumeAudio();
      } else {
        await _mediaService.playAudio(_resolvedPath);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not play audio file'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _seekTo(double value) async {
    if (_duration > Duration.zero) {
      final pos = Duration(milliseconds: value.toInt());
      await _mediaService.seekAudio(pos);
      setState(() => _position = pos);
    }
  }

  Future<void> _replaceAudio() async {
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
              leading: const Icon(Icons.mic_rounded, color: AppColors.primary),
              title: const Text('Record Voice Note', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetCtx);
                VoiceRecorderDialog.show(
                  context,
                  title: 'Replace Voice Note',
                  onSaved: (audioPath, duration) async {
                    await _applyReplacement(audioPath, duration);
                  },
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.audio_file_rounded, color: AppColors.primary),
              title: const Text('Import Audio File', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final newPath = await _mediaService.pickAudioFile();
                if (newPath != null) {
                  await _applyReplacement(newPath, 30);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyReplacement(String newPath, int durationSeconds) async {
    if (_resolvedPath.isNotEmpty && _resolvedPath != newPath) {
      await _mediaService.deleteFile(_resolvedPath);
    }

    final updated = _currentAttachment.copyWith(
      filePath: newPath,
      durationSeconds: durationSeconds,
    );
    if (updated.id != null) {
      await _dbService.updateMediaAttachment(updated);
    }

    setState(() {
      _currentAttachment = updated;
      _resolvedPath = newPath;
      _fileExists = true;
      _duration = Duration(seconds: durationSeconds);
      _position = Duration.zero;
    });

    widget.onUpdated?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Audio memo replaced successfully'),
          backgroundColor: AppColors.successDark,
        ),
      );
    }
  }

  Future<void> _deleteAudio() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Delete Audio?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to delete this voice memo? This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
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
      if (_isPlaying) {
        await _mediaService.stopAudio();
      }
      if (_currentAttachment.id != null) {
        await _dbService.deleteMediaAttachment(_currentAttachment.id!);
      }
      await _mediaService.deleteFile(_resolvedPath);
      widget.onDeleted?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio memo deleted'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isPlaying ? AppColors.primary : AppColors.border,
          width: _isPlaying ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_rounded, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentAttachment.title,
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _currentAttachment.createdAt.length >= 10
                          ? _currentAttachment.createdAt.substring(0, 10)
                          : _currentAttachment.createdAt,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.sync_rounded, color: AppColors.textSecondary, size: 18),
                tooltip: 'Replace Audio',
                onPressed: _replaceAudio,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                tooltip: 'Delete Audio',
                onPressed: _deleteAudio,
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (!_fileExists)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Audio file not found on device',
                      style: TextStyle(color: Colors.amber, fontSize: 12),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Progress Bar
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: AppColors.border,
                thumbColor: AppColors.primary,
              ),
              child: Slider(
                value: _position.inMilliseconds.clamp(
                  0,
                  _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1,
                ).toDouble(),
                min: 0,
                max: _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                onChanged: _seekTo,
              ),
            ),

            // Controls & Timers
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_position),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10_rounded, color: AppColors.textSecondary, size: 22),
                        onPressed: () {
                          final newPos = _position - const Duration(seconds: 10);
                          _seekTo(newPos.inMilliseconds.clamp(0, _duration.inMilliseconds).toDouble());
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                          color: AppColors.primary,
                          size: 38,
                        ),
                        onPressed: _togglePlay,
                      ),
                      IconButton(
                        icon: const Icon(Icons.forward_10_rounded, color: AppColors.textSecondary, size: 22),
                        onPressed: () {
                          final newPos = _position + const Duration(seconds: 10);
                          _seekTo(newPos.inMilliseconds.clamp(0, _duration.inMilliseconds).toDouble());
                        },
                      ),
                    ],
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
