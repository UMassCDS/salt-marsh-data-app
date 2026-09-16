import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/field_outing_provider.dart';
import '../models/field_outing/field_outing.dart';
import '../utils/snackbar_utils.dart';
import 'form/form_screen.dart';

class DraftsScreen extends ConsumerWidget {
  final String? monitoringTypeFilter;

  const DraftsScreen({super.key, this.monitoringTypeFilter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outingService = ref.read(fieldOutingServiceProvider);
    final filter = monitoringTypeFilter;
    final title = filter == null
        ? 'Saved Drafts'
        : '${filter[0].toUpperCase()}${filter.substring(1)} Drafts';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
      ),
      // Only when this screen is reached as the "pick which draft" fallback
      // for a monitoring type - the unfiltered /drafts route has no single
      // type to start, so it stays a pure browsing list
      floatingActionButton: filter == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context)
                  .pushReplacementNamed('/form', arguments: filter),
              icon: const Icon(Icons.add),
              label: const Text('Start New'),
            ),
      body: FutureBuilder<List<FieldOuting>>(
        future: filter == null
            ? outingService.getDrafts()
            : outingService.getDraftsByType(filter),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(error: snapshot.error.toString());
          }

          final drafts = snapshot.data ?? [];

          if (drafts.isEmpty) {
            return const _EmptyState();
          }

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
            itemCount: drafts.length,
            itemBuilder: (context, index) {
              final draft = drafts[index];
              return _DraftCard(
                draft: draft,
                onOpen: () => _openDraft(context, draft),
                onDelete: () => _deleteDraft(context, ref, draft),
                authorName: ref.watch(authProvider).user?.fullName ?? 'Unknown',
              );
            },
          );
        },
      ),
    );
  }

  void _openDraft(BuildContext context, FieldOuting draft) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FormScreen(
          monitoringType: draft.monitoringType,
          draftId: draft.id,
        ),
      ),
    );
  }

  Future<void> _deleteDraft(
      BuildContext context, WidgetRef ref, FieldOuting draft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Draft'),
        content: Text(
            'Delete the draft for "${draft.siteName.trim().isEmpty ? 'Untitled draft' : draft.siteName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final service = ref.read(fieldOutingServiceProvider);
        await service.deleteDraft(draft.id!);
        if (context.mounted) {
          showAppSnackBar(context, 'Draft deleted');
          unawaited(Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const DraftsScreen()),
          ));
        }
      } catch (e) {
        if (context.mounted) {
          showAppSnackBar(
            context,
            'Error deleting draft: $e',
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          );
        }
      }
    }
  }
}

// ── Supporting widgets ──────────────────────────────────────────────────────

class _DraftCard extends StatelessWidget {
  final FieldOuting draft;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final String authorName;

  const _DraftCard({
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.drafts_outlined,
                size: 64,
                color: colorScheme.onSurface.withValues(alpha: 0.25)),
            const SizedBox(height: 20),
            Text('No saved drafts',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    )),
            const SizedBox(height: 6),
            Text(
              'Start a field session and tap "Save as Draft" to keep your progress.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error loading drafts',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
