import 'package:patkit/src/model/pat_hierarchy.dart';
import 'package:patkit/src/model/pat_pattern.dart';
import 'package:pscore/pscore.dart';

/// Receives a recoverable hierarchy compatibility issue.
typedef PatHierarchyIssueHandler = void Function(String message);

/// Adapts the shared Photoshop hierarchy mapper to PAT pattern entries.
abstract final class PatHierarchyMapper {
  /// Decodes the ordered list stored under the root `hierarchy` key.
  static List<PatHierarchyEntry> decode({
    required PsDescriptor root,
    required List<PatPattern> patterns,
    required int maxEntries,
    required PatHierarchyIssueHandler onIssue,
  }) => List<PatHierarchyEntry>.unmodifiable(<PatHierarchyEntry>[
    for (final PsPresetHierarchyEntry entry in PsPresetHierarchyMapper.decode(
      root: root,
      presets: <PsPresetIdentity>[
        for (final PatPattern pattern in patterns)
          PsPresetIdentity(
            name: pattern.name,
            id: pattern.id,
          ),
      ],
      maxEntries: maxEntries,
      onIssue: onIssue,
      formatLabel: 'PAT',
      presetLabel: 'a decoded pattern',
    ))
      PatHierarchyEntry(
        index: entry.index,
        kind: _kind(entry.kind),
        depth: entry.depth,
        classId: entry.classId,
        name: entry.name,
        id: entry.id,
        patternIndex: entry.presetIndex,
        rawDescriptor: entry.rawDescriptor,
      ),
  ]);

  /// Converts the shared semantic role to its compatibility enum.
  static PatHierarchyEntryKind _kind(PsPresetHierarchyEntryKind kind) => switch (kind) {
    PsPresetHierarchyEntryKind.groupStart => PatHierarchyEntryKind.groupStart,
    PsPresetHierarchyEntryKind.groupEnd => PatHierarchyEntryKind.groupEnd,
    PsPresetHierarchyEntryKind.preset => PatHierarchyEntryKind.preset,
    PsPresetHierarchyEntryKind.empty => PatHierarchyEntryKind.empty,
    PsPresetHierarchyEntryKind.unknown => PatHierarchyEntryKind.unknown,
  };
}
