import 'package:patkit/src/model/pat_hierarchy.dart';
import 'package:patkit/src/model/pat_pattern.dart';
import 'package:pscore/pscore.dart';

/// Receives a recoverable hierarchy compatibility issue.
typedef PatHierarchyIssueHandler = void Function(String message);

/// Converts a generic Photoshop hierarchy descriptor into typed PAT entries.
abstract final class PatHierarchyMapper {
  /// Decodes the ordered list stored under the root `hierarchy` key.
  static List<PatHierarchyEntry> decode({
    required PsDescriptor root,
    required List<PatPattern> patterns,
    required int maxEntries,
    required PatHierarchyIssueHandler onIssue,
  }) {
    final PsDescriptorValue? hierarchyValue = root.value('hierarchy');
    if (hierarchyValue == null) {
      onIssue('The phry descriptor has no hierarchy item');
      return const <PatHierarchyEntry>[];
    }
    if (hierarchyValue is! PsListValue) {
      onIssue('The phry hierarchy item is ${hierarchyValue.type}, not a list');
      return const <PatHierarchyEntry>[];
    }
    if (hierarchyValue.values.length > maxEntries) {
      throw PsFormatException(message: 'PAT hierarchy entry count ${hierarchyValue.values.length} exceeds the configured $maxEntries limit');
    }

    final List<PatHierarchyEntry> entries = <PatHierarchyEntry>[];
    int depth = 0;
    int nextPatternIndex = 0;
    for (int index = 0; index < hierarchyValue.values.length; index++) {
      final PsDescriptorValue value = hierarchyValue.values[index];
      final PsDescriptor? descriptor = switch (value) {
        PsObjectValue(:final PsDescriptor value) => value,
        _ => null,
      };
      if (descriptor == null) {
        entries.add(
          PatHierarchyEntry(
            index: index,
            kind: PatHierarchyEntryKind.empty,
            depth: depth,
            classId: null,
            name: null,
            id: null,
            patternIndex: null,
            rawDescriptor: null,
          ),
        );
        if (value is! PsRawValue || value.value.isNotEmpty) {
          onIssue('Hierarchy entry ${index + 1} uses unsupported value type ${value.type}');
        }
        continue;
      }

      final String classId = descriptor.classId;
      final String? name = _firstString(descriptor, const <String>['Nm  ', 'name']);
      final String? id = _firstString(descriptor, const <String>['zuid', 'Idnt', 'identifier']);
      switch (classId) {
        case 'Grup':
        case 'group':
        case 'groupStart':
          entries.add(
            PatHierarchyEntry(
              index: index,
              kind: PatHierarchyEntryKind.groupStart,
              depth: depth,
              classId: classId,
              name: name,
              id: id,
              patternIndex: null,
              rawDescriptor: descriptor,
            ),
          );
          depth++;
        case 'groupEnd':
          if (depth == 0) {
            onIssue('Hierarchy entry ${index + 1} closes a group that was not open');
          } else {
            depth--;
          }
          entries.add(
            PatHierarchyEntry(
              index: index,
              kind: PatHierarchyEntryKind.groupEnd,
              depth: depth,
              classId: classId,
              name: name,
              id: id,
              patternIndex: null,
              rawDescriptor: descriptor,
            ),
          );
        case 'preset':
          final int? patternIndex = _patternIndex(
            patterns: patterns,
            id: id,
            fallback: nextPatternIndex,
          );
          if (patternIndex == null) {
            onIssue('Hierarchy preset ${index + 1} cannot be mapped to a decoded pattern');
          } else if (patternIndex >= nextPatternIndex) {
            nextPatternIndex = patternIndex + 1;
          }
          entries.add(
            PatHierarchyEntry(
              index: index,
              kind: PatHierarchyEntryKind.preset,
              depth: depth,
              classId: classId,
              name: name ?? (patternIndex == null ? null : patterns[patternIndex].name),
              id: id ?? (patternIndex == null ? null : patterns[patternIndex].id),
              patternIndex: patternIndex,
              rawDescriptor: descriptor,
            ),
          );
        case 'null':
        case '':
          entries.add(
            PatHierarchyEntry(
              index: index,
              kind: PatHierarchyEntryKind.empty,
              depth: depth,
              classId: classId,
              name: name,
              id: id,
              patternIndex: null,
              rawDescriptor: descriptor,
            ),
          );
        default:
          onIssue('Hierarchy entry ${index + 1} uses unknown class "$classId"');
          entries.add(
            PatHierarchyEntry(
              index: index,
              kind: PatHierarchyEntryKind.unknown,
              depth: depth,
              classId: classId,
              name: name,
              id: id,
              patternIndex: null,
              rawDescriptor: descriptor,
            ),
          );
      }
    }
    if (depth != 0) {
      onIssue('PAT hierarchy ends with $depth unclosed group${depth == 1 ? '' : 's'}');
    }
    return entries;
  }

  /// Returns the first string stored under one of [keys].
  static String? _firstString(PsDescriptor descriptor, List<String> keys) {
    for (final String key in keys) {
      final PsDescriptorValue? value = descriptor.value(key);
      if (value case PsStringValue(:final String value) when value.isNotEmpty) {
        final String trimmed = _trimTerminalNulls(value);
        return trimmed.isEmpty ? null : trimmed;
      }
    }
    return null;
  }

  /// Removes only terminal null characters from [value].
  static String _trimTerminalNulls(String value) {
    int end = value.length;
    while (end > 0 && value.codeUnitAt(end - 1) == 0) {
      end--;
    }
    return value.substring(0, end);
  }

  /// Resolves a preset by [id] before applying its sequential [fallback].
  static int? _patternIndex({
    required List<PatPattern> patterns,
    required String? id,
    required int fallback,
  }) {
    if (id != null && id.isNotEmpty) {
      final int matched = patterns.lastIndexWhere((pattern) => pattern.id == id);
      if (matched >= 0) {
        return matched;
      }
    }
    return fallback < patterns.length ? fallback : null;
  }
}
