import 'package:flutter/material.dart';

enum AutosaveStatus { idle, saving, saved, error }

Widget? _autosaveIndicator(BuildContext context, AutosaveStatus status) {
  final colorScheme = Theme.of(context).colorScheme;
  final IconData icon;
  final String label;
  final Color color;

  switch (status) {
    case AutosaveStatus.idle:
      return null;
    case AutosaveStatus.saving:
      icon = Icons.sync;
      label = 'Saving to device…';
      color = colorScheme.onSurface.withValues(alpha: 0.6);
    case AutosaveStatus.saved:
      icon = Icons.check_circle_outline;
      label = 'Saved on this device';
      color = colorScheme.onSurface.withValues(alpha: 0.6);
    case AutosaveStatus.error:
      icon = Icons.error_outline;
      label = 'Not saved yet, retrying…';
      color = colorScheme.error;
  }

  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    ),
  );
}

class FormActionBar extends StatelessWidget {
  final AutosaveStatus autosaveStatus;
  final VoidCallback onSaveDraft;
  final VoidCallback onEndSession;

  const FormActionBar({
    super.key,
    required this.autosaveStatus,
    required this.onSaveDraft,
    required this.onEndSession,
  });

  @override
  Widget build(BuildContext context) {
    final indicator = _autosaveIndicator(context, autosaveStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?indicator,
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: onSaveDraft,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Draft'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: onEndSession,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('End Session'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
