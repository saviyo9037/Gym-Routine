import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/media_service.dart';

class VoiceRecorderDialog extends StatefulWidget {
  final String title;
  final Function(String audioPath, int durationSeconds) onSaved;

  const VoiceRecorderDialog({
    super.key,
    this.title = 'Record Trainer Note',
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    String title = 'Record Trainer Note',
    required Function(String audioPath, int durationSeconds) onSaved,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => VoiceRecorderDialog(title: title, onSaved: onSaved),
    );
  }

  @override
  State<VoiceRecorderDialog> createState() => _VoiceRecorderDialogState();
}

class _VoiceRecorderDialogState extends State<VoiceRecorderDialog> {
  final MediaService _mediaService = MediaService.instance;

  bool _isRecording = false;
  bool _isPaused = false;
  bool _hasRecorded = false;
  bool _isPlaying = false;

  String? _recordedFilePath;
  int _secondsElapsed = 0;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _mediaService.stopAudio();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final filePath = await _mediaService.createAudioFilePath();
    final success = await _mediaService.startAudioRecording(filePath);
    if (success) {
      setState(() {
        _recordedFilePath = filePath;
        _isRecording = true;
        _isPaused = false;
        _secondsElapsed = 0;
      });
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _secondsElapsed++;
        });
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission required or recording failed'),
          ),
        );
      }
    }
  }

  Future<void> _pauseResumeRecording() async {
    if (_isPaused) {
      await _mediaService.resumeAudioRecording();
      setState(() => _isPaused = false);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _secondsElapsed++);
      });
    } else {
      await _mediaService.pauseAudioRecording();
      _ticker?.cancel();
      setState(() => _isPaused = true);
    }
  }

  Future<void> _stopRecording() async {
    _ticker?.cancel();
    final path = await _mediaService.stopAudioRecording();
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _hasRecorded = true;
      if (path != null) {
        _recordedFilePath = path;
      }
    });
  }

  Future<void> _togglePlayback() async {
    if (_recordedFilePath == null) return;
    if (_isPlaying) {
      await _mediaService.stopAudio();
      setState(() => _isPlaying = false);
    } else {
      setState(() => _isPlaying = true);
      await _mediaService.playAudio(_recordedFilePath!);
      _mediaService.audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _isPlaying = false);
      });
    }
  }

  Future<void> _importAudio() async {
    final path = await _mediaService.pickAudioFile();
    if (path != null) {
      setState(() {
        _recordedFilePath = path;
        _hasRecorded = true;
        _secondsElapsed = 30; // estimated duration
      });
    }
  }

  void _save() {
    if (_recordedFilePath != null) {
      widget.onSaved(_recordedFilePath!, _secondsElapsed);
      Navigator.pop(context);
    }
  }

  void _discard() async {
    if (_recordedFilePath != null && !_hasRecorded) {
      await _mediaService.deleteFile(_recordedFilePath);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final mins = (_secondsElapsed ~/ 60).toString().padLeft(2, '0');
    final secs = (_secondsElapsed % 60).toString().padLeft(2, '0');

    return Dialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.title.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: _discard,
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Microphone animation ring
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.cardSurface,
                border: Border.all(
                  color: _isRecording ? AppColors.primary : AppColors.border,
                  width: 2,
                ),
              ),
              child: Center(
                child: Icon(
                  _hasRecorded
                      ? (_isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded)
                      : (_isRecording
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded),
                  color: _isRecording || _isPlaying
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  size: 42,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '$mins:$secs',
              style: const TextStyle(
                color: AppColors.textMain,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isRecording
                  ? (_isPaused ? 'Recording Paused' : 'Listening to Trainer...')
                  : (_hasRecorded
                        ? 'Recording Ready for Review'
                        : 'Tap to start recording'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            // Action controls
            if (!_hasRecorded && !_isRecording) ...[
              ElevatedButton.icon(
                onPressed: _startRecording,
                icon: const Icon(Icons.mic_rounded, color: Colors.black),
                label: const Text('Start Recording'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _importAudio,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('Import Audio File'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ] else if (_isRecording) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pauseResumeRecording,
                      icon: Icon(
                        _isPaused ? Icons.play_arrow : Icons.pause,
                        size: 18,
                      ),
                      label: Text(_isPaused ? 'Resume' : 'Pause'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _stopRecording,
                      icon: const Icon(Icons.stop_rounded, color: Colors.black),
                      label: const Text('Stop & Review'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (_hasRecorded) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _togglePlayback,
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 18,
                      ),
                      label: Text(_isPlaying ? 'Pause' : 'Play'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _hasRecorded = false;
                          _secondsElapsed = 0;
                        });
                        _startRecording();
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retake'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check_rounded, color: Colors.black),
                label: const Text('Save Audio Note'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
