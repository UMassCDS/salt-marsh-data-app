import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/field_outing_provider.dart';
import '../../providers/org_provider.dart';
import '../../services/sync_service.dart';
import 'outing_details_screen.dart';
import 'widgets/session_card.dart';

class OutingsScreen extends ConsumerStatefulWidget {
  const OutingsScreen({super.key});

  @override
  ConsumerState<OutingsScreen> createState() => _OutingsScreenState();
}

class _OutingsScreenState extends ConsumerState<OutingsScreen> {
  bool _syncingAll = false;

  @override
  void initState() {
    super.initState();
    // Force a fresh DB query every time this screen is opened so newly
    // saved/synced sessions show up without having to restart the app.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final orgId = ref.read(selectedOrgIdProvider);
      ref.invalidate(fieldOutingsProvider(orgId));
    });
  }

  Future<void> _syncAll() async {
    if (_syncingAll) return;
    setState(() => _syncingAll = true);
    try {
      final orgId = ref.read(selectedOrgIdProvider);
      final userId = ref.read(authProvider).user?.id;
      final result = await SyncService.instance.resyncAllOutings(orgId, userId: userId);
      ref.invalidate(fieldOutingsProvider(orgId));
      ref.invalidate(pendingPhotoUploadsCountProvider);
      if (!mounted) return;
      final parts = <String>[];
      if (result.uploadedCount > 0) parts.add('uploaded ${result.uploadedCount} session(s)');
      if (result.plotsRecovered > 0) parts.add('recovered ${result.plotsRecovered} missing plot(s)');
      if (result.photosUploaded > 0) parts.add('uploaded ${result.photosUploaded} photo(s)');
      if (result.photosStillPending > 0) parts.add('${result.photosStillPending} photo(s) still uploading');
      final joined = parts.isEmpty ? 'Everything already up to date' : parts.join(', ');
      final message = '${joined[0].toUpperCase()}${joined.substring(1)}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.uploadFailed ? 'Some sessions could not be uploaded, check your connection' : message)),
      );
    } finally {
      if (mounted) setState(() => _syncingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orgId = ref.watch(selectedOrgIdProvider);
    final currentUserId = ref.watch(authProvider).user?.id;
    final outingsAsync = ref.watch(fieldOutingsProvider(orgId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Sessions'),
        actions: [
          IconButton(
            tooltip: 'Sync All',
            icon: _syncingAll
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onPressed: _syncingAll ? null : _syncAll,
          ),
        ],
      ),
      body: outingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(error: error.toString()),
        data: (allSessions) {
          // Show only sessions belonging to the current user.
          final sessions = currentUserId == null
              ? allSessions
              : allSessions
                  .where((s) => s.createdByUserId == currentUserId)
                  .toList();

          if (sessions.isEmpty) {
            return const _EmptyState();
          }

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              return SessionCard(
                session: session,
                observerName:
                    ref.watch(authProvider).user?.fullName ?? 'Unknown',
                onViewDetails: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OutingDetailsScreen(outing: session),
                  ),
                ),
              );
            },
          );
        },
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
            Icon(Icons.folder_open,
                size: 64,
                color: colorScheme.onSurface.withValues(alpha: 0.25)),
            const SizedBox(height: 20),
            Text('No sessions yet',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    )),
            const SizedBox(height: 6),
            Text(
              'Completed sessions will appear here.',
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
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: colorScheme.error),
            const SizedBox(height: 16),
            Text('Error loading sessions',
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
