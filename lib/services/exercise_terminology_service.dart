import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/exercise.dart';
import '../models/exercise_terminology.dart';

class ExerciseTerminologyService {
  static final ExerciseTerminologyService instance =
      ExerciseTerminologyService._internal();

  ExerciseTerminologyService._internal();

  bool _isInitialized = false;
  final Map<int, ExerciseTerminology> _byId = {};
  final Map<String, ExerciseTerminology> _byName = {};

  static const Map<String, String> _muscleSlangMap = {
    'wings': 'lats',
    'wing': 'lats',
    'quad': 'quadriceps',
    'quads': 'quadriceps',
    'quadriceps': 'quadriceps',
    'thigh': 'quadriceps',
    'thighs': 'quadriceps',
    'ham': 'hamstrings',
    'hams': 'hamstrings',
    'hamstring': 'hamstrings',
    'hamstrings': 'hamstrings',
    'delts': 'shoulders',
    'delt': 'shoulders',
    'shoulder': 'shoulders',
    'traps': 'upper back and traps',
    'trap': 'upper back and traps',
    'neck': 'upper back and traps',
    'pec': 'chest',
    'pecs': 'chest',
    'chest': 'chest',
    'bicep': 'biceps',
    'biceps': 'biceps',
    'arms': 'biceps',
    'arm': 'biceps',
    'tricep': 'triceps',
    'triceps': 'triceps',
    'forearm': 'forearms',
    'forearms': 'forearms',
    'grip': 'forearms',
    'wrists': 'forearms',
    'wrist': 'forearms',
    'calves': 'calves',
    'calf': 'calves',
    'shins': 'calves',
    'abs': 'abs and core',
    'ab': 'abs and core',
    'core': 'abs and core',
    'six pack': 'abs and core',
    'sixpack': 'abs and core',
    'obliques': 'abs and core',
    'butt': 'glutes',
    'glute': 'glutes',
    'glutes': 'glutes',
    'hips': 'glutes',
    'leg': 'legs',
    'legs': 'legs',
    'cardio': 'cardio',
    'hiit': 'cardio',
    'stamina': 'cardio',
    'aerobic': 'cardio',
    'full body': 'full body',
    'fullbody': 'full body',
  };

  Future<void> initialize({String? jsonContent, bool force = false}) async {
    if (_isInitialized && !force && _byId.isNotEmpty) return;

    try {
      final jsonStr =
          jsonContent ??
          await rootBundle.loadString('assets/exercise_terminology.json');
      final Map<String, dynamic> rawMap = json.decode(jsonStr);
      loadFromJson(rawMap);
    } catch (_) {
      try {
        final f = File('assets/exercise_terminology.json');
        if (f.existsSync()) {
          final content = await f.readAsString();
          final Map<String, dynamic> rawMap = json.decode(content);
          loadFromJson(rawMap);
          return;
        }
      } catch (_) {}
      _isInitialized = true;
    }
  }

  void loadFromJson(Map<String, dynamic> rawMap) {
    _byId.clear();
    _byName.clear();

    for (final entry in rawMap.entries) {
      final term = ExerciseTerminology.fromMap(
        Map<String, dynamic>.from(entry.value as Map),
      );
      if (term.exerciseId > 0) {
        _byId[term.exerciseId] = term;
      }
      _byName[entry.key] = term;
      _byName[_normalize(entry.key)] = term;
      _byName[_normalize(term.recommendedDisplayName)] = term;
    }
    _isInitialized = true;
  }

  String _normalize(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _getAcronym(String text) {
    return text
        .split(RegExp(r'[\s\-]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toLowerCase())
        .join('');
  }

  ExerciseTerminology? getTerminology({int? id, String? name}) {
    if (id != null && id > 0 && _byId.containsKey(id)) {
      return _byId[id];
    }
    if (name != null && name.isNotEmpty) {
      if (_byName.containsKey(name)) {
        return _byName[name];
      }
      return _byName[_normalize(name)];
    }
    return null;
  }

  ExerciseTerminology? getTerminologyFor(int? exerciseId, String name) {
    return getTerminology(id: exerciseId, name: name);
  }

  String getDisplayName(String name, {int? id}) {
    final term = getTerminology(id: id, name: name);
    return term?.recommendedDisplayName.isNotEmpty == true
        ? term!.recommendedDisplayName
        : name;
  }

  List<String> getAliases(String name, {int? id}) {
    final term = getTerminology(id: id, name: name);
    return term?.aliases ?? const [];
  }

  String? getKeralaGymNotes(String name, {int? id}) {
    final term = getTerminology(id: id, name: name);
    return term?.keralaGymNotes;
  }

  String? getMalayalamScript(String name, {int? id}) {
    final term = getTerminology(id: id, name: name);
    return term?.malayalamScript;
  }

  String getFriendlyMuscleName(String muscleGroup) {
    switch (muscleGroup.trim().toLowerCase()) {
      case 'chest':
        return 'Chest';
      case 'lats':
        return 'Back (Lats)';
      case 'back':
        return 'Back (General)';
      case 'upper back and traps':
        return 'Upper Back & Traps';
      case 'shoulders':
        return 'Shoulders (Delts)';
      case 'biceps':
        return 'Biceps';
      case 'triceps':
        return 'Triceps';
      case 'forearms':
        return 'Forearms & Grip';
      case 'quadriceps':
        return 'Quads (Front Thighs)';
      case 'hamstrings':
        return 'Hamstrings (Back of Thighs)';
      case 'glutes':
        return 'Glutes (Hips)';
      case 'calves':
        return 'Calves';
      case 'abs and core':
        return 'Abs & Core';
      case 'full body':
        return 'Full Body';
      case 'cardio':
        return 'Cardio & Conditioning';
      default:
        return muscleGroup;
    }
  }

  bool matchesSearch(
    Exercise exercise,
    String rawQuery, {
    bool matchSecondary = false,
  }) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return true;

    // 1. Muscle slang query (e.g. "wings", "quads", "hams", "delts", "thighs", "pecs", "legs")
    if (_muscleSlangMap.containsKey(query)) {
      final targetMg = _muscleSlangMap[query]!;
      if (targetMg == 'legs') {
        const legGroups = ['quadriceps', 'hamstrings', 'glutes', 'calves'];
        if (legGroups.contains(exercise.muscleGroupName.toLowerCase())) {
          return true;
        }
        if (matchSecondary) {
          final sec = exercise.secondaryMuscles.toLowerCase();
          return sec.contains('quad') ||
              sec.contains('hamstring') ||
              sec.contains('glute') ||
              sec.contains('calf');
        }
        return false;
      }
      if (targetMg == 'back') {
        const backGroups = ['back', 'lats', 'upper back and traps'];
        if (backGroups.contains(exercise.muscleGroupName.toLowerCase())) {
          return true;
        }
        if (matchSecondary) {
          final sec = exercise.secondaryMuscles.toLowerCase();
          return sec.contains('back') ||
              sec.contains('lat') ||
              sec.contains('rhomboid') ||
              sec.contains('trap');
        }
        return false;
      }
      if (exercise.muscleGroupName.toLowerCase() == targetMg) {
        return true;
      }
      if (matchSecondary &&
          exercise.secondaryMuscles.toLowerCase().contains(targetMg)) {
        return true;
      }
      return false;
    }

    // 2. Equipment abbreviations (e.g. "db", "bb", "ez", "bw")
    if (query == 'db') {
      return exercise.equipment.toLowerCase().contains('dumbbell');
    }
    if (query == 'bb') {
      return exercise.equipment.toLowerCase().contains('barbell');
    }
    if (query == 'ez' || query == 'ez-bar' || query == 'ez bar') {
      return exercise.equipment.toLowerCase().contains('ez') ||
          exercise.name.toLowerCase().contains('ez');
    }
    if (query == 'bw') {
      return exercise.equipment.toLowerCase().contains('bodyweight') ||
          exercise.equipment.toLowerCase().contains('body weight');
    }

    // 3. Direct check on Exercise Name, Primary Muscle Group, and Equipment
    if (exercise.name.toLowerCase().contains(query)) {
      return true;
    }
    if (exercise.muscleGroupName.toLowerCase().contains(query)) {
      return true;
    }
    if (exercise.equipment.toLowerCase().contains(query)) {
      return true;
    }
    if (matchSecondary &&
        exercise.secondaryMuscles.toLowerCase().contains(query)) {
      return true;
    }
    if (exercise.target.toLowerCase().contains(query)) {
      return true;
    }

    // 4. Terminology metadata & verified aliases check
    final term = getTerminology(id: exercise.id, name: exercise.name);
    if (term != null) {
      if (term.recommendedDisplayName.toLowerCase().contains(query)) {
        return true;
      }
      if (term.formalName.toLowerCase().contains(query)) {
        return true;
      }
      if (term.keralaGymNotes.toLowerCase().contains(query)) {
        return true;
      }
      if (term.malayalamScript.toLowerCase().contains(query)) {
        return true;
      }

      for (final alias in term.aliases) {
        final aLower = alias.toLowerCase();
        if (aLower.contains(query) || query.contains(aLower)) {
          return true;
        }
        if (_normalize(alias) == _normalize(query)) {
          return true;
        }
      }
    }

    // 5. Acronym match (e.g. "rdl" matches Romanian Deadlift if acronym matches)
    final normQuery = _normalize(query);
    if (normQuery.length >= 2) {
      final acronym = _getAcronym(exercise.name);
      if (acronym.length >= 2 && acronym == normQuery) {
        return true;
      }
      if (term != null) {
        final recAcronym = _getAcronym(term.recommendedDisplayName);
        if (recAcronym.length >= 2 && recAcronym == normQuery) {
          return true;
        }
      }
    }

    // 6. Longer full-text search in description/instructions (min 4 chars to avoid noise)
    if (query.length >= 4 && !_muscleSlangMap.containsKey(query)) {
      if (exercise.description.toLowerCase().contains(query)) {
        return true;
      }
      if (exercise.instructions.toLowerCase().contains(query)) {
        return true;
      }
    }

    return false;
  }
}
