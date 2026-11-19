import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/quadrat.dart';

class QuadratChip extends StatelessWidget {
  const QuadratChip({super.key, required this.widthM, required this.lengthM, required this.onChanged});
  final double? widthM;
  final double? lengthM;
  final void Function(double widthM, double lengthM) onChanged;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.crop_square, size: 20),
      label: Text('Quadrat ${quadratLabel(widthM, lengthM)}'),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      onPressed: () async {
        final picked = await showQuadratPicker(context, widthM: widthM, lengthM: lengthM);
        if (picked != null) onChanged(picked.$1, picked.$2);
      },
    );
  }
}

Future<(double, double)?> showQuadratPicker(BuildContext context, {double? widthM, double? lengthM}) {
  return showModalBottomSheet<(double, double)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _QuadratSheet(widthM: widthM, lengthM: lengthM),
  );
}

class _QuadratSheet extends StatefulWidget {
  const _QuadratSheet({this.widthM, this.lengthM});
  final double? widthM;
  final double? lengthM;

  @override
  State<_QuadratSheet> createState() => _QuadratSheetState();
}

class _QuadratSheetState extends State<_QuadratSheet> {
  late final _width = TextEditingController(text: widget.widthM?.toString() ?? '');
  late final _length = TextEditingController(text: widget.lengthM?.toString() ?? '');

  @override
  void dispose() {
    _width.dispose();
    _length.dispose();
    super.dispose();
  }

  (double, double)? get _custom {
    final w = double.tryParse(_width.text);
    final l = double.tryParse(_length.text);
    if (w == null || l == null || w <= 0 || l <= 0 || w > 10 || l > 10) return null;
    return (w, l);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Quadrat size', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            for (final preset in quadratPresets) ...[
              _PresetCard(
                preset: preset,
                selected: preset.widthM == widget.widthM && preset.lengthM == widget.lengthM,
                onTap: () => Navigator.of(context).pop((preset.widthM, preset.lengthM)),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Text('Custom size', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _metreField(_width, 'Width (m)')),
                const SizedBox(width: 12),
                Expanded(child: _metreField(_length, 'Length (m)')),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _custom == null ? null : () => Navigator.of(context).pop(_custom),
              child: const Text('Use custom size'),
            ),
            const SizedBox(height: 8),
            Text(
              'Keep the same size a site used in earlier years.',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metreField(TextEditingController controller, String label) => TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onChanged: (_) => setState(() {}),
      );
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.preset, required this.selected, required this.onTap});
  final QuadratPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Glyph drawn to the frame's proportions so the ditch frame reads as a long rectangle
    final scale = 36 / [preset.widthM, preset.lengthM].reduce((a, b) => a > b ? a : b);
    return Material(
      color: selected ? colorScheme.primaryContainer : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? colorScheme.primary : colorScheme.outlineVariant, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: preset.widthM * scale,
                    height: preset.lengthM * scale,
                    decoration: BoxDecoration(border: Border.all(color: colorScheme.primary, width: 2.5)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preset.title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text(preset.subtitle, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
