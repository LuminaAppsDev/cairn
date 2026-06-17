import 'package:cairn/src/onboarding/setup_guide.dart';
import 'package:flutter/material.dart';

/// Shows the OS-specific data-source setup guide (DESIGN.md §8). The platform
/// is taken from the ambient theme, so the correct (Android/iOS) content is
/// selected automatically.
class SetupGuidePage extends StatelessWidget {
  /// Creates the setup-guide page.
  const SetupGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final guide = setupGuideFor(theme.platform);
    return Scaffold(
      appBar: AppBar(title: const Text('Getting your data in')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Set up on ${guide.platformLabel}',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(guide.intro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          for (final step in guide.steps)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(step.body, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(guide.note, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
