import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/update_check.dart';

class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(availableUpdateProvider).value;
    if (update == null || update.dismissed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: UpdateCard(update: update, showLater: true),
    );
  }
}

class UpdateCard extends ConsumerWidget {
  const UpdateCard({super.key, required this.update, required this.showLater});
  final AvailableUpdate update;
  final bool showLater;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final installed = update.installedVersion;

    Future<void> later() async {
      await ref.read(updateCheckerProvider).dismiss(update.version);
      ref.invalidate(availableUpdateProvider);
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.tertiary),
      ),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          Icon(Icons.system_update, color: colorScheme.tertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('New app version available', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  installed == null ? 'v${update.version}' : 'v$installed → v${update.version}',
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (showLater)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(56, 48), foregroundColor: colorScheme.onSurfaceVariant),
              onPressed: later,
              child: const Text('Later'),
            ),
          const SizedBox(width: 4),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(64, 48),
              backgroundColor: colorScheme.tertiary,
              foregroundColor: colorScheme.onTertiary,
            ),
            onPressed: () => launchUrl(Uri.parse(update.url), mode: LaunchMode.externalApplication),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
}
