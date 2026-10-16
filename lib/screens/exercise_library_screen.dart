import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/muscle_group.dart';
import '../models/exercise.dart';
import '../services/database_service.dart';
import '../services/exercise_media_service.dart';
import '../services/exercise_terminology_service.dart';
import '../widgets/exercise_image_widget.dart';
import 'muscle_detail_screen.dart';
import 'exercise_detail_screen.dart';
import 'add_edit_exercise_screen.dart';

enum LibraryViewMode {
  mainCategories,
  muscleCatalogues,
  modalityCatalogues,
  allExercises,
  recommended,
  favourites,
  custom,
}

class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  static final List<MuscleGroup> mainCategories = [
    MuscleGroup(
      id: 201,
      name: 'Chest',
      description: 'Pectoralis major and minor muscles, powering pressing, push-ups, and horizontal adduction.',
      imagePath: 'assets/images/muscles/chest.jpg',
    ),
    MuscleGroup(
      id: 202,
      name: 'Triceps',
      description: 'Lateral, long, and medial heads of the triceps brachii powering elbow extension and lockout.',
      imagePath: 'assets/images/muscles/triceps.jpg',
    ),
    MuscleGroup(
      id: 203,
      name: 'Back',
      description: 'Complete posterior pulling chain including lats, rhomboids, mid-traps, and spinal erectors.',
      imagePath: 'assets/images/muscles/back.jpg',
    ),
    MuscleGroup(
      id: 204,
      name: 'Biceps',
      description: 'Biceps brachii (long and short heads) and brachialis powering elbow flexion and supination.',
      imagePath: 'assets/images/muscles/biceps.jpg',
    ),
    MuscleGroup(
      id: 205,
      name: 'Legs',
      description: 'Complete lower body kinetic chain comprising quadriceps, hamstrings, glutes, and calves.',
      imagePath: 'assets/images/muscles/quadriceps.jpg',
    ),
    MuscleGroup(
      id: 206,
      name: 'Abs / Core',
      description: 'Rectus abdominis, obliques, transverse abdominis, and deep core brace powering midline rigidity.',
      imagePath: 'assets/images/muscles/abs.jpg',
    ),
    MuscleGroup(
      id: 207,
      name: 'Shoulders',
      description: 'Anterior, lateral, and posterior deltoid heads for 3D shoulder capping and overhead pressing.',
      imagePath: 'assets/images/muscles/shoulders.jpg',
    ),
    MuscleGroup(
      id: 208,
      name: 'Cardio',
      description: 'Cardiovascular conditioning, aerobic endurance, running, cycling, rowing, and metabolic stamina.',
      imagePath: 'assets/images/muscles/cardio.jpg',
    ),
  ];

  static final List<MuscleGroup> modalityCategories = [
    MuscleGroup(
      id: 101,
      name: 'Compound Exercises',
      description: 'Multi-joint compound lifts recruiting large muscle masses for maximum strength and hypertrophy.',
      imagePath: 'assets/images/muscles/compound.jpg',
    ),
    MuscleGroup(
      id: 102,
      name: 'Bodyweight Exercises',
      description: 'Calisthenics and relative strength movements using body mass and gravity as resistance.',
      imagePath: 'assets/images/muscles/bodyweight.jpg',
    ),
    MuscleGroup(
      id: 103,
      name: 'Cable Exercises',
      description: 'Constant-tension pulley exercises providing smooth resistance curves through full ranges of motion.',
      imagePath: 'assets/images/muscles/cables.jpg',
    ),
    MuscleGroup(
      id: 104,
      name: 'Machine Exercises',
      description: 'Guided-path machines offering stabilized isolation, safety at failure, and direct target loading.',
      imagePath: 'assets/images/muscles/machines.jpg',
    ),
    MuscleGroup(
      id: 105,
      name: 'Dumbbell Exercises',
      description: 'Free-weight unilateral movements correcting bilateral strength imbalances and allowing natural wrist paths.',
      imagePath: 'assets/images/muscles/dumbbells.jpg',
    ),
    MuscleGroup(
      id: 106,
      name: 'Barbell Exercises',
      description: 'Heavy foundational bilateral free-weight training for maximal overload and progressive tension.',
      imagePath: 'assets/images/muscles/barbell.jpg',
    ),
  ];

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final DatabaseService _dbService = DatabaseService();

  List<MuscleGroup> _muscleGroups = [];
  Map<String, int> _catalogueCounts = {};
  List<Exercise> _allExercises = [];
  List<Exercise> _displayExercises = [];
  bool _isLoading = true;

  LibraryViewMode _currentMode = LibraryViewMode.mainCategories;
  String _selectedCategory = 'All';
  String _selectedSubCategory = 'All';
  String _selectedSecondary = 'All';
  String _selectedEquipment = 'All';
  String _selectedDifficulty = 'All';
  String _selectedSort = 'name_asc';
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  final List<String> _categoryFilterOptions = [
    'All',
    'Chest',
    'Triceps',
    'Back',
    'Biceps',
    'Legs',
    'Abs / Core',
    'Shoulders',
    'Cardio',
    'Forearms',
    'Traps',
    'Quads',
    'Hamstrings',
    'Glutes',
    'Calves',
    'Full Body',
  ];

  final List<String> _equipmentOptions = [
    'All',
    'Dumbbells',
    'Barbell',
    'Cable',
    'Machine',
    'Bodyweight',
    'EZ-Bar',
  ];

  final List<String> _difficultyOptions = [
    'All',
    'Beginner',
    'Intermediate',
    'Advanced',
  ];

  List<String> get _availableSecondaryMuscles {
    final Set<String> muscles = {};
    for (final ex in _allExercises) {
      if (ex.secondaryMuscles.isNotEmpty) {
        for (final m in ex.secondaryMuscles.split(',')) {
          final trimmed = m.trim();
          if (trimmed.isNotEmpty) {
            muscles.add(trimmed);
          }
        }
      }
    }
    final list = muscles.toList()..sort();
    return ['All', ...list];
  }

  bool get _hasActiveFilters {
    final isSubActive =
        _selectedSubCategory != 'All' &&
        _selectedSubCategory != 'All Legs' &&
        _selectedSubCategory != 'All Back';
    return _selectedCategory != 'All' ||
        isSubActive ||
        _selectedSecondary != 'All' ||
        _selectedEquipment != 'All' ||
        _selectedDifficulty != 'All' ||
        _searchController.text.trim().isNotEmpty;
  }

  void _clearAllFilters() {
    setState(() {
      _selectedCategory = 'All';
      _selectedSubCategory = 'All';
      _selectedSecondary = 'All';
      _selectedEquipment = 'All';
      _selectedDifficulty = 'All';
      _searchController.clear();
    });
    _applyFilters();
  }

  int _getCountForCategory(String name) {
    if (_catalogueCounts.containsKey(name)) {
      return _catalogueCounts[name]!;
    }
    if (name == 'Abs / Core' && _catalogueCounts.containsKey('Abs and Core')) {
      return _catalogueCounts['Abs and Core']!;
    }
    if (name == 'Legs') {
      const legGroups = ['Quadriceps', 'Hamstrings', 'Glutes', 'Calves'];
      return _allExercises
          .where((e) => legGroups.contains(e.muscleGroupName))
          .length;
    }
    if (name == 'Back') {
      const backGroups = ['Back', 'Lats', 'Upper Back and Traps'];
      return _allExercises
          .where((e) => backGroups.contains(e.muscleGroupName))
          .length;
    }
    return _allExercises
        .where((e) => e.muscleGroupName.toLowerCase() == name.toLowerCase())
        .length;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchOrFilterChanged);
  }

  Future<void> _loadData() async {
    await ExerciseMediaService.instance.initialize();
    final mgs = await _dbService.getAllMuscleGroups();
    final counts = await _dbService.getAllCatalogueCounts();
    final exs = await _dbService.getAllExercises();

    if (mounted) {
      setState(() {
        _muscleGroups = mgs;
        _catalogueCounts = counts;
        _allExercises = exs;
        _isLoading = false;
      });
      _applyFilters();
    }
  }

  void _onSearchOrFilterChanged() {
    setState(() {
      _isSearching = _searchController.text.trim().isNotEmpty;
    });
    _applyFilters();
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();

    List<Exercise> list;
    switch (_currentMode) {
      case LibraryViewMode.mainCategories:
      case LibraryViewMode.muscleCatalogues:
      case LibraryViewMode.modalityCatalogues:
      case LibraryViewMode.allExercises:
        list = List.from(_allExercises);
        break;
      case LibraryViewMode.recommended:
        list = _allExercises
            .where((e) => e.isRecommended && !e.isCustom)
            .toList();
        break;
      case LibraryViewMode.favourites:
        list = _allExercises.where((e) => e.isFavourite).toList();
        break;
      case LibraryViewMode.custom:
        list = _allExercises.where((e) => e.isCustom).toList();
        break;
    }

    // 1. Apply category filter
    if (_selectedCategory != 'All') {
      final cat = _selectedCategory.toLowerCase();
      if (cat == 'chest') {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'chest')
            .toList();
      } else if (cat == 'triceps') {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'triceps')
            .toList();
      } else if (cat == 'biceps') {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'biceps')
            .toList();
      } else if (cat.contains('shoulder')) {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'shoulders')
            .toList();
      } else if (cat == 'legs') {
        if (_selectedSubCategory != 'All' &&
            _selectedSubCategory != 'All Legs') {
          final sub = _selectedSubCategory.toLowerCase();
          if (sub.contains('quad')) {
            list = list
                .where((e) => e.muscleGroupName.toLowerCase() == 'quadriceps')
                .toList();
          } else if (sub.contains('hamstring')) {
            list = list
                .where((e) => e.muscleGroupName.toLowerCase() == 'hamstrings')
                .toList();
          } else if (sub.contains('glute')) {
            list = list
                .where((e) => e.muscleGroupName.toLowerCase() == 'glutes')
                .toList();
          } else if (sub.contains('calve') || sub.contains('calf')) {
            list = list
                .where((e) => e.muscleGroupName.toLowerCase() == 'calves')
                .toList();
          }
        } else {
          const legGroups = ['quadriceps', 'hamstrings', 'glutes', 'calves'];
          list = list
              .where((e) => legGroups.contains(e.muscleGroupName.toLowerCase()))
              .toList();
        }
      } else if (cat.contains('quad')) {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'quadriceps')
            .toList();
      } else if (cat.contains('hamstring')) {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'hamstrings')
            .toList();
      } else if (cat.contains('glute')) {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'glutes')
            .toList();
      } else if (cat.contains('calve') || cat.contains('calf')) {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'calves')
            .toList();
      } else if (cat == 'back') {
        if (_selectedSubCategory != 'All' &&
            _selectedSubCategory != 'All Back') {
          final sub = _selectedSubCategory.toLowerCase();
          if (sub == 'lats') {
            list = list
                .where((e) => e.muscleGroupName.toLowerCase() == 'lats')
                .toList();
          } else if (sub.contains('trap') || sub.contains('upper back')) {
            list = list
                .where(
                  (e) =>
                      e.muscleGroupName.toLowerCase() == 'upper back and traps',
                )
                .toList();
          } else if (sub.contains('mid') || sub == 'back') {
            list = list
                .where((e) => e.muscleGroupName.toLowerCase() == 'back')
                .toList();
          }
        } else {
          const backGroups = ['back', 'lats', 'upper back and traps'];
          list = list
              .where(
                (e) => backGroups.contains(e.muscleGroupName.toLowerCase()),
              )
              .toList();
        }
      } else if (cat == 'lats') {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'lats')
            .toList();
      } else if (cat.contains('upper back') || cat.contains('trap')) {
        list = list
            .where(
              (e) => e.muscleGroupName.toLowerCase() == 'upper back and traps',
            )
            .toList();
      } else if (cat.contains('forearm')) {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'forearms')
            .toList();
      } else if (cat.contains('ab') || cat.contains('core')) {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'abs and core')
            .toList();
      } else if (cat == 'cardio') {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'cardio')
            .toList();
      } else if (cat.contains('full body')) {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'full body')
            .toList();
      }
    }

    // 2. Apply secondary muscle filter
    if (_selectedSecondary != 'All') {
      list = list
          .where(
            (e) => e.secondaryMuscles.toLowerCase().contains(
              _selectedSecondary.toLowerCase(),
            ),
          )
          .toList();
    }

    // 3. Apply equipment filter
    if (_selectedEquipment != 'All') {
      list = list.where((e) {
        return e.equipment.toLowerCase().contains(
          _selectedEquipment.toLowerCase(),
        );
      }).toList();
    }

    // 4. Apply difficulty filter
    if (_selectedDifficulty != 'All') {
      list = list.where((e) {
        return e.difficulty.toLowerCase() == _selectedDifficulty.toLowerCase();
      }).toList();
    }

    // 5. Apply search query via Kerala gym-friendly terminology service
    if (query.isNotEmpty) {
      list = list.where((e) {
        return ExerciseTerminologyService.instance.matchesSearch(e, query);
      }).toList();
    }

    // 6. Apply sorting
    if (_selectedSort == 'name_desc') {
      list.sort((a, b) => b.name.compareTo(a.name));
    } else if (_selectedSort == 'difficulty') {
      const diffOrder = {'Beginner': 1, 'Intermediate': 2, 'Advanced': 3};
      list.sort(
        (a, b) => (diffOrder[a.difficulty] ?? 4).compareTo(
          diffOrder[b.difficulty] ?? 4,
        ),
      );
    } else if (_selectedSort == 'recommended') {
      list.sort(
        (a, b) => (b.isRecommended ? 1 : 0).compareTo(a.isRecommended ? 1 : 0),
      );
    } else {
      list.sort((a, b) => a.name.compareTo(b.name));
    }

    setState(() {
      _displayExercises = list;
    });
  }

  Future<void> _toggleFavourite(Exercise ex) async {
    final newFav = !ex.isFavourite;
    await _dbService.toggleExerciseFavourite(ex.id ?? 0, newFav);
    setState(() {
      final idx = _allExercises.indexWhere((e) => e.id == ex.id);
      if (idx != -1) {
        _allExercises[idx] = _allExercises[idx].copyWith(isFavourite: newFav);
      }
    });
    _applyFilters();
  }

  Future<void> _showAddMuscleGroupDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Add Custom Muscle Group',
          style: TextStyle(
            color: AppColors.textMain,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Muscle Group Name',
                hintText: 'e.g. Traps, Calves, Neck',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Functional description...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Create', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (created == true && nameCtrl.text.trim().isNotEmpty) {
      final newGroup = MuscleGroup(
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
        isCustom: true,
      );
      await _dbService.insertMuscleGroup(newGroup);
      _loadData();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final bool showExerciseList =
        _isSearching ||
        (_currentMode != LibraryViewMode.mainCategories &&
            _currentMode != LibraryViewMode.muscleCatalogues &&
            _currentMode != LibraryViewMode.modalityCatalogues);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('EXERCISE LIBRARY'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: AppColors.primary),
            tooltip: 'Add Custom Exercise',
            onPressed: () async {
              final res = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AddEditExerciseScreen(),
                ),
              );
              if (res == true) _loadData();
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert_rounded,
              color: AppColors.textSecondary,
            ),
            color: AppColors.surfaceElevated,
            onSelected: (val) {
              if (val == 'add_group') _showAddMuscleGroupDialog();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'add_group',
                child: Row(
                  children: [
                    Icon(
                      Icons.category_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text('Add Muscle Group'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search field
            TextField(
              controller: _searchController,
              style: const TextStyle(color: AppColors.textMain),
              decoration: InputDecoration(
                hintText:
                    'Search ${_allExercises.length}+ exercises, equipment, muscles...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.primary,
                ),
                suffixIcon: _isSearching
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchOrFilterChanged();
                        },
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),

            // View Mode selector pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildModeChip(
                    'Main (8)',
                    LibraryViewMode.mainCategories,
                    Icons.dashboard_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildModeChip(
                    'Muscles (14)',
                    LibraryViewMode.muscleCatalogues,
                    Icons.sports_gymnastics_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildModeChip(
                    'Modalities (6)',
                    LibraryViewMode.modalityCatalogues,
                    Icons.fitness_center_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildModeChip(
                    'All (${_allExercises.length})',
                    LibraryViewMode.allExercises,
                    Icons.list_alt_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildModeChip(
                    'Recommended',
                    LibraryViewMode.recommended,
                    Icons.star_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildModeChip(
                    'Favourites',
                    LibraryViewMode.favourites,
                    Icons.favorite_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildModeChip(
                    'Custom',
                    LibraryViewMode.custom,
                    Icons.person_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Filters & Exercise List options
            if (showExerciseList) ...[
              // 1. Category Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _categoryFilterOptions.map((cat) {
                    final isSel = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        selected: isSel,
                        label: Text(cat),
                        labelStyle: TextStyle(
                          color: isSel ? Colors.black : AppColors.textMain,
                          fontSize: 12,
                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                        ),
                        backgroundColor: AppColors.cardSurface,
                        selectedColor: AppColors.primary,
                        checkmarkColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isSel ? AppColors.primary : AppColors.border,
                          ),
                        ),
                        onSelected: (val) {
                          setState(() {
                            _selectedCategory = val ? cat : 'All';
                            _selectedSubCategory = 'All';
                          });
                          _applyFilters();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),

              // 2. Sub-Category Chips (for Legs or Back)
              if (_selectedCategory == 'Legs') ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        [
                          'All Legs',
                          'Quads',
                          'Hamstrings',
                          'Glutes',
                          'Calves',
                        ].map((sub) {
                          final isSel =
                              _selectedSubCategory == sub ||
                              (_selectedSubCategory == 'All' &&
                                  sub == 'All Legs');
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              selected: isSel,
                              label: Text(sub),
                              labelStyle: TextStyle(
                                color: isSel
                                    ? Colors.black
                                    : AppColors.textSecondary,
                                fontSize: 11.5,
                                fontWeight: isSel
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                              backgroundColor: AppColors.surfaceElevated,
                              selectedColor: AppColors.primary,
                              checkmarkColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: isSel
                                      ? AppColors.primary
                                      : AppColors.border,
                                ),
                              ),
                              onSelected: (val) {
                                setState(() {
                                  _selectedSubCategory = val ? sub : 'All Legs';
                                });
                                _applyFilters();
                              },
                            ),
                          );
                        }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
              ] else if (_selectedCategory == 'Back') ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        [
                          'All Back',
                          'Lats',
                          'Upper Back & Traps',
                          'Mid/Lower Back',
                        ].map((sub) {
                          final isSel =
                              _selectedSubCategory == sub ||
                              (_selectedSubCategory == 'All' &&
                                  sub == 'All Back');
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              selected: isSel,
                              label: Text(sub),
                              labelStyle: TextStyle(
                                color: isSel
                                    ? Colors.black
                                    : AppColors.textSecondary,
                                fontSize: 11.5,
                                fontWeight: isSel
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                              backgroundColor: AppColors.surfaceElevated,
                              selectedColor: AppColors.primary,
                              checkmarkColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: isSel
                                      ? AppColors.primary
                                      : AppColors.border,
                                ),
                              ),
                              onSelected: (val) {
                                setState(() {
                                  _selectedSubCategory = val ? sub : 'All Back';
                                });
                                _applyFilters();
                              },
                            ),
                          );
                        }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // 3. Assisting / Secondary Muscle Filter
              if (_availableSecondaryMuscles.length > 1) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Text(
                          'Assisting:',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ..._availableSecondaryMuscles.take(8).map((sec) {
                        final isSel = _selectedSecondary == sec;
                        final label = sec == 'All' ? 'All' : '+ $sec';
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            selected: isSel,
                            label: Text(label),
                            labelStyle: TextStyle(
                              color: isSel
                                  ? Colors.black
                                  : AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: isSel
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            backgroundColor: AppColors.surfaceElevated,
                            selectedColor: AppColors.primary,
                            checkmarkColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: isSel
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                            ),
                            onSelected: (val) {
                              setState(() {
                                _selectedSecondary = val ? sec : 'All';
                              });
                              _applyFilters();
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // 4. Filter chips (Equipment)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _equipmentOptions.map((eq) {
                    final isSel = _selectedEquipment == eq;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: isSel,
                        label: Text(eq),
                        labelStyle: TextStyle(
                          color: isSel ? Colors.black : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: isSel
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        backgroundColor: AppColors.cardSurface,
                        selectedColor: AppColors.primary,
                        checkmarkColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isSel ? AppColors.primary : AppColors.border,
                          ),
                        ),
                        onSelected: (val) {
                          setState(() {
                            _selectedEquipment = eq;
                          });
                          _applyFilters();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),

              // 5. Difficulty + Sort
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _difficultyOptions.map((diff) {
                          final isSel = _selectedDifficulty == diff;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              selected: isSel,
                              label: Text(diff),
                              labelStyle: TextStyle(
                                color: isSel
                                    ? Colors.black
                                    : AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: isSel
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              backgroundColor: AppColors.surfaceElevated,
                              selectedColor: AppColors.primary,
                              checkmarkColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: isSel
                                      ? AppColors.primary
                                      : AppColors.border,
                                ),
                              ),
                              onSelected: (val) {
                                setState(() {
                                  _selectedDifficulty = diff;
                                });
                                _applyFilters();
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedSort,
                        dropdownColor: AppColors.surfaceElevated,
                        icon: const Icon(
                          Icons.sort_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        style: const TextStyle(
                          color: AppColors.textMain,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'name_asc',
                            child: Text('A to Z'),
                          ),
                          DropdownMenuItem(
                            value: 'name_desc',
                            child: Text('Z to A'),
                          ),
                          DropdownMenuItem(
                            value: 'difficulty',
                            child: Text('Difficulty'),
                          ),
                          DropdownMenuItem(
                            value: 'recommended',
                            child: Text('Recommended'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedSort = val;
                            });
                            _applyFilters();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 6. Active Filters Banner with Clear All
              if (_hasActiveFilters) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.filter_list_rounded,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Filters active (${_displayExercises.length} results)',
                          style: const TextStyle(
                            color: AppColors.textMain,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: _clearAllFilters,
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.close_rounded,
                                color: Colors.redAccent,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Clear All',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),
            ],

            // Content switch: Exercise Cards List OR Catalogues
            if (showExerciseList) ...[
              // Section header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isSearching
                        ? 'SEARCH RESULTS (${_displayExercises.length})'
                        : '${_getModeTitle().toUpperCase()} (${_displayExercises.length})',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  if (_isSearching)
                    TextButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _currentMode = LibraryViewMode.mainCategories;
                        });
                        _applyFilters();
                      },
                      child: const Text(
                        'Back to Main',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              if (_displayExercises.isEmpty)
                _buildEmptyState()
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _displayExercises.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final ex = _displayExercises[index];
                    return _buildExerciseCard(ex);
                  },
                ),
            ] else if (_currentMode == LibraryViewMode.mainCategories) ...[
              // 8 Main Muscle Categories
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'MAIN MUSCLE CATEGORIES (8)',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  Text(
                    '${_allExercises.length} Total Exercises',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: ExerciseLibraryScreen.mainCategories.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final mg = ExerciseLibraryScreen.mainCategories[index];
                  final count = _getCountForCategory(mg.name);
                  return _buildMuscleGroupVisualCard(mg, count);
                },
              ),
            ] else if (_currentMode == LibraryViewMode.muscleCatalogues) ...[
              // 14/15 Target Muscle Catalogues
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TARGET MUSCLE CATALOGUES (14)',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  Text(
                    '${_allExercises.length} Exercises Seeded',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _muscleGroups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final mg = _muscleGroups[index];
                  final count =
                      _catalogueCounts[mg.name] ??
                      _allExercises
                          .where((e) => e.muscleGroupId == mg.id)
                          .length;
                  return _buildMuscleGroupVisualCard(mg, count);
                },
              ),
            ] else if (_currentMode == LibraryViewMode.modalityCatalogues) ...[
              // 6 Movement & Equipment Modality Catalogues
              const Text(
                'MOVEMENT & EQUIPMENT MODALITIES (6)',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),

              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: ExerciseLibraryScreen.modalityCategories.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final mod = ExerciseLibraryScreen.modalityCategories[index];
                  final count = _catalogueCounts[mod.name] ?? 0;
                  return _buildMuscleGroupVisualCard(mod, count);
                },
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  String _getModeTitle() {
    switch (_currentMode) {
      case LibraryViewMode.mainCategories:
        return 'Main Categories';
      case LibraryViewMode.muscleCatalogues:
        return 'Muscle Catalogues';
      case LibraryViewMode.modalityCatalogues:
        return 'Movement Modalities';
      case LibraryViewMode.allExercises:
        return 'All Exercises';
      case LibraryViewMode.recommended:
        return 'Trainer Recommended';
      case LibraryViewMode.favourites:
        return 'Favourite Exercises';
      case LibraryViewMode.custom:
        return 'Custom Exercises';
    }
  }

  Widget _buildModeChip(String label, LibraryViewMode mode, IconData icon) {
    final isSel = _currentMode == mode && !_isSearching;
    return ChoiceChip(
      selected: isSel,
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 15,
        color: isSel ? Colors.black : AppColors.textSecondary,
      ),
      label: Text(label),
      labelStyle: TextStyle(
        color: isSel ? Colors.black : AppColors.textMain,
        fontSize: 12.5,
        fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
      ),
      backgroundColor: AppColors.cardSurface,
      selectedColor: AppColors.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSel ? AppColors.primary : AppColors.border),
      ),
      onSelected: (val) {
        if (val) {
          setState(() {
            _currentMode = mode;
          });
          _applyFilters();
        }
      },
    );
  }

  Widget _buildMuscleGroupVisualCard(MuscleGroup mg, int exerciseCount) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MuscleDetailScreen(muscleGroup: mg),
          ),
        ).then((_) => _loadData());
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Muscle illustration image
            SizedBox(
              width: 105,
              height: 105,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildMuscleImage(mg.imagePath),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.cardSurface.withValues(alpha: 0.6),
                          AppColors.cardSurface,
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          mg.name,
                          style: const TextStyle(
                            color: AppColors.textMain,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            '$exerciseCount exercises',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      mg.description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.primary,
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMuscleImage(String? path) {
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('assets/')) {
        return Image.asset(
          path,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackMuscleIcon(),
        );
      } else {
        final f = File(path);
        if (f.existsSync()) {
          return Image.file(
            f,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackMuscleIcon(),
          );
        }
      }
    }
    return _buildFallbackMuscleIcon();
  }

  Widget _buildFallbackMuscleIcon() {
    return Container(
      color: AppColors.surfaceElevated,
      child: const Center(
        child: Icon(
          Icons.fitness_center_rounded,
          color: AppColors.primary,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildExerciseCard(Exercise ex) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ExerciseDetailScreen(exercise: ex, onUpdated: _loadData),
          ),
        ).then((_) => _loadData());
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Exercise Demonstration Image with Video Badge
            SizedBox(
              width: 115,
              height: 115,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExerciseImageWidget(
                    imagePath: ex.imagePath,
                    personalPhotoPath: ex.personalPhotoPath,
                    exerciseName: ex.name,
                    borderRadius: BorderRadius.zero,
                    fit: BoxFit.cover,
                  ),
                  if (ExerciseMediaService.instance.hasDemonstration(ex.name))
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.6),
                            width: 0.8,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_arrow_rounded,
                              color: AppColors.primary,
                              size: 12,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'VIDEO',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Builder(
                  builder: (context) {
                    final term = ExerciseTerminologyService.instance
                        .getTerminology(id: ex.id, name: ex.name);
                    final displayName =
                        term?.recommendedDisplayName.isNotEmpty == true
                        ? term!.recommendedDisplayName
                        : ex.name;
                    final primaryAlias = term != null && term.aliases.isNotEmpty
                        ? term.aliases.firstWhere(
                            (a) =>
                                a.toLowerCase() != displayName.toLowerCase() &&
                                a.toLowerCase() != ex.name.toLowerCase(),
                            orElse: () => term.aliases.first,
                          )
                        : '';
                    final friendlyMuscle = ExerciseTerminologyService.instance
                        .getFriendlyMuscleName(ex.muscleGroupName);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                style: const TextStyle(
                                  color: AppColors.textMain,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Favourite toggle
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                ex.isFavourite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: ex.isFavourite
                                    ? Colors.redAccent
                                    : AppColors.textMuted,
                                size: 20,
                              ),
                              onPressed: () => _toggleFavourite(ex),
                            ),
                          ],
                        ),
                        if (primaryAlias.isNotEmpty &&
                            primaryAlias.toLowerCase() !=
                                displayName.toLowerCase()) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Also: $primaryAlias',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          '$friendlyMuscle • ${ex.equipment}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Target: ${ex.target}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (ex.secondaryMuscles.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Secondary: ${ex.secondaryMuscles}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                ex.difficulty,
                                style: TextStyle(
                                  color: ex.difficulty == 'Beginner'
                                      ? Colors.greenAccent
                                      : (ex.difficulty == 'Advanced'
                                            ? Colors.orangeAccent
                                            : AppColors.primary),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (ex.isCompound) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'Compound',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 8),
                            Text(
                              '${ex.defaultSets}×${ex.defaultReps} reps',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: AppColors.textMuted,
                              size: 12,
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    String msg;
    if (_isSearching) {
      msg = 'No exercises match "${_searchController.text.trim()}".';
    } else if (_currentMode == LibraryViewMode.favourites) {
      msg = 'No favourite exercises yet. Tap the heart icon on any exercise to add it to your favourites!';
    } else if (_currentMode == LibraryViewMode.custom) {
      msg = 'No custom exercises yet. Tap the + button in the top right to create your first personal exercise!';
    } else {
      msg = 'No exercises found for the selected filter.';
    }

    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(
            Icons.search_off_rounded,
            color: AppColors.textMuted,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
