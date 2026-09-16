import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../utils/photo_viewer.dart';

class RecordCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> record;
  const RecordCard({super.key, required this.index, required this.record});

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
              const _PhotoStatusBadge(synced: true),
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
