import 'dart:typed_data';

import 'package:patkit/src/model/pat_file.dart';
import 'package:patkit/src/model/pat_options.dart';
import 'package:patkit/src/model/pat_pattern.dart';
import 'package:pscore/pscore.dart';

/// Encodes immutable PAT models into standalone Photoshop pattern libraries.
abstract final class PatEncoder {
  /// Canonical standalone PAT signature.
  static const String _fileSignature = '8BPT';

  /// Canonical standalone PAT version.
  static const int _fileVersion = 1;

  /// Canonical hierarchy Action Descriptor version.
  static const int _descriptorVersion = 16;

  /// Encodes [file] into a new big-endian PAT byte buffer.
  static Uint8List encode(
    PatFile file, {
    PatEncodeOptions options = const PatEncodeOptions(),
  }) {
    try {
      _validateRepresentable(file, options);
      if (options.mode == PatEncodeMode.strict) {
        _validateStrict(file, options);
      }
      final PsPatternEncodeOptions patternOptions = PsPatternEncodeOptions(
        mode: options.mode == PatEncodeMode.strict ? PsPatternEncodeMode.strict : PsPatternEncodeMode.permissive,
        includeVirtualMemoryTrailingData: options.includeVirtualMemoryTrailingData,
        includeRecordTrailingData: false,
      );
      final PsBinaryWriter writer = PsBinaryWriter()
        ..writeString(_fileSignature)
        ..writeUint16(file.version)
        ..writeUint32(options.mode == PatEncodeMode.strict ? file.patterns.length : file.declaredPatternCount);
      for (final PatPattern pattern in file.patterns) {
        writer.writeBytes(
          PsPatternRecordEncoder.encode(
            pattern: pattern,
            kind: PsPatternRecordKind.standalone,
            options: patternOptions,
          ),
        );
      }
      if (options.includeTaggedBlocks) {
        _writeTaggedBlocks(writer, file, options);
      }
      if (options.includeTrailingData) {
        writer.writeBytes(file.trailingData);
      }
      return writer.takeBytes();
    } on PatWriteException {
      rethrow;
    } on PsWriteException catch (error) {
      throw PatWriteException(message: error.message);
    } on RangeError catch (error) {
      throw PatWriteException(message: 'A PAT numeric value cannot be encoded: $error');
    }
  }

  /// Writes preserved tagged blocks and reconstructs unpreserved hierarchy blocks.
  static void _writeTaggedBlocks(
    PsBinaryWriter writer,
    PatFile file,
    PatEncodeOptions options,
  ) {
    int hierarchyIndex = 0;
    for (final PatTaggedBlock block in file.taggedBlocks) {
      final PsDescriptor? hierarchyDescriptor = block.key == 'phry' && hierarchyIndex < file.hierarchyDescriptors.length ? file.hierarchyDescriptors[hierarchyIndex++] : null;
      final Uint8List data = _taggedBlockData(
        block: block,
        hierarchyDescriptor: hierarchyDescriptor,
        options: options,
      );
      _writeTaggedBlock(writer, block.signature, block.key, data, block.paddingData, options);
    }
    while (hierarchyIndex < file.hierarchyDescriptors.length) {
      final Uint8List data = _encodeHierarchy(file.hierarchyDescriptors[hierarchyIndex++]);
      _writeTaggedBlock(writer, '8BIM', 'phry', data, Uint8List(0), options);
    }
  }

  /// Selects exact source bytes or a regenerated hierarchy descriptor.
  static Uint8List _taggedBlockData({
    required PatTaggedBlock block,
    required PsDescriptor? hierarchyDescriptor,
    required PatEncodeOptions options,
  }) {
    if (options.mode == PatEncodeMode.permissive && block.data.length == block.declaredLength) {
      return block.data;
    }
    if (hierarchyDescriptor != null) {
      return _encodeHierarchy(hierarchyDescriptor);
    }
    if (block.data.length != block.declaredLength) {
      throw PatWriteException(
        message: 'Tagged block ${block.key} has only ${block.data.length} of ${block.declaredLength} payload bytes',
      );
    }
    return block.data;
  }

  /// Encodes one version 16 hierarchy descriptor payload.
  static Uint8List _encodeHierarchy(PsDescriptor descriptor) =>
      (PsBinaryWriter()
            ..writeUint32(_descriptorVersion)
            ..writeBytes(PsDescriptorCodec.encode(descriptor)))
          .takeBytes();

  /// Writes one ordinary or wide tagged block.
  static void _writeTaggedBlock(
    PsBinaryWriter writer,
    String signature,
    String key,
    Uint8List data,
    Uint8List preservedPadding,
    PatEncodeOptions options,
  ) {
    writer
      ..writeString(signature)
      ..writeString(key)
      ..writeLength(data.length, wide: signature == '8B64')
      ..writeBytes(data);
    if (options.mode == PatEncodeMode.permissive) {
      writer.writeBytes(preservedPadding);
    } else {
      writer.writeZeros((4 - data.length % 4) % 4);
    }
  }

  /// Checks that the PAT envelope and preserved tagged blocks are representable.
  static void _validateRepresentable(PatFile file, PatEncodeOptions options) {
    _requireUnsigned(file.version, 16, 'PAT version');
    _requireUnsigned(file.declaredPatternCount, 32, 'PAT declared pattern count');
    if (file.patterns.length > 0xffffffff) {
      throw const PatWriteException(message: 'PAT pattern count exceeds the 32-bit container capacity');
    }
    if (options.includeTaggedBlocks) {
      for (final PatTaggedBlock block in file.taggedBlocks) {
        _requireLatin1(block.signature, 4, 'Tagged-block signature');
        _requireLatin1(block.key, 4, 'Tagged-block key');
        _requireUnsigned(block.declaredLength, block.signature == '8B64' ? 64 : 32, 'Tagged-block ${block.key} declared length');
      }
    }
  }

  /// Applies canonical standalone PAT constraints.
  static void _validateStrict(PatFile file, PatEncodeOptions options) {
    if (file.version != _fileVersion) {
      throw const PatWriteException(message: 'Strict PAT output requires version $_fileVersion');
    }
    if (file.declaredPatternCount != file.patterns.length) {
      throw const PatWriteException(message: 'Strict PAT output requires the declared pattern count to match the pattern list');
    }
    final Set<String> identifiers = <String>{};
    for (final PatPattern pattern in file.patterns) {
      if (!identifiers.add(pattern.id)) {
        throw PatWriteException(message: 'Strict PAT output cannot contain duplicate identifier "${pattern.id}"');
      }
    }
    if (options.includeTaggedBlocks) {
      for (final PatTaggedBlock block in file.taggedBlocks) {
        if (block.signature != '8BIM') {
          throw PatWriteException(message: 'Strict PAT output cannot contain tagged-block signature "${block.signature}"');
        }
        if (block.key != 'phry' && block.data.length != block.declaredLength) {
          throw PatWriteException(message: 'Tagged block ${block.key} has no complete preserved payload');
        }
      }
    }
    if (options.includeTrailingData && file.trailingData.isNotEmpty) {
      throw const PatWriteException(message: 'Strict PAT output cannot contain unrecognized trailing bytes');
    }
  }

  /// Requires [value] to fit an unsigned integer field.
  static void _requireUnsigned(int value, int bits, String label) {
    final bool exceedsMaximum = bits < 64 && value > (1 << bits) - 1;
    if (value < 0 || exceedsMaximum) {
      throw PatWriteException(message: '$label value $value does not fit an unsigned $bits-bit field');
    }
  }

  /// Requires [value] to contain exactly [length] one-byte characters.
  static void _requireLatin1(String value, int length, String label) {
    if (value.length != length || value.codeUnits.any((codeUnit) => codeUnit > 0xff)) {
      throw PatWriteException(message: '$label must contain exactly $length Latin-1 bytes');
    }
  }
}
