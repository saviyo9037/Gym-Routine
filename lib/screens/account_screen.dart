import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../data/db_helper.dart';
import '../services/auth_service.dart';
import '../services/cloud_services.dart';
import '../services/premium_service.dart';
import '../services/sync_service.dart';
import 'auth_flow_screen.dart';
import 'paywall_screen.dart';

/// Optional account: sign in / up, sync status, sign out, delete account.
/// The app never asks for an account; everything free works without one.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.onLocalDataWiped});

  /// Called after the user chose to also erase local data on this device.
  final VoidCallback? onLocalDataWiped;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _busy = false;

  AuthService get _auth => CloudServices.auth;
  SyncService get _sync => CloudServices.sync;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_rebuild);
    _sync.addListener(_rebuild);
    CloudServices.premium.addListener(_rebuild);
  }

  @override
  void dispose() {
    _auth.removeListener(_rebuild);
    _sync.removeListener(_rebuild);
    CloudServices.premium.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on AuthFailure catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkDevice() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text("Use this device's data with this account?"),
        content: const Text(
          'The workouts, plans and routines on this device were synced with '
          'another account. If you continue they will be uploaded to the '
          'account you are signed in to now. Nothing on this device is '
          'changed or deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Upload to this account'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _sync.linkLocalDataToCurrentAccount();
    });
  }

  Future<void> _signOut() async {
    await _run(() async {
      await _auth.signOut();
      _toast('Signed out. Your data stays on this device.');
    });
  }

  Future<void> _delete() async {
    final result = await showDialog<_DeleteChoice>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    final ok = result != null;
    final wipe = result?.wipeLocal ?? false;
    if (ok != true) return;
    await _run(() async {
      await _auth.deleteAccount();
      // The cloud account is gone: forget it so a future account receives this
      // device's data again instead of believing everything is already synced.
      await _sync.forgetAccount();
      await CloudServices.accountSwitch.forget();
      if (wipe) {
        await DatabaseHelper.instance.clearAllData();
        widget.onLocalDataWiped?.call();
      }
      _toast(
        wipe
            ? 'Account deleted and local data erased.'
            : 'Account deleted. Your local data is still on this device.',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('ACCOUNT & CLOUD')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!_auth.isConfigured)
            _card(
              Icons.cloud_off_rounded,
              'Cloud accounts are not set up in this build',
              'Accounts, subscriptions and cloud sync need a build that is '
                  'connected to the RepTrack cloud. Your data on this phone is '
                  'safe and is never deleted.',
            )
          else if (_auth.isSignedIn)
            ..._signedIn()
          else
            ..._signedOut(),
        ],
      ),
    );
  }

  Widget _card(IconData icon, String title, String body, {Widget? trailing}) {
    return Material(
      color: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (trailing != null) ...[const SizedBox(height: 10), trailing],
          ],
        ),
      ),
    );
  }

  List<Widget> _signedOut() {
    return [
      _card(
        Icons.lock_open_rounded,
        'You are not signed in',
        'Your RepTrack account holds your subscription. Sign in or create '
            'an account to subscribe, back up and sync. Your workouts stay on '
            'this phone either way.',
      ),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AuthFlowScreen(popOnSignedIn: true),
          ),
        ),
        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text('Sign in or create an account'),
      ),
    ];
  }

  List<Widget> _signedIn() {
    final premium = CloudServices.premium;
    final user = _auth.user!;
    final fmt = DateFormat('EEE d MMM, HH:mm');
    final last = _sync.lastSyncedAt;
    final statusText = switch (_sync.state) {
      SyncState.syncing => 'Syncing...',
      SyncState.error => _sync.lastError ?? 'Sync failed.',
      SyncState.partial =>
        _sync.lastError ?? 'Some data could not be synced yet.',
      SyncState.needsAccountLink =>
        'This device was synced with a different account.',
      SyncState.needsPremium => 'Cloud sync is a Premium feature.',
      SyncState.idle =>
        last == null ? 'Not synced yet.' : 'Last synced ${fmt.format(last)}',
      _ => '',
    };
    return [
      _card(
        Icons.person_rounded,
        user.email ?? 'Signed in',
        premium.isPremium
            ? 'Subscription active on this account.'
            : 'No active subscription on this account. Your workouts stay on '
                  'this device.',
      ),
      const SizedBox(height: 14),
      _card(
        Icons.cloud_sync_rounded,
        'Cloud backup & sync',
        statusText,
        trailing: _sync.state == SyncState.needsAccountLink
            ? ElevatedButton(
                onPressed: _busy ? null : _linkDevice,
                child: const Text("Use this device's data"),
              )
            : premium.canUse(PremiumFeature.cloudSync)
            ? ElevatedButton.icon(
                onPressed: _sync.state == SyncState.syncing
                    ? null
                    : _sync.syncNow,
                icon: const Icon(Icons.sync_rounded, color: Colors.black),
                label: const Text('Sync now'),
              )
            : ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PaywallScreen()),
                ),
                child: const Text('Unlock with Premium'),
              ),
      ),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: _busy ? null : _signOut,
        child: const Text('Sign out'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _busy ? null : _delete,
        child: const Text(
          'Delete my account',
          style: TextStyle(color: AppColors.error),
        ),
      ),
    ];
  }
}

class _DeleteChoice {
  const _DeleteChoice({required this.wipeLocal});
  final bool wipeLocal;
}

/// Destructive confirmation: needs the word DELETE typed, offers the optional
/// local wipe. Owns (and disposes) its own text controller.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _confirm = TextEditingController();
  bool _wipe = false;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typed = _confirm.text.trim().toUpperCase() == 'DELETE';
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes your cloud data and your sign-in. '
              'It cannot be undone. An active subscription is NOT cancelled '
              'by this: cancel it in Google Play.',
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _wipe,
              activeColor: AppColors.primary,
              onChanged: (v) => setState(() => _wipe = v ?? false),
              title: const Text(
                'Also erase all workout data on this device',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: const Text(
                'Leave unchecked to keep your local data.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            TextField(
              controller: _confirm,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Type DELETE to confirm',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: typed
              ? () => Navigator.pop(context, _DeleteChoice(wipeLocal: _wipe))
              : null,
          child: const Text(
            'Delete account',
            style: TextStyle(color: AppColors.error),
          ),
        ),
      ],
    );
  }
}
