import 'package:patkit/src/model/pat_pattern.dart';
import 'package:pscore/pscore.dart';

/// Identifies the role of one slot in Photoshop's optional pattern hierarchy.
enum PatHierarchyEntryKind {
  /// Opens a named pattern group.
  groupStart,

  /// Closes the most recently opened pattern group.
  groupEnd,

  /// Refers to a pattern preset in source order.
  preset,

  /// Preserves an intentionally empty hierarchy slot.
  empty,

  /// Preserves an object class not understood by this release.
  unknown,
}

/// One ordered item from a trailing Photoshop `phry` hierarchy descriptor.
final class PatHierarchyEntry {
  /// Zero-based position in the source hierarchy list.
  final int index;

  /// Semantic role inferred from the descriptor class.
  final PatHierarchyEntryKind kind;

  /// Zero-based nesting depth at which this item appears.
  final int depth;

  /// Original Photoshop descriptor class, or `null` for an empty slot.
  final String? classId;

  /// User-visible group or preset name, when stored.
  final String? name;

  /// Photoshop identifier associated with the item, when stored.
  final String? id;

  /// Index of the referred pattern, when this is a mapped preset.
  final int? patternIndex;

  /// Complete source descriptor, or `null` for an empty slot.
  final PsDescriptor? rawDescriptor;

  /// Creates an immutable hierarchy item.
  const PatHierarchyEntry({
    required this.index,
    required this.kind,
    required this.depth,
    required this.classId,
    required this.name,
    required this.id,
    required this.patternIndex,
    required this.rawDescriptor,
  });

  /// Returns the referred pattern from [patterns], when the mapping is valid.
  PatPattern? resolvePattern(List<PatPattern> patterns) {
    final int? index = patternIndex;
    if (index == null || index < 0 || index >= patterns.length) {
      return null;
    }
    return patterns[index];
  }
}
