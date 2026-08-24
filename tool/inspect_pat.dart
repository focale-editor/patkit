import 'dart:io';
import 'dart:typed_data';

import 'package:patkit/patkit.dart';

/// Inspects PAT libraries and reports their decoded structural coverage.
void main(List<String> arguments) {
  final bool metadataOnly = arguments.contains('--metadata-only');
  final bool render = arguments.contains('--render');
  final bool strict = arguments.contains('--strict');
  final List<String> paths = <String>[
    for (final String argument in arguments)
      if (!argument.startsWith('--')) argument,
  ];
  if (paths.isEmpty) {
    stderr.writeln('Usage: dart run tool/inspect_pat.dart [--metadata-only] [--render] [--strict] <file-or-directory> [...]');
    exitCode = 64;
    return;
  }

  final List<File> files = _patFiles(paths);
  if (files.isEmpty) {
    stderr.writeln('No PAT files found.');
    exitCode = 66;
    return;
  }
  for (final File file in files) {
    _inspect(
      file,
      metadataOnly: metadataOnly,
      render: render,
      strict: strict,
    );
  }
}

/// Returns PAT files contained in the requested [paths].
List<File> _patFiles(List<String> paths) {
  final List<File> files = <File>[];
  for (final String path in paths) {
    switch (FileSystemEntity.typeSync(path)) {
      case FileSystemEntityType.file:
        if (path.toLowerCase().endsWith('.pat')) {
          files.add(File(path));
        }
      case FileSystemEntityType.directory:
        files.addAll(
          Directory(path).listSync(recursive: true).whereType<File>().where((file) => file.path.toLowerCase().endsWith('.pat')),
        );
      case FileSystemEntityType.link:
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        break;
    }
  }
  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}

/// Decodes and prints one concise report for [file].
void _inspect(
  File file, {
  required bool metadataOnly,
  required bool render,
  required bool strict,
}) {
  try {
    final Uint8List bytes = file.readAsBytesSync();
    final PatFile decoded = PatDecoder.decode(
      bytes,
      options: PatDecodeOptions(
        mode: strict ? PatDecodeMode.strict : PatDecodeMode.tolerant,
        decodeChannelData: render || !metadataOnly,
        preserveChannelData: false,
        preserveRecordData: false,
        preserveTaggedBlockData: false,
      ),
    );
    stdout.writeln('${file.path}: ${decoded.patterns.length}/${decoded.declaredPatternCount} patterns, ${decoded.hierarchy.length} hierarchy entries, ${decoded.warnings.length} warnings');
    for (int index = 0; index < decoded.patterns.length; index++) {
      final PatPattern pattern = decoded.patterns[index];
      final Set<int> depths = <int>{for (final PatPatternChannel channel in pattern.channels) channel.depth};
      final Set<int> compressionCodes = <int>{for (final PatPatternChannel channel in pattern.channels) channel.compressionCode};
      stdout.writeln(
        '  ${index + 1}. ${pattern.name} [${pattern.id}] ${pattern.width}x${pattern.height}, mode ${pattern.colorModeCode}, slots ${pattern.slots.length}, depths $depths, compression $compressionCodes',
      );
      if (render) {
        final PatPatternImage image = pattern.renderRgba8();
        stdout.writeln('     rendered ${image.rgba.length} RGBA bytes');
      }
    }
    for (final PatHierarchyEntry entry in decoded.hierarchy) {
      final String indentation = '  ' * (entry.depth + 1);
      final String label = switch (entry.kind) {
        PatHierarchyEntryKind.groupStart => '+ ${entry.name ?? '<unnamed group>'}',
        PatHierarchyEntryKind.groupEnd => '- <group end>',
        PatHierarchyEntryKind.preset => decoded.patternFor(entry)?.name ?? entry.name ?? '<missing preset>',
        PatHierarchyEntryKind.empty => '<empty>',
        PatHierarchyEntryKind.unknown => '<unknown ${entry.classId}>',
      };
      stdout.writeln('$indentation$label');
    }
    for (final PatWarning warning in decoded.warnings) {
      stdout.writeln('  warning: $warning');
    }
  } on Object catch (error) {
    stderr.writeln('${file.path}: $error');
    exitCode = 1;
  }
}
