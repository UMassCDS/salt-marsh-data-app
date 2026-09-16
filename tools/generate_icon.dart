// Run from project root: dart run tools/generate_icon.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  _generateMainIcon();
  _generateForegroundIcon();
}

void _generateMainIcon() {
  const size = 1024;
  const cx = size ~/ 2;

  // RGBA so we can share _drawDesign with the foreground generator
  final image = img.Image(width: size, height: size, numChannels: 4);

  // Background: deep forest green, brighter radial glow from upper-centre
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final dx = (x - cx).toDouble();
      final dy = (y - size * 0.35).toDouble();
      final dist = math.sqrt(dx * dx + dy * dy) / size;
      final t = (1.0 - dist * 1.3).clamp(0.0, 1.0);
      final r = _lerp(12, 40, t).round().clamp(0, 255);
      final g = _lerp(52, 110, t).round().clamp(0, 255);
      final b = _lerp(20, 48, t).round().clamp(0, 255);
      image.setPixel(x, y, img.ColorRgba8(r, g, b, 255));
    }
  }

  _drawDesign(image, 1.0);

  final outPath = 'assets/icon.png';
  final bytes = img.encodePng(image);
  File(outPath).writeAsBytesSync(bytes);
  stdout.writeln('✅ Icon saved to $outPath  (${(bytes.length / 1024).toStringAsFixed(1)} KB)');
}

void _generateForegroundIcon() {
  const size = 1024;

  // Fully transparent RGBA canvas
  final image = img.Image(width: size, height: size, numChannels: 4);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      image.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0));
    }
  }

  // Draw at 60% scale - keeps content well within Android's safe zone (66%)
  _drawDesign(image, 0.6);

  final outPath = 'assets/icon_foreground.png';
  final bytes = img.encodePng(image);
  File(outPath).writeAsBytesSync(bytes);
  stdout.writeln('✅ Foreground saved to $outPath  (${(bytes.length / 1024).toStringAsFixed(1)} KB)');
}

/// Draws the marsh grass + water design at [scale] relative to image centre.
/// scale=1.0 fills the canvas naturally; scale=0.6 fits within Android safe zone.
void _drawDesign(img.Image image, double scale) {
  // Fixed origin for the scale transform (canvas centre X, content centre Y)
  const origCx = 512.0;
  const origCy = 517.0; // mid-point between top blade tip (185) and bottom arc (848)

  int tx(num x) => (origCx + (x - origCx) * scale).round();
  int ty(num y) => (origCy + (y - origCy) * scale).round();
  int ts(num s) => (s.abs() * scale).round() * (s < 0 ? -1 : 1);

  const baseY = 640; // ground line

  // Marsh grass: 5 tapered blades, varying heights & lean
  // (bx, topY, baseWidth, tipWidth, lean)
  final blades = [
    (512 - 175, 310, 36, 8, -22),
    (512 - 72,  225, 42, 10, -10),
    (512,       185, 48, 12,   0),
    (512 + 82,  240, 40,  9,  12),
    (512 + 185, 320, 34,  7,  24),
  ];

  final white    = img.ColorRgba8(255, 255, 255, 255);
  final midWhite = img.ColorRgba8(210, 235, 213, 255);
  final dimWhite = img.ColorRgba8(155, 195, 160, 255);

  for (final b in blades) {
    _drawBlade(image, tx(b.$1), ty(b.$2), ty(baseY),
        ts(b.$3), ts(b.$4), ts(b.$5), white);
  }

  // Water: 3 upward-arching ripple bands below the grass line
  _drawArc(image, tx(512), ty(baseY + 60),  ts(300), ts(32), white);
  _drawArc(image, tx(512), ty(baseY + 138), ts(228), ts(26), midWhite);
  _drawArc(image, tx(512), ty(baseY + 208), ts(160), ts(20), dimWhite);
}

double _lerp(num a, num b, double t) => a + (b - a) * t;

/// Tapered blade: wide at [baseY], [tipWidth] at [topY], leaning by [lean] px at tip.
void _drawBlade(
    img.Image image, int bx, int topY, int baseY,
    int baseWidth, int tipWidth, int lean, img.Color color) {
  final height = (baseY - topY).toDouble();
  if (height <= 0) return;
  for (int y = topY; y <= baseY; y++) {
    final t = (y - topY) / height; // 0 at tip, 1 at base
    final w = (tipWidth + (baseWidth - tipWidth) * t).round();
    final lx = (lean * (1.0 - t)).round();
    final x1 = bx - w ~/ 2 + lx;
    final x2 = bx + w ~/ 2 + lx;
    for (int x = x1; x <= x2; x++) {
      if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
        image.setPixel(x, y, color);
      }
    }
  }
}

/// Upward-arching arc (∩) drawn with a 5-px stroke for visibility at small sizes.
void _drawArc(img.Image image, int cx, int cy, int rx, int ry, img.Color color) {
  if (rx <= 0 || ry <= 0) return;
  const steps = 1200;
  for (int i = 0; i <= steps; i++) {
    final angle = math.pi + (math.pi * i / steps);
    final x = (cx + rx * math.cos(angle)).round();
    final y = (cy + ry * math.sin(angle)).round();
    for (int dx = -2; dx <= 2; dx++) {
      for (int dy = -2; dy <= 2; dy++) {
        final px = x + dx;
        final py = y + dy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, color);
        }
      }
    }
  }
}
