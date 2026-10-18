import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

class RestTimerSheet extends StatefulWidget {
  final int initialSeconds;
  final VoidCallback? onComplete;

  const RestTimerSheet({super.key, this.initialSeconds = 90, this.onComplete});

  static Future<void> show(
    BuildContext context, {
    int seconds = 90,
    VoidCallback? onComplete,
  }) {
    return showModalBottomSheet(
      context: context,
      isDismissible: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          RestTimerSheet(initialSeconds: seconds, onComplete: onComplete),
    );
  }

  @override
  State<RestTimerSheet> createState() => _RestTimerSheetState();
}

class _RestTimerSheetState extends State<RestTimerSheet> {
  late int _remaining;
  late int _total;
  Timer? _timer;
  bool _isRunning = true;

  @override
  void initState() {
    super.initState();
    _remaining = widget.initialSeconds;
    _total = widget.initialSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining > 0) {
        setState(() {
          _remaining--;
        });
      } else {
        _timer?.cancel();
        HapticFeedback.mediumImpact();
        widget.onComplete?.call();
        Navigator.pop(context);
      }
    });
  }

  void _togglePause() {
    setState(() {
      _isRunning = !_isRunning;
      if (_isRunning) {
        _startTimer();
      } else {
        _timer?.cancel();
      }
    });
  }

  void _addThirtySeconds() {
    setState(() {
      _remaining += 30;
      _total += 30;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? _remaining / _total : 0.0;
    final mins = (_remaining ~/ 60).toString().padLeft(2, '0');
    final secs = (_remaining % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.border, width: 1.5)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'REST TIMER',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 170,
                  height: 170,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 8,
                    backgroundColor: AppColors.cardSurface,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$mins:$secs',
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'RECOVER FOR NEXT SET',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addThirtySeconds,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('+30s'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textMain,
                      side: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _togglePause,
                    icon: Icon(
                      _isRunning
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.black,
                    ),
                    label: Text(_isRunning ? 'Pause' : 'Resume'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _timer?.cancel();
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: const Text('Skip'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
