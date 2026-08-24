import 'package:pscore/pscore.dart';

/// Controls whether recoverable PAT compatibility issues stop decoding.
enum PatDecodeMode {
  /// Rejects unknown extensions and malformed optional data.
  strict,

  /// Preserves unknown data and reports recoverable defects as warnings.
  tolerant,
}

/// Resource and preservation limits applied while decoding a PAT library.
final class PatDecodeOptions {
  /// Handling policy for recoverable format extensions and damaged records.
  final PatDecodeMode mode;

  /// Maximum accepted input size.
  final int maxFileBytes;

  /// Maximum number of pattern records declared by one library.
  final int maxPatterns;

  /// Maximum width or height accepted for decoded source planes.
  final int maxDimension;

  /// Maximum number of ordinary virtual-memory channel slots.
  final int maxChannelCount;

  /// Maximum byte length accepted for one virtual-memory payload.
  final int maxPatternBytes;

  /// Maximum UTF-16 code-unit count accepted for one pattern name.
  final int maxPatternNameCodeUnits;

  /// Maximum aggregate number of retained uncompressed channel bytes.
  final int maxDecodedPixelBytes;

  /// Maximum payload length accepted for one trailing tagged block.
  final int maxTaggedBlockBytes;

  /// Maximum number of hierarchy entries exposed from `phry` descriptors.
  final int maxHierarchyEntries;

  /// Resource limits applied to every hierarchy Action Descriptor.
  final PsDescriptorDecodeOptions descriptorOptions;

  /// Whether recognized channel data is decompressed.
  final bool decodeChannelData;

  /// Whether channel slots retain their original encoded payload bytes.
  final bool preserveChannelData;

  /// Whether each pattern retains a complete copy of its source record.
  final bool preserveRecordData;

  /// Whether tagged trailer blocks retain their complete payload bytes.
  final bool preserveTaggedBlockData;

  /// Creates bounded decode options suitable for untrusted input.
  const PatDecodeOptions({
    this.mode = PatDecodeMode.tolerant,
    this.maxFileBytes = 1024 * 1024 * 1024,
    this.maxPatterns = 100000,
    this.maxDimension = 100000,
    this.maxChannelCount = 1024,
    this.maxPatternBytes = 512 * 1024 * 1024,
    this.maxPatternNameCodeUnits = 1024 * 1024,
    this.maxDecodedPixelBytes = 512 * 1024 * 1024,
    this.maxTaggedBlockBytes = 64 * 1024 * 1024,
    this.maxHierarchyEntries = 100000,
    this.descriptorOptions = const PsDescriptorDecodeOptions(),
    this.decodeChannelData = true,
    this.preserveChannelData = true,
    this.preserveRecordData = true,
    this.preserveTaggedBlockData = true,
  });
}

/// Describes a recoverable compatibility issue found while decoding.
final class PatWarning {
  /// Human-readable explanation of the compatibility issue.
  final String message;

  /// Absolute byte offset associated with the issue, when known.
  final int? offset;

  /// Zero-based pattern index associated with the issue, when known.
  final int? patternIndex;

  /// Tagged-block key associated with the issue, when known.
  final String? blockKey;

  /// Creates a warning with optional source context.
  const PatWarning({
    required this.message,
    this.offset,
    this.patternIndex,
    this.blockKey,
  });

  @override
  String toString() {
    final String location = offset == null ? '' : ' at byte $offset';
    final int? currentPatternIndex = patternIndex;
    final String pattern = currentPatternIndex == null ? '' : ' in pattern ${currentPatternIndex + 1}';
    final String block = blockKey == null ? '' : ' in $blockKey';
    return 'PatWarning$location$pattern$block: $message';
  }
}

/// Reports malformed, truncated, unsupported, or unsafe PAT input.
final class PatFormatException implements FormatException {
  /// Human-readable explanation of the malformed data.
  @override
  final String message;

  /// Input associated with the failure, when useful.
  @override
  final Object? source;

  /// Absolute byte offset associated with the failure, when known.
  @override
  final int? offset;

  /// Creates a PAT format error at an optional absolute byte [offset].
  const PatFormatException({
    required this.message,
    this.source,
    this.offset,
  });

  @override
  String toString() {
    final String location = offset == null ? '' : ' at byte $offset';
    return 'PatFormatException$location: $message';
  }
}
