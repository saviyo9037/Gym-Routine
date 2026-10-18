import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_info.dart';
import '../core/theme.dart';
import '../services/app_config_service.dart';

/// Wraps the app: shows a calm maintenance screen or an "update required"
/// screen when the remote config says so, otherwise [child].
///
/// * The config is validated and cached by [AppConfigService]; if it cannot be
///   reached the last good config (or the defaults) is used, so a server
///   problem never blocks the app.
/// * Maintenance never touches local data, and alarms that are already
///   scheduled keep ringing (they are native and independent of this screen).
/// * The Play Store button uses the package id (`market://details?id=...`);
///   no web URL is invented. If it cannot be opened, the text tells the user to
///   open Google Play.
class AppConfigGate extends StatefulWidget {
  const AppConfigGate({
    super.key,
    required this.child,
    this.service,
    this.installedVersion = kAppVersion,
    this.openStore,
  });

  final Widget child;

  /// Defaults to [AppConfigService.instance].
  final AppConfigService? service;
  final String installedVersion;

  /// Test hook; defaults to opening the market:// link.
  final Future<bool> Function(Uri uri)? openStore;

  @override
  State<AppConfigGate> createState() => _AppConfigGateState();
}

class _AppConfigGateState extends State<AppConfigGate>
    with WidgetsBindingObserver {
  AppConfigService get _service => widget.service ?? AppConfigService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Rate-limited inside the service, so this is cheap.
    if (state == AppLifecycleState.resumed) _service.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final cfg = _service.config;
        if (cfg.maintenanceMode) {
          return MaintenanceScreen(
            message: cfg.effectiveMaintenanceMessage,
            service: _service,
          );
        }
        if (_service.updateRequired(widget.installedVersion)) {
          return UpdateRequiredScreen(
            installed: widget.installedVersion,
            minimum: cfg.minAppVersion!,
            openStore: widget.openStore,
          );
        }
        return widget.child;
      },
    );
  }
}

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({
    super.key,
    required this.message,
    required this.service,
  });

  final String message;
  final AppConfigService service;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      await widget.service.refresh(force: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.construction_rounded,
                    color: AppColors.primary,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Back soon',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMain,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    widget.message,
                    key: const ValueKey('maintenance_message'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _retry,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, color: Colors.black),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.installed,
    required this.minimum,
    this.openStore,
  });

  final String installed;
  final String minimum;
  final Future<bool> Function(Uri uri)? openStore;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse('market://details?id=$kApplicationId');
    var ok = false;
    try {
      ok =
          await (openStore ??
              (u) => launchUrl(u, mode: LaunchMode.externalApplication))(uri);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open Google Play and search for RepTrack to update.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.system_update_rounded,
                  color: AppColors.primary,
                  size: 56,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Update required',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMain,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'This version of RepTrack ($installed) is no longer supported. '
                  'Please update to $minimum or newer from Google Play. Your data '
                  'on this phone is safe, and alarms you already set keep ringing.',
                  key: const ValueKey('update_message'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _open(context),
                  icon: const Icon(Icons.shop_rounded, color: Colors.black),
                  label: const Text('Open Google Play'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
