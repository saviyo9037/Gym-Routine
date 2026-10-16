import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/exercise.dart';
import '../models/muscle_group.dart';
import '../services/database_service.dart';
import '../services/media_service.dart';
import '../widgets/exercise_image_widget.dart';

class AddEditExerciseScreen extends StatefulWidget {
  final Exercise? exerciseToEdit;
  final int? defaultMuscleGroupId;
  final String? defaultMuscleGroupName;

  const AddEditExerciseScreen({
    super.key,
    this.exerciseToEdit,
    this.defaultMuscleGroupId,
    this.defaultMuscleGroupName,
  });

  @override
  State<AddEditExerciseScreen> createState() => _AddEditExerciseScreenState();
}

class _AddEditExerciseScreenState extends State<AddEditExerciseScreen> {
  final DatabaseService _dbService = DatabaseService();
  final MediaService _mediaService = MediaService.instance;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _targetController;
  late TextEditingController _descriptionController;
  late TextEditingController _instructionsController;
  late TextEditingController _equipmentController;
  late TextEditingController _mistakesController;
  late TextEditingController _setsController;
  late TextEditingController _repsController;
  late TextEditingController _weightController;
  late TextEditingController _restController;
  late TextEditingController _notesController;

  List<MuscleGroup> _muscleGroups = [];
  MuscleGroup? _selectedMuscleGroup;
  String? _imagePath;
  String? _personalPhotoPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final ex = widget.exerciseToEdit;

    _nameController = TextEditingController(text: ex?.name ?? '');
    _targetController = TextEditingController(text: ex?.target ?? '');
    _descriptionController = TextEditingController(text: ex?.description ?? '');
    _instructionsController = TextEditingController(
      text: ex?.instructions ?? '',
    );
    _equipmentController = TextEditingController(
      text: ex?.equipment ?? 'Dumbbells',
    );
    _mistakesController = TextEditingController(text: ex?.commonMistakes ?? '');
    _setsController = TextEditingController(text: '${ex?.defaultSets ?? 3}');
    _repsController = TextEditingController(text: '${ex?.defaultReps ?? 10}');
    _weightController = TextEditingController(
      text: '${ex?.defaultWeightKg ?? 15.0}',
    );
    _restController = TextEditingController(text: '${ex?.restSeconds ?? 90}');
    _notesController = TextEditingController(text: ex?.personalNotes ?? '');

    _imagePath = ex?.imagePath;
    _personalPhotoPath = ex?.personalPhotoPath;

    _loadMuscleGroups();
  }

  Future<void> _loadMuscleGroups() async {
    final groups = await _dbService.getAllMuscleGroups();
    if (mounted) {
      setState(() {
        _muscleGroups = groups;
        if (widget.exerciseToEdit != null) {
          _selectedMuscleGroup = groups
              .where((g) => g.id == widget.exerciseToEdit!.muscleGroupId)
              .firstOrNull;
        } else if (widget.defaultMuscleGroupId != null) {
          _selectedMuscleGroup = groups
              .where((g) => g.id == widget.defaultMuscleGroupId)
              .firstOrNull;
        }
        _selectedMuscleGroup ??= groups.isNotEmpty ? groups.first : null;
        _isLoading = false;
      });
    }
  }

  Future<void> _capturePhoto() async {
    final path = await _mediaService.capturePhoto();
    if (path != null) {
      setState(() => _personalPhotoPath = path);
    }
  }

  Future<void> _pickGalleryPhoto() async {
    final path = await _mediaService.pickPhotoFromGallery();
    if (path != null) {
      setState(() => _personalPhotoPath = path);
    }
  }

  Future<void> _saveExercise() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMuscleGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a muscle group')),
      );
      return;
    }

    final newExercise = Exercise(
      id: widget.exerciseToEdit?.id,
      muscleGroupId: _selectedMuscleGroup!.id ?? 1,
      muscleGroupName: _selectedMuscleGroup!.name,
      name: _nameController.text.trim(),
      target: _targetController.text.trim().isNotEmpty
          ? _targetController.text.trim()
          : _selectedMuscleGroup!.name,
      description: _descriptionController.text.trim(),
      instructions: _instructionsController.text.trim(),
      equipment: _equipmentController.text.trim(),
      commonMistakes: _mistakesController.text.trim(),
      defaultSets: int.tryParse(_setsController.text) ?? 3,
      defaultReps: int.tryParse(_repsController.text) ?? 10,
      defaultWeightKg: double.tryParse(_weightController.text) ?? 15.0,
      restSeconds: int.tryParse(_restController.text) ?? 90,
      imagePath: _imagePath,
      personalPhotoPath: _personalPhotoPath,
      personalNotes: _notesController.text.trim(),
      isCustom: true,
    );

    if (widget.exerciseToEdit == null) {
      await _dbService.insertExercise(newExercise);
    } else {
      await _dbService.updateExercise(newExercise);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${newExercise.name} saved successfully'),
          backgroundColor: AppColors.successDark,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  Future<void> _deleteExercise() async {
    if (widget.exerciseToEdit?.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text(
          'Delete Exercise?',
          style: TextStyle(color: AppColors.textMain),
        ),
        content: Text(
          'Are you sure you want to remove "${widget.exerciseToEdit!.name}"?',
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _dbService.deleteExercise(widget.exerciseToEdit!.id!);
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Exercise')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isEditing = widget.exerciseToEdit != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          isEditing ? 'EDIT EXERCISE' : 'NEW EXERCISE',
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              onPressed: _deleteExercise,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton(
              onPressed: _saveExercise,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
              ),
              child: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo Preview & Actions
              Center(
                child: Column(
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: ExerciseImageWidget(
                        imagePath: _imagePath,
                        personalPhotoPath: _personalPhotoPath,
                        exerciseName: _nameController.text.isNotEmpty
                            ? _nameController.text
                            : 'Exercise',
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _capturePhoto,
                          icon: const Icon(Icons.camera_alt_outlined, size: 16),
                          label: const Text('Take Photo'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.border),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _pickGalleryPhoto,
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            size: 16,
                          ),
                          label: const Text('Gallery'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textMain,
                            side: const BorderSide(color: AppColors.border),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Muscle Group Selector
              const Text(
                'MUSCLE GROUP',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<MuscleGroup>(
                    value: _selectedMuscleGroup,
                    isExpanded: true,
                    dropdownColor: AppColors.surfaceElevated,
                    items: _muscleGroups.map((mg) {
                      return DropdownMenuItem<MuscleGroup>(
                        value: mg,
                        child: Text(
                          mg.name,
                          style: const TextStyle(
                            color: AppColors.textMain,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) =>
                        setState(() => _selectedMuscleGroup = val),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Name
              const Text(
                'EXERCISE NAME',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'e.g. Incline Dumbbell Hammer Curl',
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Exercise name is required'
                    : null,
              ),
              const SizedBox(height: 16),

              // Target & Equipment
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TARGET MUSCLE',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _targetController,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Biceps Peak',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'EQUIPMENT',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _equipmentController,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Dumbbells',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Defaults: Sets, Reps, Weight, Rest
              const Text(
                'DEFAULT PARAMETERS',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _setsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Sets'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _repsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Reps'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _weightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Weight',
                        suffixText: 'kg',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _restController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Rest',
                        suffixText: 's',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Instructions
              const Text(
                'STEP-BY-STEP INSTRUCTIONS',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _instructionsController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Describe setup, tempo, range of motion...',
                ),
              ),
              const SizedBox(height: 16),

              // Common Mistakes
              const Text(
                'COMMON MISTAKES',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _mistakesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'e.g. Swinging elbows, locking out too fast...',
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
