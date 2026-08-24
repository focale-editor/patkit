import 'dart:typed_data';

import 'package:patkit/src/codec/pat_hierarchy_mapper.dart';
import 'package:patkit/src/model/pat_file.dart';
import 'package:patkit/src/model/pat_hierarchy.dart';
import 'package:patkit/src/model/pat_options.dart';
import 'package:patkit/src/model/pat_pattern.dart';
import 'package:pscore/pscore.dart';

/// Decodes Adobe Photoshop `8BPT` pattern libraries.
abstract final class PatDecoder {
  /// Four-byte file signature used by every standalone PAT library.
  static const String _fileSignature = '8BPT';

  /// Four-byte signature used by ordinary Photoshop tagged blocks.
  static const String _taggedBlockSignature = '8BIM';

  /// Alternate signature accepted for forward-compatible tagged blocks.
  static const String _largeTaggedBlockSignature = '8B64';

  /// Descriptor version stored before a Photoshop Action Descriptor.
  static const int _descriptorVersion = 16;

  /// Decodes one complete in-memory PAT [bytes] buffer.
  static PatFile decode(
    Uint8List bytes, {
    PatDecodeOptions options = const PatDecodeOptions(),
  }) {
    if (bytes.length > options.maxFileBytes) {
      throw PatFormatException(
        message: 'PAT file size ${bytes.length} exceeds the configured ${options.maxFileBytes} byte limit',
        source: bytes,
        offset: 0,
      );
    }
    try {
      return _decode(bytes, options);
    } on PatFormatException {
      rethrow;
    } on PsFormatException catch (error) {
      throw PatFormatException(
        message: error.message,
        source: bytes,
        offset: error.offset,
      );
    } on RangeError catch (error) {
      throw PatFormatException(
        message: 'Invalid PAT numeric range: $error',
        source: bytes,
      );
    }
  }

  /// Decodes the header, source records, and optional trailing tagged blocks.
  static PatFile _decode(Uint8List bytes, PatDecodeOptions options) {
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final String signature = reader.readString(4);
    if (signature != _fileSignature) {
      throw PsFormatException(message: 'Invalid PAT signature "$signature"; expected "$_fileSignature"', source: bytes, offset: 0);
    }
    final int version = reader.readUint16();
    if (version != 1) {
      throw PsFormatException(message: 'Unsupported PAT version $version', source: bytes, offset: 4);
    }
    final int declaredPatternCount = reader.readUint32();
    if (declaredPatternCount > options.maxPatterns) {
      throw PsFormatException(
        message: 'PAT pattern count $declaredPatternCount exceeds the configured ${options.maxPatterns} limit',
        source: bytes,
        offset: 6,
      );
    }
    final _PatDecodeContext context = _PatDecodeContext(
      source: bytes,
      options: options,
      version: version,
      declaredPatternCount: declaredPatternCount,
    );
    _decodePatterns(reader, context);
    _decodeTaggedBlocks(reader, context);
    return context.build();
  }

  /// Decodes every unframed pattern record declared by the file header.
  static void _decodePatterns(PsBinaryReader reader, _PatDecodeContext context) {
    for (int index = 0; index < context.declaredPatternCount; index++) {
      context.patternIndex = index;
      final int recordOffset = reader.baseOffset + reader.offset;
      final PsPatternDecodeResult decoded = PsPatternRecordDecoder.decode(
        reader: reader,
        kind: PsPatternRecordKind.standalone,
        options: PsPatternDecodeOptions(
          maxDimension: context.options.maxDimension,
          maxChannelCount: context.options.maxChannelCount,
          maxVirtualMemoryBytes: context.options.maxPatternBytes,
          maxNameCodeUnits: context.options.maxPatternNameCodeUnits,
          maxDecodedBytes: context.options.maxDecodedPixelBytes - context.decodedPixelBytes,
          decodeChannelData: context.options.decodeChannelData,
          preserveChannelData: context.options.preserveChannelData,
          preserveRecordData: context.options.preserveRecordData,
        ),
        onIssue: (message, offset) => context.issue(message, offset),
        onDecodedBytesRequired: (bytes, offset) => context.ensureDecodedBytes(bytes, offset),
      );
      context.addPattern(decoded.pattern, decoded.decodedBytes, recordOffset);
    }
    context.patternIndex = null;
  }

  /// Decodes recognizable length-prefixed blocks after the declared patterns.
  static void _decodeTaggedBlocks(PsBinaryReader reader, _PatDecodeContext context) {
    while (!reader.isAtEnd) {
      final int blockOffset = reader.baseOffset + reader.offset;
      if (reader.remaining < 12 || !_hasTaggedSignature(reader, 0)) {
        context.trailingData = reader.readBytes(reader.remaining);
        context.issue('${context.trailingData.length} unrecognized trailing bytes remain after the PAT payload', blockOffset);
        return;
      }

      final bool usesWideLength = _hasLargeTaggedSignature(reader);
      if (usesWideLength && reader.remaining < 16) {
        context.trailingData = reader.readBytes(reader.remaining);
        context.issue('Truncated PAT 8B64 tagged-block header', blockOffset);
        return;
      }

      final String signature = reader.readString(4);
      final String key = reader.readString(4);
      final int length = usesWideLength ? reader.readUint64() : reader.readUint32();
      final int payloadOffset = blockOffset + (usesWideLength ? 16 : 12);
      context.blockKey = key;
      if (length > context.options.maxTaggedBlockBytes) {
        throw PsFormatException(
          message: 'PAT tagged block $key length $length exceeds the configured ${context.options.maxTaggedBlockBytes} byte limit',
          source: reader.bytes,
          offset: blockOffset + 8,
        );
      }
      if (length > reader.remaining) {
        final Uint8List available = reader.readView(reader.remaining);
        context.addTaggedBlock(
          signature: signature,
          key: key,
          offset: blockOffset,
          declaredLength: length,
          data: available,
          paddingData: Uint8List(0),
        );
        context.issue('PAT tagged block $key length $length exceeds the ${available.length} available bytes', blockOffset + 8);
        context.blockKey = null;
        return;
      }

      final Uint8List payload = reader.readView(length);
      final int paddingLength = _taggedPaddingLength(reader, length);
      final Uint8List padding = reader.readBytes(paddingLength);
      context.addTaggedBlock(
        signature: signature,
        key: key,
        offset: blockOffset,
        declaredLength: length,
        data: payload,
        paddingData: padding,
      );
      if (signature != _taggedBlockSignature) {
        context.issue('PAT tagged block $key uses alternate signature "$signature"', blockOffset);
      }
      if (key == 'phry') {
        _decodeHierarchyBlock(
          payload: payload,
          payloadOffset: payloadOffset,
          context: context,
        );
      } else {
        context.issue('Unknown PAT tagged block $key was preserved', blockOffset + 4);
      }
      context.blockKey = null;
    }
  }

  /// Decodes the versioned Action Descriptor inside a `phry` payload.
  static void _decodeHierarchyBlock({
    required Uint8List payload,
    required int payloadOffset,
    required _PatDecodeContext context,
  }) {
    try {
      final PsBinaryReader descriptorReader = PsBinaryReader(bytes: payload, baseOffset: payloadOffset);
      final int version = descriptorReader.readUint32();
      if (version != _descriptorVersion) {
        context.issue('PAT hierarchy descriptor version $version is not currently defined', payloadOffset);
      }
      final PsDescriptor descriptor = PsDescriptorCodec.decodeReader(
        descriptorReader,
        options: context.options.descriptorOptions,
      );
      if (!descriptorReader.isAtEnd) {
        context.issue('${descriptorReader.remaining} extension bytes remain after the PAT hierarchy descriptor', descriptorReader.baseOffset + descriptorReader.offset);
      }
      context.addHierarchyDescriptor(descriptor);
      final List<PatHierarchyEntry> entries = PatHierarchyMapper.decode(
        root: descriptor,
        patterns: context.patterns,
        maxEntries: context.options.maxHierarchyEntries,
        onIssue: (message) => context.issue(message, payloadOffset),
      );
      context.addHierarchyEntries(entries);
    } on PsFormatException catch (error) {
      if (context.options.mode == PatDecodeMode.strict) {
        rethrow;
      }
      context.warning('PAT hierarchy could not be decoded: ${error.message}', error.offset ?? payloadOffset);
    }
  }

  /// Returns the optional zero padding before the next recognizable block.
  static int _taggedPaddingLength(PsBinaryReader reader, int payloadLength) {
    if (_hasTaggedSignature(reader, 0)) {
      return 0;
    }
    final int expectedLength = (4 - payloadLength % 4) % 4;
    if (expectedLength == 0 || reader.remaining < expectedLength || !_allZero(reader, expectedLength)) {
      return 0;
    }
    if (reader.remaining == expectedLength || _hasTaggedSignature(reader, expectedLength)) {
      return expectedLength;
    }
    return 0;
  }

  /// Tests whether the first [length] remaining bytes are all zero.
  static bool _allZero(PsBinaryReader reader, int length) {
    for (int index = 0; index < length; index++) {
      if (reader.bytes[reader.offset + index] != 0) {
        return false;
      }
    }
    return true;
  }

  /// Tests whether a supported tagged signature starts at [relativeOffset].
  static bool _hasTaggedSignature(PsBinaryReader reader, int relativeOffset) {
    if (relativeOffset < 0 || reader.remaining < relativeOffset + 4) {
      return false;
    }
    final int offset = reader.offset + relativeOffset;
    final String signature = String.fromCharCodes(Uint8List.sublistView(reader.bytes, offset, offset + 4));
    return signature == _taggedBlockSignature || signature == _largeTaggedBlockSignature;
  }

  /// Tests whether the current tagged block uses a 64-bit payload length.
  static bool _hasLargeTaggedSignature(PsBinaryReader reader) {
    if (reader.remaining < 4) {
      return false;
    }
    final int offset = reader.offset;
    return String.fromCharCodes(Uint8List.sublistView(reader.bytes, offset, offset + 4)) == _largeTaggedBlockSignature;
  }
}

/// Accumulates immutable PAT models and source-aware compatibility warnings.
final class _PatDecodeContext {
  /// Complete input used as an exception source.
  final Uint8List source;

  /// Caller-selected limits and compatibility behavior.
  final PatDecodeOptions options;

  /// PAT container version.
  final int version;

  /// Number of records promised by the header.
  final int declaredPatternCount;

  /// Successfully decoded patterns.
  final List<PatPattern> patterns = <PatPattern>[];

  /// Flattened typed hierarchy entries.
  final List<PatHierarchyEntry> hierarchy = <PatHierarchyEntry>[];

  /// Decoded source hierarchy descriptors.
  final List<PsDescriptor> hierarchyDescriptors = <PsDescriptor>[];

  /// Preserved tagged blocks.
  final List<PatTaggedBlock> taggedBlocks = <PatTaggedBlock>[];

  /// Collected tolerant-mode warnings.
  final List<PatWarning> warnings = <PatWarning>[];

  /// First pattern index for each seen non-empty identifier.
  final Map<String, int> _patternIndicesById = <String, int>{};

  /// Bytes that could not be assigned to a recognized structure.
  Uint8List trailingData = Uint8List(0);

  /// Aggregate retained uncompressed channel bytes.
  int decodedPixelBytes = 0;

  /// Pattern currently being decoded, when applicable.
  int? patternIndex;

  /// Tagged block currently being decoded, when applicable.
  String? blockKey;

  /// Creates an empty decode accumulator.
  _PatDecodeContext({
    required this.source,
    required this.options,
    required this.version,
    required this.declaredPatternCount,
  });

  /// Promotes a compatibility issue in strict mode or records a warning.
  void issue(String message, int offset) {
    if (options.mode == PatDecodeMode.strict) {
      throw PsFormatException(message: message, source: source, offset: offset);
    }
    warning(message, offset);
  }

  /// Records a warning without applying the strict-mode promotion policy.
  void warning(String message, int offset) {
    warnings.add(
      PatWarning(
        message: message,
        offset: offset,
        patternIndex: patternIndex,
        blockKey: blockKey,
      ),
    );
  }

  /// Rejects a channel allocation that would exceed the file-wide budget.
  void ensureDecodedBytes(int patternBytes, int offset) {
    if (patternBytes > options.maxDecodedPixelBytes - decodedPixelBytes) {
      throw PsFormatException(
        message: 'Decoded PAT bytes exceed the configured ${options.maxDecodedPixelBytes} byte limit',
        source: source,
        offset: offset,
      );
    }
  }

  /// Adds one decoded pattern and validates its identifier.
  void addPattern(PatPattern pattern, int decodedBytes, int offset) {
    final int index = patterns.length;
    patterns.add(pattern);
    decodedPixelBytes += decodedBytes;
    if (pattern.id.isEmpty) {
      issue('Pattern ${index + 1} has an empty identifier', offset);
      return;
    }
    final int? previous = _patternIndicesById[pattern.id];
    if (previous != null) {
      issue('Pattern ${index + 1} duplicates identifier "${pattern.id}" from pattern ${previous + 1}', offset);
    }
    _patternIndicesById[pattern.id] = index;
  }

  /// Preserves one tagged block according to the caller's retention policy.
  void addTaggedBlock({
    required String signature,
    required String key,
    required int offset,
    required int declaredLength,
    required Uint8List data,
    required Uint8List paddingData,
  }) {
    taggedBlocks.add(
      PatTaggedBlock(
        signature: signature,
        key: key,
        offset: offset,
        declaredLength: declaredLength,
        data: options.preserveTaggedBlockData ? data : Uint8List(0),
        paddingData: paddingData,
      ),
    );
  }

  /// Preserves one successfully decoded hierarchy descriptor.
  void addHierarchyDescriptor(PsDescriptor descriptor) {
    hierarchyDescriptors.add(descriptor);
  }

  /// Adds decoded hierarchy [entries] after rebasing their source indices.
  void addHierarchyEntries(List<PatHierarchyEntry> entries) {
    final int indexOffset = hierarchy.length;
    hierarchy.addAll(<PatHierarchyEntry>[
      for (final PatHierarchyEntry entry in entries)
        PatHierarchyEntry(
          index: entry.index + indexOffset,
          kind: entry.kind,
          depth: entry.depth,
          classId: entry.classId,
          name: entry.name,
          id: entry.id,
          patternIndex: entry.patternIndex,
          rawDescriptor: entry.rawDescriptor,
        ),
    ]);
  }

  /// Builds the immutable public result.
  PatFile build() => PatFile(
    version: version,
    declaredPatternCount: declaredPatternCount,
    patterns: patterns,
    hierarchy: hierarchy,
    hierarchyDescriptors: hierarchyDescriptors,
    taggedBlocks: taggedBlocks,
    trailingData: trailingData,
    warnings: warnings,
    decodedPixelBytes: decodedPixelBytes,
  );
}
