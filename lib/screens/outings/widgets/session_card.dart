import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/field_outing_provider.dart';

class SessionCard extends StatelessWidget {
  final dynamic session;
  final String observerName;
  final VoidCallback onViewDetails;

  const SessionCard({
    super.key,
    required this.session,
    required this.observerName,
    required this.onViewDetails,
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
    final type = session.monitoringType as String;
    final accent = _typeColors[type] ?? colorScheme.primary;
    final icon = _typeIcons[type] ?? Icons.description;
    final isDraft = session.isDraft as bool;
    final uploaded = !isDraft && session.syncStatus == 'synced';
    final typeLabel = '${type[0].toUpperCase()}${type.substring(1)}';
    final createdAt = session.createdAt as DateTime?;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onViewDetails,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Icon badge
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.siteName as String,
                      style: textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // Type chip
                        _LabelChip(
                          label: typeLabel,
                          color: accent,
                          background: accent.withValues(alpha: 0.1),
                        ),
                        // Status chip
                        if (isDraft)
                          _LabelChip(
                            label: 'Draft',
                            color: Colors.orange.shade700,
                            background: Colors.orange.withValues(alpha: 0.1),
                          )
                        else
                          _SyncStatusChip(
                            metadataSynced: uploaded,
                            outingId: session.id as int?,
                          ),
                      ],
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}  ·  $observerName',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              Icon(Icons.chevron_right,
                  color: colorScheme.onSurface.withValues(alpha: 0.35)),
            ],
          ),
        ),
      ),
    );
  }
}

// Combines metadata sync status with pending-photo count into one signal,
// so "fully synced" always means the whole session, not just the record row
class _SyncStatusChip extends ConsumerWidget {
  final bool metadataSynced;
  final int? outingId;
  const _SyncStatusChip({required this.metadataSynced, required this.outingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosPending = outingId == null
        ? 0
        : ref
            .watch(pendingPhotoUploadsCountProvider(outingId!))
            .maybeWhen(data: (v) => v, orElse: () => 0);
    final fullySynced = metadataSynced && photosPending == 0;

    final label = fullySynced
        ? 'Fully synced'
        : photosPending > 0
            ? 'Needs resync ($photosPending photo${photosPending == 1 ? '' : 's'})'
            : 'Needs resync';
    final color = fullySynced ? Colors.green.shade700 : Colors.amber.shade800;
    final background = fullySynced
        ? Colors.green.withValues(alpha: 0.1)
        : Colors.amber.withValues(alpha: 0.12);

    return _LabelChip(label: label, color: color, background: background);
  }
}

// Named to avoid colliding with Flutter's own material Chip widget
class _LabelChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  const _LabelChip(
      {required this.label, required this.color, required this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
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
