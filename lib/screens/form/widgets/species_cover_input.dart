import 'package:flutter/material.dart';
import '../../../models/field_outing/plot_data.dart';
import '../../../services/species_service.dart';

class SpeciesCoverInput extends StatefulWidget {
  final PlotData plot;
  final List<SpeciesItem> allSpecies;
  final VoidCallback onChanged;
  final int coverIncrement;
  final List<String> pinnedCodes;

  const SpeciesCoverInput({
    super.key,
    required this.plot,
    required this.allSpecies,
    required this.onChanged,
    this.coverIncrement = 1,
    this.pinnedCodes = const ['SPALT', 'SPPAT', 'BARE', 'DEAD'],
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

  Widget _speciesLabel(BuildContext context, String code, String commonLabel, String scientificName) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(commonLabel, style: theme.textTheme.bodyMedium),
        Text(
          scientificName,
          style: theme.textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
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

    // Build a lookup map for extra species scientific names
    final speciesMap = {for (final s in widget.allSpecies) s.code: s};

    // Helper: builds a cover input — TextField for increment=1, ChoiceChips otherwise
    Widget buildCoverInput({
      required String code,
      required TextEditingController? controller,
      required int currentValue,
      required void Function(String) onChanged,
    }) {
      if (widget.coverIncrement == 1) {
        return SizedBox(
          width: 64,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              suffixText: '%',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Text(
          'Species in this Plot (${plot.species.length})',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
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
          if (widget.coverIncrement == 1) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _speciesLabel(context, code, '$code – $commonLabel', scientificName),
                  ),
                  buildCoverInput(
                    code: code,
                    controller: controller,
                    currentValue: currentValue,
                    onChanged: (v) => _updatePinned(code, v),
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
                _speciesLabel(context, code, '$code – $commonLabel', scientificName),
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
                    Expanded(child: _speciesLabel(context, code, commonLabel, scientificName)),
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
                      Expanded(child: _speciesLabel(context, code, commonLabel, scientificName)),
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

        // Search results
        if (filtered.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = filtered[i];
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
