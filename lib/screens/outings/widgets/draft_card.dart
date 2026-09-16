import 'package:flutter/material.dart';
import '../../../models/field_outing/field_outing.dart';

class DraftCard extends StatelessWidget {
  final FieldOuting draft;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final String authorName;

  const DraftCard({
    super.key,
    required this.draft,
    required this.onOpen,
    required this.onDelete,
    required this.authorName,
  });

  static const _typeColors = {
    'vegetation': Color(0xFF2E7D32),
    'hydrology': Color(0xFF0277BD),
    'elevation': Color(0xFF6A3F00),
  };

  static const _typeIcons = {
    'vegetation': Icons.grass,
    'hydrology': Icons.water_drop,
    'elevation': Icons.terrain,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = _typeColors[draft.monitoringType] ?? colorScheme.primary;
    final icon = _typeIcons[draft.monitoringType] ?? Icons.description;
    final typeLabel =
        '${draft.monitoringType[0].toUpperCase()}${draft.monitoringType.substring(1)} Monitoring';
    final lastEdited = draft.updatedAt ?? draft.createdAt;
    final dateLabel = 'Edited ${_formatRelative(lastEdited)}';
    final exactLabel = _formatExact(lastEdited);
    final title = draft.siteName.trim().isEmpty ? 'Untitled draft' : draft.siteName;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Coloured left accent bar
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(icon, color: accent, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              style: textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: colorScheme.error, size: 20),
                            onPressed: onDelete,
                            tooltip: 'Delete draft',
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _MetaChip(label: typeLabel, color: accent),
                          const SizedBox(width: 8),
                          Icon(Icons.access_time,
                              size: 13,
                              color: colorScheme.onSurface.withValues(alpha: 0.45)),
                          const SizedBox(width: 3),
                          Text(dateLabel,
                              style: textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.55),
                              )),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 12,
                              color: colorScheme.onSurface.withValues(alpha: 0.45)),
                          const SizedBox(width: 4),
                          Text(exactLabel,
                              style: textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.55),
                              )),
                          const SizedBox(width: 10),
                          Icon(Icons.person_outline,
                              size: 13,
                              color: colorScheme.onSurface.withValues(alpha: 0.45)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(authorName,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurface.withValues(alpha: 0.55),
                                )),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatRelative(DateTime? date) {
    if (date == null) return 'unknown';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) {
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inHours == 0) return '${diff.inMinutes} min ago';
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }

  String _formatExact(DateTime? date) {
    if (date == null) return 'Unknown date';
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '${_monthNames[date.month - 1]} ${date.day}, ${date.year} · $hour12:$minute $ampm';
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MetaChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
