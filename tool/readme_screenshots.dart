// Export real app UI from the reviewed Linux golden snapshots for the README.
// Refresh test/goldens first, then run: tool/flutter pub run tool/readme_screenshots.dart
import 'dart:io';
import 'package:image/image.dart' as image;

void main() {
  const source = 'test/goldens/goldens/linux';
  const output = 'docs/screenshots';
  Directory(output).createSync(recursive: true);
  const captures = <({String file, String golden, int x, int height})>[
    (file: 'dashboard-light', golden: 'device_tiles_phone', x: 0, height: 915),
    (file: 'dashboard-dark', golden: 'device_tiles_phone', x: 412, height: 915),
    (file: 'device-controls', golden: 'device_page_phone', x: 0, height: 915),
    (file: 'devices', golden: 'devices_tab_phone', x: 0, height: 915),
    (
      file: 'wirenboard-panel',
      golden: 'wirenboard_device_card',
      x: 0,
      height: 220,
    ),
  ];
  for (final shot in captures) {
    final file = File('$source/${shot.golden}.png');
    if (!file.existsSync()) {
      throw StateError(
        'Missing ${file.path}. Refresh the Linux goldens first.',
      );
    }
    final original = image.decodePng(file.readAsBytesSync())!;
    // GoldenTestScenario adds a 31px case label above the actual UI.
    // Select the English 1x light/dark case and a phone viewport, without
    // the matrix labels or other test variants. No app pixels are recoloured.
    final cropped = image.copyCrop(
      original,
      x: shot.x,
      y: 31,
      width: 412,
      height: shot.height,
    );
    final destination = File('$output/${shot.file}.png');
    destination.writeAsBytesSync(image.encodePng(cropped));
    stdout.writeln(destination.path);
  }
}
