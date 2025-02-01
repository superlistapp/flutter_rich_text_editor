import 'dart:math';

import 'package:flutter/services.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/composable_text.dart';

/// Collection of generic text inspection behavior that does not belong
/// to any particular `DocumentNode` or `Component`.

final _log = Logger(scope: 'text_tools.dart');

/// Returns the word of text that contains the given `docPosition`, or `null` if
/// no text exists at the given `docPosition`.
///
/// A word is defined by `TextComposable#getWordSelectionAt()`.
DocumentSelection? getWordSelection({
  required DocumentPosition docPosition,
  required DocumentLayout docLayout,
}) {
  _log.log('getWordSelection', '_getWordSelection()');
  _log.log('getWordSelection', ' - doc position: $docPosition');

  final component = docLayout.getComponentByNodeId(docPosition.nodeId);
  if (component is! TextComposable) {
    return null;
  }

  final nodePosition = docPosition.nodePosition;
  if (nodePosition is! TextNodePosition) {
    return null;
  }

  // Create a new TextNodePosition to ensure that we're searching with downstream affinity, for consistent results.
  final searchPosition = TextNodePosition(offset: nodePosition.offset);
  final TextSelection wordTextSelection = (component as TextComposable).getWordSelectionAt(searchPosition);
  final wordNodeSelection = TextNodeSelection.fromTextSelection(wordTextSelection);

  _log.log('getWordSelection', ' - word selection: $wordNodeSelection');
  return DocumentSelection(
    base: DocumentPosition(
      documentPath: docPosition.documentPath,
      nodePosition: wordNodeSelection.base,
    ),
    extent: DocumentPosition(
      documentPath: docPosition.documentPath,
      nodePosition: wordNodeSelection.extent,
    ),
  );
}

/// Expands a selection in both directions starting at [textPosition] until
/// the selection reaches a space, or the end of the available text.
TextSelection expandPositionToWord({
  required String text,
  required TextPosition textPosition,
}) {
  if (text.isEmpty) {
    return const TextSelection.collapsed(offset: -1);
  }

  int start = min(textPosition.offset, text.length);
  int end = min(textPosition.offset, text.length);

  // We're checking for the character before the start index because
  // TextPosition's offset indexes the character after the caret
  while (start > 0 && text[start - 1] != ' ') {
    start -= 1;
  }
  while (end < text.length && text[end] != ' ') {
    end += 1;
  }
  return TextSelection(
    baseOffset: start,
    extentOffset: end,
  );
}

/// Returns the paragraph of text that contains the given `docPosition`, or `null`
/// if there is no text at the given `docPosition`.
///
/// A paragraph is defined as all text within the given document node, bounded by
/// newlines or the beginning/end of the node's text.
DocumentSelection? getParagraphSelection({
  required DocumentPosition docPosition,
  required DocumentLayout docLayout,
}) {
  _log.log('getParagraphSelection', '_getWordSelection()');
  _log.log('getParagraphSelection', ' - doc position: $docPosition');

  final component = docLayout.getComponentByNodeId(docPosition.nodeId);
  if (component is! TextComposable) {
    return null;
  }

  final nodePosition = docPosition.nodePosition;
  if (nodePosition is! TextNodePosition) {
    return null;
  }

  final paragraphNodeSelection = (component as TextComposable).getContiguousTextSelectionAt(nodePosition);

  return DocumentSelection(
    base: DocumentPosition(
      documentPath: docPosition.documentPath,
      nodePosition: paragraphNodeSelection.base,
    ),
    extent: DocumentPosition(
      documentPath: docPosition.documentPath,
      nodePosition: paragraphNodeSelection.extent,
    ),
  );
}

/// Expands a selection in both directions starting at [textPosition] until
/// the selection reaches a newline, or the end of the available text.
TextSelection expandPositionToParagraph({
  required String text,
  required TextPosition textPosition,
}) {
  if (text.isEmpty) {
    return const TextSelection.collapsed(offset: -1);
  }

  int start = min(textPosition.offset, text.length - 1);
  int end = min(textPosition.offset, text.length - 1);
  while (start > 0 && text[start - 1] != '\n') {
    start -= 1;
  }
  while (end < text.length && text[end] != '\n') {
    end += 1;
  }
  return TextSelection(
    baseOffset: start,
    extentOffset: end,
  );
}

// copied from: flutter/lib/src/widgets/editable_text.dart
// RTL covers Arabic, Hebrew, and other RTL languages such as Urdu,
// Aramic, Farsi, Dhivehi.
final RegExp _rtlRegExp = RegExp(r'[\u0591-\u07FF\uFB1D-\uFDFD\uFE70-\uFEFC]');

/// Returns the [TextDirection] of the text based on its first non-whitespace character.
///
/// The default value is [TextDirection.ltr] for any character that is not from an RTL language.
TextDirection getParagraphDirection(String text) {
  text = text.trim();

  if (text.isNotEmpty && _rtlRegExp.hasMatch(String.fromCharCode(text.runes.first))) {
    return TextDirection.rtl;
  } else {
    return TextDirection.ltr;
  }
}
