import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/exercise.dart';
import '../models/exercise_demonstration.dart';
import '../models/exercise_terminology.dart';
import '../services/database_service.dart';
import '../services/exercise_media_service.dart';
import '../services/exercise_terminology_service.dart';
import '../widgets/exercise_demonstration_player.dart';
import '../widgets/media_attachment_section.dart';
import 'active_workout_screen.dart';

class ExerciseDetailScreen extends StatefulWidget {
  final Exercise exercise;
  final VoidCallback? onUpdated;

  const ExerciseDetailScreen({
    super.key,
    required this.exercise,
    this.onUpdated,
  });

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  final DatabaseService _dbService = DatabaseService();

  late Exercise _exercise;
  final TextEditingController _notesController = TextEditingController();

  // Editable example targets
  late int _targetSets;
  late int _targetReps;
  late double _targetWeightKg;
  late int _targetRestSeconds;

  ExerciseDemonstration? _demonstration;

  @override
  void initState() {
    super.initState();
    _exercise = widget.exercise;
    _notesController.text = _exercise.personalNotes ?? '';
    _targetSets = _exercise.defaultSets;
    _targetReps = _exercise.defaultReps;
    _targetWeightKg = _exercise.defaultWeightKg;
    _targetRestSeconds = _exercise.restSeconds;
    _loadDemonstration();
  }

  @override
  void didUpdateWidget(covariant ExerciseDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exercise.id != widget.exercise.id ||
        oldWidget.exercise.name != widget.exercise.name) {
      setState(() {
        _exercise = widget.exercise;
        _notesController.text = _exercise.personalNotes ?? '';
        _targetSets = _exercise.defaultSets;
        _targetReps = _exercise.defaultReps;
        _targetWeightKg = _exercise.defaultWeightKg;
        _targetRestSeconds = _exercise.restSeconds;
      });
      _loadDemonstration();
    }
  }

  Future<void> _loadDemonstration() async {
    await ExerciseMediaService.instance.initialize();
    if (mounted) {
      ExerciseDemonstration? demo;
      if (_exercise.id != null && _exercise.id! > 0) {
        demo = ExerciseMediaService.instance.getDemonstrationById(
          _exercise.id!,
        );
      }
      demo ??= ExerciseMediaService.instance.getDemonstration(_exercise.name);
      setState(() {
        _demonstration = demo;
      });
    }
  }

  Future<void> _toggleFavourite() async {
    final newFav = !_exercise.isFavourite;
    await _dbService.toggleExerciseFavourite(_exercise.id ?? 0, newFav);
    setState(() {
      _exercise = _exercise.copyWith(isFavourite: newFav);
    });
    widget.onUpdated?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newFav
                ? 'Saved ${_exercise.name} to Favourites'
                : 'Removed from Favourites',
          ),
          duration: const Duration(seconds: 1),
          backgroundColor: AppColors.cardSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _addToToday() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await _dbService.addExerciseToDatePlan(
      today,
      _exercise,
      customSets: _targetSets,
      customReps: _targetReps,
      customWeight: _targetWeightKg,
      customRest: _targetRestSeconds,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${_exercise.name} to Today\'s Workout'),
          backgroundColor: AppColors.cardSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _addToTomorrow() async {
    final tomorrow = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().add(const Duration(days: 1)));
    await _dbService.addExerciseToDatePlan(
      tomorrow,
      _exercise,
      customSets: _targetSets,
      customReps: _targetReps,
      customWeight: _targetWeightKg,
      customRest: _targetRestSeconds,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${_exercise.name} to Tomorrow\'s Workout'),
          backgroundColor: AppColors.cardSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _addToAnotherDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 2)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.black,
              surface: AppColors.surfaceElevated,
              onSurface: AppColors.textMain,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate == null || !mounted) return;
    final dateStr = DateFormat('yyyy-MM-dd').format(pickedDate);
    final existingPlan = await _dbService.getPlanForDate(dateStr);

    int targetSlot = 1;
    bool replaceSlot = false;

    // Check if the target date already has two muscle groups scheduled
    if (existingPlan != null &&
        existingPlan.primaryMuscleId != null &&
        existingPlan.primaryMuscleId != 0 &&
        existingPlan.secondaryMuscleId != null &&
        existingPlan.secondaryMuscleId != 0 &&
        existingPlan.primaryMuscleId != _exercise.muscleGroupId &&
        existingPlan.secondaryMuscleId != _exercise.muscleGroupId) {
      if (!mounted) return;
      // Require user confirmation: never silently overwrite existing groups
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Workout Slot Assignment',
            style: TextStyle(
              color: AppColors.textMain,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The workout plan for $dateStr already has 2 muscle groups:\n'
                '• Slot 1: ${existingPlan.primaryMuscleName}\n'
                '• Slot 2: ${existingPlan.secondaryMuscleName}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'How would you like to assign this exercise?',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'append'),
              child: const Text(
                'Keep Both & Append',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'slot1'),
              child: Text(
                'Replace ${existingPlan.primaryMuscleName}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'slot2'),
              child: Text(
                'Replace ${existingPlan.secondaryMuscleName}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );

      if (choice == null || !mounted) return;
      if (choice == 'slot1') {
        targetSlot = 1;
        replaceSlot = true;
      } else if (choice == 'slot2') {
        targetSlot = 2;
        replaceSlot = true;
      } else {
        replaceSlot = false;
      }
    }

    await _dbService.addExerciseToDatePlan(
      dateStr,
      _exercise,
      targetSlot: targetSlot,
      replaceSlotIfFull: replaceSlot,
      customSets: _targetSets,
      customReps: _targetReps,
      customWeight: _targetWeightKg,
      customRest: _targetRestSeconds,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${_exercise.name} to workout on $dateStr'),
          backgroundColor: AppColors.cardSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _editTargetsDialog() async {
    int sets = _targetSets;
    int reps = _targetReps;
    double weight = _targetWeightKg;
    int rest = _targetRestSeconds;

    final updated = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'EDIT SUGGESTED TARGETS',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Sets counter
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Sets',
                        style: TextStyle(
                          color: AppColors.textMain,
                          fontSize: 15,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Decrease',
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: AppColors.primary,
                            ),
                            onPressed: () => setModalState(() {
                              if (sets > 1) sets--;
                            }),
                          ),
                          Text(
                            '$sets',
                            style: const TextStyle(
                              color: AppColors.textMain,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Add',
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: AppColors.primary,
                            ),
                            onPressed: () => setModalState(() => sets++),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Reps counter
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Reps per set',
                        style: TextStyle(
                          color: AppColors.textMain,
                          fontSize: 15,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Decrease',
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: AppColors.primary,
                            ),
                            onPressed: () => setModalState(() {
                              if (reps > 1) reps--;
                            }),
                          ),
                          Text(
                            '$reps',
                            style: const TextStyle(
                              color: AppColors.textMain,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Add',
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: AppColors.primary,
                            ),
                            onPressed: () => setModalState(() => reps++),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Weight counter
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Weight (kg)',
                        style: TextStyle(
                          color: AppColors.textMain,
                          fontSize: 15,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Decrease',
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: AppColors.primary,
                            ),
                            onPressed: () => setModalState(() {
                              if (weight >= 2.5) weight -= 2.5;
                            }),
                          ),
                          Text(
                            '${weight.toStringAsFixed(1)} kg',
                            style: const TextStyle(
                              color: AppColors.textMain,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Add',
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: AppColors.primary,
                            ),
                            onPressed: () => setModalState(() => weight += 2.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Rest seconds
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Rest duration',
                        style: TextStyle(
                          color: AppColors.textMain,
                          fontSize: 15,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Decrease',
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: AppColors.primary,
                            ),
                            onPressed: () => setModalState(() {
                              if (rest >= 15) rest -= 15;
                            }),
                          ),
                          Text(
                            '${rest}s',
                            style: const TextStyle(
                              color: AppColors.textMain,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Add',
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: AppColors.primary,
                            ),
                            onPressed: () => setModalState(() => rest += 15),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Save Targets',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (updated == true) {
      setState(() {
        _targetSets = sets;
        _targetReps = reps;
        _targetWeightKg = weight;
        _targetRestSeconds = rest;
      });

      // Persist as new exercise defaults
      final updatedEx = _exercise.copyWith(
        defaultSets: sets,
        defaultReps: reps,
        defaultWeightKg: weight,
        restSeconds: rest,
      );
      await _dbService.updateExercise(updatedEx);
      setState(() {
        _exercise = updatedEx;
      });
      widget.onUpdated?.call();
    }
  }

  Future<void> _savePersonalNotes() async {
    final updated = _exercise.copyWith(
      personalNotes: _notesController.text.trim(),
    );
    await _dbService.updateExercise(updated);
    setState(() => _exercise = updated);
    widget.onUpdated?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notes saved successfully'),
          backgroundColor: AppColors.cardSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = ExerciseTerminologyService.instance.getTerminology(
      id: _exercise.id,
      name: _exercise.name,
    );
    final displayName = term?.recommendedDisplayName.isNotEmpty == true
        ? term!.recommendedDisplayName
        : _exercise.name;
    final friendlyMuscle = ExerciseTerminologyService.instance
        .getFriendlyMuscleName(_exercise.muscleGroupName);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Pinned App Bar with controls and title
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.background,
            elevation: 0,
            title: Text(
              displayName,
              style: const TextStyle(
                color: AppColors.textMain,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _exercise.isFavourite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: _exercise.isFavourite
                      ? Colors.redAccent
                      : AppColors.textMain,
                ),
                tooltip: _exercise.isFavourite
                    ? 'Remove from Favourites'
                    : 'Save as Favourite',
                onPressed: _toggleFavourite,
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.textMain,
                ),
                color: AppColors.surfaceElevated,
                onSelected: (val) {
                  if (val == 'today') _addToToday();
                  if (val == 'tomorrow') _addToTomorrow();
                  if (val == 'another') _addToAnotherDate();
                  if (val == 'edit_targets') _editTargetsDialog();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'today',
                    child: Row(
                      children: [
                        Icon(
                          Icons.today_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text('Add to Today\'s Workout'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'tomorrow',
                    child: Row(
                      children: [
                        Icon(
                          Icons.upcoming_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text('Add to Tomorrow\'s Workout'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'another',
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_month_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text('Add to Another Date...'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit_targets',
                    child: Row(
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          color: AppColors.textMain,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text('Edit Example Targets'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Prominent Exercise Demonstration Player
                  ExerciseDemonstrationPlayer(
                    key: ValueKey(
                      'demo_player_${_exercise.id}_${_exercise.name}',
                    ),
                    exerciseId: _exercise.id,
                    exerciseName: _exercise.name,
                    fallbackImagePath: _exercise.imagePath,
                    personalPhotoPath: _exercise.personalPhotoPath,
                    height: 250,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  const SizedBox(height: 16),
                  // Badges Row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildPill(
                        icon: Icons.fitness_center_rounded,
                        label: friendlyMuscle.toUpperCase(),
                        color: AppColors.primary,
                      ),
                      if (_exercise.secondaryMuscles.isNotEmpty)
                        _buildPill(
                          icon: Icons.alt_route_rounded,
                          label: 'Also: ${_exercise.secondaryMuscles}',
                          color: AppColors.textMain,
                        ),
                      _buildPill(
                        icon: Icons.construction_rounded,
                        label: _exercise.equipment,
                        color: AppColors.textMain,
                      ),
                      if (_exercise.isCompound)
                        _buildPill(
                          icon: Icons.hub_rounded,
                          label: 'Compound Lift',
                          color: AppColors.primary,
                        ),
                      _buildPill(
                        icon: Icons.speed_rounded,
                        label: _exercise.difficulty,
                        color: _exercise.difficulty == 'Beginner'
                            ? Colors.greenAccent
                            : (_exercise.difficulty == 'Advanced'
                                  ? Colors.orangeAccent
                                  : AppColors.primary),
                      ),
                      _buildPill(
                        icon: Icons.track_changes_rounded,
                        label: _exercise.target,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Exercise Primary Name
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (displayName.toLowerCase() !=
                      _exercise.name.toLowerCase()) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Technical / Catalogue: ${_exercise.name}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),

                  // Description
                  Text(
                    _exercise.description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Quick Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ActiveWorkoutScreen(
                                  singleExercise: _exercise,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.black,
                          ),
                          label: const Text(
                            'Start Now',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Add to Today
                      IconButton.filledTonal(
                        onPressed: _addToToday,
                        icon: const Icon(
                          Icons.today_rounded,
                          color: AppColors.primary,
                        ),
                        tooltip: 'Add to Today',
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.cardSurface,
                          padding: const EdgeInsets.all(13),
                          side: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Add to Tomorrow
                      IconButton.filledTonal(
                        onPressed: _addToTomorrow,
                        icon: const Icon(
                          Icons.upcoming_rounded,
                          color: AppColors.primary,
                        ),
                        tooltip: 'Add to Tomorrow',
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.cardSurface,
                          padding: const EdgeInsets.all(13),
                          side: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Add to Another Date
                      IconButton.filledTonal(
                        onPressed: _addToAnotherDate,
                        icon: const Icon(
                          Icons.calendar_month_rounded,
                          color: AppColors.primary,
                        ),
                        tooltip: 'Add to Another Date',
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.cardSurface,
                          padding: const EdgeInsets.all(13),
                          side: const BorderSide(color: AppColors.border),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Demonstration Movement Breakdown Card
                  if (_demonstration != null &&
                      _demonstration!.demonstrationCues.isNotEmpty) ...[
                    _buildSectionHeader('DEMONSTRATION MOVEMENT BREAKDOWN'),
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _demonstration!.hasVideo
                              ? AppColors.primary.withValues(alpha: 0.35)
                              : AppColors.border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _demonstration!.hasVideo
                                    ? Icons.video_library_rounded
                                    : Icons.photo_library_rounded,
                                color: AppColors.primary,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _demonstration!.hasVideo
                                      ? '3-Phase Biomechanical Breakdown (~10s)'
                                      : 'Technique Reference Guide',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ..._demonstration!.demonstrationCues.map(
                            (cue) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(
                                      top: 5,
                                      right: 10,
                                    ),
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      cue,
                                      style: const TextStyle(
                                        color: AppColors.textMain,
                                        fontSize: 13,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(color: AppColors.border, height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Media: ${_demonstration!.attribution}',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Text(
                                  _demonstration!.license,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Gym Terminology & Kerala Aliases Card
                  _buildTerminologyCard(term, displayName),

                  // Suggested Plan Card with Edit affordance
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildSectionHeader('SUGGESTED WORKOUT TARGETS'),
                      TextButton.icon(
                        onPressed: _editTargetsDialog,
                        icon: const Icon(
                          Icons.tune_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        label: const Text(
                          'Edit Targets',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 6, bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatCol('SETS', '$_targetSets'),
                        _buildDivider(),
                        _buildStatCol('REPS', '$_targetReps'),
                        _buildDivider(),
                        _buildStatCol(
                          'WEIGHT',
                          '${_targetWeightKg.toStringAsFixed(1)} kg',
                        ),
                        _buildDivider(),
                        _buildStatCol('REST', '${_targetRestSeconds}s'),
                      ],
                    ),
                  ),

                  // Starting Position
                  if (_exercise.startingPosition.isNotEmpty) ...[
                    _buildSectionHeader('STARTING SETUP & POSITION'),
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.accessibility_new_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _exercise.startingPosition,
                              style: const TextStyle(
                                color: AppColors.textMain,
                                fontSize: 13.5,
                                height: 1.55,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Step-by-Step Instructions
                  _buildSectionHeader('STEP-BY-STEP INSTRUCTIONS'),
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      _exercise.instructions,
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontSize: 13.5,
                        height: 1.6,
                      ),
                    ),
                  ),

                  // Breathing Guidance
                  if (_exercise.breathingGuidance.isNotEmpty) ...[
                    _buildSectionHeader('BREATHING PATTERN & CADENCE'),
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.air_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _exercise.breathingGuidance,
                              style: const TextStyle(
                                color: AppColors.textMain,
                                fontSize: 13.5,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Common Form Mistakes
                  if (_exercise.commonMistakes.isNotEmpty) ...[
                    _buildSectionHeader('COMMON FORM MISTAKES & CUES'),
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: AppColors.error,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _exercise.commonMistakes,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13.5,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Beginner Modification
                  if (_exercise.beginnerModification.isNotEmpty) ...[
                    _buildSectionHeader('BEGINNER REGRESSION / MODIFICATION'),
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.greenAccent.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.lightbulb_outline_rounded,
                            color: Colors.greenAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _exercise.beginnerModification,
                              style: const TextStyle(
                                color: AppColors.textMain,
                                fontSize: 13.5,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Form Media & Attachments
                  MediaAttachmentSection(
                    entityType: 'exercise',
                    entityId: _exercise.id ?? 0,
                    entityTitle: _exercise.name,
                    sectionTitle: 'FORM MEDIA & ATTACHMENTS',
                    onChanged: () {
                      widget.onUpdated?.call();
                    },
                  ),
                  const SizedBox(height: 20),

                  // Personal Notes input
                  _buildSectionHeader('PERSONAL NOTES & CUES'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontSize: 13.5,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Add personal form cues, bench angle, machine pin settings, or trainer advice...',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _savePersonalNotes,
                      icon: const Icon(
                        Icons.save_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      label: const Text(
                        'Save Notes',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.primary,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildTerminologyCard(ExerciseTerminology? term, String displayName) {
    if (term == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('GYM TERMINOLOGY & LOCAL ALIASES'),
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.translate_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: AppColors.textMain,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (term.formalName.isNotEmpty &&
                            term.formalName.toLowerCase() !=
                                displayName.toLowerCase()) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Formal Movement: ${term.formalName}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (term.malayalamScript.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        term.malayalamScript,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              if (term.aliases.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Recognized Search Terms & Slang:',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: term.aliases.map((alias) {
                    final isDisplay =
                        alias.toLowerCase() == displayName.toLowerCase();
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4.5,
                      ),
                      decoration: BoxDecoration(
                        color: isDisplay
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDisplay
                              ? AppColors.primary.withValues(alpha: 0.4)
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        alias,
                        style: TextStyle(
                          color: isDisplay
                              ? AppColors.primary
                              : AppColors.textMain,
                          fontSize: 11.5,
                          fontWeight: isDisplay
                              ? FontWeight.bold
                              : FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (term.keralaGymNotes.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.sports_rounded,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          term.keralaGymNotes,
                          style: const TextStyle(
                            color: AppColors.textMain,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCol(String title, String val) {
    return Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              val,
              style: const TextStyle(
                color: AppColors.textMain,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 28, color: AppColors.border);
  }
}
