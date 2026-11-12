import 'package:flutter/material.dart';
import '../../../utils/time_format.dart';

// Filled in automatically; tapping a time lets the user correct it, e.g. when typing up a paper sheet later
class PlotTimeRow extends StatelessWidget {
  final DateTime? start;
  final DateTime? end;
  final ValueChanged<DateTime> onStartChanged;
  final ValueChanged<DateTime> onEndChanged;

  const PlotTimeRow({
    super.key,
    required this.start,
    required this.end,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  Future<void> _pick(BuildContext context, DateTime? current, ValueChanged<DateTime> onPicked) async {
    final base = (current ?? start ?? end ?? DateTime.now()).toLocal();
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (picked == null) return;
    onPicked(DateTime(base.year, base.month, base.day, picked.hour, picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget slot(String label, DateTime? value, ValueChanged<DateTime> onPicked) => Expanded(
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 48),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () => _pick(context, value, onPicked),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$label ', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                TextSpan(
                  text: value == null ? 'not yet' : formatClockTime(value.toLocal()),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Icon(Icons.schedule, size: 20, color: colorScheme.onSurfaceVariant),
          ),
          slot('Started', start, onStartChanged),
          slot('Ended', end, onEndChanged),
        ],
      ),
    );
  }
}
