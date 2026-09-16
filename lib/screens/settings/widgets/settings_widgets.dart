import 'package:flutter/material.dart';

class SectionHeader extends StatelessWidget {
  final String label;
  const SectionHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.5),
          ),
    );
  }
}

class InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const InfoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      leading: Icon(icon,
          size: 20, color: colorScheme.onSurface.withValues(alpha: 0.5)),
      title: Text(label,
          style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5))),
      trailing: Text(value,
          style:
              textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
    );
  }
}

class DataTileIcon extends StatelessWidget {
  final IconData icon;
  final bool busy;

  const DataTileIcon({super.key, required this.icon, required this.busy});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: busy
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onPrimaryContainer,
              ),
            )
          : Icon(icon, size: 20, color: colorScheme.onPrimaryContainer),
    );
  }
}

class ThemeOptionTile extends StatelessWidget {
  final ThemeMode value;
  final IconData icon;
  final String label;
  final String subtitle;
  final Color accentColor;
  final bool isFirst;
  final bool isLast;

  const ThemeOptionTile({
    super.key,
    required this.value,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.accentColor,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return RadioListTile<ThemeMode>(
      value: value,
      title: Text(label,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.55),
              )),
      secondary: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: accentColor, size: 20),
      ),
    );
  }
}
