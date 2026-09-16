import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// Copies a picked image to the app's documents directory so the path
// remains valid after iOS clears its temporary cache.
Future<String> copyImageToPermanentStorage(String tempPath) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final photosDir = Directory(p.join(docsDir.path, 'photos'));
  if (!await photosDir.exists()) await photosDir.create(recursive: true);
  final filename = '${DateTime.now().millisecondsSinceEpoch}${p.extension(tempPath)}';
  final dest = p.join(photosDir.path, filename);
  await File(tempPath).copy(dest);
  return dest;
}
