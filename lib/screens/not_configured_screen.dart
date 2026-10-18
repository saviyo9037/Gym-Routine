import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../widgets/auth_widgets.dart';

/// Shown instead of the sign-in / paywall screens when this build has no
/// cloud (Supabase) configuration: accounts and purchases are impossible, so
/// say so clearly instead of showing forms that cannot work. The options that
/// must stay available (export, manage subscription, legal links) remain.
class NotConfiguredScreen extends StatelessWidget {
  const NotConfiguredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthScaffold(
      title: 'RepTrack',
      children: [
        Icon(Icons.cloud_off_rounded, color: AppColors.textMuted, size: 52),
        SizedBox(height: 12),
        AuthHeading(
          'This build is not connected to RepTrack accounts',
          'RepTrack needs a RepTrack account and a subscription, but this '
              'build was made without the account service. Install the official '
              'build to sign up. Your data on this phone is safe and untouched.',
        ),
        LockedOptions(),
      ],
    );
  }
}
