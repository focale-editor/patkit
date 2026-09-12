import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:patkit/patkit.dart';
import 'package:test/test.dart';

import 'support/pat_fixture_builder.dart';

/// Exercises PAT pattern reconstruction and compatibility preservation.
void main() {
  group('PatEncoder', () {
    test('rebuilds decoded channels without preserved source bytes', () {
      final Uint8List bytes = PatFixtureBuilder.file(
        patterns: <Uint8List>[_pattern()],
      );
      final PatFile file = PatDecoder.decode(
        bytes,
        options: const PatDecodeOptions(
          preserveChannelData: false,
          preserveRecordData: false,
        ),
      );

      final Uint8List encoded = PatEncoder.encode(file);

      check(encoded).deepEquals(bytes);
      check(PatDecoder.decode(encoded).patterns.single.renderRgba8().rgba).deepEquals(<int>[32, 32, 32, 255, 224, 224, 224, 255]);
    });

    test('regenerates hierarchy blocks whose payload was not preserved', () {
      final Uint8List bytes = PatFixtureBuilder.file(
        patterns: <Uint8List>[_pattern()],
        blocks: <PatTestTaggedBlock>[PatFixtureBuilder.hierarchyBlock()],
      );
      final PatFile file = PatDecoder.decode(
        bytes,
        options: const PatDecodeOptions(preserveTaggedBlockData: false),
      );

      final PatFile decoded = PatDecoder.decode(PatEncoder.encode(file));

      check(decoded.hierarchy).length.equals(4);
      check(decoded.patternFor(decoded.hierarchy[1])?.id).equals('pattern-id');
    });

    test('keeps alternate blocks and trailing bytes in permissive mode', () {
      final Uint8List complete = PatFixtureBuilder.file(
        patterns: <Uint8List>[_pattern()],
        blocks: <PatTestTaggedBlock>[
          PatTestTaggedBlock(
            signature: '8B64',
            key: 'futr',
            data: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ],
      );
      final Uint8List bytes = Uint8List.fromList(<int>[...complete, 7, 8]);
      final PatFile file = PatDecoder.decode(bytes);

      check(() => PatEncoder.encode(file)).throws<PatWriteException>();
      check(
        PatEncoder.encode(
          file,
          options: const PatEncodeOptions(mode: PatEncodeMode.permissive),
        ),
      ).deepEquals(bytes);
    });
  });
}

/// Builds a compact PackBits grayscale pattern.
Uint8List _pattern() => PatFixtureBuilder.pattern(
  name: 'Pattern',
  id: 'pattern-id',
  mode: PsPatternColorMode.grayscale,
  width: 2,
  height: 1,
  channels: const <PatTestChannel>[
    PatTestChannel(depth: 8, bytes: <int>[32, 224], packBits: true),
  ],
);
