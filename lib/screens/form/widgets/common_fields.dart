import 'package:flutter/material.dart';

class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Colors.green[700],
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const ReadOnlyField(this.label, this.value, this.icon, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(4),
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(value, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
            Icon(Icons.lock_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType inputType;
  final int maxLines;
  final bool isOptional;

  const AppTextField(
    this.controller,
    this.label,
    this.icon, {
    super.key,
    this.inputType = TextInputType.text,
    this.maxLines = 1,
    this.isOptional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
          prefixIcon: Icon(icon),
        ),
        keyboardType: inputType,
        maxLines: maxLines,
        validator: (value) {
          if (!isOptional && (value == null || value.isEmpty)) {
            if (label.contains('Crew Leader') || label.contains('Site Name')) {
              return 'This field is required';
            }
          }
          return null;
        },
      ),
    );
  }
}

class TimeField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const TimeField(this.controller, this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.access_time),
        ),
        readOnly: true,
        onTap: () async {
          final time = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.now(),
          );
          if (time != null && context.mounted) {
            controller.text = time.format(context);
          }
        },
      ),
    );
  }
}

class VisibilitySelector extends StatelessWidget {
  final String visibility;
  final String? embargoUntil;
  final ValueChanged<String> onVisibilityChanged;
  final ValueChanged<String?> onEmbargoChanged;

  const VisibilitySelector({
    super.key,
    required this.visibility,
    required this.embargoUntil,
    required this.onVisibilityChanged,
    required this.onEmbargoChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Visibility', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'public', label: Text('Public'), icon: Icon(Icons.public, size: 16)),
              ButtonSegment(value: 'private', label: Text('Private'), icon: Icon(Icons.lock, size: 16)),
              ButtonSegment(value: 'embargo', label: Text('Embargo'), icon: Icon(Icons.schedule, size: 16)),
            ],
            selected: {visibility},
            onSelectionChanged: (v) => onVisibilityChanged(v.first),
          ),
          if (visibility == 'embargo') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(embargoUntil != null
                  ? 'Embargo until: $embargoUntil'
                  : 'Pick embargo date'),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 90)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (picked != null && context.mounted) {
                  onEmbargoChanged(picked.toIso8601String().substring(0, 10));
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
