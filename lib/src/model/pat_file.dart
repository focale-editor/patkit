import 'dart:typed_data';

import 'package:patkit/src/model/pat_hierarchy.dart';
import 'package:patkit/src/model/pat_options.dart';
import 'package:patkit/src/model/pat_pattern.dart';
import 'package:pscore/pscore.dart';

/// One tagged trailer block following the declared pattern records.
final class PatTaggedBlock {
  /// Four-byte Photoshop signature, normally `8BIM`.
  final String signature;

  /// Four-byte block key, such as `phry`.
  final String key;

  /// Absolute offset of the block signature.
  final int offset;

  /// Payload length exactly as declared in the block header.
  final int declaredLength;

  /// Unpadded payload, or an empty list when preservation was disabled.
  final Uint8List data;

  /// Optional alignment bytes before a following block or end-of-file.
  final Uint8List paddingData;

  /// Creates an immutable tagged trailer block.
  PatTaggedBlock({
    required this.signature,
    required this.key,
    required this.offset,
    required this.declaredLength,
    required Uint8List data,
    required Uint8List paddingData,
  }) : data = Uint8List.fromList(data).asUnmodifiableView(),
       paddingData = Uint8List.fromList(paddingData).asUnmodifiableView();
}

/// Complete decoded contents of one Adobe Photoshop pattern library.
final class PatFile {
  /// PAT container version exactly as stored in the file.
  final int version;

  /// Pattern count declared by the PAT header.
  final int declaredPatternCount;

  /// Successfully decoded patterns in source order.
  final List<PatPattern> patterns;

  /// Flattened group and preset hierarchy from all recognized `phry` blocks.
  final List<PatHierarchyEntry> hierarchy;

  /// Complete root descriptors from every recognized `phry` block.
  final List<PsDescriptor> hierarchyDescriptors;

  /// Every trailing tagged block, including unknown forward-compatible keys.
  final List<PatTaggedBlock> taggedBlocks;

  /// Bytes following the last recognized pattern or tagged block.
  final Uint8List trailingData;

  /// Recoverable compatibility issues encountered while decoding.
  final List<PatWarning> warnings;

  /// Aggregate uncompressed channel bytes retained by [patterns].
  final int decodedPixelBytes;

  /// Last pattern for every non-empty identifier.
  final Map<String, PatPattern> _patternsById;

  /// Creates an immutable decoded PAT library.
  PatFile({
    required this.version,
    required this.declaredPatternCount,
    required List<PatPattern> patterns,
    required List<PatHierarchyEntry> hierarchy,
    required List<PsDescriptor> hierarchyDescriptors,
    required List<PatTaggedBlock> taggedBlocks,
    required Uint8List trailingData,
    required List<PatWarning> warnings,
    required this.decodedPixelBytes,
  }) : patterns = List<PatPattern>.unmodifiable(patterns),
       hierarchy = List<PatHierarchyEntry>.unmodifiable(hierarchy),
       hierarchyDescriptors = List<PsDescriptor>.unmodifiable(hierarchyDescriptors),
       taggedBlocks = List<PatTaggedBlock>.unmodifiable(taggedBlocks),
       trailingData = Uint8List.fromList(trailingData).asUnmodifiableView(),
       warnings = List<PatWarning>.unmodifiable(warnings),
       _patternsById = Map<String, PatPattern>.unmodifiable(<String, PatPattern>{
         for (final PatPattern pattern in patterns)
           if (pattern.id.isNotEmpty) pattern.id: pattern,
       });

  /// Whether every pattern declared in the header was decoded.
  bool get isComplete => patterns.length == declaredPatternCount;

  /// Returns the last pattern matching [id], or `null` when absent.
  PatPattern? patternById(String id) => _patternsById[id];

  /// Resolves the pattern referred to by [entry], when available.
  PatPattern? patternFor(PatHierarchyEntry entry) => entry.resolvePattern(patterns);
}
