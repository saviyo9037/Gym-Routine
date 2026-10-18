import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/training_plan.dart';
import '../services/training_plan_service.dart';
import '../widgets/premium_upsell.dart';
import 'training_plan_editor_screen.dart';

/// Lists the user's weekly training plans: create, edit, duplicate, activate
/// and delete (with confirmation). Works fully offline.
class TrainingPlansScreen extends StatefulWidget {
  const TrainingPlansScreen({super.key});

  @override
  State<TrainingPlansScreen> createState() => _TrainingPlansScreenState();
}

class _TrainingPlansScreenState extends State<TrainingPlansScreen> {
  final _service = TrainingPlanService();
  List<TrainingPlan> _plans = [];
  bool _loading = true;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final plans = await _service.listPlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your plans.';
      });
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openEditor([TrainingPlan? plan]) async {
    // Free accounts keep up to PremiumService.freePlanLimit plans; creating
    // more needs Premium. Editing existing plans is never gated.
    if (plan == null &&
        !await PremiumGate.ensureCanCreatePlan(context, _plans.length)) {
      return;
    }
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TrainingPlanEditorScreen(planId: plan?.id),
      ),
    );
    if (saved == true) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _duplicate(TrainingPlan plan) async {
    if (!await PremiumGate.ensureCanCreatePlan(context, _plans.length)) return;
    try {
      await _service.duplicatePlan(plan.id!);
      _changed = true;
      await _load();
      _toast('Plan duplicated');
    } catch (_) {
      _toast('Could not duplicate the plan');
    }
  }

  Future<void> _toggleActive(TrainingPlan plan) async {
    try {
      await _service.setActivePlan(plan.isActive ? null : plan.id);
      _changed = true;
      await _load();
      _toast(
        plan.isActive
            ? 'Plan deactivated'
            : '"${plan.name}" is now your active weekly plan. '
                  'Days without a saved workout will follow it.',
      );
    } catch (_) {
      _toast('Could not change the active plan');
    }
  }

  Future<void> _delete(TrainingPlan plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Delete this plan?'),
        content: Text(
          '"${plan.name}" will be removed. Workouts you already scheduled or '
          'completed are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deletePlan(plan.id!);
      _changed = true;
      await _load();
      _toast('Plan deleted');
    } catch (_) {
      _toast('Could not delete the plan');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('MY TRAINING PLANS')),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add),
          label: const Text('New plan'),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
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
    if (_plans.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calendar_month_rounded,
                color: AppColors.primary,
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'Build your weekly plan',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pick your training and rest days, then add as many exercises '
                'as you like to each day. Six training days do not mean six '
                'exercises: every day can have its own list.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add),
                label: const Text('Create a plan'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: _plans.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _planCard(_plans[i]),
    );
  }

  Widget _planCard(TrainingPlan plan) {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Semantics(
      container: true,
      label:
          '${plan.name}, ${plan.trainingDayCount} training days, '
          '${plan.exerciseCount} exercises${plan.isActive ? ', active' : ''}',
      child: Material(
        color: AppColors.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: plan.isActive ? AppColors.primary : AppColors.border,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openEditor(plan),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        plan.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMain,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (plan.isActive)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'ACTIVE',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'Plan actions',
                      color: AppColors.surfaceElevated,
                      onSelected: (v) {
                        switch (v) {
                          case 'edit':
                            _openEditor(plan);
                          case 'active':
                            _toggleActive(plan);
                          case 'dup':
                            _duplicate(plan);
                          case 'del':
                            _delete(plan);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                          value: 'active',
                          child: Text(
                            plan.isActive ? 'Deactivate' : 'Set as active',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'dup',
                          child: Text('Duplicate'),
                        ),
                        const PopupMenuItem(
                          value: 'del',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${plan.trainingDayCount} training days • '
                  '${plan.exerciseCount} exercises',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: i == 6 ? 0 : 6),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: plan.days[i].isRest
                                ? AppColors.surfaceElevated
                                : AppColors.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Text(
                                letters[i],
                                style: TextStyle(
                                  color: plan.days[i].isRest
                                      ? AppColors.textMuted
                                      : AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                plan.days[i].isRest
                                    ? '–'
                                    : '${plan.days[i].exercises.length}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
