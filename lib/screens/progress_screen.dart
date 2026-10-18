import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/cloud_services.dart';
import '../services/premium_service.dart';
import '../services/stats_service.dart';
import '../widgets/premium_upsell.dart';

/// Premium: per-exercise progress charts built from [StatsService] data.
/// Free users see an upsell instead (nothing is computed for them).
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

enum _Metric { weight, volume, oneRm }

class _ProgressScreenState extends State<ProgressScreen> {
  final _stats = StatsService();
  List<ExerciseProgressEntry> _entries = [];
  ExerciseProgress? _progress;
  int? _selected;
  _Metric _metric = _Metric.weight;
  bool _loading = true;
  String? _error;

  bool get _allowed =>
      CloudServices.premium.canUse(PremiumFeature.advancedStats);

  @override
  void initState() {
    super.initState();
    CloudServices.premium.addListener(_onPremium);
    if (_allowed) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    CloudServices.premium.removeListener(_onPremium);
    super.dispose();
  }

  void _onPremium() {
    if (!mounted) return;
    if (_allowed && _entries.isEmpty && !_loading) _load();
    setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _stats.exercisesWithHistory();
      ExerciseProgress? progress;
      int? selected;
      if (entries.isNotEmpty) {
        selected = entries.first.exerciseId;
        progress = await _stats.exerciseProgress(selected);
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _selected = selected;
        _progress = progress;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your progress.';
      });
    }
  }

  Future<void> _select(int id) async {
    setState(() => _selected = id);
    try {
      final p = await _stats.exerciseProgress(id);
      if (mounted && _selected == id) setState(() => _progress = p);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load this exercise.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('PROGRESS & CHARTS')),
      body: _body(),
    );
  }

  Widget _body() {
    if (!_allowed) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: PremiumUpsellCard(
            title: 'Progress charts are a Premium feature',
            body:
                'See your best weight, estimated 1RM and volume for every '
                'exercise over time. Your workout history itself stays free.',
          ),
        ),
      );
    }
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Finish a workout to see your progress here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final p = _progress;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<int>(
          initialValue: _selected,
          isExpanded: true,
          dropdownColor: AppColors.surfaceElevated,
          decoration: const InputDecoration(labelText: 'Exercise'),
          items: [
            for (final e in _entries)
              DropdownMenuItem(
                value: e.exerciseId,
                child: Text(
                  '${e.exerciseName} (${e.sessions})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) _select(v);
          },
        ),
        const SizedBox(height: 12),
        if (p != null && p.hasData) ...[
          if (!p.isCardio)
            SegmentedButton<_Metric>(
              segments: const [
                ButtonSegment(value: _Metric.weight, label: Text('Best kg')),
                ButtonSegment(value: _Metric.oneRm, label: Text('Est. 1RM')),
                ButtonSegment(value: _Metric.volume, label: Text('Volume')),
              ],
              selected: {_metric},
              onSelectionChanged: (s) => setState(() => _metric = s.first),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: Semantics(
              label: 'Progress chart for ${p.exerciseName}',
              child: CustomPaint(
                painter: LineChartPainter(
                  values: _values(p),
                  labels: [for (final x in p.points) x.date],
                ),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _summary(p),
        ] else
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No completed sets for this exercise yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }

  List<double?> _values(ExerciseProgress p) {
    if (p.isCardio) {
      return [for (final x in p.points) x.volumeKg];
    }
    switch (_metric) {
      case _Metric.weight:
        return [for (final x in p.points) x.bestWeightKg];
      case _Metric.oneRm:
        return [for (final x in p.points) x.estimatedOneRepMaxKg];
      case _Metric.volume:
        return [for (final x in p.points) x.volumeKg];
    }
  }

  Widget _summary(ExerciseProgress p) {
    String f(double? v) => v == null ? '–' : v.toStringAsFixed(1);
    return Material(
      color: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${p.points.length} sessions',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              'Best weight: ${f(p.bestWeightKg)} kg',
              style: const TextStyle(color: AppColors.textMain),
            ),
            Text(
              'Best estimated 1RM: ${f(p.bestOneRepMaxKg)} kg',
              style: const TextStyle(color: AppColors.textMain),
            ),
            if (p.volumeTrendKg != null)
              Text(
                'Last session volume: '
                '${p.volumeTrendKg! >= 0 ? '+' : ''}${f(p.volumeTrendKg)} kg vs previous',
                style: const TextStyle(color: AppColors.textMain),
              ),
          ],
        ),
      ),
    );
  }
}

/// Minimal dependency-free line chart (null values leave gaps).
class LineChartPainter extends CustomPainter {
  LineChartPainter({required this.values, required this.labels});

  final List<double?> values;
  final List<String> labels;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0, bottom = 22.0, pad = 8.0;
    final plot = Rect.fromLTWH(
      left,
      pad,
      size.width - left - pad,
      size.height - bottom - pad,
    );
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    final nums = values.whereType<double>().toList();
    if (nums.isEmpty) return;
    var minV = nums.reduce((a, b) => a < b ? a : b);
    var maxV = nums.reduce((a, b) => a > b ? a : b);
    if (maxV - minV < 0.001) {
      maxV += 1;
      minV = (minV - 1).clamp(0, double.infinity);
    }
    for (var i = 0; i <= 3; i++) {
      final y = plot.bottom - plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _text(
        canvas,
        (minV + (maxV - minV) * i / 3).toStringAsFixed(0),
        Offset(2, y - 6),
      );
    }
    double x(int i) => values.length == 1
        ? plot.center.dx
        : plot.left + plot.width * i / (values.length - 1);
    double y(double v) =>
        plot.bottom - plot.height * (v - minV) / (maxV - minV);

    final line = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = AppColors.primary;
    Offset? prev;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        prev = null;
        continue;
      }
      final pt = Offset(x(i), y(v));
      if (prev != null) canvas.drawLine(prev, pt, line);
      canvas.drawCircle(pt, 3.5, dot);
      prev = pt;
    }
    if (labels.isNotEmpty) {
      _text(canvas, labels.first, Offset(plot.left, size.height - 16));
      if (labels.length > 1) {
        _text(canvas, labels.last, Offset(plot.right - 62, size.height - 16));
      }
    }
  }

  void _text(Canvas c, String s, Offset o) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(LineChartPainter old) =>
      old.values != values || old.labels != labels;
}
