import 'dart:typed_data';

import 'package:pscore/pscore.dart';

/// Describes one source channel used by synthetic PAT records.
final class PatTestChannel {
  /// Source sample precision.
  final int depth;

  /// Uncompressed row-major source bytes.
  final List<int> bytes;

  /// Whether each row is encoded with PackBits.
  final bool packBits;

  /// Explicit compression marker used for compatibility tests.
  final int? compressionCode;

  /// Creates a synthetic pattern channel.
  const PatTestChannel({
    required this.depth,
    required this.bytes,
    this.packBits = false,
    this.compressionCode,
  });
}

/// Describes one trailing tagged block used by synthetic PAT files.
final class PatTestTaggedBlock {
  /// Four-byte block signature.
  final String signature;

  /// Four-byte block key.
  final String key;

  /// Unpadded block payload.
  final Uint8List data;

  /// Number of zero bytes written after the payload.
  final int padding;

  /// Creates a synthetic tagged block.
  const PatTestTaggedBlock({
    required this.key,
    required this.data,
    this.signature = '8BIM',
    this.padding = 0,
  });
}

/// Builds small deterministic PAT buffers covering container variants.
abstract final class PatFixtureBuilder {
  /// Builds a complete standalone PAT file from [patterns] and [blocks].
  static Uint8List file({
    required List<Uint8List> patterns,
    List<PatTestTaggedBlock> blocks = const <PatTestTaggedBlock>[],
    String signature = '8BPT',
    int version = 1,
    int? declaredPatternCount,
  }) {
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeString(signature)
      ..writeUint16(version)
      ..writeUint32(declaredPatternCount ?? patterns.length);
    patterns.forEach(writer.writeBytes);
    for (final PatTestTaggedBlock block in blocks) {
      writer
        ..writeString(block.signature)
        ..writeString(block.key);
      if (block.signature == '8B64') {
        writer.writeUint64(block.data.length);
      } else {
        writer.writeUint32(block.data.length);
      }
      writer
        ..writeBytes(block.data)
        ..writeZeros(block.padding);
    }
    return writer.takeBytes();
  }

  /// Builds one standalone-compatible version 1 pattern record.
  static Uint8List pattern({
    required String name,
    required String id,
    required PsPatternColorMode mode,
    required int width,
    required int height,
    required List<PatTestChannel> channels,
    PatTestChannel? userMask,
    PatTestChannel? alpha,
    Uint8List? palette,
    int colorsUsed = 0,
    int transparentIndex = 0xffff,
    int declaredChannelCount = 24,
    int virtualMemoryVersion = 3,
  }) {
    final PsBinaryWriter virtualMemory = PsBinaryWriter()
      ..writeInt32(0)
      ..writeInt32(0)
      ..writeInt32(height)
      ..writeInt32(width)
      ..writeUint32(declaredChannelCount);
    for (int index = 0; index < declaredChannelCount + 2; index++) {
      final PatTestChannel? channel = switch (index) {
        _ when index < channels.length => channels[index],
        _ when index == declaredChannelCount => userMask,
        _ when index == declaredChannelCount + 1 => alpha,
        _ => null,
      };
      if (channel == null) {
        virtualMemory.writeUint32(0);
      } else {
        _writeChannel(
          virtualMemory,
          channel,
          width: width,
          height: height,
        );
      }
    }
    final Uint8List virtualMemoryBytes = virtualMemory.takeBytes();
    final PsBinaryWriter record = PsBinaryWriter()
      ..writeUint32(1)
      ..writeUint32(mode.code)
      ..writeUint16(height)
      ..writeUint16(width);
    _writeUnicodeString(record, name);
    record
      ..writeUint8(id.length)
      ..writeString(id);
    if (mode == PsPatternColorMode.indexed) {
      record
        ..writeBytes(palette ?? Uint8List(256 * 3))
        ..writeUint16(colorsUsed)
        ..writeUint16(transparentIndex);
    }
    record
      ..writeUint32(virtualMemoryVersion)
      ..writeUint32(virtualMemoryBytes.length)
      ..writeBytes(virtualMemoryBytes);
    return record.takeBytes();
  }

  /// Builds a `phry` block containing a nested group and two presets.
  static PatTestTaggedBlock hierarchyBlock() {
    final PsDescriptor group = PsDescriptor(
      name: '',
      classId: 'Grup',
      items: <PsDescriptorItem>[
        _item('Nm  ', const PsStringValue(value: 'Favorites\u0000')),
        _item('zuid', const PsStringValue(value: 'group-id\u0000')),
      ],
    );
    const PsDescriptor preset = PsDescriptor(name: '', classId: 'preset');
    const PsDescriptor end = PsDescriptor(name: '', classId: 'groupEnd');
    final PsDescriptor root = PsDescriptor(
      name: '',
      classId: 'null',
      items: <PsDescriptorItem>[
        _item(
          'hierarchy',
          PsListValue(
            values: <PsDescriptorValue>[
              PsObjectValue(value: group),
              const PsObjectValue(value: preset),
              const PsObjectValue(value: preset),
              const PsObjectValue(value: end),
            ],
          ),
        ),
      ],
    );
    final PsBinaryWriter payload = PsBinaryWriter()
      ..writeUint32(16)
      ..writeBytes(PsDescriptorCodec.encode(root));
    return PatTestTaggedBlock(key: 'phry', data: payload.takeBytes());
  }

  /// Builds an unknown tagged block with optional [padding].
  static PatTestTaggedBlock unknownBlock({int padding = 0}) => PatTestTaggedBlock(
    key: 'futr',
    data: Uint8List.fromList(<int>[1, 2, 3]),
    padding: padding,
  );

  /// Writes one complete virtual-memory channel slot.
  static void _writeChannel(
    PsBinaryWriter writer,
    PatTestChannel channel, {
    required int width,
    required int height,
  }) {
    final PsBinaryWriter payload = PsBinaryWriter()
      ..writeUint32(channel.depth)
      ..writeInt32(0)
      ..writeInt32(0)
      ..writeInt32(height)
      ..writeInt32(width)
      ..writeUint16(channel.depth)
      ..writeUint8(channel.compressionCode ?? (channel.packBits ? 1 : 0));
    if (channel.packBits) {
      final int rowBytes = (width * channel.depth + 7) ~/ 8;
      final List<Uint8List> rows = <Uint8List>[
        for (int row = 0; row < height; row++)
          PsPackBitsCodec.encodeRow(
            Uint8List.fromList(channel.bytes.sublist(row * rowBytes, (row + 1) * rowBytes)),
          ),
      ];
      for (final Uint8List row in rows) {
        payload.writeUint16(row.length);
      }
      rows.forEach(payload.writeBytes);
    } else {
      payload.writeBytes(channel.bytes);
    }
    final Uint8List bytes = payload.takeBytes();
    writer
      ..writeUint32(1)
      ..writeUint32(bytes.length)
      ..writeBytes(bytes);
  }

  /// Writes a big-endian UTF-16 string including its terminal null code unit.
  static void _writeUnicodeString(PsBinaryWriter writer, String value) {
    writer.writeUint32(value.length + 1);
    value.codeUnits.forEach(writer.writeUint16);
    writer.writeUint16(0);
  }

  /// Creates one descriptor item.
  static PsDescriptorItem _item(String key, PsDescriptorValue value) => PsDescriptorItem(key: key, value: value);
}
