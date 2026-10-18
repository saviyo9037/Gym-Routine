import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../widgets/load_error_view.dart';
import '../models/muscle_group.dart';
import '../models/exercise.dart';
import '../models/media_attachment.dart';
import '../services/database_service.dart';
import '../services/media_service.dart';
import '../services/exercise_media_service.dart';
import '../services/exercise_terminology_service.dart';
import '../widgets/exercise_image_widget.dart';
import '../widgets/media_attachment_section.dart';
import 'exercise_detail_screen.dart';
import 'add_edit_exercise_screen.dart';
import '../core/dev_log.dart';

class MuscleDetailScreen extends StatefulWidget {
  final MuscleGroup muscleGroup;

  const MuscleDetailScreen({super.key, required this.muscleGroup});

  @override
  State<MuscleDetailScreen> createState() => _MuscleDetailScreenState();
}

class _MuscleDetailScreenState extends State<MuscleDetailScreen> {
  final DatabaseService _dbService = DatabaseService();
  final MediaService _mediaService = MediaService.instance;

  late MuscleGroup _muscleGroup;
  List<Exercise> _allExercises = [];
  List<Exercise> _filteredExercises = [];
  List<MediaAttachment> _media = [];
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  String _selectedEquipment = 'All';
  String _selectedDifficulty = 'All';
  String _selectedSort = 'name_asc';
  String _selectedSubCategory = 'All';
  String _selectedSecondaryMuscle = 'All';

  final List<String> _equipmentFilters = [
    'All',
    'Dumbbells',
    'Barbell',
    'Cable',
    'Machine',
    'Bodyweight',
    'EZ-Bar',
  ];

  final List<String> _difficultyFilters = [
    'All',
    'Beginner',
    'Intermediate',
    'Advanced',
  ];

  bool get _isLegsCategory {
    final n = _muscleGroup.name.toLowerCase();
    return n == 'legs';
  }

  bool get _isBackCategory {
    final n = _muscleGroup.name.toLowerCase();
    return n == 'back';
  }

  List<String> get _subCategoryOptions {
    if (_isLegsCategory) {
      return ['All Legs', 'Quads', 'Hamstrings', 'Glutes', 'Calves'];
    }
    if (_isBackCategory) {
      return ['All Back', 'Lats', 'Upper Back & Traps', 'Mid/Lower Back'];
    }
    return [];
  }

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
    return _selectedEquipment != 'All' ||
        _selectedDifficulty != 'All' ||
        _searchController.text.trim().isNotEmpty ||
        isSubActive ||
        _selectedSecondaryMuscle != 'All';
  }

  void _clearAllFilters() {
    setState(() {
      _selectedEquipment = 'All';
      _selectedDifficulty = 'All';
      _selectedSubCategory = _isLegsCategory
          ? 'All Legs'
          : (_isBackCategory ? 'All Back' : 'All');
      _selectedSecondaryMuscle = 'All';
      _searchController.clear();
    });
    _filterExercises();
  }

  @override
  void initState() {
    super.initState();
    _muscleGroup = widget.muscleGroup;
    _selectedSubCategory = _isLegsCategory
        ? 'All Legs'
        : (_isBackCategory ? 'All Back' : 'All');
    _loadData();
    _searchController.addListener(_filterExercises);
  }

  bool _loadFailed = false;

  Future<void> _loadData() async {
    try {
      await _loadDataImpl();
      if (mounted && _loadFailed) setState(() => _loadFailed = false);
    } catch (e, st) {
      devLog('muscle_detail_screen.dart: load failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _isLoading = false;
      });
    }
  }

  void _retryLoad() {
    setState(() {
      _loadFailed = false;
      _isLoading = true;
    });
    _loadData();
  }

  Future<void> _loadDataImpl() async {
    await ExerciseMediaService.instance.initialize();
    final exList = await _dbService.getCatalogueExercises(
      _muscleGroup.name,
      sortBy: _selectedSort,
    );
    final mediaList = _muscleGroup.id != null
        ? await _dbService.getMediaAttachments('muscle', _muscleGroup.id!)
        : <MediaAttachment>[];
    if (mounted) {
      setState(() {
        _allExercises = exList;
        _media = mediaList;
        _isLoading = false;
      });
      _filterExercises();
    }
  }

  void _filterExercises() {
    final query = _searchController.text.trim().toLowerCase();
    List<Exercise> list = List.from(_allExercises);

    // 1. Filter by sub-category (for Legs or Back)
    if (_isLegsCategory &&
        _selectedSubCategory != 'All' &&
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
    } else if (_isBackCategory &&
        _selectedSubCategory != 'All' &&
        _selectedSubCategory != 'All Back') {
      final sub = _selectedSubCategory.toLowerCase();
      if (sub == 'lats') {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'lats')
            .toList();
      } else if (sub.contains('trap') || sub.contains('upper back')) {
        list = list
            .where(
              (e) => e.muscleGroupName.toLowerCase() == 'upper back and traps',
            )
            .toList();
      } else if (sub.contains('mid') || sub == 'back') {
        list = list
            .where((e) => e.muscleGroupName.toLowerCase() == 'back')
            .toList();
      }
    }

    // 2. Filter by secondary muscle (if selected)
    if (_selectedSecondaryMuscle != 'All') {
      list = list
          .where(
            (e) => e.secondaryMuscles.toLowerCase().contains(
              _selectedSecondaryMuscle.toLowerCase(),
            ),
          )
          .toList();
    }

    // 3. Filter by equipment
    if (_selectedEquipment != 'All') {
      list = list.where((e) {
        return e.equipment.toLowerCase().contains(
          _selectedEquipment.toLowerCase(),
        );
      }).toList();
    }

    // 4. Filter by difficulty
    if (_selectedDifficulty != 'All') {
      list = list.where((e) {
        return e.difficulty.toLowerCase() == _selectedDifficulty.toLowerCase();
      }).toList();
    }

    // 5. Filter by search query via Kerala gym-friendly terminology service
    if (query.isNotEmpty) {
      list = list.where((e) {
        return ExerciseTerminologyService.instance.matchesSearch(e, query);
      }).toList();
    }

    // 6. Sort list
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
      _filteredExercises = list;
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
    _filterExercises();
  }

  Future<void> _captureMusclePhoto() async {
    final path = await _mediaService.capturePhoto();
    if (path != null) {
      final updated = _muscleGroup.copyWith(imagePath: path);
      await _dbService.updateMuscleGroup(updated);
      setState(() => _muscleGroup = updated);
      _loadData();
    }
  }

  Future<void> _pickMusclePhoto() async {
    final path = await _mediaService.pickPhotoFromGallery();
    if (path != null) {
      final updated = _muscleGroup.copyWith(imagePath: path);
      await _dbService.updateMuscleGroup(updated);
      setState(() => _muscleGroup = updated);
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
    if (_loadFailed) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(),
        body: LoadErrorView(onRetry: _retryLoad),
      );
    }
    final isBiceps = _muscleGroup.name.toLowerCase() == 'biceps';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        key: PageStorageKey<String>('muscle_detail_scroll_${_muscleGroup.id}'),
        slivers: [
          // Collapsible Banner Header
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppColors.background,
            actions: [
              IconButton(
                icon: const Icon(Icons.add_rounded, color: AppColors.primary),
                tooltip: 'Add Exercise to ${_muscleGroup.name}',
                onPressed: () async {
                  final res = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddEditExerciseScreen(
                        defaultMuscleGroupId: _muscleGroup.id,
                        defaultMuscleGroupName: _muscleGroup.name,
                      ),
                    ),
                  );
                  if (res == true) _loadData();
                },
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.textMain,
                ),
                color: AppColors.surfaceElevated,
                onSelected: (val) {
                  if (val == 'camera') _captureMusclePhoto();
                  if (val == 'gallery') _pickMusclePhoto();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'camera',
                    child: Row(
                      children: [
                        Icon(
                          Icons.camera_alt_outlined,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text('Take Cover Photo'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'gallery',
                    child: Row(
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          color: AppColors.textMain,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text('Import from Gallery'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                _muscleGroup.name.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textMain,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: -0.3,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _buildMuscleBanner(),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.background.withValues(alpha: 0.8),
                          AppColors.background,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Anatomy & Muscle group description card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: AppColors.primary,
                              size: 18,
                            ),
                            const Text(
                              'ANATOMY & FUNCTION',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
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
                                '${_allExercises.length} Total Exercises',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _muscleGroup.description,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Special Biceps Banner Highlight if Biceps
                  if (isBiceps) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF261806), Color(0xFF141414)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.star_rounded,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'COMPLETE 12-EXERCISE BICEPS CATALOGUE',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Every curl variation features distinct demonstration imagery, biomechanics breakdown, sets/reps suggestions, and common error checklists.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Media & Posing Cues
                  MediaAttachmentSection(
                    entityType: 'muscle',
                    entityId: _muscleGroup.id ?? 0,
                    entityTitle: '${_muscleGroup.name} Anatomy & Cues',
                    sectionTitle:
                        '${_muscleGroup.name.toUpperCase()} MEDIA & POSING CUES',
                  ),

                  const SizedBox(height: 16),

                  // Search field within this muscle group
                  TextField(
                    controller: _searchController,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search ${_muscleGroup.name} exercises...',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(
                                Icons.clear,
                                color: AppColors.textSecondary,
                                size: 18,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                _filterExercises();
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),

                  // Sub-category filter chips (for Legs: All Legs, Quads, Hamstrings, Glutes, Calves; for Back: All Back, Lats, Traps, Mid/Lower Back)
                  if (_subCategoryOptions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.alt_route_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isLegsCategory
                              ? 'LEG SUB-GROUPS'
                              : 'BACK SUB-GROUPS',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _subCategoryOptions.map((sub) {
                          final isSel = _selectedSubCategory == sub;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
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
                                    : FontWeight.normal,
                              ),
                              backgroundColor: AppColors.cardSurface,
                              selectedColor: AppColors.primary,
                              checkmarkColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: isSel
                                      ? AppColors.primary
                                      : AppColors.border,
                                ),
                              ),
                              onSelected: (val) {
                                setState(() {
                                  _selectedSubCategory = sub;
                                });
                                _filterExercises();
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],

                  // Secondary / Assisting Muscle Filter Chips
                  if (_availableSecondaryMuscles.length > 1) ...[
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Icon(
                          Icons.hub_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'ASSISTING / SECONDARY MUSCLE',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _availableSecondaryMuscles.take(10).map((
                          sec,
                        ) {
                          final isSel = _selectedSecondaryMuscle == sec;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              selected: isSel,
                              label: Text(
                                sec == 'All' ? 'Primary Only' : '+ $sec',
                              ),
                              labelStyle: TextStyle(
                                color: isSel
                                    ? Colors.black
                                    : AppColors.textSecondary,
                                fontSize: 11.5,
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
                                  color: isSel
                                      ? AppColors.primary
                                      : AppColors.border,
                                ),
                              ),
                              onSelected: (val) {
                                setState(() {
                                  _selectedSecondaryMuscle = sec;
                                });
                                _filterExercises();
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Equipment Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _equipmentFilters.map((eq) {
                        final isSel = _selectedEquipment == eq;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            selected: isSel,
                            label: Text(eq),
                            labelStyle: TextStyle(
                              color: isSel
                                  ? Colors.black
                                  : AppColors.textSecondary,
                              fontSize: 11.5,
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
                                color: isSel
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                            ),
                            onSelected: (val) {
                              setState(() {
                                _selectedEquipment = eq;
                              });
                              _filterExercises();
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Difficulty Filter Chips & Sort
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _difficultyFilters.map((diff) {
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
                                    _filterExercises();
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
                                _filterExercises();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Active Filters banner & Clear All
                  if (_hasActiveFilters) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.filter_alt_rounded,
                            size: 15,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Showing ${_filteredExercises.length} filtered exercises',
                              style: const TextStyle(
                                color: AppColors.textMain,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _clearAllFilters,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.close_rounded,
                                    size: 13,
                                    color: Colors.redAccent,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Clear Filters',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 11,
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
                    const SizedBox(height: 12),
                  ],

                  // Header with Count
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        'EXERCISES (${_filteredExercises.length})',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        'Showing ${_filteredExercises.length} of ${_allExercises.length}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),

          // Exercise cards: lazy sliver (only visible cards are built).
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
            )
          else if (_filteredExercises.isEmpty)
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    const Icon(
                      Icons.search_off_rounded,
                      color: AppColors.textMuted,
                      size: 40,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No ${_muscleGroup.name} exercises found matching your filter.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: _filteredExercises.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _buildExerciseCard(_filteredExercises[index]),
              ),
            ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Media attachments section
                  if (_media.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const Text(
                      'PROGRESS PHOTOS & FORM ATTACHMENTS',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: _media
                          .map(
                            (m) => Chip(
                              label: Text(
                                m.title,
                                style: const TextStyle(
                                  color: AppColors.textMain,
                                  fontSize: 12,
                                ),
                              ),
                              backgroundColor: AppColors.cardSurface,
                            ),
                          )
                          .toList(),
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMuscleBanner() {
    if (_muscleGroup.imagePath != null && _muscleGroup.imagePath!.isNotEmpty) {
      if (_muscleGroup.imagePath!.startsWith('assets/')) {
        return Image.asset(
          _muscleGroup.imagePath!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultMuscleVisual(),
        );
      } else {
        final f = File(_muscleGroup.imagePath!);
        if (f.existsSync()) {
          return Image.file(
            f,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildDefaultMuscleVisual(),
          );
        }
      }
    }
    return _buildDefaultMuscleVisual();
  }

  Widget _buildDefaultMuscleVisual() {
    return Container(
      color: AppColors.cardSurface,
      child: Center(
        child: Icon(
          Icons.fitness_center_rounded,
          color: AppColors.primary.withValues(alpha: 0.3),
          size: 64,
        ),
      ),
    );
  }

  Widget _buildExerciseCard(Exercise ex) {
    return InkWell(
      key: ValueKey('muscle_card_${ex.id}'),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ExerciseDetailScreen(exercise: ex, onUpdated: _loadData),
          ),
        );
        _loadData();
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
            // Exercise Demonstration Image (Large and distinct) with Video Badge
            SizedBox(
              width: 120,
              height: 120,
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
                            IconButton(
                              tooltip: 'Toggle favourite',
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
                          '${ex.equipment} • ${ex.target}',
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
                          'Suggested: ${ex.defaultSets} sets × ${ex.defaultReps} reps',
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
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.border),
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
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Flexible(
                                  child: Text(
                                    'View Details',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: AppColors.primary,
                                  size: 11,
                                ),
                              ],
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
}
