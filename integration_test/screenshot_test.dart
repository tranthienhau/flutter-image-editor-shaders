import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_image_editor_shaders/main.dart';

/// Builds a colorful synthetic photo (smooth horizontal + vertical gradient
/// with a bright sweep) so the shader pipeline has real pixels to process.
Future<ui.Image> buildSampleImage() async {
  const w = 720;
  const h = 900;
  final pixels = Uint8List(w * h * 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final fx = x / w;
      final fy = y / h;
      final r = (180 + 70 * (fx)) .clamp(0, 255).toInt();
      final g = (90 + 150 * (1 - fy)).clamp(0, 255).toInt();
      final b = (120 + 120 * (fx * fy)).clamp(0, 255).toInt();
      final i = (y * w + x) * 4;
      pixels[i] = r;
      pixels[i + 1] = g;
      pixels[i + 2] = b;
      pixels[i + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shoot(WidgetTester tester, String name) async {
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot(name);
  }

  testWidgets('capture shader photo editor flow', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
    // Let the shader load + identity LUT build.
    await tester.pumpAndSettle();

    // Seed a real image so the editor renders actual pixels.
    final img = await buildSampleImage();
    container.read(editorProvider.notifier).setImage(img);
    await tester.pumpAndSettle();
    await shoot(tester, '01-editor-loaded');

    // Apply the Kodak preset (warm, punchy).
    container.read(editorProvider.notifier).applyPreset(Preset.kodak);
    await tester.pumpAndSettle();
    await shoot(tester, '02-kodak-preset');

    // Apply the Noir preset (desaturated, high-contrast, vignette + grain).
    container.read(editorProvider.notifier).applyPreset(Preset.noir);
    await tester.pumpAndSettle();
    await shoot(tester, '03-noir-preset');

    // Manual edit: push exposure + saturation + temperature.
    container.read(editorProvider.notifier).applyPreset(Preset.none);
    container.read(editorProvider.notifier).updateParams(
          const FilterParams(
            exposure: 0.4,
            contrast: 0.25,
            saturation: 0.5,
            temperature: 0.3,
            vignette: 0.3,
          ),
        );
    await tester.pumpAndSettle();
    await shoot(tester, '04-manual-edit');
  });
}
