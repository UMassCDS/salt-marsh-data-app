import 'dart:io';
import 'package:flutter/material.dart';
import '../../../models/field_outing/additional_photo.dart';
import '../../../utils/photo_viewer.dart';

class AdditionalPhotosSection extends StatelessWidget {
  const AdditionalPhotosSection({
    super.key,
    required this.photos,
    required this.onTake,
    required this.onChoose,
    required this.onRemove,
  });

  final List<AdditionalPhoto> photos;
  final VoidCallback onTake;
  final VoidCallback onChoose;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: 'Additional photos', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          TextSpan(text: '  optional', style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
        ])),
        const SizedBox(height: 8),
        if (photos.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final photo in photos)
                Stack(
                  children: [
                    GestureDetector(
                      onTap: () => showFullScreenPhoto(context, File(photo.path)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(photo.path), width: 96, height: 96, fit: BoxFit.cover, cacheWidth: 192),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        tooltip: 'Remove photo',
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        icon: Icon(Icons.close, color: Colors.red[400]),
                        style: IconButton.styleFrom(backgroundColor: Colors.white70),
                        onPressed: () => onRemove(photo.localId),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        if (photos.isNotEmpty) const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: onTake,
                icon: const Icon(Icons.add_a_photo),
                label: const Text('Take'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: onChoose,
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('Choose'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
