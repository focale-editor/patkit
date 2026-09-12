import 'dart:convert';
import 'dart:typed_data';

import 'package:patkit/src/codec/pat_decoder.dart';
import 'package:patkit/src/codec/pat_encoder.dart';
import 'package:patkit/src/model/pat_file.dart';
import 'package:patkit/src/model/pat_options.dart';

/// Converts PAT models to and from their binary representation.
///
/// Each conversion handles one complete in-memory file. The encoded type is
/// [List<int>] so this codec can be composed with standard `dart:convert`
/// codecs, while [encode] keeps the more precise [Uint8List] return type.
final class PatCodec extends Codec<PatFile, List<int>> {
  /// Options applied while decoding.
  final PatDecodeOptions decodeOptions;

  /// Options applied while encoding.
  final PatEncodeOptions encodeOptions;

  /// Creates a reusable codec with fixed decoding and encoding options.
  const PatCodec({
    this.decodeOptions = const PatDecodeOptions(),
    this.encodeOptions = const PatEncodeOptions(),
  });

  @override
  PatDecoder get decoder => PatDecoder(options: decodeOptions);

  @override
  PatEncoder get encoder => PatEncoder(options: encodeOptions);

  @override
  Uint8List encode(PatFile input) => encoder.convert(input);
}
