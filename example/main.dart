import 'dart:io';
import 'dart:typed_data';

import 'package:patkit/patkit.dart';

/// Prints the patterns and optional hierarchy from one PAT library.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run example/patkit_example.dart <library.pat>');
    exitCode = 64;
    return;
  }
  final Uint8List bytes = await File(arguments.single).readAsBytes();
  final PatFile library = PatDecoder.decode(
    bytes,
    options: const PatDecodeOptions(
      preserveChannelData: false,
      preserveRecordData: false,
      preserveTaggedBlockData: false,
    ),
  );
  for (final PatPattern pattern in library.patterns) {
    final PatPatternImage image = pattern.renderRgba8();
    stdout.writeln('${pattern.name}: ${image.width} × ${image.height} (${pattern.id})');
  }
  library.warnings.forEach(stderr.writeln);
}
