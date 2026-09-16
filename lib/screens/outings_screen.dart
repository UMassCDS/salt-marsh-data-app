import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/field_outing_provider.dart';
import '../providers/org_provider.dart';
import '../services/sync_service.dart';
import 'outing_details_screen.dart';

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
              return _SessionCard(
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

// Supporting widgets

class _SessionCard extends StatelessWidget {
  final dynamic session;
  final String observerName;
  final VoidCallback onViewDetails;

  const _SessionCard({
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
                        _Chip(
                          label: typeLabel,
                          color: accent,
                          background: accent.withValues(alpha: 0.1),
                        ),
                        // Status chip
                        if (isDraft)
                          _Chip(
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

    return _Chip(label: label, color: color, background: background);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  const _Chip(
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
