import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Audits documentation and member ordering for production Dart sources.
void main(List<String> arguments) {
  final List<File> files = _dartFiles(arguments.isEmpty ? <String>['lib'] : arguments);
  final List<String> issues = <String>[];
  for (final File file in files) {
    final String source = file.readAsStringSync();
    final CompilationUnit unit = parseString(content: source, path: file.path).unit;
    unit.accept(
      _DocumentationVisitor(
        path: file.path,
        source: source,
        issues: issues,
      ),
    );
  }
  if (issues.isNotEmpty) {
    stderr.writeln(issues.join('\n'));
    exitCode = 1;
  }
}

/// Checks documented declarations and type-member ordering in one source file.
final class _DocumentationVisitor extends RecursiveAstVisitor<void> {
  /// Path shown in diagnostics.
  final String path;

  /// Complete source used to calculate line numbers.
  final String source;

  /// Shared issue accumulator.
  final List<String> issues;

  /// Creates an audit visitor for one [path].
  _DocumentationVisitor({
    required this.path,
    required this.source,
    required this.issues,
  });

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final String name = node.namePart.typeName.lexeme;
    _requireDocumentation(node, 'class $name');
    _checkOrder(node.body.members, name);
    super.visitClassDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _requireDocumentation(node, 'constructor ${node.typeName?.name ?? '<primary>'}');
    if (node.parameters.parameters.any((parameter) => parameter.isPositional)) {
      issues.add('$path:${_line(node.offset)}: constructor parameters must be named');
    }
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) {
    _requireDocumentation(node, 'enum constant ${node.name.lexeme}');
    super.visitEnumConstantDeclaration(node);
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final String name = node.namePart.typeName.lexeme;
    _requireDocumentation(node, 'enum $name');
    _checkOrder(node.body.members, name);
    super.visitEnumDeclaration(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _requireDocumentation(node, 'extension ${node.name?.lexeme ?? '<unnamed>'}');
    _checkOrder(node.body.members, node.name?.lexeme ?? '<unnamed>');
    super.visitExtensionDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    _requireDocumentation(node, 'field ${node.fields.variables.map((variable) => variable.name.lexeme).join(', ')}');
    super.visitFieldDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _requireDocumentation(node, 'function ${node.name.lexeme}');
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (!node.metadata.any((annotation) => annotation.name.name == 'override')) {
      _requireDocumentation(node, 'method ${node.name.lexeme}');
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _requireDocumentation(node, 'mixin ${node.name.lexeme}');
    _checkOrder(node.body.members, node.name.lexeme);
    super.visitMixinDeclaration(node);
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    _requireDocumentation(node, 'variable ${node.variables.variables.map((variable) => variable.name.lexeme).join(', ')}');
    super.visitTopLevelVariableDeclaration(node);
  }

  /// Verifies [node] has a Dart documentation comment.
  void _requireDocumentation(AnnotatedNode node, String label) {
    if (node.documentationComment == null && !_hasLexicalDocumentation(node.offset)) {
      issues.add('$path:${_line(node.offset)}: missing documentation for $label');
    }
  }

  /// Recognizes a leading doc comment that the analyzer does not attach to a local declaration.
  bool _hasLexicalDocumentation(int offset) {
    final String preceding = source.substring(0, offset).trimRight();
    if (preceding.endsWith('*/')) {
      final int opening = preceding.lastIndexOf('/**');
      final int closing = preceding.lastIndexOf('*/');
      return opening >= 0 && closing > opening;
    }
    final int lineStart = preceding.lastIndexOf('\n') + 1;
    return preceding.substring(lineStart).trimLeft().startsWith('///');
  }

  /// Verifies [members] never move back from methods to constructors or fields.
  void _checkOrder(NodeList<ClassMember> members, String typeName) {
    int previous = 0;
    for (final ClassMember member in members) {
      final int category = _memberCategory(member);
      if (category < previous) {
        issues.add('$path:${_line(member.offset)}: $typeName must order fields, constructors, then methods');
        return;
      }
      previous = category;
    }
  }

  /// Returns the one-based source line containing [offset].
  int _line(int offset) => '\n'.allMatches(source.substring(0, offset)).length + 1;
}

/// Returns every Dart file beneath the requested files or directories.
List<File> _dartFiles(List<String> paths) {
  final List<File> files = <File>[];
  for (final String path in paths) {
    final FileSystemEntityType type = FileSystemEntity.typeSync(path);
    switch (type) {
      case FileSystemEntityType.file:
        if (path.endsWith('.dart')) {
          files.add(File(path));
        }
      case FileSystemEntityType.directory:
        files.addAll(
          Directory(path).listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart')),
        );
      case FileSystemEntityType.link:
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        break;
    }
  }
  return files;
}

/// Returns zero for fields, one for constructors, and two for methods.
int _memberCategory(ClassMember member) => switch (member) {
  FieldDeclaration() => 0,
  ConstructorDeclaration() => 1,
  _ => 2,
};
