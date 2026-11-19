import 'package:flutter/material.dart';
import '../../../utils/plot_validation.dart';
import '../../../utils/time_format.dart';

Future<bool?> showEndPlotMissingDialog(BuildContext context, int plotNumber, List<String> missing) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: Theme.of(ctx).colorScheme.error, size: 32),
      title: Text('Plot $plotNumber is missing ${missing.length == 1 ? 'a value' : '${missing.length} values'}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in missing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.close, size: 20, color: Theme.of(ctx).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item, style: Theme.of(ctx).textTheme.bodyLarge)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'You can still end the plot. It will be marked as incomplete and the session can still be submitted.',
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Keep editing'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('End anyway'),
        ),
      ],
    ),
  );
}

class EndPlotButton extends StatelessWidget {
  const EndPlotButton({super.key, required this.endState, required this.onPressed});
  final String? endState;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      icon: const Icon(Icons.check_circle_outline),
      label: Text(endState == null ? 'End plot' : 'End plot again'),
      onPressed: onPressed,
    );
  }
}

// Shown on a collapsed plot so an unfinished one stands out
class PlotEndStatus extends StatelessWidget {
  const PlotEndStatus({super.key, required this.endState, required this.endTime});
  final String? endState;
  final DateTime? endTime;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color, String label) = switch (endState) {
      plotEnded => (Icons.check_circle, Colors.green.shade700, endTime == null ? 'Ended' : 'Ended ${formatClockTime(endTime!)}'),
      plotEndedIncomplete => (Icons.error, Colors.orange.shade800, 'Ended, values missing'),
      _ => (Icons.radio_button_unchecked, colorScheme.error, 'Not ended'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
