import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:patkit/patkit.dart';
import 'package:test/test.dart';

import 'support/pat_fixture_builder.dart';

/// Exercises the reusable `dart:convert` PAT interface.
void main() {
  group('PatCodec', () {
    test('converts complete files and composes with base64', () {
      const PatCodec codec = PatCodec(
        decodeOptions: PatDecodeOptions(mode: PatDecodeMode.strict),
        encodeOptions: PatEncodeOptions(mode: PatEncodeMode.strict),
      );
      final Uint8List bytes = PatFixtureBuilder.file(patterns: <Uint8List>[]);

      final PatFile file = codec.decode(bytes.toList(growable: false));
      final Uint8List encoded = codec.encode(file);
      final Codec<PatFile, String> base64Codec = codec.fuse(base64);
      final PatFile decodedBase64 = base64Codec.decode(base64Codec.encode(file));

      check(encoded).deepEquals(bytes);
      check(decodedBase64.patterns).isEmpty();
      check(codec.decoder.options.mode).equals(PatDecodeMode.strict);
      check(codec.encoder.options.mode).equals(PatEncodeMode.strict);
    });
  });
}
