import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/exercise.dart';
import '../models/training_plan.dart';
import '../services/exercise_terminology_service.dart';
import '../services/training_plan_service.dart';
import '../widgets/exercise_picker_sheet.dart';

double? parseDecimal(String raw) =>
    double.tryParse(raw.trim().replaceAll(',', '.'));

/// Create / edit one weekly training plan.
///
/// The user chooses which weekdays are training or rest days and builds an
/// unlimited, re-orderable exercise list per training day.
class TrainingPlanEditorScreen extends StatefulWidget {
  const TrainingPlanEditorScreen({super.key, this.planId});

  final int? planId;

  @override
  State<TrainingPlanEditorScreen> createState() =>
      _TrainingPlanEditorScreenState();
}

class _TrainingPlanEditorScreenState extends State<TrainingPlanEditorScreen> {
  static const _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final _service = TrainingPlanService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _dayTitleController = TextEditingController();

  TrainingPlan _plan = TrainingPlan(name: '');
  List<TrainingPlanDay> _days = TrainingPlan.defaultDays();
  int _selectedWeekday = 1;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _dayTitleController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await ExerciseTerminologyService.instance.initialize();
      if (widget.planId != null) {
        final p = await _service.getPlan(widget.planId!);
        if (p == null) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _loadError = 'This plan no longer exists.';
          });
          return;
        }
        _plan = p;
        _days = List.of(p.days);
        _nameController.text = p.name;
        _notesController.text = p.notes ?? '';
      }
      _syncDayTitle();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load the plan.';
      });
    }
  }

  TrainingPlanDay get _day => _days[_selectedWeekday - 1];

  void _setDay(TrainingPlanDay d) {
    _days[_selectedWeekday - 1] = d;
    _dirty = true;
  }

  void _syncDayTitle() {
    _dayTitleController.text = _day.title ?? '';
  }

  void _selectWeekday(int wd) {
    setState(() {
      _selectedWeekday = wd;
      _syncDayTitle();
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------ exercises

  Future<void> _addExercise() async {
    final ex = await ExercisePickerSheet.show(
      context,
      title: 'Add to ${_dayNames[_selectedWeekday - 1]}',
      alreadyAddedIds: {for (final e in _day.exercises) e.exerciseId},
    );
    if (ex == null || !mounted) return;
    if (_day.exercises.any((e) => e.exerciseId == ex.id)) {
      final again = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Already in this day'),
          content: Text(
            '"${ex.name}" is already on ${_dayNames[_selectedWeekday - 1]}. '
            'Add it again?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add again'),
            ),
          ],
        ),
      );
      if (again != true || !mounted) return;
    }
    final item = _fromCatalogue(ex);
    final edited = await _editExercise(item, isNew: true);
    if (edited == null || !mounted) return;
    setState(() {
      _setDay(_day.copyWith(exercises: [..._day.exercises, edited]));
    });
  }

  TrainingPlanExercise _fromCatalogue(Exercise ex) {
    final cardio = isCardioExercise(
      muscleGroup: ex.muscleGroupName,
      equipment: ex.equipment,
      name: ex.name,
    );
    return TrainingPlanExercise(
      exerciseId: ex.id ?? 0,
      exerciseName: ex.name,
      muscleGroupName: ex.muscleGroupName,
      targetSets: cardio ? 1 : ex.defaultSets,
      targetReps: ex.defaultReps,
      targetWeightKg: cardio ? 0 : ex.defaultWeightKg,
      restSeconds: ex.restSeconds,
      targetDurationSeconds: cardio ? 20 * 60 : null,
      targetDistanceKm: null,
    );
  }

  Future<TrainingPlanExercise?> _editExercise(
    TrainingPlanExercise item, {
    bool isNew = false,
  }) {
    return showModalBottomSheet<TrainingPlanExercise>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ExerciseEditSheet(item: item, isNew: isNew),
    );
  }

  Future<void> _editAt(int index) async {
    final updated = await _editExercise(_day.exercises[index]);
    if (updated == null || !mounted) return;
    setState(() {
      final list = [..._day.exercises]..[index] = updated;
      _setDay(_day.copyWith(exercises: list));
    });
  }

  void _removeAt(int index) {
    final removed = _day.exercises[index];
    setState(() {
      final list = [..._day.exercises]..removeAt(index);
      _setDay(_day.copyWith(exercises: list));
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${removed.exerciseName}'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () {
              if (!mounted) return;
              setState(() {
                final list = [..._day.exercises];
                list.insert(index.clamp(0, list.length), removed);
                _setDay(_day.copyWith(exercises: list));
              });
            },
          ),
        ),
      );
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final list = [..._day.exercises];
      list.insert(newIndex, list.removeAt(oldIndex));
      _setDay(_day.copyWith(exercises: list));
    });
  }

  Future<void> _copyDayFrom() async {
    final sources = [
      for (final d in _days)
        if (d.weekday != _selectedWeekday &&
            !d.isRest &&
            d.exercises.isNotEmpty)
          d,
    ];
    if (sources.isEmpty) {
      _toast('No other day has exercises to copy yet');
      return;
    }
    final picked = await showModalBottomSheet<TrainingPlanDay>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'COPY EXERCISES FROM',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final d in sources)
              ListTile(
                title: Text(_dayNames[d.weekday - 1]),
                subtitle: Text('${d.exercises.length} exercises'),
                onTap: () => Navigator.pop(ctx, d),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _setDay(
        _day.copyWith(
          isRest: false,
          exercises: [
            for (final e in picked.exercises)
              TrainingPlanExercise(
                exerciseId: e.exerciseId,
                exerciseName: e.exerciseName,
                muscleGroupName: e.muscleGroupName,
                targetSets: e.targetSets,
                targetReps: e.targetReps,
                targetWeightKg: e.targetWeightKg,
                restSeconds: e.restSeconds,
                targetDurationSeconds: e.targetDurationSeconds,
                targetDistanceKm: e.targetDistanceKm,
                notes: e.notes,
              ),
          ],
        ),
      );
    });
  }

  // ----------------------------------------------------------------- save

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      _toast('Give your plan a name first');
      return;
    }
    // Commit the day title typed but not yet submitted.
    _days[_selectedWeekday - 1] = _day.copyWith(
      title: _dayTitleController.text.trim().isEmpty
          ? null
          : _dayTitleController.text.trim(),
    );
    final trainingDays = _days.where((d) => !d.isRest).length;
    if (trainingDays == 0) {
      _toast('Choose at least one training day');
      return;
    }
    for (final d in _days) {
      if (d.isRest) continue;
      for (final e in d.exercises) {
        final err = TrainingPlanValidator.validateExercise(e);
        if (err != null) {
          setState(() => _selectedWeekday = d.weekday);
          _toast('${_dayNames[d.weekday - 1]} • ${e.exerciseName}: $err');
          return;
        }
      }
    }
    setState(() => _saving = true);
    try {
      final plan = TrainingPlan(
        id: _plan.id,
        name: _nameController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        isActive: _plan.isActive,
        createdAt: _plan.createdAt,
        days: _days,
      );
      await _service.savePlan(plan);
      if (!mounted) return;
      _dirty = false;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save the plan. Your changes are still here.');
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes to this plan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Discard',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    return discard == true;
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('TRAINING PLAN')),
        body: Center(child: Text(_loadError!)),
      );
    }
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) nav.pop(false);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(widget.planId == null ? 'NEW PLAN' : 'EDIT PLAN'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'SAVE',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              TextFormField(
                controller: _nameController,
                maxLength: TrainingPlanValidator.maxNameLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Plan name'),
                validator: TrainingPlanValidator.validateName,
                onChanged: (_) => _dirty = true,
              ),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
                onChanged: (_) => _dirty = true,
              ),
              const SizedBox(height: 16),
              const Text(
                'WEEKLY SCHEDULE',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              _weekdayBar(),
              const SizedBox(height: 14),
              _dayPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weekdayBar() {
    return Row(
      children: [
        for (var wd = 1; wd <= 7; wd++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: wd == 7 ? 0 : 6),
              child: Semantics(
                button: true,
                selected: wd == _selectedWeekday,
                label:
                    '${_dayNames[wd - 1]}, '
                    '${_days[wd - 1].isRest ? 'rest day' : '${_days[wd - 1].exercises.length} exercises'}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _selectWeekday(wd),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: wd == _selectedWeekday
                          ? AppColors.primary
                          : AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: wd == _selectedWeekday
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _dayShort[wd - 1],
                          style: TextStyle(
                            color: wd == _selectedWeekday
                                ? Colors.black
                                : AppColors.textMain,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _days[wd - 1].isRest
                              ? 'Rest'
                              : '${_days[wd - 1].exercises.length}',
                          style: TextStyle(
                            color: wd == _selectedWeekday
                                ? Colors.black87
                                : AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _dayPanel() {
    final day = _day;
    final dups = TrainingPlanValidator.duplicateExerciseIds(day);
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dayNames[_selectedWeekday - 1].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const Text(
                  'Rest day',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Switch(
                  value: day.isRest,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) =>
                      setState(() => _setDay(day.copyWith(isRest: v))),
                ),
              ],
            ),
            if (day.isRest)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Rest & recovery. No exercises are scheduled. You can still '
                  'start an unplanned workout from the Home screen.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                ),
              )
            else ...[
              TextField(
                controller: _dayTitleController,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Day name (optional, e.g. Push)',
                  counterText: '',
                ),
                onChanged: (v) {
                  _days[_selectedWeekday - 1] = _day.copyWith(title: v);
                  _dirty = true;
                },
              ),
              const SizedBox(height: 8),
              if (day.exercises.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No exercises yet. Add as many as you need.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: day.exercises.length,
                  onReorderItem: _reorder,
                  itemBuilder: (_, i) =>
                      _exerciseTile(day.exercises[i], i, dups),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _addExercise,
                      icon: const Icon(Icons.add, color: Colors.black),
                      label: const Text('Add exercise'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _copyDayFrom,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy day'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _summary(TrainingPlanExercise e) {
    if (e.isCardio) {
      final parts = <String>[];
      if (e.targetDurationSeconds != null && e.targetDurationSeconds! > 0) {
        parts.add('${(e.targetDurationSeconds! / 60).round()} min');
      }
      if (e.targetDistanceKm != null && e.targetDistanceKm! > 0) {
        parts.add('${_fmt(e.targetDistanceKm!)} km');
      }
      return '${e.targetSets} × ${parts.join(' • ')}';
    }
    final w = e.targetWeightKg > 0 ? ' @ ${_fmt(e.targetWeightKg)} kg' : '';
    return '${e.targetSets} × ${e.targetReps}$w • rest ${e.restSeconds}s';
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Widget _exerciseTile(TrainingPlanExercise e, int index, Set<int> dups) {
    final name = ExerciseTerminologyService.instance.getDisplayName(
      e.exerciseName,
      id: e.exerciseId,
    );
    final isDup = dups.contains(e.exerciseId);
    return Dismissible(
      key: ValueKey('plan_ex_${_selectedWeekday}_${index}_${e.exerciseId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error.withValues(alpha: 0.3),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => _removeAt(index),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: () => _editAt(index),
        leading: ReorderableDragStartListener(
          index: index,
          child: const Tooltip(
            message: 'Drag to reorder',
            child: Icon(
              Icons.drag_indicator_rounded,
              color: AppColors.textMuted,
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(
            color: AppColors.textMain,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          isDup ? '${_summary(e)}\nDuplicate in this day' : _summary(e),
          style: TextStyle(
            color: isDup ? AppColors.warning : AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        trailing: IconButton(
          tooltip: 'Remove $name',
          icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
          onPressed: () => _removeAt(index),
        ),
      ),
    );
  }
}

class _ExerciseEditSheet extends StatefulWidget {
  const _ExerciseEditSheet({required this.item, required this.isNew});

  final TrainingPlanExercise item;
  final bool isNew;

  @override
  State<_ExerciseEditSheet> createState() => _ExerciseEditSheetState();
}

class _ExerciseEditSheetState extends State<_ExerciseEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _sets;
  late final TextEditingController _reps;
  late final TextEditingController _weight;
  late final TextEditingController _rest;
  late final TextEditingController _minutes;
  late final TextEditingController _km;
  late final TextEditingController _notes;

  bool get _cardio => widget.item.isCardio;

  @override
  void initState() {
    super.initState();
    final e = widget.item;
    String fmt(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    _sets = TextEditingController(text: '${e.targetSets}');
    _reps = TextEditingController(text: '${e.targetReps}');
    _weight = TextEditingController(
      text: e.targetWeightKg > 0 ? fmt(e.targetWeightKg) : '',
    );
    _rest = TextEditingController(text: '${e.restSeconds}');
    _minutes = TextEditingController(
      text: e.targetDurationSeconds != null
          ? fmt(e.targetDurationSeconds! / 60)
          : '',
    );
    _km = TextEditingController(
      text: e.targetDistanceKm != null && e.targetDistanceKm! > 0
          ? fmt(e.targetDistanceKm!)
          : '',
    );
    _notes = TextEditingController(text: e.notes ?? '');
  }

  @override
  void dispose() {
    for (final c in [_sets, _reps, _weight, _rest, _minutes, _km, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  TrainingPlanExercise _build() {
    final minutes = parseDecimal(_minutes.text);
    final km = parseDecimal(_km.text);
    return TrainingPlanExercise(
      id: widget.item.id,
      dayId: widget.item.dayId,
      exerciseId: widget.item.exerciseId,
      exerciseName: widget.item.exerciseName,
      muscleGroupName: widget.item.muscleGroupName,
      exerciseOrder: widget.item.exerciseOrder,
      targetSets: int.tryParse(_sets.text.trim()) ?? 0,
      targetReps: _cardio
          ? widget.item.targetReps
          : (int.tryParse(_reps.text.trim()) ?? 0),
      targetWeightKg: _cardio ? 0 : (parseDecimal(_weight.text) ?? 0),
      restSeconds: int.tryParse(_rest.text.trim()) ?? 0,
      targetDurationSeconds: _cardio && minutes != null && minutes > 0
          ? (minutes * 60).round()
          : null,
      targetDistanceKm: _cardio && km != null && km > 0 ? km : null,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
  }

  String? _numberValidator(
    String? v, {
    required bool decimal,
    bool required = true,
  }) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return required ? 'Required' : null;
    return (decimal ? parseDecimal(t) : int.tryParse(t)) == null
        ? 'Enter a number'
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + inset),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item.exerciseName,
                style: const TextStyle(
                  color: AppColors.textMain,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _sets,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _cardio ? 'Rounds' : 'Sets',
                      ),
                      validator: (v) => _numberValidator(v, decimal: false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (!_cardio)
                    Expanded(
                      child: TextFormField(
                        controller: _reps,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Reps'),
                        validator: (v) => _numberValidator(v, decimal: false),
                      ),
                    )
                  else
                    Expanded(
                      child: TextFormField(
                        controller: _minutes,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Minutes'),
                        validator: (v) =>
                            _numberValidator(v, decimal: true, required: false),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _cardio
                        ? TextFormField(
                            controller: _km,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Distance (km)',
                            ),
                            validator: (v) => _numberValidator(
                              v,
                              decimal: true,
                              required: false,
                            ),
                          )
                        : TextFormField(
                            controller: _weight,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Weight (kg)',
                              helperText: 'Decimals allowed, e.g. 12.5',
                            ),
                            validator: (v) => _numberValidator(
                              v,
                              decimal: true,
                              required: false,
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _rest,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Rest (seconds)',
                      ),
                      validator: (v) => _numberValidator(v, decimal: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (!(_formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        final built = _build();
                        final err = TrainingPlanValidator.validateExercise(
                          built,
                        );
                        if (err != null) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(err)));
                          return;
                        }
                        Navigator.pop(context, built);
                      },
                      child: Text(widget.isNew ? 'Add' : 'Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
