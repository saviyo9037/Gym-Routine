import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/app_config_service.dart';

/// Dismissible announcements from the admin panel (max 3 shown at once).
/// Renders nothing when there is nothing live and not dismissed, so the parent
/// can place it anywhere (for example at the top of Home) without a layout
/// cost. The server already filters by window and active flag; the service
/// filters again and remembers dismissals per announcement id.
class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({super.key, this.service});

  /// Defaults to [AppConfigService.instance].
  final AppConfigService? service;

  @override
  Widget build(BuildContext context) {
    final s = service ?? AppConfigService.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final items = s.visibleAnnouncements.take(3).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final a in items)
              _AnnouncementCard(
                key: ValueKey('announcement_${a.id}'),
                announcement: a,
                onDismiss: () => s.dismissAnnouncement(a.id),
              ),
          ],
        );
      },
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    super.key,
    required this.announcement,
    required this.onDismiss,
  });

  final Announcement announcement;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final warning = announcement.level == AnnouncementLevel.warning;
    final color = warning ? AppColors.warning : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        container: true,
        label:
            '${warning ? 'Warning' : 'Announcement'}: ${announcement.title}. ${announcement.body}',
        child: Material(
          color: color.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: color.withValues(alpha: 0.6)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  warning
                      ? Icons.warning_amber_rounded
                      : Icons.campaign_rounded,
                  color: color,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        announcement.title,
                        style: const TextStyle(
                          color: AppColors.textMain,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        announcement.body,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.35,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss announcement',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: AppColors.textMuted,
                  onPressed: onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
