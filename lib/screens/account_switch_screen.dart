import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/cloud_services.dart';
import '../widgets/auth_widgets.dart';

/// Shown when a different account signs in on a phone whose data belongs to
/// another account. Nothing is ever merged or deleted silently: the user
/// either links this phone's data to the new account or signs out.
class AccountSwitchScreen extends StatefulWidget {
  const AccountSwitchScreen({super.key, required this.onResolved});

  /// Called after the user chose to link this phone's data.
  final VoidCallback onResolved;

  @override
  State<AccountSwitchScreen> createState() => _AccountSwitchScreenState();
}

class _AccountSwitchScreenState extends State<AccountSwitchScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _link() async {
    final user = CloudServices.auth.user;
    if (_busy || user == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Explicit re-upload of this phone's data to the new account. Nothing
      // on the phone is changed or deleted.
      await CloudServices.sync.linkLocalDataToCurrentAccount();
      await CloudServices.accountSwitch.remember(user.id);
      if (mounted) widget.onResolved();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not link this phone. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await CloudServices.auth.signOut();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = CloudServices.auth.user?.email;
    return AuthScaffold(
      title: 'Different account',
      children: [
        const Icon(
          Icons.swap_horiz_rounded,
          color: AppColors.primary,
          size: 48,
        ),
        const SizedBox(height: 12),
        AuthHeading(
          'This phone belongs to another account',
          'The workouts, plans and routines on this phone were used with a '
              'different RepTrack account${email == null ? '' : ' than $email'}. '
              'Your data on this phone will not be deleted or merged unless you '
              'choose to.',
        ),
        if (_error != null) AuthBanner(_error!),
        AuthButton(
          label: "Keep this phone's data and link it to this account",
          busy: _busy,
          onPressed: _link,
        ),
        const SizedBox(height: 4),
        const Text(
          'The data on this phone is uploaded to the account you just signed '
          'in to (if it has a subscription that includes sync).',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: _busy ? null : _cancel,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
          child: const Text('Cancel and sign out', textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
