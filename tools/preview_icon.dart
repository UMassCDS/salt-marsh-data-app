// Run from project root: dart run tools/preview_icon.dart
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final src = img.decodePng(File('assets/icon.png').readAsBytesSync())!;

  // Sizes to preview (with labels)
  final sizes = [48, 72, 96, 144, 192, 512];
  const pad = 24;
  const labelH = 28;
  // Calculate canvas dimensions
  final totalW = sizes.fold(0, (sum, s) => sum + s + pad) + pad;
  final maxH = sizes.last;
  final canvasH = maxH + pad * 2 + labelH;

  final canvas = img.Image(width: totalW, height: canvasH);
  img.fill(canvas, color: img.ColorRgb8(238, 238, 238));

  // Draw each size
  int offsetX = pad;
  for (final size in sizes) {
    final resized = img.copyResize(src, width: size, height: size,
        interpolation: img.Interpolation.average);

    // Centre vertically (align bottoms to same baseline)
    final yOffset = pad + (maxH - size);

    img.compositeImage(canvas, resized, dstX: offsetX, dstY: yOffset);

    // Draw size label below
    img.drawString(
      canvas,
      '${size}px',
      font: img.arial14,
      x: offsetX,
      y: yOffset + size + 4,
      color: img.ColorRgb8(80, 80, 80),
    );

    offsetX += size + pad;
  }

  // Draw a thin divider between each icon
  // (optional - canvas is already clear)

  final bytes = img.encodePng(canvas);
  File('assets/icon_preview.png').writeAsBytesSync(bytes);
  stdout.writeln('✅ Preview saved to assets/icon_preview.png');
}
