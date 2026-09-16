import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../constants/species_constants.dart';
import '../../../models/field_outing/plot_data.dart';
import '../../../services/species_service.dart';

// Blocks non-digit characters and clamps the parsed value to [0, 100] as
// the user types, so the field can never visibly hold an out-of-range %.
class _PercentInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return newValue.copyWith(text: digits);
    }
    final parsed = int.parse(digits).clamp(0, 100);
    digits = parsed.toString();
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

class SpeciesCoverInput extends StatefulWidget {
  final PlotData plot;
  final List<SpeciesItem> allSpecies;
  final VoidCallback onChanged;
  final int coverIncrement;
  final List<String> pinnedCodes;
  final bool require100Percent;

  const SpeciesCoverInput({
    super.key,
    required this.plot,
    required this.allSpecies,
    required this.onChanged,
    this.coverIncrement = 1,
    this.pinnedCodes = const ['SPALT', 'SPPAT', 'BARE', 'DEAD'],
    this.require100Percent = false,
  });

  @override
  State<SpeciesCoverInput> createState() => SpeciesCoverInputState();
}

class SpeciesCoverInputState extends State<SpeciesCoverInput> {
  static const _pinnedLabels = {
    'SPALT': 'Smooth Cordgrass',
    'SPPAT': 'Salt Meadow Cordgrass',
    'BARE': 'Bare Ground',
    'DEAD': 'Dead Vegetation',
  };

  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Map<String, GlobalKey> _pinnedRowKeys = {};

  GlobalKey _pinnedKey(String code) =>
      _pinnedRowKeys.putIfAbsent(code, GlobalKey.new);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SpeciesItem> _filteredSpecies() {
    final q = _searchQuery.toLowerCase().trim();
    if (q.isEmpty) return [];

    final addedCodes = widget.plot.species.map((s) => s.speciesCode).toSet();

    return widget.allSpecies.where((s) {
      if (widget.pinnedCodes.contains(s.code)) return false;
      if (addedCodes.contains(s.code)) return false;
      final haystack = '${s.label.toLowerCase()} ${s.scientificName.toLowerCase()}';
      return s.code.toLowerCase().contains(q) || haystack.contains(q);
    }).toList()
      ..sort((a, b) {
        final aStarts = a.code.toLowerCase().startsWith(q) ? 0 : 1;
        final bStarts = b.code.toLowerCase().startsWith(q) ? 0 : 1;
        return aStarts.compareTo(bStarts);
      });
  }

  // Pinned species matching the search query, so a field user typing an
  // abbreviation for an already-pinned species can still find it - just
  // routed to the fixed pinned row above instead of a second, duplicate entry.
  List<String> _filteredPinnedMatches() {
    final q = _searchQuery.toLowerCase().trim();
    if (q.isEmpty) return [];
    final speciesMap = {for (final s in widget.allSpecies) s.code: s};
    return widget.pinnedCodes.where((code) {
      final item = speciesMap[code];
      final commonName = item?.commonName ?? _pinnedLabels[code] ?? '';
      final scientificName = item?.scientificName ?? '';
      final haystack = '$code $commonName $scientificName'.toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  void _jumpToPinned(String code) {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
    });
    final ctx = _pinnedKey(code).currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    }
  }

  void _updatePinned(String code, String rawValue) {
    final percent = int.tryParse(rawValue);
    final plot = widget.plot;
    setState(() {
      plot.species.removeWhere((s) => s.speciesCode == code);
      if (percent != null && percent > 0) {
        plot.species.add(PlotSpeciesEntry(
          speciesCode: code,
          percentageCover: percent.clamp(0, 100),
        ));
      }
    });
    widget.onChanged();
  }

  void _clearPinned(String code) {
    widget.plot.pinnedControllers[code]?.clear();
    _updatePinned(code, '');
  }

  void _addExtra(SpeciesItem species) {
    final plot = widget.plot;
    if (plot.species.any((s) => s.speciesCode == species.code)) return;
    setState(() {
      plot.species.add(PlotSpeciesEntry(speciesCode: species.code, percentageCover: 0));
      plot.extraControllers[species.code] = TextEditingController(text: '');
      _searchController.clear();
      _searchQuery = '';
    });
    widget.onChanged();
  }

  void _removeExtra(String code) {
    final plot = widget.plot;
    setState(() {
      plot.species.removeWhere((s) => s.speciesCode == code);
      plot.extraControllers[code]?.dispose();
      plot.extraControllers.remove(code);
    });
    widget.onChanged();
  }

  void _updateExtra(String code, String rawValue) {
    final percent = int.tryParse(rawValue);
    final plot = widget.plot;
    final idx = plot.species.indexWhere((s) => s.speciesCode == code);
    if (idx < 0 || percent == null) return;
    setState(() {
      plot.species[idx] = PlotSpeciesEntry(
        speciesCode: code,
        percentageCover: percent.clamp(0, 100),
      );
    });
    widget.onChanged();
  }

  Widget _speciesLabel(BuildContext context, String code, String commonLabel, String scientificName,
      {required bool isWideScreen}) {
    final theme = Theme.of(context);
    // A touch smaller on narrow phones so more of the name fits before it
    // has to truncate - still ellipsizes past that, by design
    final primaryStyle = isWideScreen ? theme.textTheme.bodyLarge : theme.textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          scientificName.isEmpty ? commonLabel : scientificName,
          style: primaryStyle?.copyWith(
            fontStyle: scientificName.isEmpty ? FontStyle.normal : FontStyle.italic,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (scientificName.isNotEmpty)
          Text(
            commonLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plot = widget.plot;
    final extraSpecies = plot.species
        .where((s) => !widget.pinnedCodes.contains(s.speciesCode))
        .toList();
    final filtered = _filteredSpecies();
    final pinnedMatches = _filteredPinnedMatches();

    // Build a lookup map for extra species scientific names
    final speciesMap = {for (final s in widget.allSpecies) s.code: s};

    // Wide screens (tablets in the field) get a bigger, easier-to-hit box
    final isWideScreen = MediaQuery.sizeOf(context).width >= 600;
    final coverBoxWidth = isWideScreen ? 88.0 : 68.0;
    final darkOutline = OutlineInputBorder(
      borderSide: BorderSide(color: theme.colorScheme.outline, width: 1.5),
    );

    // Helper: builds a cover input - TextField for increment=1, ChoiceChips otherwise
    Widget buildCoverInput({
      required String code,
      required TextEditingController? controller,
      required int currentValue,
      required void Function(String) onChanged,
    }) {
      if (widget.coverIncrement == 1) {
        return SizedBox(
          width: coverBoxWidth,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [_PercentInputFormatter()],
            style: isWideScreen ? theme.textTheme.titleMedium : null,
            decoration: InputDecoration(
              suffixText: '%',
              border: darkOutline,
              enabledBorder: darkOutline,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              isDense: true,
            ),
            onChanged: onChanged,
          ),
        );
      }
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        children: List.generate(11, (i) {
          final v = i * 10;
          return ChoiceChip(
            label: Text('$v', style: const TextStyle(fontSize: 11)),
            selected: currentValue == v,
            onSelected: (_) => onChanged(v.toString()),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 2),
          );
        }),
      );
    }

    final coverTotal = plot.species
        .where((s) => !kCoverExcludedSpeciesCodes.contains(s.speciesCode))
        .fold<int>(0, (sum, s) => sum + s.percentageCover);
    final totalMet = coverTotal == 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Species in this Plot (${plot.species.length})',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: totalMet
                    ? Colors.green.withValues(alpha: 0.15)
                    : (widget.require100Percent
                        ? Colors.orange.withValues(alpha: 0.15)
                        : theme.colorScheme.surfaceContainerHighest),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                widget.require100Percent
                    ? 'Total: $coverTotal% ${totalMet ? '' : '(need 100%)'}'
                    : 'Total: $coverTotal%',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: totalMet
                      ? Colors.green.shade800
                      : (widget.require100Percent ? Colors.orange.shade900 : null),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Pinned species rows (always shown in fixed order)
        ...widget.pinnedCodes.map((code) {
          // .commonName, not .label - label already has "CODE - " baked in,
          // and the row below prepends code again, showing it twice
          final commonName = speciesMap[code]?.commonName ?? _pinnedLabels[code];
          final commonLabel = commonName ?? code;
          final scientificName = speciesMap[code]?.scientificName ?? '';
          final controller = plot.pinnedControllers[code];
          final currentValue = plot.species
              .firstWhere((s) => s.speciesCode == code,
                  orElse: () => PlotSpeciesEntry(speciesCode: code, percentageCover: 0))
              .percentageCover;
          final clearButton = currentValue > 0
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.red),
                  padding: EdgeInsets.zero,
                  tooltip: 'Reset to 0%',
                  onPressed: () => _clearPinned(code),
                )
              : null;
          if (widget.coverIncrement == 1) {
            return Padding(
              key: _pinnedKey(code),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _speciesLabel(context, code, '$code – $commonLabel', scientificName,
                        isWideScreen: isWideScreen),
                  ),
                  buildCoverInput(
                    code: code,
                    controller: controller,
                    currentValue: currentValue,
                    onChanged: (v) => _updatePinned(code, v),
                  ),
                  ?clearButton,
                ],
              ),
            );
          }
          return Padding(
            key: _pinnedKey(code),
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _speciesLabel(context, code, '$code – $commonLabel', scientificName,
                          isWideScreen: isWideScreen),
                    ),
                    ?clearButton,
                  ],
                ),
                const SizedBox(height: 4),
                buildCoverInput(
                  code: code,
                  controller: controller,
                  currentValue: currentValue,
                  onChanged: (v) => _updatePinned(code, v),
                ),
              ],
            ),
          );
        }),

        // Extra (non-pinned) added species
        if (extraSpecies.isNotEmpty) ...[
          const Divider(height: 20),
          ...extraSpecies.map((obs) {
            final code = obs.speciesCode;
            final item = speciesMap[code];
            final commonLabel = item?.label ?? code;
            final scientificName = item?.scientificName ?? '';
            final controller = plot.extraControllers[code] ??
                TextEditingController(text: obs.percentageCover.toString());
            if (widget.coverIncrement == 1) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(child: _speciesLabel(context, code, commonLabel, scientificName, isWideScreen: isWideScreen)),
                    buildCoverInput(
                      code: code,
                      controller: controller,
                      currentValue: obs.percentageCover,
                      onChanged: (v) => _updateExtra(code, v),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.red),
                      padding: EdgeInsets.zero,
                      onPressed: () => _removeExtra(code),
                    ),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _speciesLabel(context, code, commonLabel, scientificName, isWideScreen: isWideScreen)),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Colors.red),
                        padding: EdgeInsets.zero,
                        onPressed: () => _removeExtra(code),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  buildCoverInput(
                    code: code,
                    controller: controller,
                    currentValue: obs.percentageCover,
                    onChanged: (v) => _updateExtra(code, v),
                  ),
                ],
              ),
            );
          }),
        ],

        // Search field
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 20),
            hintText: 'Search to add more species...',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),

        // Search results (pinned matches first, greyed - they route back to
        // the fixed pinned row above rather than adding a duplicate)
        if (filtered.isNotEmpty || pinnedMatches.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: pinnedMatches.length + filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i < pinnedMatches.length) {
                  final code = pinnedMatches[i];
                  final item = speciesMap[code];
                  final commonLabel = item?.commonName ?? _pinnedLabels[code] ?? code;
                  return ListTile(
                    dense: true,
                    title: Text(
                      '$code – $commonLabel (pinned)',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    subtitle: Text(
                      item?.scientificName ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_upward, size: 18),
                    onTap: () => _jumpToPinned(code),
                  );
                }
                final s = filtered[i - pinnedMatches.length];
                return ListTile(
                  dense: true,
                  title: Text(s.label, style: theme.textTheme.bodyMedium),
                  subtitle: Text(
                    s.scientificName,
                    style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                  ),
                  trailing: const Icon(Icons.add, size: 18),
                  onTap: () => _addExtra(s),
                );
              },
            ),
          ),
      ],
    );
  }
}
