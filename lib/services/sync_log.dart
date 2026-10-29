import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SyncLogEntry {
  final DateTime time;
  final String method;
  final String path;
  final String network;
  final int durationMs;
  final String outcome;
  final int? status;

  const SyncLogEntry({
    required this.time,
    required this.method,
    required this.path,
    required this.network,
    required this.durationMs,
    required this.outcome,
    this.status,
  });

  Map<String, Object?> toJson() => {
        't': time.toIso8601String(),
        'm': method,
        'p': path,
        'n': network,
        'ms': durationMs,
        'o': outcome,
        if (status != null) 's': status,
      };

  static SyncLogEntry? tryParse(String line) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      return SyncLogEntry(
        time: DateTime.parse(json['t'] as String),
        method: json['m'] as String,
        path: json['p'] as String,
        network: json['n'] as String,
        durationMs: json['ms'] as int,
        outcome: json['o'] as String,
        status: json['s'] as int?,
      );
    } catch (_) {
      return null;
    }
  }

  String get summary =>
      '${time.toIso8601String()} $method $path network=$network ${durationMs}ms $outcome${status != null ? ' ($status)' : ''}';
}

// Request metadata only: never bodies, query strings or anything a user typed
class SyncLog {
  final Future<File> Function() _fileProvider;
  final Duration retention;
  final DateTime Function() _clock;
  bool _prunedThisSession = false;

  SyncLog({
    required Future<File> Function() fileProvider,
    this.retention = const Duration(days: 14),
    DateTime Function()? clock,
  })  : _fileProvider = fileProvider,
        _clock = clock ?? DateTime.now;

  static final SyncLog persistent = SyncLog(fileProvider: () async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'sync_log.jsonl'));
  });

  Future<void> record(SyncLogEntry entry) async {
    try {
      final file = await _fileProvider();
      if (!_prunedThisSession) {
        _prunedThisSession = true;
        await _prune(file);
      }
      await file.writeAsString('${jsonEncode(entry.toJson())}\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // A broken log must never break syncing
    }
  }

  Future<List<SyncLogEntry>> entries() async {
    try {
      final file = await _fileProvider();
      if (!await file.exists()) return [];
      final lines = await file.readAsLines();
      return lines.map(SyncLogEntry.tryParse).whereType<SyncLogEntry>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<String> dump() async {
    final all = await entries();
    if (all.isEmpty) return 'No sync attempts recorded.';
    return all.map((e) => e.summary).join('\n');
  }

  Future<void> _prune(File file) async {
    if (!await file.exists()) return;
    final cutoff = _clock().subtract(retention);
    final kept = (await file.readAsLines())
        .map((line) => (line: line, entry: SyncLogEntry.tryParse(line)))
        .where((r) => r.entry != null && r.entry!.time.isAfter(cutoff))
        .map((r) => r.line);
    await file.writeAsString(kept.isEmpty ? '' : '${kept.join('\n')}\n');
  }
}
