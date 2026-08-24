import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:patkit/patkit.dart';
import 'package:test/test.dart';

/// Exercises PAT files produced by Photoshop in several color modes.
void main() {
  group('Photoshop PAT corpus', () {
    test('decodes and renders the color-mode matrix', () {
      final PatFile file = PatDecoder.decode(_fixture('colormodes.pat'));

      check(file.patterns).length.equals(14);
      check(file.warnings).isEmpty();
      check(file.taggedBlocks).length.equals(1);
      check(file.hierarchyDescriptors).length.equals(1);
      check(file.hierarchy).isEmpty();
      check(file.patterns.map((pattern) => pattern.colorMode).toSet()).deepEquals(<PatColorMode>{
        PatColorMode.grayscale,
        PatColorMode.rgb,
        PatColorMode.cmyk,
        PatColorMode.multichannel,
        PatColorMode.lab,
      });
      for (final PatPattern pattern in file.patterns) {
        final PatPatternImage image = pattern.renderRgba8();
        check(image.width).equals(4);
        check(image.height).equals(4);
        check(image.rgba).length.equals(64);
      }
    });

    test('decodes PackBits rows from a 100 by 100 RGB tile', () {
      final PatFile file = PatDecoder.decode(_fixture('hue.pat'));
      final PatPattern pattern = file.patterns.single;
      final PatPatternImage image = pattern.renderRgba8();

      check(pattern.name).equals('hue');
      check(pattern.colorMode).equals(PatColorMode.rgb);
      check(pattern.channels).length.equals(4);
      check(pattern.channels.every((channel) => channel.compression == PatCompression.packBits)).isTrue();
      check(image.width).equals(100);
      check(image.height).equals(100);
      check(image.rgba).length.equals(40000);
      check(file.warnings).isEmpty();
    });

    test('preserves and previews a five-ink multichannel source', () {
      final PatFile file = PatDecoder.decode(_fixture('multichannel-5.pat'));
      final PatPattern pattern = file.patterns.single;
      final PatPatternImage image = pattern.renderRgba8();

      check(pattern.name).equals('multichannel-5');
      check(pattern.colorMode).equals(PatColorMode.multichannel);
      check(pattern.declaredChannelCount).equals(24);
      check(pattern.channels).length.equals(1);
      check(image.width).equals(4);
      check(image.height).equals(4);
      check(file.warnings).isEmpty();
    });
  });
}

/// Decodes one base64-wrapped binary fixture from the test corpus.
Uint8List _fixture(String name) {
  final String encoded = File('test/fixtures/$name.b64').readAsStringSync();
  return base64Decode(encoded.replaceAll(RegExp(r'\s'), ''));
}
