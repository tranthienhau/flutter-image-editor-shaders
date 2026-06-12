# Screenshot capture flow

Real captures from the iOS Simulator via an integration-test driver (no mockups).

## Steps

1. Boot the simulator:
   ```bash
   xcrun simctl boot "iPhone 16e"
   open -a Simulator
   ```
2. Scaffold the iOS platform folder (if missing) and get dependencies:
   ```bash
   flutter create . --platforms=ios --project-name flutter_image_editor_shaders
   flutter pub get
   ```
3. Drive the screenshot test:
   ```bash
   flutter drive \
     --driver test_driver/integration_test.dart \
     --target integration_test/screenshot_test.dart \
     -d "889A2E50-D60F-4785-84BD-5700F9048279"
   ```
4. Build the demo GIF from the PNGs:
   ```bash
   cd screenshots
   ffmpeg -y -framerate 1 -pattern_type glob -i '*.png' \
     -vf "scale=320:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
     -loop 0 demo.gif
   ```

PNGs + `demo.gif` are written to `screenshots/` and embedded in `README.md`.

## How it works

- `test_driver/integration_test.dart` - `integrationDriver(onScreenshot:)` writes each PNG to `screenshots/<name>.png`.
- `integration_test/screenshot_test.dart`:
  - Pumps `EditorScreen` inside an `UncontrolledProviderScope`, letting the GLSL `FragmentProgram` load and the runtime identity LUT build.
  - Generates a synthetic 720x900 gradient photo with `ui.decodeImageFromPixels` and seeds it into the editor state via `editorProvider.notifier.setImage(...)`, so the shader pipeline processes real pixels instead of a blank "pick an image" state.
  - Captures four key views: `01-editor-loaded` (raw image), `02-kodak-preset`, `03-noir-preset` (applied through `applyPreset`), and `04-manual-edit` (exposure / contrast / saturation / temperature / vignette pushed via `updateParams`).
  - Each shot calls `binding.convertFlutterSurfaceToImage()` + `pumpAndSettle()` + `binding.takeScreenshot('NN-name')`.
