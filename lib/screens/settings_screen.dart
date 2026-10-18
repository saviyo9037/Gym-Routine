import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../core/access_config.dart';
import '../core/theme.dart';
import '../services/cloud_config.dart';
import '../models/media_attachment.dart';
import '../services/database_service.dart';
import '../services/media_service.dart';
import '../services/stats_service.dart';
import '../services/backup_service.dart';
import '../services/export_service.dart';
import '../widgets/backup_import_dialog.dart';
import '../services/premium_service.dart';
import '../widgets/premium_upsell.dart';
import '../widgets/video_player_dialog.dart';
import 'account_screen.dart';
import 'paywall_screen.dart';
import 'progress_screen.dart';
import 'alarm_settings_screen.dart';
import 'diagnostics_screen.dart';
import '../widgets/image_viewer_dialog.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onResetData;

  const SettingsScreen({super.key, this.onResetData});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DatabaseService _dbService = DatabaseService();
  final MediaService _mediaService = MediaService.instance;

  bool _sundayStart = false;
  List<MediaAttachment> _allMedia = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final media = await _dbService.getAllMedia();
    final sunday = await StatsService().weekStartsOnSunday();

    if (mounted) {
      setState(() {
        _sundayStart = sunday;
        _allMedia = media;
        _isLoading = false;
      });
    }
  }

  Future<void> _setWeekStart(bool sunday) async {
    await StatsService().setWeekStartsOnSunday(sunday);
    setState(() => _sundayStart = sunday);
    // Home / History / Plan tabs rebuild so every week view uses the new start.
    widget.onResetData?.call();
  }

  Widget _navTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textMain,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textMuted,
      ),
      onTap: onTap,
    );
  }

  Future<void> _exportHistory() async {
    final allowed = await PremiumGate.ensure(
      context,
      PremiumFeature.exportData,
      reason: 'Exporting your history as CSV or JSON is a Premium feature.',
    );
    if (!allowed || !mounted) return;
    final csv = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('CSV (spreadsheet)'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              title: const Text('JSON'),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (csv == null) return;
    try {
      final path = await ExportService().exportToFile(csv: csv);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], subject: 'RepTrack history export'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export failed. Please try again.')),
        );
      }
    }
  }

  Future<void> _openLink(Uri uri) async {
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open the link.')));
    }
  }

  Future<void> _exportBackup() async {
    try {
      final jsonStr = await _dbService.exportBackupJson();
      final tempDir = Directory.systemTemp;
      final file = File(
        '${tempDir.path}/reptrack_backup_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(jsonStr);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'RepTrack Complete Local SQLite Backup JSON',
          subject: 'RepTrack Backup Export',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _restoreBackup() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (files.isNotEmpty && files.first.path != null) {
        final content = await File(files.first.path!).readAsString();
        final BackupFile parsed;
        try {
          parsed = BackupService().parse(content);
        } on BackupException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Not a valid RepTrack backup: ${e.message}'),
              ),
            );
          }
          return;
        }
        if (!mounted) return;
        final imported = await BackupImportFlow.run(context, parsed);
        if (mounted && imported) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Backup imported'),
              backgroundColor: AppColors.successDark,
            ),
          );
          _loadSettings();
          widget.onResetData?.call();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Reset All RepTrack Data?',
          style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will permanently delete all custom exercises, workout history, and plans, and re-seed the default starter programs.\n\nAre you sure you wish to proceed?',
          style: TextStyle(color: AppColors.textSecondary),
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
            child: const Text(
              'Reset Everything',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _dbService.clearAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data cleared and default database reset.'),
          ),
        );
        _loadSettings();
        widget.onResetData?.call();
      }
    }
  }

  void _showMediaLibrary() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ListView(
                controller: controller,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'APP-PRIVATE MEDIA LIBRARY',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Text(
                        '${_allMedia.length} files',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_allMedia.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Text(
                          'No media files recorded yet.\nTake photos, record form videos or voice memos in exercises to populate.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _allMedia.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final m = _allMedia[idx];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.cardSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: InkWell(
                            onTap: () {
                              if (m.mediaType == 'photo') {
                                ImageViewerDialog.show(
                                  context,
                                  attachment: m,
                                  onUpdated: _loadSettings,
                                  onDeleted: _loadSettings,
                                );
                              } else if (m.mediaType == 'video') {
                                VideoPlayerDialog.show(
                                  context,
                                  videoPath: m.filePath,
                                  title: m.title,
                                  attachment: m,
                                  onUpdated: _loadSettings,
                                  onDeleted: _loadSettings,
                                );
                              } else if (m.mediaType == 'audio') {
                                _mediaService.playAudio(m.filePath);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Playing ${m.title}...'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Row(
                              children: [
                                Icon(
                                  m.mediaType == 'audio'
                                      ? Icons.mic_rounded
                                      : (m.mediaType == 'video'
                                            ? Icons.videocam_rounded
                                            : Icons.photo_camera_rounded),
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m.title,
                                        style: const TextStyle(
                                          color: AppColors.textMain,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        '${m.entityType.toUpperCase()} • ${m.createdAt.length >= 10 ? m.createdAt.substring(0, 10) : m.createdAt}',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    m.mediaType == 'photo'
                                        ? Icons.fullscreen_rounded
                                        : Icons.play_circle_fill_rounded,
                                    color: AppColors.primary,
                                  ),
                                  onPressed: () {
                                    if (m.mediaType == 'photo') {
                                      ImageViewerDialog.show(
                                        context,
                                        attachment: m,
                                        onUpdated: _loadSettings,
                                        onDeleted: _loadSettings,
                                      );
                                    } else if (m.mediaType == 'video') {
                                      VideoPlayerDialog.show(
                                        context,
                                        videoPath: m.filePath,
                                        title: m.title,
                                        attachment: m,
                                        onUpdated: _loadSettings,
                                        onDeleted: _loadSettings,
                                      );
                                    } else {
                                      _mediaService.playAudio(m.filePath);
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppColors.textMuted,
                                    size: 20,
                                  ),
                                  onPressed: () async {
                                    if (m.id != null) {
                                      await _dbService.deleteMediaAttachment(
                                        m.id!,
                                      );
                                      await _mediaService.deleteFile(
                                        m.filePath,
                                      );
                                      await _loadSettings();
                                      if (ctx.mounted) {
                                        Navigator.pop(ctx);
                                        _showMediaLibrary();
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 36),
                ],
              ),
            );
          },
        );
      },
    );
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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('PROFILE & SETTINGS')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Portfolio Header Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.fitness_center_rounded,
                        color: AppColors.primary,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RepTrack Athlete',
                          style: TextStyle(
                            color: AppColors.textMain,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Cinematic Dark Portfolio Theme Active',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ACCOUNT & PREMIUM
            _buildSectionTitle('ACCOUNT & PREMIUM'),
            const SizedBox(height: 10),
            Material(
              // A Material (not a decorated Container) so the ListTile ink
              // splashes are visible.
              color: AppColors.cardSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _navTile(
                    icon: Icons.cloud_sync_rounded,
                    title: 'Account & cloud sync',
                    subtitle: AccessConfig.subscriptionRequired
                        ? 'Optional. Sign in to back up and sync'
                        : 'Optional. Sign in to back up and sync (Premium)',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AccountScreen(onLocalDataWiped: widget.onResetData),
                      ),
                    ),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  _navTile(
                    icon: Icons.workspace_premium_rounded,
                    title: AccessConfig.subscriptionRequired
                        ? 'Subscription'
                        : 'RepTrack Premium',
                    subtitle: AccessConfig.subscriptionRequired
                        ? 'Your plan, trial and Google Play management'
                        : 'Sync, charts, unlimited plans, export',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PaywallScreen()),
                    ),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  _navTile(
                    icon: Icons.show_chart_rounded,
                    title: 'Progress & charts',
                    subtitle: AccessConfig.subscriptionRequired
                        ? 'Per-exercise strength trends'
                        : 'Per-exercise strength trends (Premium)',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProgressScreen()),
                    ),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  _navTile(
                    icon: Icons.ios_share_rounded,
                    title: 'Export history (CSV / JSON)',
                    subtitle: AccessConfig.subscriptionRequired
                        ? 'Your workout history as a file'
                        : 'Premium. The local backup below is always free',
                    onTap: _exportHistory,
                  ),
                  if (CloudConfig.privacyUri != null) ...[
                    const Divider(color: AppColors.border, height: 1),
                    _navTile(
                      icon: Icons.privacy_tip_rounded,
                      title: 'Privacy policy',
                      subtitle: 'Opens in your browser',
                      onTap: () => _openLink(CloudConfig.privacyUri!),
                    ),
                  ],
                  if (CloudConfig.termsUri != null) ...[
                    const Divider(color: AppColors.border, height: 1),
                    _navTile(
                      icon: Icons.description_rounded,
                      title: 'Terms of use',
                      subtitle: 'Opens in your browser',
                      onTap: () => _openLink(CloudConfig.termsUri!),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // PREFERENCES SECTION
            _buildSectionTitle('PREFERENCES'),
            const SizedBox(height: 10),
            Material(
              // A Material (not a decorated Container) so the ListTile ink
              // splashes are visible.
              color: AppColors.cardSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border),
              ),
              child: Column(
                children: [
                  ListTile(
                    title: const Text(
                      'Week starts on',
                      style: TextStyle(
                        color: AppColors.textMain,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Used for weekly history, stats and the home week strip',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    trailing: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('MON')),
                        ButtonSegment(value: true, label: Text('SUN')),
                      ],
                      selected: {_sundayStart},
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith((
                          states,
                        ) {
                          if (states.contains(WidgetState.selected)) {
                            return AppColors.primary;
                          }
                          return AppColors.surfaceElevated;
                        }),
                        foregroundColor: WidgetStateProperty.resolveWith((
                          states,
                        ) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.black;
                          }
                          return AppColors.textMain;
                        }),
                      ),
                      onSelectionChanged: (val) => _setWeekStart(val.first),
                    ),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.alarm_on_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text(
                      'Reminder reliability',
                      style: TextStyle(
                        color: AppColors.textMain,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Permissions, battery settings and a test alarm',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textMuted,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AlarmSettingsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // MEDIA & STORAGE SECTION
            _buildSectionTitle('LOCAL STORAGE & PRIVACY'),
            const SizedBox(height: 10),
            Material(
              // A Material (not a decorated Container) so the ListTile ink
              // splashes are visible.
              color: AppColors.cardSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.perm_media_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text(
                      'App-Private Media Library',
                      style: TextStyle(
                        color: AppColors.textMain,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${_allMedia.length} attached photos, videos & voice notes',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: AppColors.textMuted,
                      size: 14,
                    ),
                    onTap: _showMediaLibrary,
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.file_download_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text(
                      'Export Local Backup (JSON)',
                      style: TextStyle(
                        color: AppColors.textMain,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Backup plans, sessions, sets and metadata',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    onTap: _exportBackup,
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.file_upload_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text(
                      'Import Backup (merge or replace)',
                      style: TextStyle(
                        color: AppColors.textMain,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Import previously exported JSON file',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    onTap: _restoreBackup,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Privacy Notice Card (Section 13)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Privacy Guarantee: All workout logs, recorded photos, form videos, and trainer audio memos are kept 100% offline in your app-private sandbox. Note that clearing app data or uninstalling the app may remove local files unless backed up.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Diagnostics: compiled out of release builds (kDebugMode is const).
            if (kDebugMode) ...[
              _buildSectionTitle('DEVELOPER (DEBUG BUILD ONLY)'),
              const SizedBox(height: 10),
              Material(
                color: AppColors.cardSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: ListTile(
                  leading: const Icon(
                    Icons.bug_report_rounded,
                    color: AppColors.primary,
                  ),
                  title: const Text('Diagnostics'),
                  subtitle: const Text(
                    'Versions, row counts, alarms, permissions, sync, entitlement',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DiagnosticsScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // DANGER ZONE
            _buildSectionTitle('DANGER ZONE'),
            const SizedBox(height: 10),
            Material(
              color: AppColors.cardSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
              ),
              child: ListTile(
                leading: const Icon(
                  Icons.delete_forever_rounded,
                  color: AppColors.error,
                ),
                title: const Text(
                  'Reset All Data',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'Erase custom data and restore default starter plans',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                onTap: _clearAllData,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.primary,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    );
  }
}
