import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/exercise.dart';
import '../services/database_service.dart';
import '../services/exercise_terminology_service.dart';

/// Full-height exercise picker used by plans and live workouts.
///
/// Uses the corrected library semantics: the category chips filter on the
/// exercise's **primary** muscle group only, and the search box understands
/// Kerala-gym aliases / slang through [ExerciseTerminologyService].
class ExercisePickerSheet extends StatefulWidget {
  const ExercisePickerSheet({
    super.key,
    this.title = 'Add exercise',
    this.alreadyAddedIds = const {},
  });

  final String title;

  /// Ids already in the target list; shown with an "Added" tag (still
  /// selectable — the caller decides whether to warn).
  final Set<int> alreadyAddedIds;

  static Future<Exercise?> show(
    BuildContext context, {
    String title = 'Add exercise',
    Set<int> alreadyAddedIds = const {},
  }) {
    return showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          ExercisePickerSheet(title: title, alreadyAddedIds: alreadyAddedIds),
    );
  }

  @override
  State<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<ExercisePickerSheet> {
  static const _groups = [
    'All',
    'Chest',
    'Back',
    'Lats',
    'Upper Back and Traps',
    'Shoulders',
    'Biceps',
    'Triceps',
    'Forearms',
    'Quadriceps',
    'Hamstrings',
    'Glutes',
    'Calves',
    'Abs and Core',
    'Full Body',
    'Cardio',
  ];

  final _searchController = TextEditingController();
  List<Exercise> _all = [];
  String _group = 'All';
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await ExerciseTerminologyService.instance.initialize();
      final list = await DatabaseService().getAllExercises();
      list.sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load exercises.';
        _loading = false;
      });
    }
  }

  List<Exercise> get _filtered {
    final term = ExerciseTerminologyService.instance;
    return _all.where((e) {
      if (_group != 'All' && e.muscleGroupName != _group) return false;
      return term.matchesSearch(e, _query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _loading ? const <Exercise>[] : _filtered;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.92,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search name, alias or muscle (e.g. wings, db press)',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _groups.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final g = _groups[i];
                final selected = g == _group;
                return ChoiceChip(
                  label: Text(g),
                  selected: selected,
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.cardSurface,
                  labelStyle: TextStyle(
                    color: selected ? Colors.black : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  side: BorderSide(
                    color: selected ? AppColors.primary : AppColors.border,
                  ),
                  onSelected: (_) => setState(() => _group = g),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Expanded(child: _buildBody(list)),
        ],
      ),
    );
  }

  Widget _buildBody(List<Exercise> list) {
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
            Text(_error!, style: const TextStyle(color: AppColors.textMain)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _load();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (list.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No exercises match. Try another word or category.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final term = ExerciseTerminologyService.instance;
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final e = list[i];
        final added = widget.alreadyAddedIds.contains(e.id);
        final display = term.getDisplayName(e.name, id: e.id);
        return ListTile(
          key: ValueKey('pick_${e.id}'),
          title: Text(
            display,
            style: const TextStyle(
              color: AppColors.textMain,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '${e.muscleGroupName} • ${e.equipment}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          trailing: added
              ? const Chip(
                  label: Text('Added', style: TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                )
              : const Icon(Icons.add_circle_outline, color: AppColors.primary),
          onTap: () => Navigator.pop(context, e),
        );
      },
    );
  }
}
