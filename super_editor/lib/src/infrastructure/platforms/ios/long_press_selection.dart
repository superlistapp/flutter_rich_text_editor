import 'package:flutter/rendering.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/default_editor/selection_upstream_downstream.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/default_editor/text_tools.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';

/// A strategy for selecting text during a long-press drag gesture, similar to
/// how iOS selects text during a long-press drag.
///
/// This strategy is made to operate over a document layout.
///
/// This strategy is expected to be identical to iOS. If differences are found,
/// they should be logged as bugs.
class IosLongPressSelectionStrategy {
  IosLongPressSelectionStrategy({
    required Document document,
    required DocumentLayout documentLayout,
    required void Function(DocumentSelection) select,
  })  : _document = document,
        _docLayout = documentLayout,
        _select = select;

  final Document _document;
  final DocumentLayout _docLayout;
  final void Function(DocumentSelection) _select;

  /// The word the user initially selects upon long-pressing.
  DocumentSelection? _longPressInitialSelection;

  /// Clients should call this method when a long press gesture is initially
  /// recognized.
  ///
  /// Returns `true` if a long-press selection started, or `false` if the user's
  /// press didn't occur over selectable content.
  bool onLongPressStart({
    required Offset tapDownDocumentOffset,
  }) {
    longPressSelectionLog.fine("Long press start");
    final docPosition = _docLayout.getDocumentPositionNearestToOffset(tapDownDocumentOffset);
    if (docPosition == null) {
      longPressSelectionLog.finer("No doc position where the user pressed");
      return false;
    }

    if (docPosition.nodePosition is! TextNodePosition) {
      // Select the whole node.
      _longPressInitialSelection = DocumentSelection(
        base: DocumentPosition(
          documentPath: docPosition.documentPath,
          nodePosition: const UpstreamDownstreamNodePosition.upstream(),
        ),
        extent: DocumentPosition(
          documentPath: docPosition.documentPath,
          nodePosition: const UpstreamDownstreamNodePosition.downstream(),
        ),
      );
    } else {
      _longPressInitialSelection = getWordSelection(docPosition: docPosition, docLayout: _docLayout);
    }

    _select(_longPressInitialSelection!);
    return true;
  }

  /// Clients should call this method when an existing long-press gesture first
  /// begins to pan.
  ///
  /// Upon long-press pan movements, clients should call [onLongPressDragUpdate].
  void onLongPressDragStart() {
    longPressSelectionLog.fine("Long press drag start");
  }

  /// Clients should call this method whenever a long-press gesture pans, after
  /// initially calling [onLongPressStart].
  void onLongPressDragUpdate(Offset fingerDocumentOffset, DocumentPosition? fingerDocumentPosition) {
    longPressSelectionLog.finer("--------------------------------------------");
    longPressSelectionLog.fine("Long press drag update");

    if (fingerDocumentPosition == null) {
      return;
    }

    final isOverNonTextNode = fingerDocumentPosition.nodePosition is! TextNodePosition;
    if (isOverNonTextNode) {
      // Don't change selection if the user long-presses over a non-text node and then
      // moves the finger over the same node. This prevents the selection from collapsing
      // when the user moves the finger towards the starting edge of the node.
      if (fingerDocumentPosition.nodeId != _longPressInitialSelection!.base.nodeId) {
        // The user is dragging over content that isn't text, therefore it doesn't have
        // a concept of "words". Select the whole node.
        _select(_longPressInitialSelection!.expandTo(fingerDocumentPosition));
      }
      return;
    }

    // In the case of long-press dragging, we select by word, and the base/extent
    // of the selection depends on whether the user drags upstream or downstream
    // from the originally selected word.
    //
    // Examples:
    //  - one two th|ree four five
    //  - one two [three] four five
    //  - one [two three] four five
    //  - one two [three four] five
    final wordUnderFinger = getWordSelection(docPosition: fingerDocumentPosition, docLayout: _docLayout);
    if (wordUnderFinger == null) {
      // This shouldn't happen. If we've gotten here, the user is selecting over
      // text content but we couldn't find a word selection. The best we can do
      // is fizzle.
      longPressSelectionLog.warning("Long-press selecting. Couldn't find word at position: $fingerDocumentPosition");
      return;
    }

    if (wordUnderFinger == _longPressInitialSelection) {
      // The user is on the original word. Nothing more to do.
      _select(_longPressInitialSelection!);
      return;
    }

    // Figure out whether the newly selected word comes before or after the initially
    // selected word.
    final newWordDirection = _document.getAffinityForSelection(
      DocumentSelection(
        base: wordUnderFinger.start,
        extent: _longPressInitialSelection!.start,
      ),
    );

    late final DocumentSelection newSelection;
    if (newWordDirection == TextAffinity.downstream) {
      // The newly selected word comes before the initially selected word.
      newSelection = DocumentSelection(base: wordUnderFinger.start, extent: _longPressInitialSelection!.end);
    } else {
      // The newly selected word comes after the initially selected word.
      newSelection = DocumentSelection(base: _longPressInitialSelection!.start, extent: wordUnderFinger.end);
    }

    _select(newSelection);
  }

  /// Clients should call this method when a long-press drag ends, or is cancelled.
  void onLongPressEnd() {
    longPressSelectionLog.fine("Long press end");
    _longPressInitialSelection = null;
  }
}
