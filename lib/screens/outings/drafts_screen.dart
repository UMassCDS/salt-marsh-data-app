import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/field_outing_provider.dart';
import '../../models/field_outing/field_outing.dart';
import '../../utils/snackbar_utils.dart';
import '../form/form_screen.dart';
import 'widgets/draft_card.dart';

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
              return DraftCard(
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
