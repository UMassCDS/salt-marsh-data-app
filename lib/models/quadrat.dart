import 'field_outing/plot_data.dart';

class QuadratConfig {
  const QuadratConfig({required this.widthM, required this.lengthM, required this.allowOverride});

  // SOP default frame: 0.5 m2 square
  static const sopDefault = QuadratConfig(widthM: 0.71, lengthM: 0.71, allowOverride: true);

  final double widthM;
  final double lengthM;
  final bool allowOverride;

  factory QuadratConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return sopDefault;
    return QuadratConfig(
      widthM: (json['width_m'] as num?)?.toDouble() ?? sopDefault.widthM,
      lengthM: (json['length_m'] as num?)?.toDouble() ?? sopDefault.lengthM,
      allowOverride: (json['allow_override'] as bool?) ?? true,
    );
  }
}

class QuadratPreset {
  const QuadratPreset(this.title, this.subtitle, this.widthM, this.lengthM);
  final String title;
  final String subtitle;
  final double widthM;
  final double lengthM;
}

// The 0.05 m2 pool-edge plot has no dimensions in the SOP, so it goes through Custom
const quadratPresets = [
  QuadratPreset('0.5 m² square', '0.71 × 0.71 m, standard plot', 0.71, 0.71),
  QuadratPreset('0.25 m² ditch frame', '0.25 × 1.0 m, ditch centres', 0.25, 1.0),
  QuadratPreset('1 m² square', '1.0 × 1.0 m', 1.0, 1.0),
];

String _metres(double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

String quadratLabel(double? widthM, double? lengthM) {
  if (widthM == null || lengthM == null) return 'Quadrat not set';
  final area = (widthM * lengthM).toStringAsFixed(2);
  return '${_metres(widthM)} × ${_metres(lengthM)} m ($area m²)';
}

// New plots, and plots from before quadrat size existed, start at the org default; a size already chosen is kept
void applyQuadratDefault(List<PlotData> plots, QuadratConfig config) {
  for (final plot in plots) {
    if (plot.quadratWidthM == null || plot.quadratLengthM == null) {
      plot.quadratWidthM = config.widthM;
      plot.quadratLengthM = config.lengthM;
    }
  }
}
