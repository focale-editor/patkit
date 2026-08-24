import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:patkit/patkit.dart';
import 'package:test/test.dart';

import 'support/pat_fixture_builder.dart';

/// Exercises PAT container decoding, preservation, and hierarchy mapping.
void main() {
  group('PatDecoder', () {
    test('decodes, resolves, and renders RGB and indexed patterns', () {
      final Uint8List palette = Uint8List(256 * 3)..setRange(0, 6, <int>[255, 0, 0, 0, 0, 255]);
      final Uint8List bytes = PatFixtureBuilder.file(
        patterns: <Uint8List>[
          PatFixtureBuilder.pattern(
            name: 'RGB tile',
            id: 'rgb-id',
            mode: PsPatternColorMode.rgb,
            width: 2,
            height: 1,
            channels: const <PatTestChannel>[
              PatTestChannel(depth: 8, bytes: <int>[255, 0], packBits: true),
              PatTestChannel(depth: 8, bytes: <int>[0, 255], packBits: true),
              PatTestChannel(depth: 8, bytes: <int>[0, 0], packBits: true),
            ],
            alpha: const PatTestChannel(depth: 8, bytes: <int>[255, 64], packBits: true),
          ),
          PatFixtureBuilder.pattern(
            name: 'Indexed tile',
            id: 'indexed-id',
            mode: PsPatternColorMode.indexed,
            width: 2,
            height: 1,
            channels: const <PatTestChannel>[
              PatTestChannel(depth: 8, bytes: <int>[0, 1]),
            ],
            palette: palette,
            colorsUsed: 2,
            transparentIndex: 1,
          ),
        ],
      );

      final PatFile file = PatDecoder.decode(bytes);
      final PatPattern rgb = file.patterns.first;
      final PatPattern indexed = file.patterns.last;

      check(file.version).equals(1);
      check(file.declaredPatternCount).equals(2);
      check(file.isComplete).isTrue();
      check(file.warnings).isEmpty();
      check(file.patternById('rgb-id')).identicalTo(rgb);
      check(rgb.recordData).isNotNull();
      check(rgb.renderRgba8().rgba).deepEquals(<int>[255, 0, 0, 255, 0, 255, 0, 64]);
      check(indexed.indexedMetadata?.colorsUsed).equals(2);
      check(indexed.renderRgba8().rgba).deepEquals(<int>[255, 0, 0, 255, 0, 0, 255, 0]);
    });

    test('maps an unpadded phry hierarchy to source patterns', () {
      final Uint8List bytes = PatFixtureBuilder.file(
        patterns: <Uint8List>[
          _grayPattern(name: 'First', id: 'first-id'),
          _grayPattern(name: 'Second', id: 'second-id'),
        ],
        blocks: <PatTestTaggedBlock>[
          PatFixtureBuilder.hierarchyBlock(),
        ],
      );

      final PatFile file = PatDecoder.decode(bytes);

      check(file.taggedBlocks).length.equals(1);
      check(file.hierarchyDescriptors).length.equals(1);
      check(file.hierarchy).length.equals(4);
      check(file.hierarchy[0].kind).equals(PatHierarchyEntryKind.groupStart);
      check(file.hierarchy[0].name).equals('Favorites');
      check(file.hierarchy[0].id).equals('group-id');
      check(file.hierarchy[1].kind).equals(PatHierarchyEntryKind.preset);
      check(file.hierarchy[1].depth).equals(1);
      check(file.patternFor(file.hierarchy[1])?.name).equals('First');
      check(file.patternFor(file.hierarchy[2])?.name).equals('Second');
      check(file.hierarchy[3].kind).equals(PatHierarchyEntryKind.groupEnd);
      check(file.hierarchy[3].depth).equals(0);
      check(file.warnings).isEmpty();
    });

    test('detects optional padding between tagged blocks without requiring final padding', () {
      final Uint8List bytes = PatFixtureBuilder.file(
        patterns: <Uint8List>[_grayPattern(name: 'Tile', id: 'tile-id')],
        blocks: <PatTestTaggedBlock>[
          PatFixtureBuilder.unknownBlock(padding: 1),
          PatFixtureBuilder.hierarchyBlock(),
        ],
      );

      final PatFile file = PatDecoder.decode(bytes);

      check(file.taggedBlocks).length.equals(2);
      check(file.taggedBlocks.first.paddingData).deepEquals(<int>[0]);
      check(file.taggedBlocks.last.paddingData).isEmpty();
      check(file.hierarchy).length.equals(4);
      check(file.warnings).isNotEmpty();
    });

    test('accepts optional alignment after the final tagged block', () {
      final Uint8List bytes = PatFixtureBuilder.file(
        patterns: <Uint8List>[_grayPattern(name: 'Tile', id: 'tile-id')],
        blocks: <PatTestTaggedBlock>[
          PatFixtureBuilder.unknownBlock(padding: 1),
        ],
      );

      final PatFile file = PatDecoder.decode(bytes);

      check(file.taggedBlocks.single.paddingData).deepEquals(<int>[0]);
      check(file.trailingData).isEmpty();
      check(file.warnings).length.equals(1);
    });

    test('preserves unknown data in tolerant mode and rejects it in strict mode', () {
      final Uint8List bytes = PatFixtureBuilder.file(
        patterns: <Uint8List>[_grayPattern(name: 'Tile', id: 'tile-id')],
        blocks: <PatTestTaggedBlock>[
          PatFixtureBuilder.unknownBlock(),
        ],
      );

      final PatFile tolerant = PatDecoder.decode(bytes);

      check(tolerant.taggedBlocks.single.data).deepEquals(<int>[1, 2, 3]);
      check(tolerant.warnings).isNotEmpty();
      check(() => PatDecoder.decode(bytes, options: const PatDecodeOptions(mode: PatDecodeMode.strict))).throws<PatFormatException>();
    });

    test('preserves an alternate 8B64 block with its wide length', () {
      final Uint8List bytes = PatFixtureBuilder.file(
        patterns: <Uint8List>[_grayPattern(name: 'Tile', id: 'tile-id')],
        blocks: <PatTestTaggedBlock>[
          PatTestTaggedBlock(
            signature: '8B64',
            key: 'futr',
            data: Uint8List.fromList(<int>[4, 5, 6]),
          ),
        ],
      );

      final PatFile file = PatDecoder.decode(bytes);

      check(file.taggedBlocks.single.signature).equals('8B64');
      check(file.taggedBlocks.single.declaredLength).equals(3);
      check(file.taggedBlocks.single.data).deepEquals(<int>[4, 5, 6]);
      check(file.warnings).length.equals(2);
    });

    test('can omit decoded and preserved bulk data', () {
      final Uint8List bytes = PatFixtureBuilder.file(
        patterns: <Uint8List>[_grayPattern(name: 'Tile', id: 'tile-id')],
        blocks: <PatTestTaggedBlock>[
          PatFixtureBuilder.unknownBlock(),
        ],
      );

      final PatFile file = PatDecoder.decode(
        bytes,
        options: const PatDecodeOptions(
          decodeChannelData: false,
          preserveChannelData: false,
          preserveRecordData: false,
          preserveTaggedBlockData: false,
        ),
      );

      check(file.patterns.single.channelForSlot(0)?.decodedData).isNull();
      check(file.patterns.single.channelForSlot(0)?.encodedData).isNotNull().isEmpty();
      check(file.patterns.single.slots.first.data).isEmpty();
      check(file.patterns.single.recordData).isNull();
      check(file.taggedBlocks.single.data).isEmpty();
      check(file.decodedPixelBytes).equals(0);
    });

    test('reports typed failures for invalid headers and resource limits', () {
      final Uint8List pattern = _grayPattern(name: 'Tile', id: 'tile-id');
      final Uint8List wrongSignature = PatFixtureBuilder.file(patterns: <Uint8List>[pattern], signature: 'NOPE');
      final Uint8List wrongVersion = PatFixtureBuilder.file(patterns: <Uint8List>[pattern], version: 2);
      final Uint8List tooMany = PatFixtureBuilder.file(patterns: <Uint8List>[pattern], declaredPatternCount: 2);
      final Uint8List valid = PatFixtureBuilder.file(patterns: <Uint8List>[pattern]);
      final Uint8List tagged = PatFixtureBuilder.file(
        patterns: <Uint8List>[pattern],
        blocks: <PatTestTaggedBlock>[PatFixtureBuilder.unknownBlock()],
      );

      check(() => PatDecoder.decode(wrongSignature)).throws<PatFormatException>();
      check(() => PatDecoder.decode(wrongVersion)).throws<PatFormatException>();
      check(() => PatDecoder.decode(tooMany, options: const PatDecodeOptions(maxPatterns: 1))).throws<PatFormatException>();
      check(() => PatDecoder.decode(valid, options: PatDecodeOptions(maxFileBytes: valid.length - 1))).throws<PatFormatException>();
      check(() => PatDecoder.decode(valid, options: const PatDecodeOptions(maxPatternNameCodeUnits: 2))).throws<PatFormatException>();
      check(() => PatDecoder.decode(valid, options: const PatDecodeOptions(maxPatternBytes: 1))).throws<PatFormatException>();
      check(() => PatDecoder.decode(valid, options: const PatDecodeOptions(maxDecodedPixelBytes: 1))).throws<PatFormatException>();
      check(() => PatDecoder.decode(tagged, options: const PatDecodeOptions(maxTaggedBlockBytes: 2))).throws<PatFormatException>();
    });

    test('reports duplicate identifiers and resolves the last occurrence', () {
      final Uint8List bytes = PatFixtureBuilder.file(
        patterns: <Uint8List>[
          _grayPattern(name: 'First', id: 'duplicate-id'),
          _grayPattern(name: 'Second', id: 'duplicate-id'),
        ],
      );

      final PatFile file = PatDecoder.decode(bytes);

      check(file.warnings).length.equals(1);
      check(file.patternById('duplicate-id')).identicalTo(file.patterns.last);
      check(() => PatDecoder.decode(bytes, options: const PatDecodeOptions(mode: PatDecodeMode.strict))).throws<PatFormatException>();
    });

    test('preserves unrecognized bytes after the last pattern', () {
      final Uint8List complete = PatFixtureBuilder.file(
        patterns: <Uint8List>[_grayPattern(name: 'Tile', id: 'tile-id')],
      );
      final Uint8List bytes = Uint8List.fromList(<int>[...complete, 7, 8, 9]);

      final PatFile file = PatDecoder.decode(bytes);

      check(file.trailingData).deepEquals(<int>[7, 8, 9]);
      check(file.warnings).length.equals(1);
      check(() => PatDecoder.decode(bytes, options: const PatDecodeOptions(mode: PatDecodeMode.strict))).throws<PatFormatException>();
    });
  });
}

/// Builds one two-pixel grayscale pattern.
Uint8List _grayPattern({
  required String name,
  required String id,
}) => PatFixtureBuilder.pattern(
  name: name,
  id: id,
  mode: PsPatternColorMode.grayscale,
  width: 2,
  height: 1,
  channels: const <PatTestChannel>[
    PatTestChannel(depth: 8, bytes: <int>[32, 224]),
  ],
);
