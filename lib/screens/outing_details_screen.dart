import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart';
import '../models/field_outing/field_outing.dart';
import '../providers/auth_provider.dart';
import '../providers/field_outing_provider.dart';
import '../services/sync_service.dart';
import '../utils/photo_viewer.dart';

class OutingDetailsScreen extends ConsumerStatefulWidget {
  final FieldOuting outing;

  const OutingDetailsScreen({required this.outing, super.key});

  @override
  ConsumerState<OutingDetailsScreen> createState() =>
      _OutingDetailsScreenState();
}

class _OutingDetailsScreenState extends ConsumerState<OutingDetailsScreen> {
  List<Map<String, dynamic>> _childRecords = [];
  bool _loading = true;
  bool _resyncing = false;

  @override
  void initState() {
    super.initState();
    _loadChildRecords();
  }

  Future<void> _loadChildRecords() async {
    final db = await AppDatabase.instance.database;
    final id = widget.outing.id;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }

    final String table;
    switch (widget.outing.monitoringType) {
      case 'vegetation':
        table = 'vegetation_records';
      case 'hydrology':
        table = 'hydrology_records';
      case 'elevation':
        table = 'elevation_records';
      default:
        setState(() => _loading = false);
        return;
    }

    final records =
        await db.query(table, where: 'outing_id = ?', whereArgs: [id]);
    setState(() {
      _childRecords = records;
      _loading = false;
    });
  }

  Future<void> _resyncOuting() async {
    final id = widget.outing.id;
    if (id == null || _resyncing) return;
    setState(() => _resyncing = true);
    try {
      final result = await SyncService.instance.resyncOuting(id);
      ref.invalidate(pendingPhotoUploadsCountProvider(id));
      await _loadChildRecords();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_resyncMessage(result))),
      );
    } finally {
      if (mounted) setState(() => _resyncing = false);
    }
  }

  String _resyncMessage(ResyncResult result) {
    if (result.uploadFailed) {
      return 'Could not upload session, check your connection and try again';
    }
    final parts = <String>[];
    if (result.uploadedNow) parts.add('session uploaded');
    if (result.plotsRecovered > 0) parts.add('recovered ${result.plotsRecovered} missing plot(s)');
    if (result.photosUploaded > 0) parts.add('uploaded ${result.photosUploaded} photo(s)');
    if (result.photosStillPending > 0) parts.add('${result.photosStillPending} photo(s) still uploading');
    if (parts.isEmpty) return result.alreadyOnServer ? 'Already fully synced' : 'Nothing to sync';
    final msg = parts.join(', ');
    return '${msg[0].toUpperCase()}${msg.substring(1)}';
  }

  static const _typeColors = {
    'vegetation': Color(0xFF2E7D32),
    'hydrology': Color(0xFF0277BD),
    'elevation': Color(0xFF6A3F00),
  };

  @override
  Widget build(BuildContext context) {
    final session = widget.outing;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent =
        _typeColors[session.monitoringType] ?? colorScheme.primary;
    final isDraft = session.isDraft;

    return Scaffold(
      appBar: AppBar(
        title: Text(session.siteName),
        actions: [
          IconButton(
            tooltip: 'Resync',
            icon: _resyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onPressed: (isDraft || _resyncing) ? null : _resyncOuting,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status + type banner
            Row(
              children: [
                _TypeBadge(
                    type: session.monitoringType, accent: accent),
                const SizedBox(width: 8),
                _StatusBadge(
                  isDraft: isDraft,
                  syncStatus: session.syncStatus,
                  outingId: session.id,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Session info card
            _SectionCard(
              title: 'Session Info',
              children: [
                _InfoRow(
                    icon: Icons.person_outline,
                    label: 'Observer',
                    value: ref.watch(authProvider).user?.fullName ?? 'Unknown'),
                if (session.otherMembers != null &&
                    session.otherMembers!.isNotEmpty)
                  _InfoRow(
                      icon: Icons.group_outlined,
                      label: 'Other Members',
                      value: session.otherMembers!),
                if (session.startTime != null)
                  _InfoRow(
                      icon: Icons.schedule,
                      label: 'Start',
                      value: session.startTime!
                          .toString()
                          .split('.')
                          .first),
                if (session.endTime != null)
                  _InfoRow(
                      icon: Icons.timer_outlined,
                      label: 'End',
                      value: session.endTime!
                          .toString()
                          .split('.')
                          .first),
                if (session.createdAt != null)
                  _InfoRow(
                      icon: Icons.calendar_today_outlined,
                      label: 'Created',
                      value: session.createdAt!
                          .toString()
                          .split('.')
                          .first),
              ],
            ),
            const SizedBox(height: 16),

            // Records
            Row(
              children: [
                Text('Records',
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_childRecords.length}',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator()))
            else if (_childRecords.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('No records found.',
                    style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.5))),
              )
            else
              ..._childRecords.asMap().entries.map(
                    (entry) => _RecordCard(
                      index: entry.key + 1,
                      record: entry.value,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

// Sub-widgets

class _TypeBadge extends StatelessWidget {
  final String type;
  final Color accent;
  const _TypeBadge({required this.type, required this.accent});

  @override
  Widget build(BuildContext context) {
    final label = '${type[0].toUpperCase()}${type.substring(1)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              )),
    );
  }
}

// Combines metadata sync status with pending-photo count into one signal,
// so "fully synced" always means the whole session, not just the record row
class _StatusBadge extends ConsumerWidget {
  final bool isDraft;
  final String syncStatus;
  final int? outingId;
  const _StatusBadge({
    required this.isDraft,
    required this.syncStatus,
    required this.outingId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadataSynced = !isDraft && syncStatus == 'synced';
    final photosPending = (isDraft || outingId == null)
        ? 0
        : ref
            .watch(pendingPhotoUploadsCountProvider(outingId!))
            .maybeWhen(data: (v) => v, orElse: () => 0);
    final fullySynced = metadataSynced && photosPending == 0;

    final color = isDraft
        ? Colors.orange.shade700
        : fullySynced
            ? Colors.green.shade700
            : Colors.amber.shade800;
    final bg = isDraft
        ? Colors.orange.withValues(alpha: 0.1)
        : fullySynced
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.amber.withValues(alpha: 0.12);
    final label = isDraft
        ? 'Draft'
        : fullySynced
            ? 'Fully synced'
            : photosPending > 0
                ? 'Needs resync ($photosPending photo${photosPending == 1 ? '' : 's'})'
                : 'Needs resync';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              )),
    );
  }
}

class _PhotoStatusBadge extends StatelessWidget {
  final bool synced;
  final String? error;
  const _PhotoStatusBadge({required this.synced, this.error});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final Color bg;
    final String label;
    if (synced) {
      color = Colors.green.shade700;
      bg = Colors.green.withValues(alpha: 0.1);
      label = 'Photo synced';
    } else if (error != null && error!.isNotEmpty) {
      color = Colors.red.shade700;
      bg = Colors.red.withValues(alpha: 0.1);
      label = 'Photo not uploaded';
    } else {
      color = Colors.amber.shade800;
      bg = Colors.amber.withValues(alpha: 0.12);
      label = 'Photo pending upload';
    }

    final hasReason = error != null && error!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  )),
        ),
        if (hasReason) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurface.withValues(alpha: 0.45)),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(label,
                style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.55))),
          ),
          Expanded(
            child: Text(value,
                style:
                    textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> record;
  const _RecordCard({required this.index, required this.record});

  static const _skip = {
    'id',
    'local_id',
    'server_id',
    'outing_id',
    'sync_status',
    'created_at',
    'updated_at',
    'photo_filename',
    'photo_local_path',
    'photo_upload_error',
    'photo_upload_attempts',
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final photoUrl = record['photo_filename'] as String?;
    final photoLocalPath = record['photo_local_path'] as String?;
    final photoUploadError = record['photo_upload_error'] as String?;
    final photoSynced = photoUrl != null && photoUrl.startsWith('http');
    // Preferred over the uploaded copy - a synced photo whose local file is
    // still on disk stays viewable with no signal, which the network URL
    // cannot do
    final localFile = photoLocalPath != null && photoLocalPath.isNotEmpty
        ? File(photoLocalPath)
        : null;
    final hasLocalFile = localFile != null && localFile.existsSync();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    'Record #$index',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),

            // Photo
            if (hasLocalFile) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: GestureDetector(
                    onTap: () => showFullScreenPhoto(context, localFile),
                    child: Stack(
                      children: [
                        Image.file(localFile, fit: BoxFit.cover, cacheWidth: 800),
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.zoom_in, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text('Tap to enlarge',
                                      style: TextStyle(color: Colors.white, fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _PhotoStatusBadge(
                synced: photoSynced,
                error: photoSynced ? null : photoUploadError,
              ),
            ] else if (photoSynced) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) =>
                      progress == null
                          ? child
                          : const Center(
                              child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator())),
                  errorBuilder: (_, _, _) => Text('Failed to load photo',
                      style: TextStyle(color: colorScheme.error)),
                ),
              ),
              const SizedBox(height: 6),
              _PhotoStatusBadge(synced: true),
            ],

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Field rows
            ...record.entries
                .where((e) => !_skip.contains(e.key) && e.value != null)
                .map((e) {
              String displayValue;
              if (e.key == 'species_observations') {
                try {
                  final List decoded = jsonDecode(e.value as String);
                  displayValue = decoded
                      .map((s) =>
                          '${s['species_code']}: ${s['percentage_cover']}%')
                      .join(', ');
                } catch (_) {
                  displayValue = e.value.toString();
                }
              } else {
                displayValue = e.value.toString();
              }
              final label = e.key
                  .replaceAll('_', ' ')
                  .split(' ')
                  .map((w) =>
                      w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w)
                  .join(' ');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text('$label:',
                          style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface
                                  .withValues(alpha: 0.55))),
                    ),
                    Expanded(
                        child: Text(displayValue,
                            style: textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500))),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
