import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../providers/auth_provider.dart';
import '../../providers/org_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/sync_service.dart';
import '../../utils/database_export_helper.dart';
import '../../utils/sign_out_confirmation.dart';
import '../../utils/snackbar_utils.dart';
import '../login_screen.dart';
import 'widgets/sections.dart';

final _packageInfoProvider =
    FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _uploading = false;
  double _uploadProgress = 0;
  String? _phase;

  static const _batchBytes = 40 * 1024 * 1024;

  String get _statusLine => _phase == null
      ? ''
      : '$_phase ${(_uploadProgress * 100).toStringAsFixed(0)}%';

  Future<void> _signOut() async {
    final confirmed = await confirmSignOut(context);
    if (confirmed && context.mounted) {
      ref.read(selectedOrgProvider.notifier).clear();
      await ref.read(authProvider.notifier).logout();
      if (context.mounted) {
        unawaited(Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final user = ref.watch(authProvider).user;
    final versionLabel = ref.watch(_packageInfoProvider).maybeWhen(
          data: (info) => 'v${info.version}',
          orElse: () => '',
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          AccountSection(user: user, onSignOut: _signOut),
          const SizedBox(height: 28),
          AppearanceSection(
            themeMode: themeMode,
            onChanged: (v) {
              if (v != null) ref.read(themeModeProvider.notifier).set(v);
            },
          ),
          const SizedBox(height: 28),
          DataSection(
            uploading: _uploading,
            statusLine: _statusLine,
            onSendAll: _sendAll,
            onSendOneDay: _sendOneDay,
          ),
          const SizedBox(height: 28),
          AboutSection(versionLabel: versionLabel),
        ],
      ),
    );
  }

  Future<void> _sendAll() => _send(null);

  Future<void> _sendOneDay() async {
    final day = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
      helpText: 'Send data from',
    );
    if (day == null) return;
    await _send(day);
  }

  // One path for both buttons: data as one small upload, photos in batches
  Future<void> _send(DateTime? day) async {
    setState(() {
      _uploading = true;
      _uploadProgress = 0;
      _phase = 'Preparing';
    });

    try {
      await WakelockPlus.enable();

      final scope = DatabaseExportHelper.scopeLabel(day);

      final summary = await DatabaseExportHelper.inspect();
      final photos = await DatabaseExportHelper.photosForDay(day);
      final resumable = await DatabaseExportHelper.resumableFor(scope);
      final pending = photos
          .where((f) => !resumable.contains(p.basename(f.path)))
          .toList();
      if (!mounted) return;

      final withPhotos = await _askScope(day, pending);
      if (withPhotos == null) return;

      setState(() => _phase = 'Sending data');
      final bundle = await DatabaseExportHelper.buildBundle(summary, scope);
      final dataResult = await SyncService.instance.uploadRecoveryBundle(
        bundle.path,
        onProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          setState(() => _uploadProgress = sent / total);
        },
      );
      if (await bundle.exists()) await bundle.delete();

      if (!dataResult.success) {
        _report('Data upload failed: ${dataResult.error}', isError: true);
        return;
      }

      if (!withPhotos || photos.isEmpty) {
        _report('Data sent.');
        return;
      }

      if (pending.isEmpty) {
        // Every photo went up on a previous attempt, so the run is finished
        await DatabaseExportHelper.clearRunState();
        _report('Data sent. Photos were already finished.');
        return;
      }

      final sent = await _uploadPhotoBatches(pending, scope);
      if (sent.failure == null) {
        // Run complete: forget the progress so the next upload sends it all
        await DatabaseExportHelper.clearRunState();
        _report('Data sent, plus ${sent.count} photo(s) '
            '(${_humanSize(sent.bytes)}).');
      } else {
        _report(
            'Data sent, plus ${sent.count} photo(s), then stopped: '
            '${sent.failure}. Start it again to carry on.',
            isError: true);
      }
    } catch (e) {
      _report('Upload failed: $e', isError: true);
    } finally {
      await WakelockPlus.disable();
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = 0;
          _phase = null;
        });
      }
    }
  }

  static String _humanSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  // Deliberately shows no photo count or size here. Whoever runs this may be
  // in the field with no one to interpret a number for them, and a low or
  // zero count before anything has even been sent reads as data loss when it
  // usually just means "wrong date" or "not taken yet". The real numbers go
  // into the after-the-fact report and the summary the admin receives.
  Future<bool?> _askScope(DateTime? day, List<File> pending) async {
    final what = day == null
        ? 'everything on this device'
        : 'the database plus photos from '
            '${day.month}/${day.day}/${day.year}';
    final resuming = pending.isNotEmpty &&
        (await DatabaseExportHelper.resumableFor(
                DatabaseExportHelper.scopeLabel(day)))
            .isNotEmpty;

    if (!mounted) return null;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send to server?'),
        content: Text(
          'This sends $what so an admin can review it. Nothing on this '
          'device is changed or deleted.\n\n'
          '${resuming ? 'Continuing a previous upload that stopped partway. ' : ''}'
          'Photos go in small batches. If this stops partway you can start it '
          'again and it will pick up where it left off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Data only'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Data + photos'),
          ),
        ],
      ),
    );
  }

  Future<({int count, int bytes, String? failure})> _uploadPhotoBatches(
      List<File> pending, String scope) async {
    final batches = await DatabaseExportHelper.batchBySize(pending, _batchBytes);
    var count = 0;
    var bytes = 0;

    for (var i = 0; i < batches.length; i++) {
      if (mounted) {
        setState(() {
          _uploadProgress = 0;
          _phase = 'Photos ${i + 1} of ${batches.length}';
        });
      }

      final zip = await DatabaseExportHelper.buildPhotoBatch(
          batches[i], scope, i + 1, batches.length);
      try {
        final result = await SyncService.instance.uploadRecoveryBundle(
          zip.path,
          onProgress: (sent, total) {
            if (!mounted || total <= 0) return;
            setState(() => _uploadProgress = sent / total);
          },
        );
        if (!result.success) {
          return (count: count, bytes: bytes, failure: result.error);
        }
      } finally {
        if (await zip.exists()) await zip.delete();
      }

      // Recorded before any mounted check, so leaving the screen cannot lose
      // the fact that these are safely on the server
      await DatabaseExportHelper.recordRunProgress(
          scope, batches[i].map((f) => p.basename(f.path)));
      count += batches[i].length;
      for (final f in batches[i]) {
        bytes += await f.length();
      }
    }

    return (count: count, bytes: bytes, failure: null);
  }

  void _report(String message, {bool isError = false}) {
    if (!mounted) return;
    if (isError) {
      showAppSnackBar(
        context,
        message,
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 8),
      );
    } else {
      showAppSnackBar(context, message, duration: const Duration(seconds: 6));
    }
  }
}
