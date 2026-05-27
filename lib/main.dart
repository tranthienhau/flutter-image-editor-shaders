import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const ProviderScope(child: EditorApp()));
}

class FilterParams {
  final double exposure;
  final double contrast;
  final double saturation;
  final double temperature;
  final double tint;
  final double shadows;
  final double highlights;
  final double grain;
  final double vignette;
  final double lutMix;

  const FilterParams({
    this.exposure = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.temperature = 0,
    this.tint = 0,
    this.shadows = 0,
    this.highlights = 0,
    this.grain = 0,
    this.vignette = 0,
    this.lutMix = 0,
  });

  FilterParams copyWith({
    double? exposure,
    double? contrast,
    double? saturation,
    double? temperature,
    double? tint,
    double? shadows,
    double? highlights,
    double? grain,
    double? vignette,
    double? lutMix,
  }) {
    return FilterParams(
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      shadows: shadows ?? this.shadows,
      highlights: highlights ?? this.highlights,
      grain: grain ?? this.grain,
      vignette: vignette ?? this.vignette,
      lutMix: lutMix ?? this.lutMix,
    );
  }
}

enum Preset { none, vsco, kodak, noir, fade }

class EditorState {
  final ui.Image? image;
  final ui.Image? lut;
  final FilterParams params;
  final Preset preset;
  const EditorState({this.image, this.lut, this.params = const FilterParams(), this.preset = Preset.none});

  EditorState copyWith({ui.Image? image, ui.Image? lut, FilterParams? params, Preset? preset}) {
    return EditorState(
      image: image ?? this.image,
      lut: lut ?? this.lut,
      params: params ?? this.params,
      preset: preset ?? this.preset,
    );
  }
}

class EditorController extends StateNotifier<EditorState> {
  EditorController() : super(const EditorState()) {
    _buildIdentityLut();
  }

  final _picker = ImagePicker();

  Future<void> _buildIdentityLut() async {
    const size = 512;
    final pixels = Uint8List(size * size * 4);
    for (int b = 0; b < 64; b++) {
      final qx = b % 8;
      final qy = b ~/ 8;
      for (int g = 0; g < 64; g++) {
        for (int r = 0; r < 64; r++) {
          final x = qx * 64 + r;
          final y = qy * 64 + g;
          final i = (y * size + x) * 4;
          pixels[i] = (r * 255 ~/ 63);
          pixels[i + 1] = (g * 255 ~/ 63);
          pixels[i + 2] = (b * 255 ~/ 63);
          pixels[i + 3] = 255;
        }
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, size, size, ui.PixelFormat.rgba8888, completer.complete);
    final lut = await completer.future;
    state = state.copyWith(lut: lut);
  }

  Future<void> pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 2400);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final img = await decodeImageFromList(bytes);
    state = state.copyWith(image: img);
  }

  void updateParams(FilterParams p) => state = state.copyWith(params: p);

  void applyPreset(Preset p) {
    final params = switch (p) {
      Preset.vsco => const FilterParams(exposure: 0.1, contrast: 0.1, saturation: -0.1, temperature: 0.05, shadows: 0.05, highlights: -0.1, lutMix: 0.7),
      Preset.kodak => const FilterParams(exposure: 0.05, contrast: 0.2, saturation: 0.15, temperature: 0.15, highlights: -0.05, grain: 0.05),
      Preset.noir => const FilterParams(exposure: 0, contrast: 0.35, saturation: -1.0, shadows: -0.1, highlights: 0.1, vignette: 0.4, grain: 0.08),
      Preset.fade => const FilterParams(exposure: 0.05, contrast: -0.15, saturation: -0.2, shadows: 0.15, highlights: -0.1, lutMix: 0.5),
      Preset.none => const FilterParams(),
    };
    state = state.copyWith(params: params, preset: p);
  }
}

final editorProvider = StateNotifierProvider<EditorController, EditorState>((ref) => EditorController());
final shaderProvider = FutureProvider<ui.FragmentShader>((ref) async {
  final program = await ui.FragmentProgram.fromAsset('shaders/filter.frag');
  return program.fragmentShader();
});

class EditorApp extends StatelessWidget {
  const EditorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shader Photo Editor',
      theme: ThemeData.dark(useMaterial3: true),
      home: const EditorScreen(),
    );
  }
}

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final shaderAsync = ref.watch(shaderProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shader Photo Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate),
            onPressed: () => ref.read(editorProvider.notifier).pickImage(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: shaderAsync.when(
                data: (shader) {
                  if (state.image == null) {
                    return const Text('Pick an image to start');
                  }
                  return AspectRatio(
                    aspectRatio: state.image!.width / state.image!.height,
                    child: CustomPaint(
                      painter: _FilterPainter(
                        image: state.image!,
                        lut: state.lut,
                        shader: shader,
                        params: state.params,
                      ),
                    ),
                  );
                },
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Shader error: $e'),
              ),
            ),
          ),
          const _PresetBar(),
          const Divider(height: 1),
          const SizedBox(height: 280, child: _Sliders()),
        ],
      ),
    );
  }
}

class _PresetBar extends ConsumerWidget {
  const _PresetBar();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(editorProvider).preset;
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: Preset.values.map((p) {
          final selected = p == current;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(p.name.toUpperCase()),
              selected: selected,
              onSelected: (_) => ref.read(editorProvider.notifier).applyPreset(p),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Sliders extends ConsumerWidget {
  const _Sliders();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(editorProvider).params;
    final ctrl = ref.read(editorProvider.notifier);

    Widget row(String label, double value, double min, double max, void Function(double) on) {
      return Row(
        children: [
          SizedBox(width: 92, child: Text(label)),
          Expanded(child: Slider(value: value, min: min, max: max, onChanged: on)),
          SizedBox(width: 48, child: Text(value.toStringAsFixed(2), textAlign: TextAlign.end)),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        row('Exposure', p.exposure, -2, 2, (v) => ctrl.updateParams(p.copyWith(exposure: v))),
        row('Contrast', p.contrast, -1, 1, (v) => ctrl.updateParams(p.copyWith(contrast: v))),
        row('Saturation', p.saturation, -1, 1, (v) => ctrl.updateParams(p.copyWith(saturation: v))),
        row('Temperature', p.temperature, -1, 1, (v) => ctrl.updateParams(p.copyWith(temperature: v))),
        row('Tint', p.tint, -1, 1, (v) => ctrl.updateParams(p.copyWith(tint: v))),
        row('Shadows', p.shadows, -0.5, 0.5, (v) => ctrl.updateParams(p.copyWith(shadows: v))),
        row('Highlights', p.highlights, -0.5, 0.5, (v) => ctrl.updateParams(p.copyWith(highlights: v))),
        row('Grain', p.grain, 0, 0.3, (v) => ctrl.updateParams(p.copyWith(grain: v))),
        row('Vignette', p.vignette, 0, 1, (v) => ctrl.updateParams(p.copyWith(vignette: v))),
        row('LUT Mix', p.lutMix, 0, 1, (v) => ctrl.updateParams(p.copyWith(lutMix: v))),
      ],
    );
  }
}

class _FilterPainter extends CustomPainter {
  final ui.Image image;
  final ui.Image? lut;
  final ui.FragmentShader shader;
  final FilterParams params;

  _FilterPainter({required this.image, required this.lut, required this.shader, required this.params});

  @override
  void paint(Canvas canvas, Size size) {
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, params.exposure);
    shader.setFloat(3, params.contrast);
    shader.setFloat(4, params.saturation);
    shader.setFloat(5, params.temperature);
    shader.setFloat(6, params.tint);
    shader.setFloat(7, params.shadows);
    shader.setFloat(8, params.highlights);
    shader.setFloat(9, params.grain);
    shader.setFloat(10, params.vignette);
    shader.setFloat(11, params.lutMix);
    shader.setFloat(12, DateTime.now().millisecondsSinceEpoch.toDouble() % 1000);
    shader.setImageSampler(0, image);
    if (lut != null) shader.setImageSampler(1, lut!);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _FilterPainter old) =>
      old.image != image || old.lut != lut || old.params != params;
}
