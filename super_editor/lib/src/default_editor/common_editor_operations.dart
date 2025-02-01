import 'dart:math';
import 'dart:ui';

import 'package:attributed_text/attributed_text.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:linkify/linkify.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/default_editor/box_component.dart';
import 'package:super_editor/src/default_editor/default_document_editor_reactions.dart';
import 'package:super_editor/src/default_editor/list_items.dart';
import 'package:super_editor/src/default_editor/paragraph.dart';
import 'package:super_editor/src/default_editor/selection_upstream_downstream.dart';
import 'package:super_editor/src/default_editor/tasks.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';

import 'attributions.dart';
import 'horizontal_rule.dart';
import 'image.dart';
import 'multi_node_editing.dart';
import 'text_tools.dart';

/// Performs common, high-level editing and composition tasks
/// with a simplified API.
///
/// [CommonEditorOperations] is intended to provide a simple and
/// easy to use API for common tasks; it is not intended to operate
/// as a fundamental document manipulation tool. [CommonEditorOperations]
/// is built on top of [DocumentEditor], [DocumentLayout], and
/// [DocumentComposer]. Use those core artifacts to implement any
/// operations that are not supported by [CommonEditorOperations].
///
/// If you implement operations for your editor that are not provided
/// by [CommonEditorOperations], consider implementing those operations
/// as extension methods on top of [CommonEditorOperations] so that the
/// rest of your editor can use those behaviors as if they were
/// implemented within [CommonEditorOperations].
class CommonEditorOperations {
  CommonEditorOperations({
    required this.document,
    required this.editor,
    required this.composer,
    required this.documentLayoutResolver,
  });

  // Marked as protected for extension methods and subclasses
  @protected
  final Document document;
  // Marked as protected for extension methods and subclasses
  @protected
  final Editor editor;
  // Marked as protected for extension methods and subclasses
  @protected
  final DocumentComposer composer;
  // Marked as protected for extension methods and subclasses
  @protected
  final DocumentLayoutResolver documentLayoutResolver;

  /// Clears the [DocumentComposer]'s current selection and sets
  /// the selection to the given collapsed [documentPosition].
  ///
  /// Returns [true] if the selection was set to the given [documentPosition],
  /// or [false] if the given [documentPosition] could not be
  /// resolved to a location within the [Document].
  bool insertCaretAtPosition(DocumentPosition documentPosition) {
    if (document.getNodeById(documentPosition.documentPath.targetNodeId) == null) {
      return false;
    }

    editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(position: documentPosition),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);

    return true;
  }

  /// Locates the [DocumentPosition] at the given [documentOffset] and
  /// sets the [DocumentComposer]'s selection to that collapsed position.
  ///
  /// If [findNearestPosition] is [true] (the default), then the [DocumentPosition]
  /// nearest the given [documentOffset] is used. If [findNearestPosition] is
  /// [false] then the selection is only changed if the given [documentOffset]
  /// sits directly on top of a valid [DocumentPosition], e.g., within the
  /// bounding box of a line of text, or within the bounds of an image.
  ///
  /// Returns [true] if the selection is set based on the given [documentOffset],
  /// or [false] if no relevant [DocumentPosition could be located.
  bool insertCaretAtOffset(
    Offset documentOffset, {
    findNearestPosition = true,
  }) {
    DocumentPosition? position;
    if (findNearestPosition) {
      position = documentLayoutResolver().getDocumentPositionNearestToOffset(documentOffset);
    } else {
      position = documentLayoutResolver().getDocumentPositionAtOffset(documentOffset);
    }

    if (position != null) {
      editor.execute([
        ChangeSelectionRequest(
          DocumentSelection.collapsed(position: position),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);

      return true;
    } else {
      return false;
    }
  }

  /// Sets the [DocumentComposer]'s selection to a [DocumentSelection]
  /// that spans from [baseDocumentPosition] to [extentDocumentPosition]
  /// with the selection direction going from the base position to the
  /// extent position.
  ///
  /// Returns [true] if the selection is successfully changed. Returns
  /// [false] if either [DocumentPosition] could not be mapped to locations
  /// within the [Document], and therefore the selection could not be set.
  bool selectRegion({
    required DocumentPosition baseDocumentPosition,
    required DocumentPosition extentDocumentPosition,
  }) {
    if (document.getNodeById(baseDocumentPosition.documentPath.targetNodeId) == null) {
      return false;
    }
    if (document.getNodeById(extentDocumentPosition.documentPath.targetNodeId) == null) {
      return false;
    }

    editor.execute([
      ChangeSelectionRequest(
        DocumentSelection(
          base: baseDocumentPosition,
          extent: extentDocumentPosition,
        ),
        SelectionChangeType.expandSelection,
        SelectionReason.userInteraction,
      ),
    ]);

    return true;
  }

  /// Given a collapsed selection in a [TextNode], expands the
  /// [DocumentComposer]'s selection to include the entire word in
  /// which the current selection sits.
  ///
  /// Returns [true] if a word was selected. Returns [false] if no
  /// selection could be computed, e.g., the selection was not collapsed,
  /// the selection was not in a [TextNode].
  bool selectSurroundingWord() {
    if (composer.selection == null) {
      return false;
    }
    if (composer.selection!.base.documentPath != composer.selection!.extent.documentPath) {
      return false;
    }

    final selectedNode = document.getNodeById(composer.selection!.extent.documentPath.targetNodeId);
    if (selectedNode is! TextNode) {
      return false;
    }

    final docSelection = composer.selection!;
    final currentSelection = TextSelection(
      baseOffset: (docSelection.base.nodePosition as TextNodePosition).offset,
      extentOffset: (docSelection.extent.nodePosition as TextNodePosition).offset,
    );
    final selectedText = currentSelection.textInside(selectedNode.text.toPlainText());

    if (selectedText.contains(' ')) {
      // The selection already spans multiple paragraphs. Nothing to do.
      return false;
    }

    final wordTextSelection = expandPositionToWord(
      text: selectedNode.text.toPlainText(),
      textPosition: TextPosition(offset: (docSelection.extent.nodePosition as TextNodePosition).offset),
    );
    final wordNodeSelection = TextNodeSelection.fromTextSelection(wordTextSelection);

    editor.execute([
      ChangeSelectionRequest(
        selectedNode.selectionBetween(
          docSelection.extent.documentPath,
          wordNodeSelection.baseOffset,
          wordNodeSelection.extentOffset,
        ),
        SelectionChangeType.expandSelection,
        SelectionReason.userInteraction,
      ),
    ]);

    return true;
  }

  /// Sets the [DocumentComposer]'s selection to include the entire
  /// [Document].
  ///
  /// Always returns [true].
  bool selectAll() {
    if (document.isEmpty) {
      return false;
    }

    editor.execute([
      ChangeSelectionRequest(
        document.selectAll(),
        SelectionChangeType.expandSelection,
        SelectionReason.userInteraction,
      ),
    ]);

    return true;
  }

  /// Collapses the [DocumentComposer]'s selection at the current
  /// extent [DocumentPosition].
  ///
  /// Returns [true] if the selection was collapsed, or [false] if
  /// there was no selection to collapse.
  bool collapseSelection() {
    if (composer.selection == null) {
      return false;
    }

    editor.execute([
      ChangeSelectionRequest(
        composer.selection!.collapse(),
        SelectionChangeType.collapseSelection,
        SelectionReason.userInteraction,
      ),
    ]);

    return true;
  }

  /// Moves the [DocumentComposer]'s selection extent position in the
  /// upstream direction (to the left for left-to-right languages).
  ///
  /// {@template skip_unselectable_components}
  /// This selection movement skips any node whose visual component is
  /// not visually selectable, e.g., a horizontal rule that doesn't
  /// change it's visual state when it's selected.
  /// {@endtemplate}
  ///
  /// Expands/contracts the selection if [expand] is `true`, otherwise
  /// collapses the selection or keeps it collapsed.
  ///
  /// By default, moves one character at a time when the extent sits in
  /// a [TextNode]. To move word-by-word, pass [MovementModifier.word]
  /// in [movementModifier]. To move to the beginning of a line, pass
  /// [MovementModifier.line] in [movementModifier].
  ///
  /// Returns [true] if the extent moved, or the selection changed, e.g., the
  /// selection collapsed but the extent stayed in the same place. Returns
  /// [false] if the extent did not move and the selection did not change.
  bool moveCaretUpstream({
    bool expand = false,
    MovementModifier? movementModifier,
  }) {
    if (composer.selection == null) {
      return false;
    }

    if (!composer.selection!.isCollapsed && !expand) {
      editor.execute([
        ChangeSelectionRequest(
          composer.selection!.collapseUpstream(document),
          SelectionChangeType.collapseSelection,
          SelectionReason.userInteraction,
        ),
      ]);

      return true;
    }

    final currentExtent = composer.selection!.extent;
    final nodeId = currentExtent.documentPath.targetNodeId;
    final node = document.getNodeById(nodeId);
    if (node == null) {
      return false;
    }
    final extentComponent = documentLayoutResolver().getComponentByNodeId(nodeId);
    if (extentComponent == null) {
      return false;
    }

    String newExtentNodeId = nodeId;
    NodePosition? newExtentNodePosition =
        extentComponent.movePositionLeft(currentExtent.nodePosition, movementModifier);

    if (newExtentNodePosition == null) {
      if (movementModifier == MovementModifier.line) {
        // The user is trying to move to the beginning of the current line,
        // and we're already there. Do nothing.
        return false;
      }

      // Move to next node
      final nextNode = _getUpstreamSelectableNodeBefore(node);

      if (nextNode == null) {
        // We're at the beginning of the document and can't go anywhere.
        return false;
      }

      newExtentNodeId = nextNode.id;
      final nextComponent = documentLayoutResolver().getComponentByNodeId(nextNode.id);
      if (nextComponent == null) {
        return false;
      }
      newExtentNodePosition = nextComponent.getEndPosition();
    }

    final newExtent = DocumentPosition(
      documentPath: document.getPathByNodeId(newExtentNodeId)!,
      nodePosition: newExtentNodePosition,
    );

    if (expand) {
      // Push the extent of an expanded selection.
      editor.execute([
        ChangeSelectionRequest(
          composer.selection!.expandTo(
            newExtent,
          ),
          SelectionChangeType.pushExtent,
          SelectionReason.userInteraction,
        ),
      ]);
    } else {
      // Push the caret upstream.
      editor.execute([
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: newExtent,
          ),
          SelectionChangeType.pushCaret,
          SelectionReason.userInteraction,
        ),
      ]);
    }

    return true;
  }

  /// Moves the [DocumentComposer]'s selection extent position in the
  /// downstream direction (to the right for left-to-right languages).
  ///
  /// {@macro skip_unselectable_components}
  ///
  /// Expands/contracts the selection if [expand] is [true], otherwise
  /// collapses the selection or keeps it collapsed.
  ///
  /// By default, moves one character at a time when the extent sits in
  /// a [TextNode]. To move word-by-word, pass [MovementModifier.word]
  /// in [movementModifier]. To move to the end of a line, pass
  /// [MovementModifier.line] in [movementModifier].
  ///
  /// Returns [true] if the extent moved, or the selection changed, e.g., the
  /// selection collapsed but the extent stayed in the same place. Returns
  /// [false] if the extent did not move and the selection did not change.
  bool moveCaretDownstream({
    bool expand = false,
    MovementModifier? movementModifier,
  }) {
    if (composer.selection == null) {
      return false;
    }

    if (!composer.selection!.isCollapsed && !expand) {
      editor.execute([
        ChangeSelectionRequest(
          composer.selection!.collapseDownstream(document),
          SelectionChangeType.collapseSelection,
          SelectionReason.userInteraction,
        ),
      ]);

      return true;
    }

    final currentExtent = composer.selection!.extent;
    final nodeId = currentExtent.targetNodeId;
    final node = document.getNodeById(nodeId);
    if (node == null) {
      return false;
    }
    final extentComponent = documentLayoutResolver().getComponentByNodeId(nodeId);
    if (extentComponent == null) {
      return false;
    }

    String newExtentNodeId = nodeId;
    NodePosition? newExtentNodePosition =
        extentComponent.movePositionRight(currentExtent.nodePosition, movementModifier);

    if (newExtentNodePosition == null) {
      if (movementModifier == MovementModifier.line) {
        // The user is trying to move to the end of the current line,
        // and we're already there. Do nothing.
        return false;
      }

      // Move to next node
      final nextNode = _getDownstreamSelectableNodeAfter(node);

      if (nextNode == null) {
        // We're at the beginning/end of the document and can't go
        // anywhere.
        return false;
      }

      newExtentNodeId = nextNode.id;
      final nextComponent = documentLayoutResolver().getComponentByNodeId(nextNode.id);
      if (nextComponent == null) {
        throw Exception(
            'Could not find next component to move the selection horizontally. Next node ID: ${nextNode.id}');
      }
      print("Next component: $nextComponent, beginning position: ${nextComponent.getBeginningPosition()}");
      newExtentNodePosition = nextComponent.getBeginningPosition();
    }

    final newExtent = DocumentPosition(
      documentPath: document.getPathByNodeId(newExtentNodeId)!,
      nodePosition: newExtentNodePosition,
    );

    if (expand) {
      // Push the extent of an expanded selection downstream.
      editor.execute([
        ChangeSelectionRequest(
          composer.selection!.expandTo(
            newExtent,
          ),
          SelectionChangeType.pushExtent,
          SelectionReason.userInteraction,
        ),
      ]);
    } else {
      // Push the caret downstream.
      editor.execute([
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: newExtent,
          ),
          SelectionChangeType.pushCaret,
          SelectionReason.userInteraction,
        ),
      ]);
    }

    return true;
  }

  /// Moves the [DocumentComposer]'s selection extent position up,
  /// vertically, either by moving the selection extent up one line of
  /// text, or by moving the selection extent up to the node above the
  /// current extent.
  ///
  /// If the current selection extent wants to move to the node above,
  /// but there is no node above the current extent, the extent is moved
  /// to the "start" position of the current node. For example: the extent
  /// moves from the middle of the first line of text in a paragraph to
  /// the beginning of the paragraph.
  ///
  /// {@macro skip_unselectable_components}
  ///
  /// Expands/contracts the selection if [expand] is [true], otherwise
  /// collapses the selection or keeps it collapsed.
  ///
  /// Returns [true] if the extent moved, or the selection changed, e.g., the
  /// selection collapsed but the extent stayed in the same place. Returns
  /// [false] if the extent did not move and the selection did not change.
  bool moveCaretUp({
    bool expand = false,
  }) {
    if (composer.selection == null) {
      return false;
    }

    final currentExtent = composer.selection!.extent;
    final nodeId = currentExtent.targetNodeId;
    final node = document.getNodeById(nodeId);
    if (node == null) {
      return false;
    }
    final extentComponent = documentLayoutResolver().getComponentByNodeId(nodeId);
    if (extentComponent == null) {
      return false;
    }

    String newExtentNodeId = nodeId;
    NodePosition? newExtentNodePosition = extentComponent.movePositionUp(currentExtent.nodePosition);

    if (newExtentNodePosition == null) {
      // Move to next node
      final nextNode = _getUpstreamSelectableNodeBefore(node);
      if (nextNode != null) {
        newExtentNodeId = nextNode.id;
        final nextComponent = documentLayoutResolver().getComponentByNodeId(nextNode.id);
        if (nextComponent == null) {
          editorOpsLog.shout("Tried to obtain non-existent component by node id: $newExtentNodeId");
          return false;
        }
        final offsetToMatch = extentComponent.getOffsetForPosition(currentExtent.nodePosition);
        newExtentNodePosition = nextComponent.getEndPositionNearX(offsetToMatch.dx);
      } else {
        // We're at the top of the document. Move the cursor to the
        // beginning of the current node.
        newExtentNodePosition = extentComponent.getBeginningPosition();
      }
    }

    final newExtent = DocumentPosition(
      documentPath: document.getPathByNodeId(newExtentNodeId)!,
      nodePosition: newExtentNodePosition,
    );

    _updateSelectionExtent(position: newExtent, expandSelection: expand);

    return true;
  }

  /// Moves the [DocumentComposer]'s selection extent position down,
  /// vertically, either by moving the selection extent down one line of
  /// text, or by moving the selection extent down to the node below the
  /// current extent.
  ///
  /// If the current selection extent wants to move to the node below,
  /// but there is no node below the current extent, the extent is moved
  /// to the "end" position of the current node. For example: the extent
  /// moves from the middle of the last line of text in a paragraph to
  /// the end of the paragraph.
  ///
  /// {@macro skip_unselectable_components}
  ///
  /// Expands/contracts the selection if [expand] is [true], otherwise
  /// collapses the selection or keeps it collapsed.
  ///
  /// Returns [true] if the extent moved, or the selection changed, e.g., the
  /// selection collapsed but the extent stayed in the same place. Returns
  /// [false] if the extent did not move and the selection did not change.
  bool moveCaretDown({
    bool expand = false,
  }) {
    if (composer.selection == null) {
      return false;
    }

    final currentExtent = composer.selection!.extent;
    final nodeId = currentExtent.targetNodeId;
    final node = document.getNodeById(nodeId);
    if (node == null) {
      return false;
    }
    final extentComponent = documentLayoutResolver().getComponentByNodeId(nodeId);
    if (extentComponent == null) {
      return false;
    }

    String newExtentNodeId = nodeId;
    NodePosition? newExtentNodePosition = extentComponent.movePositionDown(currentExtent.nodePosition);

    if (newExtentNodePosition == null) {
      // Move to next node
      final nextNode = _getDownstreamSelectableNodeAfter(node);
      if (nextNode != null) {
        newExtentNodeId = nextNode.id;
        final nextComponent = documentLayoutResolver().getComponentByNodeId(nextNode.id);
        if (nextComponent == null) {
          editorOpsLog.shout("Tried to obtain non-existent component by node id: $newExtentNodeId");
          return false;
        }
        final offsetToMatch = extentComponent.getOffsetForPosition(currentExtent.nodePosition);
        newExtentNodePosition = nextComponent.getBeginningPositionNearX(offsetToMatch.dx);
      } else {
        // We're at the bottom of the document. Move the cursor to the
        // end of the current node.
        newExtentNodePosition = extentComponent.getEndPosition();
      }
    }

    final newExtent = DocumentPosition(
      documentPath: document.getPathByNodeId(newExtentNodeId)!,
      nodePosition: newExtentNodePosition,
    );

    _updateSelectionExtent(position: newExtent, expandSelection: expand);

    return true;
  }

  /// Moves the [DocumentComposer]'s selection to the nearest node to [startingNode],
  /// whose [DocumentComponent] is visually selectable.
  ///
  /// Expands the selection if [expand] is `true`, otherwise collapses the selection.
  ///
  /// If a downstream selectable node if found, it will be used, otherwise,
  /// a upstream selectable node will be searched.
  ///
  /// If a selectable node is found, the selection will move to its beginning.
  /// If no selectable node is found, the selection will remain unchanged.
  ///
  /// Returns `true` if the selection is moved and `false` otherwise, e.g., there
  /// are no selectable nodes in the document.
  bool moveSelectionToNearestSelectableNode(
    DocumentNode startingNode, {
    bool expand = false,
  }) {
    String? newNodeId;
    NodePosition? newPosition;

    // Try to find a new selection downstream.
    final downstreamNode = _getDownstreamSelectableNodeAfter(startingNode);
    if (downstreamNode != null) {
      newNodeId = downstreamNode.id;
      final nextComponent = documentLayoutResolver().getComponentByNodeId(newNodeId);
      newPosition = nextComponent?.getBeginningPosition();
    }

    // Try to find a new selection upstream.
    if (newPosition == null) {
      final upstreamNode = _getUpstreamSelectableNodeBefore(startingNode);
      if (upstreamNode != null) {
        newNodeId = upstreamNode.id;
        final previousComponent = documentLayoutResolver().getComponentByNodeId(newNodeId);
        newPosition = previousComponent?.getBeginningPosition();
      }
    }

    if (newNodeId == null || newPosition == null) {
      return false;
    }

    final newExtent = DocumentPosition(
      documentPath: document.getPathByNodeId(newNodeId)!,
      nodePosition: newPosition,
    );
    _updateSelectionExtent(position: newExtent, expandSelection: expand);

    return true;
  }

  /// Moves the [DocumentComposer]'s selection extent to the beginning of the document.
  ///
  /// Expands/contracts the selection if [expand] is `true`, otherwise
  /// collapses the selection or keeps it collapsed.
  ///
  /// Returns `true` if the extent moved, or the selection changed, e.g., the
  /// selection collapsed but the extent stayed in the same place. Returns
  /// `false` if the extent did not move and the selection did not change.
  bool moveSelectionToBeginningOfDocument({
    bool expand = false,
  }) {
    if (composer.selection == null) {
      return false;
    }

    if (document.isEmpty) {
      return false;
    }

    // FIXME: Now that we have a tree document, what is the "beginning"?
    final firstNode = document.first;
    final firstNodePath = document.getPathByNodeId(firstNode.id)!;

    if (expand) {
      final currentExtentNode = document.getNodeById(composer.selection!.extent.targetNodeId);
      if (currentExtentNode == null) {
        return false;
      }

      if (currentExtentNode is! TextNode) {
        return false;
      }

      editor.execute([
        ChangeSelectionRequest(
          DocumentSelection(
            base: composer.selection!.base,
            extent: DocumentPosition(
              documentPath: firstNodePath,
              nodePosition: firstNode.beginningPosition,
            ),
          ),
          SelectionChangeType.expandSelection,
          SelectionReason.userInteraction,
        ),
      ]);

      return true;
    }

    editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: firstNodePath,
            nodePosition: firstNode.beginningPosition,
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);

    return true;
  }

  /// Moves the [DocumentComposer]'s selection extent to the end of the document.
  ///
  /// Expands/contracts the selection if [expand] is `true`, otherwise
  /// collapses the selection or keeps it collapsed.
  ///
  /// Returns `true` if the extent moved, or the selection changed, e.g., the
  /// selection collapsed but the extent stayed in the same place. Returns
  /// `false` if the extent did not move and the selection did not change.
  bool moveSelectionToEndOfDocument({
    bool expand = false,
  }) {
    if (composer.selection == null) {
      return false;
    }

    if (document.isEmpty) {
      return false;
    }

    // FIXME: Now that we have a tree document, what is the "end"?
    final lastNode = document.last;
    final lastNodePath = document.getPathByNodeId(lastNode.id)!;

    if (expand) {
      final currentExtentNode = document.getNodeById(composer.selection!.extent.targetNodeId);
      if (currentExtentNode == null) {
        return false;
      }

      if (currentExtentNode is! TextNode) {
        return false;
      }

      editor.execute([
        ChangeSelectionRequest(
          // FIXME: Change this to something like `document.end`
          DocumentSelection(
            base: composer.selection!.base,
            extent: DocumentPosition(
              documentPath: lastNodePath,
              nodePosition: lastNode.endPosition,
            ),
          ),
          SelectionChangeType.expandSelection,
          SelectionReason.userInteraction,
        ),
      ]);

      return true;
    }

    editor.execute([
      ChangeSelectionRequest(
        // FIXME: Change this to something like `document.end`
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: lastNodePath,
            nodePosition: lastNode.endPosition,
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);

    return true;
  }

  void _updateSelectionExtent({
    required DocumentPosition position,
    required bool expandSelection,
  }) {
    if (expandSelection) {
      // Selection should be expanded.
      editor.execute([
        ChangeSelectionRequest(
          composer.selection!.expandTo(position),
          SelectionChangeType.expandSelection,
          SelectionReason.userInteraction,
        ),
      ]);
    } else {
      // Selection should be replaced by new collapsed position.
      editor.execute([
        ChangeSelectionRequest(
          DocumentSelection.collapsed(position: position),
          SelectionChangeType.collapseSelection,
          SelectionReason.userInteraction,
        ),
      ]);
    }
  }

  /// Returns the first [DocumentNode] before [startingNode] whose
  /// [DocumentComponent] is visually selectable.
  DocumentNode? _getUpstreamSelectableNodeBefore(DocumentNode startingNode) {
    bool foundSelectableNode = false;
    DocumentNode prevNode = startingNode;
    DocumentNode? selectableNode;
    do {
      selectableNode = document.getNodeBeforeById(prevNode.id);

      if (selectableNode != null) {
        final nextComponent = documentLayoutResolver().getComponentByNodeId(selectableNode.id);
        if (nextComponent != null) {
          foundSelectableNode = nextComponent.isVisualSelectionSupported();
        }
        prevNode = selectableNode;
      }
    } while (!foundSelectableNode && selectableNode != null);

    return selectableNode;
  }

  /// Returns the first [DocumentNode] after [startingNode] whose
  /// [DocumentComponent] is visually selectable.
  DocumentNode? _getDownstreamSelectableNodeAfter(DocumentNode startingNode) {
    bool foundSelectableNode = false;
    DocumentNode prevNode = startingNode;
    DocumentNode? selectableNode;
    do {
      selectableNode = document.getNodeAfterById(prevNode.id);

      if (selectableNode != null) {
        final nextComponent = documentLayoutResolver().getComponentByNodeId(selectableNode.id);
        if (nextComponent != null) {
          foundSelectableNode = nextComponent.isVisualSelectionSupported();
        }
        prevNode = selectableNode;
      }
    } while (!foundSelectableNode && selectableNode != null);

    return selectableNode;
  }

  /// Deletes a unit of content that comes after the [DocumentComposer]'s
  /// selection extent, or deletes all selected content if the selection
  /// is not collapsed.
  ///
  /// In the case of text editing, deletes the character that appears after
  /// the caret.
  ///
  /// If the caret sits at the end of a content block, such as the end of
  /// a text node, and the next node is not visually selectable, then the
  /// next node is deleted and the caret is kept where it is.
  ///
  /// Returns [true] if content was deleted, or [false] if no downstream
  /// content exists.
  bool deleteDownstream() {
    if (composer.selection == null) {
      return false;
    }

    if (!composer.selection!.isCollapsed) {
      // A span of content is selected. Delete the selection.
      _deleteExpandedSelection(TextAffinity.downstream);
      return true;
    }

    if (composer.selection!.extent.nodePosition is UpstreamDownstreamNodePosition) {
      final nodePosition = composer.selection!.extent.nodePosition as UpstreamDownstreamNodePosition;
      if (nodePosition.affinity == TextAffinity.upstream) {
        // The caret is sitting on the upstream edge of block-level content.
        final nodeId = composer.selection!.extent.targetNodeId;

        if (!document.getNodeById(nodeId)!.isDeletable) {
          // The node is not deletable. Fizzle.
          return false;
        }

        //Delete the whole block by replacing it with an empty paragraph.
        replaceBlockNodeWithEmptyParagraphAndCollapsedSelection(nodeId);

        return true;
      } else {
        // The caret is sitting on the downstream edge of block-level content and
        // the user is trying to delete downstream. It's not obvious what should
        // happen in this situation. Super Editor chooses to move the caret to
        // the next node and to not delete anything.
        return _moveSelectionToBeginningOfNextNode();
      }
    }

    if (composer.selection!.extent.nodePosition is TextNodePosition) {
      final textPosition = composer.selection!.extent.nodePosition as TextNodePosition;
      final text = (document.getNodeById(composer.selection!.extent.targetNodeId) as TextNode).text;
      if (textPosition.offset == text.length) {
        final node = document.getNodeById(composer.selection!.extent.targetNodeId)!;
        final nodeAfter = document.getNodeAfterById(node.id);

        if (nodeAfter is TextNode) {
          // The caret is at the end of one TextNode and is followed by
          // another TextNode. Merge the two TextNodes.
          return _mergeTextNodeWithDownstreamTextNode();
        } else if (nodeAfter != null) {
          final componentAfter = documentLayoutResolver().getComponentByNodeId(nodeAfter.id)!;

          if (nodeAfter is BlockNode && !nodeAfter.isDeletable) {
            // The user is trying to delete at the end of a node, and the downstream node
            // is not deletable. Skip the non-deletable node and try to merge the selected
            // node with the next non-deletable node.
            return _mergeTextNodeWithDownstreamTextNode();
          } else if (componentAfter.isVisualSelectionSupported()) {
            // The caret is at the end of a TextNode, but the next node
            // is not a TextNode. Move the document selection to the
            // next node.
            return _moveSelectionToBeginningOfNextNode();
          } else {
            // The next node/component isn't selectable. Delete it.
            deleteNonSelectedNode(nodeAfter);
            return true;
          }
        }
      } else {
        return _deleteDownstreamCharacter();
      }
    }

    return false;
  }

  bool _moveSelectionToBeginningOfNextNode() {
    if (composer.selection == null) {
      return false;
    }

    final node = document.getNodeById(composer.selection!.extent.targetNodeId);
    if (node == null) {
      return false;
    }

    final nodeAfter = document.getNodeAfterById(node.id);
    if (nodeAfter == null) {
      return false;
    }

    editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: document.getPathByNodeId(nodeAfter.id)!,
            nodePosition: nodeAfter.beginningPosition,
          ),
        ),
        SelectionChangeType.pushCaret,
        SelectionReason.userInteraction,
      ),
    ]);

    return true;
  }

  bool _mergeTextNodeWithDownstreamTextNode() {
    final node = document.getNodeById(composer.selection!.extent.targetNodeId);
    if (node == null) {
      return false;
    }
    if (node is! TextNode) {
      return false;
    }

    DocumentNode? nodeAfter = document.getNodeAfterById(node.id);
    while (nodeAfter is BlockNode && !nodeAfter.isDeletable) {
      nodeAfter = document.getNodeAfterById(nodeAfter.id);
    }

    if (nodeAfter == null) {
      return false;
    }
    if (nodeAfter is! TextNode) {
      return false;
    }

    final firstNodeTextLength = node.text.length;

    // Send edit command.
    editor.execute([
      CombineParagraphsRequest(
        firstNodeId: node.id,
        secondNodeId: nodeAfter.id,
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: document.getPathByNodeId(node.id)!,
            nodePosition: TextNodePosition(offset: firstNodeTextLength),
          ),
        ),
        SelectionChangeType.deleteContent,
        SelectionReason.userInteraction,
      ),
    ]);

    return true;
  }

  bool _deleteDownstreamCharacter() {
    if (composer.selection == null) {
      return false;
    }
    if (!_isTextEntryNode(document: document, selection: composer.selection!)) {
      return false;
    }
    if (composer.selection!.isCollapsed && (composer.selection!.extent.nodePosition as TextNodePosition).offset < 0) {
      return false;
    }

    final textNode = document.getNode(composer.selection!.extent) as TextNode;
    final text = textNode.text;
    final currentTextOffset = (composer.selection!.extent.nodePosition as TextNodePosition).offset;
    if (currentTextOffset >= text.length) {
      return false;
    }

    final nextCharacterOffset = getCharacterEndBounds(text.toPlainText(), currentTextOffset);

    // Delete the selected content.
    editor.execute([
      DeleteContentRequest(
        documentRange: textNode.selectionBetween(
          composer.selection!.extent.documentPath,
          currentTextOffset,
          nextCharacterOffset,
        ),
      ),
    ]);

    return true;
  }

  /// Deletes a unit of content that comes before the [DocumentComposer]'s
  /// selection extent, or deletes all selected content if the selection
  /// is not collapsed.
  ///
  /// In the case of text editing, deletes the character that appears before
  /// the caret.
  ///
  /// If the caret sits at the beginning of a content block, such as the
  /// beginning of a text node, and the upstream node is not visually selectable,
  /// then the upstream node is deleted and the caret is kept where it is.
  ///
  /// Returns [true] if content was deleted, or [false] if no upstream
  /// content exists.
  bool deleteUpstream() {
    if (composer.selection == null) {
      return false;
    }

    if (!composer.selection!.isCollapsed) {
      // A span of content is selected. Delete the selection.
      _deleteExpandedSelection(TextAffinity.upstream);
      return true;
    }

    final node = document.getNodeById(composer.selection!.extent.targetNodeId)!;

    // If the caret is at the beginning of a list item, unindent the list item.
    if (node is ListItemNode && (composer.selection!.extent.nodePosition as TextNodePosition).offset == 0) {
      return unindentListItem();
    }

    if (composer.selection!.extent.nodePosition is UpstreamDownstreamNodePosition) {
      final nodePosition = composer.selection!.extent.nodePosition as UpstreamDownstreamNodePosition;
      if (nodePosition.affinity == TextAffinity.downstream) {
        // The caret is sitting on the downstream edge of block-level content.
        final nodeId = composer.selection!.extent.targetNodeId;

        if (!document.getNodeById(nodeId)!.isDeletable) {
          // The node is not deletable. Fizzle.
          return false;
        }

        // Delete the whole block by replacing it with an empty paragraph.
        replaceBlockNodeWithEmptyParagraphAndCollapsedSelection(nodeId);

        return true;
      } else {
        // The caret is sitting on the upstream edge of block-level content and
        // the user is trying to delete upstream.
        //  * If the node above is an empty paragraph, delete it.
        //  * If the node above is non-selectable, delete it.
        //  * Otherwise, move the caret up to the node above.
        final nodeBefore = document.getNodeBeforeById(node.id);
        if (nodeBefore == null) {
          return false;
        }

        final componentBefore = documentLayoutResolver().getComponentByNodeId(nodeBefore.id)!;

        if (nodeBefore is TextNode && nodeBefore.text.isEmpty) {
          editor.execute([
            DeleteNodeRequest(nodeId: nodeBefore.id),
          ]);
          return true;
        }

        if (!componentBefore.isVisualSelectionSupported() && nodeBefore.isDeletable) {
          // The node/component above is not selectable. Delete it.
          deleteNonSelectedNode(nodeBefore);
          return true;
        }

        return _moveSelectionToEndOfFirstSelectableUpstreamNode();
      }
    }

    if (composer.selection!.extent.nodePosition is TextNodePosition) {
      final textPosition = composer.selection!.extent.nodePosition as TextNodePosition;
      if (textPosition.offset == 0) {
        final nodeBefore = document.getNodeBeforeById(node.id);
        if (nodeBefore == null) {
          return false;
        }

        final componentBefore = documentLayoutResolver().getComponentByNodeId(nodeBefore.id)!;

        if (nodeBefore is TextNode) {
          // The caret is at the beginning of one TextNode and is preceded by
          // another TextNode. Merge the two TextNodes.
          return mergeTextNodeWithUpstreamTextNode();
        } else if (nodeBefore is BlockNode && !nodeBefore.isDeletable) {
          return mergeTextNodeWithUpstreamTextNode();
        } else if (!componentBefore.isVisualSelectionSupported()) {
          // The node/component above is not selectable. Delete it.
          deleteNonSelectedNode(nodeBefore);
          return true;
        } else if ((node as TextNode).text.isEmpty) {
          // The caret is at the beginning of an empty TextNode and the preceding
          // node is not a TextNode. Delete the current TextNode and move the
          // selection up to the preceding node if exist.
          if (moveSelectionToEndOfPrecedingNode()) {
            editor.execute([
              DeleteNodeRequest(nodeId: node.id),
            ]);
          }
          return true;
        } else {
          // The caret is at the beginning of a non-empty TextNode, and the
          // preceding node is not a TextNode. Move the document selection to the
          // preceding node.
          return moveSelectionToEndOfPrecedingNode();
        }
      } else {
        editor.execute([const DeleteUpstreamCharacterRequest()]);
        return true;
      }
    }

    return false;
  }

  bool moveSelectionToEndOfPrecedingNode() {
    if (composer.selection == null) {
      return false;
    }

    final node = document.getNodeById(composer.selection!.extent.targetNodeId);
    if (node == null) {
      return false;
    }

    final nodeBefore = document.getNodeBeforeById(node.id);
    if (nodeBefore == null) {
      return false;
    }

    editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: document.getPathByNodeId(nodeBefore.id)!,
            nodePosition: nodeBefore.endPosition,
          ),
        ),
        SelectionChangeType.collapseSelection,
        SelectionReason.userInteraction,
      ),
    ]);

    return true;
  }

  /// Finds the first visually selectable node above the selection extent
  /// and changes the selection to its end.
  ///
  /// Does nothing if no selectable node is found.
  bool _moveSelectionToEndOfFirstSelectableUpstreamNode() {
    if (composer.selection == null) {
      return false;
    }

    final node = document.getNodeById(composer.selection!.extent.targetNodeId);
    if (node == null) {
      return false;
    }

    DocumentNode? nodeBefore = document.getNodeBeforeById(node.id);
    while (nodeBefore != null) {
      final component = documentLayoutResolver().getComponentByNodeId(nodeBefore.id);
      if (component == null) {
        // Assume we are in a transitive state where the node was created, but
        // the component is not yet available.
        return false;
      }
      if (component.isVisualSelectionSupported()) {
        editor.execute([
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                documentPath: document.getPathByNodeId(nodeBefore.id)!,
                nodePosition: nodeBefore.endPosition,
              ),
            ),
            SelectionChangeType.collapseSelection,
            SelectionReason.userInteraction,
          ),
        ]);

        return true;
      }

      nodeBefore = document.getNodeBeforeById(nodeBefore.id);
    }

    // We didn't find any selectable nodes before the current node.
    return false;
  }

  /// Merges the selected [TextNode] with the upstream [TextNode].
  ///
  /// If there are non-deletable [BlockNode]s between the two [TextNode]s,
  /// the [BlockNode]s are ignored.
  bool mergeTextNodeWithUpstreamTextNode() {
    final node = document.getNodeById(composer.selection!.extent.targetNodeId);
    if (node == null) {
      return false;
    }

    DocumentNode? nodeAbove = document.getNodeBeforeById(node.id);
    while (nodeAbove != null && nodeAbove is BlockNode && !nodeAbove.isDeletable) {
      nodeAbove = document.getNodeBeforeById(nodeAbove.id);
    }

    if (nodeAbove == null) {
      return false;
    }
    if (nodeAbove is! TextNode) {
      return false;
    }

    final aboveParagraphLength = nodeAbove.text.length;

    // Send edit command.
    editor.execute([
      CombineParagraphsRequest(
        firstNodeId: nodeAbove.id,
        secondNodeId: node.id,
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: document.getPathByNodeId(nodeAbove.id)!,
            nodePosition: TextNodePosition(offset: aboveParagraphLength),
          ),
        ),
        SelectionChangeType.deleteContent,
        SelectionReason.userInteraction,
      ),
      // Since two paragraphs were combined, the composing region might point
      // to a deleted paragraph. Clear it.
      const ClearComposingRegionRequest(),
    ]);

    return true;
  }

  bool deleteUpstreamCharacter() {
    if (composer.selection == null) {
      return false;
    }
    if (!_isTextEntryNode(document: document, selection: composer.selection!)) {
      return false;
    }
    if (composer.selection!.isCollapsed && (composer.selection!.extent.nodePosition as TextNodePosition).offset <= 0) {
      return false;
    }

    final textNodePath = composer.selection!.extent.documentPath;
    final textNode = document.getNodeAtPath(textNodePath) as TextNode;
    final currentTextOffset = (composer.selection!.extent.nodePosition as TextNodePosition).offset;

    final previousCharacterOffset = getCharacterStartBounds(textNode.text.toPlainText(), currentTextOffset);

    final newSelectionPosition = DocumentPosition(
      documentPath: textNodePath,
      nodePosition: TextNodePosition(offset: previousCharacterOffset),
    );

    // Delete the selected content.
    editor.execute([
      DeleteContentRequest(
        documentRange: textNode.selectionBetween(
          textNodePath,
          currentTextOffset,
          previousCharacterOffset,
        ),
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(position: newSelectionPosition),
        SelectionChangeType.deleteContent,
        SelectionReason.userInteraction,
      )
    ]);

    return true;
  }

  /// Replaces the [DocumentNode] with the given `nodeId` with a [ParagraphNode],
  /// and places the caret in the new [ParagraphNode].
  ///
  /// This can be used, for example, to effectively delete an image by replacing
  /// it with an empty paragraph.
  void replaceBlockNodeWithEmptyParagraphAndCollapsedSelection(String nodeId) {
    editor.execute([
      ReplaceNodeWithEmptyParagraphWithCaretRequest(nodeId: nodeId),
    ]);
  }

  /// Deletes all selected content.
  ///
  /// The [affinity] defines the direction to where the user is trying to
  /// delete. For example, if the users presses the backspace key, the
  /// [affinity] should be [TextAffinity.upstream]. If the user presses the
  /// delete key, the [affinity] should be [TextAffinity.downstream].
  ///
  /// Returns [true] if content was deleted, or [false] if no content was
  /// selected.
  bool deleteSelection(TextAffinity affinity) {
    if (composer.selection == null) {
      return false;
    }

    if (composer.selection!.isCollapsed) {
      return false;
    }

    // The document selection includes a span of content. It may or may not
    // cross nodes. Either way, delete the selected content.
    _deleteExpandedSelection(affinity);
    return true;
  }

  void _deleteExpandedSelection(TextAffinity affinity) {
    // Delete the selected content.
    editor.execute([
      DeleteSelectionRequest(affinity),
    ]);
  }

  /// Returns the [DocumentPosition] where the caret should sit after deleting
  /// the given [selection] from the given [document].
  ///
  /// Returns `null` if there are no deletable nodes within the [selection].
  ///
  /// This method doesn't delete any content. Instead, it determines what would
  /// be deleted if a delete operation was run for the given [selection]. Based
  /// on the shared understanding of content deletion rules, the resulting caret
  /// position is returned.
  // TODO: Move this method to an appropriate place. It was made public and static
  //       because document_keyboard_actions.dart also uses this behavior.
  static DocumentPosition? getDocumentPositionAfterExpandedDeletion({
    required Document document,
    required DocumentSelection selection,
  }) {
    // Figure out where the caret should appear after the
    // deletion.

    if (selection.isCollapsed) {
      // There is no expanded deletion when the selection is collapsed. Therefore,
      // no selection change is expected.
      return null;
    }

    // TODO: This calculation depends upon the first
    //       selected node still existing after the deletion. This
    //       is a fragile expectation and should be revisited.
    final basePosition = selection.base;
    final baseNode = document.getNode(basePosition);
    if (baseNode == null) {
      throw Exception('Failed to _getDocumentPositionAfterDeletion because the base node no longer exists.');
    }

    final extentPosition = selection.extent;
    final extentNode = document.getNode(extentPosition);
    if (extentNode == null) {
      throw Exception('Failed to _getDocumentPositionAfterDeletion because the extent node no longer exists.');
    }

    final selectionAffinity = document.getAffinityForSelection(selection);
    final topPosition = selectionAffinity == TextAffinity.downstream //
        ? selection.base
        : selection.extent;
    final topNodePosition = topPosition.nodePosition;
    final topNode = document.getNodeById(topPosition.targetNodeId)!;

    final bottomPosition = selectionAffinity == TextAffinity.downstream //
        ? selection.extent
        : selection.base;
    final bottomNodePosition = bottomPosition.nodePosition;
    final bottomNode = document.getNodeById(bottomPosition.targetNodeId)!;

    final normalizedRange = selection.normalize(document);
    final nodes = document.getNodesInside(normalizedRange.start, normalizedRange.end);
    final firstDeletableNodeId = nodes.firstWhereOrNull((node) => node.isDeletable)?.id;

    DocumentPosition newSelectionPosition;

    if (topPosition.documentPath != bottomPosition.documentPath) {
      if (topNodePosition == topNode.beginningPosition && bottomNodePosition == bottomNode.endPosition) {
        // All deletable nodes in the selection will be deleted. Assume that one of the
        // nodes will be retained and converted into a paragraph, if it's not
        // already a paragraph.

        final emptyParagraphId = topNode.isDeletable
            ? topNode.id
            : bottomNode.isDeletable
                ? bottomNode.id
                : firstDeletableNodeId;

        if (emptyParagraphId == null) {
          // There are no deletable nodes in the selection. Fizzle.
          // We don't expect this method to be called if there are no deletable nodes.
          return null;
        }

        newSelectionPosition = DocumentPosition(
          documentPath: document.getPathByNodeId(emptyParagraphId)!,
          nodePosition: const TextNodePosition(offset: 0),
        );
      } else if (topNodePosition == topNode.beginningPosition) {
        // The top node will be deleted, but only part of the bottom node
        // will be deleted.
        newSelectionPosition = DocumentPosition(
          documentPath: document.getPathByNodeId(bottomNode.id)!,
          nodePosition: bottomNode.beginningPosition,
        );
      } else if (bottomNodePosition == bottomNode.endPosition) {
        // The bottom node will be deleted, but only part of the top node
        // will be deleted.
        newSelectionPosition = DocumentPosition(
          documentPath: document.getPathByNodeId(topNode.id)!,
          nodePosition: topNodePosition,
        );
      } else {
        // Part of the top and bottom nodes will be deleted, but both of
        // those nodes will remain.

        // The caret should end up at the base position
        newSelectionPosition = selectionAffinity == TextAffinity.downstream ? selection.base : selection.extent;
      }
    } else {
      // Selection is within a single node.
      //
      // If it's an upstream/downstream selection node, then the whole node
      // is selected, and it will be replaced by a Paragraph Node.
      //
      // Otherwise, it must be a TextNode, in which case we need to figure
      // out which DocumentPosition contains the earlier TextNodePosition.
      if (basePosition.nodePosition is UpstreamDownstreamNodePosition) {
        // Assume that the node was replace with an empty paragraph.
        newSelectionPosition = DocumentPosition(
          documentPath: document.getPathByNodeId(baseNode.id)!,
          nodePosition: const TextNodePosition(offset: 0),
        );
      } else if (basePosition.nodePosition is TextNodePosition) {
        final baseOffset = (basePosition.nodePosition as TextNodePosition).offset;
        final extentOffset = (extentPosition.nodePosition as TextNodePosition).offset;

        newSelectionPosition = DocumentPosition(
          documentPath: document.getPathByNodeId(baseNode.id)!,
          nodePosition: TextNodePosition(offset: min(baseOffset, extentOffset)),
        );
      } else {
        throw Exception(
            'Unknown selection position type: $basePosition, for node: $baseNode, within document selection: $selection');
      }
    }

    return newSelectionPosition;
  }

  void deleteNonSelectedNode(DocumentNode node) {
    assert(composer.selection?.base.targetNodeId != node.id);
    assert(composer.selection?.extent.targetNodeId != node.id);

    editor.execute([DeleteNodeRequest(nodeId: node.id)]);
  }

  /// Adds the given [attributions] to all [AttributedText] within the
  /// [DocumentComposer]'s current selection.
  ///
  /// Returns [true] if any text exists within the selection, or [false]
  /// otherwise.
  bool addAttributionsToSelection(Set<Attribution> attributions) {
    if (composer.selection == null) {
      return false;
    }

    if (composer.selection!.isCollapsed) {
      return false;
    }

    editor.execute([
      AddTextAttributionsRequest(
        documentRange: composer.selection!,
        attributions: attributions,
      ),
    ]);

    return false;
  }

  /// Removes the given [attributions] from all [AttributedText] within the
  /// [DocumentComposer]'s current selection.
  ///
  /// Returns [true] if any text exists within the selection, or [false]
  /// otherwise.
  bool removeAttributionsFromSelection(Set<Attribution> attributions) {
    if (composer.selection == null) {
      return false;
    }

    if (composer.selection!.isCollapsed) {
      return false;
    }

    editor.execute([
      RemoveTextAttributionsRequest(
        documentRange: composer.selection!,
        attributions: attributions,
      ),
    ]);

    return false;
  }

  /// Toggles the given [attributions] on all [AttributedText] within the
  /// [DocumentComposer]'s current selection.
  ///
  /// Returns [true] if any text exists within the selection, or [false]
  /// otherwise.
  bool toggleAttributionsOnSelection(Set<Attribution> attributions) {
    if (composer.selection == null) {
      return false;
    }

    if (composer.selection!.isCollapsed) {
      return false;
    }

    editor.execute([
      ToggleTextAttributionsRequest(
        documentRange: composer.selection!,
        attributions: attributions,
      ),
    ]);

    return false;
  }

  /// Adds the given [attributions] to the [DocumentComposer]'s input
  /// mode so that any new plain text inserted using [insertPlainText()]
  /// will contain the given [attributions].
  ///
  /// Always returns [true].
  bool activateComposerAttributions(Set<Attribution> attributions) {
    composer.preferences.addStyles(attributions);
    return true;
  }

  /// Removes the given [attributions] from the [DocumentComposer]'s input
  /// mode so that any new plain text inserted using [insertPlainText()]
  /// **doesn't** contain the given [attributions].
  ///
  /// Always returns [true].
  bool deactivateComposerAttributions(Set<Attribution> attributions) {
    composer.preferences.removeStyles(attributions);
    return true;
  }

  /// Toggles the presence of the given [attributions] within the
  /// [DocumentComposer]'s input mode.
  ///
  /// Always returns [true].
  bool toggleComposerAttributions(Set<Attribution> attributions) {
    composer.preferences.toggleStyles(attributions);
    return true;
  }

  /// Removes all [attributions] within the [DocumentComposer]'s
  /// input mode.
  ///
  /// Always returns [true].
  bool clearComposerAttributions() {
    composer.preferences.clearStyles();
    return true;
  }

  /// Inserts the given [text] at the [DocumentComposer]'s current
  /// selection extent, applying any [Attribution]s that are
  /// currently activated in the [DocumentComposer]'s input mode.
  ///
  /// Any selected content is deleted before inserting the new text.
  ///
  /// Returns `true` if the [text] was successfully inserted, or [false]
  /// if it wasn't, e.g., there was no selection, or more than one node
  /// was selected.
  @Deprecated("Execute a relevant EditRequest in an Editor, e.g., InsertPlainTextAtCaretRequest.")
  bool insertPlainText(String text) {
    editorOpsLog.fine('Attempting to insert "$text" at document selection: ${composer.selection}');
    if (composer.selection == null) {
      editorOpsLog.fine("The composer has no selection. Can't insert.");
      return false;
    }

    if (!composer.selection!.isCollapsed) {
      // The selection is expanded. Delete the selected content
      // and then insert the new text.
      editorOpsLog.fine("The selection is expanded. Deleting the selection before inserting text.");

      // As we are replacing text by deleting the selection and then inserting the new text,
      // we need to store the current attributions.
      // This is required as deleting text can clear the composer current attributions.
      // Without this, the new text doesn't preserve the attributions of the replaced text.
      final composerAttributions = {...composer.preferences.currentAttributions};

      _deleteExpandedSelection(TextAffinity.downstream);

      // Restore the previous attributions.
      composer.preferences
        ..clearStyles()
        ..addStyles(composerAttributions);
    }

    final extentNodePosition = composer.selection!.extent.nodePosition;
    if (extentNodePosition is UpstreamDownstreamNodePosition) {
      editorOpsLog.fine("The selected position is an UpstreamDownstreamPosition. Inserting new paragraph first.");
      insertBlockLevelNewline();
    }

    final extentNode = document.getNodeById(composer.selection!.extent.targetNodeId)!;
    if (extentNode is! TextNode) {
      editorOpsLog
          .fine("Couldn't insert text because Super Editor doesn't know how to handle a node of type: $extentNode");
      return false;
    }

    editorOpsLog.fine("Executing text insertion command.");
    editor.execute([
      InsertTextRequest(
        documentPosition: composer.selection!.extent,
        textToInsert: text,
        attributions: composer.preferences.currentAttributions,
      ),
    ]);

    return true;
  }

  /// Inserts the given [character] at the current extent position.
  ///
  /// By default, the current [DocumentComposer] input mode's [Attribution]s
  /// are added to the given [character]. To insert [character] exactly as it's provided,
  /// set [ignoreComposerAttributions] to [true].
  ///
  /// If the current selection is expanded, the current selection is deleted
  /// before the character is inserted.
  ///
  /// If the caret sits at the boundary of a block node, a new paragraph is
  /// inserted before or after the block node, and then the character is inserted.
  ///
  /// Returns [true] if the [character] was successfully inserted, or [false]
  /// if it wasn't, e.g., the currently selected node is not a [TextNode].
  bool insertCharacter(
    String character, {
    bool ignoreComposerAttributions = false,
  }) {
    editorOpsLog.fine("Trying to insert '$character'");
    if (composer.selection == null) {
      return false;
    }

    if (!composer.selection!.isCollapsed) {
      _deleteExpandedSelection(TextAffinity.downstream);
    }

    final extentNodePosition = composer.selection!.extent.nodePosition;
    if (extentNodePosition is UpstreamDownstreamNodePosition) {
      editorOpsLog.fine("The selected position is an UpstreamDownstreamPosition. Inserting new paragraph first.");
      editor.execute([InsertNewlineAtCaretRequest()]);
    }

    final extentNode = document.getNodeById(composer.selection!.extent.targetNodeId)!;
    if (extentNode is! TextNode) {
      editorOpsLog.fine(
          "Couldn't insert character because Super Editor doesn't know how to handle a node of type: $extentNode");
      return false;
    }

    // Delegate the action to the standard insert-character behavior.
    final inserted = _insertCharacterInTextComposable(
      character,
      ignoreComposerAttributions: ignoreComposerAttributions,
    );
    editorOpsLog.fine("Did insert '$character'? $inserted");
    return inserted;
  }

  bool _insertCharacterInTextComposable(
    String character, {
    bool ignoreComposerAttributions = false,
  }) {
    if (composer.selection == null) {
      return false;
    }
    if (!composer.selection!.isCollapsed) {
      return false;
    }
    if (!_isTextEntryNode(document: document, selection: composer.selection!)) {
      return false;
    }

    editor.execute([
      InsertTextRequest(
        documentPosition: composer.selection!.extent,
        textToInsert: character,
        attributions: ignoreComposerAttributions ? {} : composer.preferences.currentAttributions,
      ),
    ]);

    return true;
  }

  /// Inserts a new [ParagraphNode], or splits an existing node into two.
  ///
  /// If the [DocumentComposer] selection is collapsed, and the extent is
  /// at the end of a node, such as the end of a paragraph, then a new
  /// [ParagraphNode] is added after the current node and the selection
  /// extent is moved to the new [ParagraphNode].
  ///
  /// If the [DocumentComposer] selection is collapsed, and the extent is
  /// in the middle of a node, such as in the middle of a paragraph, list
  /// item, or blockquote, then the current node is split into two nodes
  /// of the same type at that position.
  ///
  /// If the current selection is not collapsed then the current selection
  /// is first deleted, then the aforementioned operation takes place.
  ///
  /// Returns `true` if a new node was inserted or a node was split into two.
  /// Returns `false` if there was no selection.
  @Deprecated("Execute a relevant EditRequest in an Editor, e.g., InsertNewlineAtCaretRequest.")
  bool insertBlockLevelNewline() {
    editorOpsLog.fine("Inserting block-level newline");
    if (composer.selection == null) {
      editorOpsLog.finer("Selection is null. Can't insert newline.");
      return false;
    }

    // Ensure that the entire selection sits within the same node.
    final baseNode = document.getNodeById(composer.selection!.base.targetNodeId)!;
    final extentNode = document.getNodeById(composer.selection!.extent.targetNodeId)!;
    if (baseNode.id != extentNode.id) {
      editorOpsLog.finer("The selection spans multiple nodes. Can't insert block-level newline.");
      return false;
    }

    if (!composer.selection!.isCollapsed) {
      // The selection is not collapsed. Delete the selected content first,
      // then continue the process.
      editorOpsLog.finer("Deleting selection before inserting block-level newline");
      _deleteExpandedSelection(TextAffinity.downstream);
    }

    final newNodeId = Editor.createNodeId();

    if (extentNode is ListItemNode) {
      if (extentNode.text.isEmpty) {
        // The list item is empty. Convert it to a paragraph.
        editorOpsLog.finer(
            "The current node is an empty list item. Converting it to a paragraph instead of inserting block-level newline.");
        return convertToParagraph();
      }

      // Split the list item into two.
      editorOpsLog.finer("Splitting list item in two.");
      editor.execute([
        SplitListItemRequest(
          nodeId: extentNode.id,
          splitPosition: composer.selection!.extent.nodePosition as TextNodePosition,
          newNodeId: newNodeId,
        ),
        // Place the caret at the beginning of the new node.
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              documentPath: document.getPathByNodeId(newNodeId)!,
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.insertContent,
          SelectionReason.userInteraction,
        ),
      ]);
    } else if (extentNode is ParagraphNode) {
      // Split the paragraph into two. This includes headers, blockquotes, and
      // any other block-level paragraph.
      final currentExtentPosition = composer.selection!.extent.nodePosition as TextNodePosition;
      final endOfParagraph = extentNode.endPosition;

      editorOpsLog.finer("Splitting paragraph in two.");
      editor.execute([
        SplitParagraphRequest(
          nodeId: extentNode.id,
          splitPosition: currentExtentPosition,
          newNodeId: newNodeId,
          replicateExistingMetadata: currentExtentPosition.offset != endOfParagraph.offset,
        ),
        // Place the caret at the beginning of the new node.
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              documentPath: document.getPathByNodeId(newNodeId)!,
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.insertContent,
          SelectionReason.userInteraction,
        ),
      ]);
    } else if (composer.selection!.extent.nodePosition is UpstreamDownstreamNodePosition) {
      final extentPosition = composer.selection!.extent.nodePosition as UpstreamDownstreamNodePosition;
      if (extentPosition.affinity == TextAffinity.downstream) {
        // The caret sits on the downstream edge of block-level content. Insert
        // a new paragraph after this node.
        editorOpsLog.finer("Inserting paragraph after block-level node.");
        editor.execute([
          InsertNodeAfterNodeRequest(
            existingNodeId: extentNode.id,
            newNode: ParagraphNode(
              id: newNodeId,
              text: AttributedText(),
            ),
          ),
          // Place the caret at the beginning of the new node.
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                documentPath: document.getPathByNodeId(newNodeId)!,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
            SelectionChangeType.insertContent,
            SelectionReason.userInteraction,
          ),
        ]);
      } else {
        // The caret sits on the upstream edge of block-level content. Insert
        // a new paragraph before this node.
        editorOpsLog.finer("Inserting paragraph before block-level node.");
        editor.execute([
          InsertNodeBeforeNodeRequest(
            existingNodeId: extentNode.id,
            newNode: ParagraphNode(
              id: newNodeId,
              text: AttributedText(),
            ),
          ),
          // Place the caret at the beginning of the new node.
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                documentPath: document.getPathByNodeId(newNodeId)!,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
            SelectionChangeType.insertContent,
            SelectionReason.userInteraction,
          ),
        ]);
      }
    } else if (extentNode is TaskNode) {
      if (extentNode.text.isEmpty) {
        // The task is empty. Convert it to a paragraph.
        return convertToParagraph();
      }

      final splitOffset = (composer.selection!.extent.nodePosition as TextNodePosition).offset;

      editor.execute([
        SplitExistingTaskRequest(
          existingNodeId: extentNode.id,
          splitOffset: splitOffset,
          newNodeId: newNodeId,
        ),
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              documentPath: document.getPathByNodeId(newNodeId)!,
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.insertContent,
          SelectionReason.userInteraction,
        ),
      ]);
    } else {
      // We don't know how to handle this type of node position. Do nothing.
      editorOpsLog.fine("Can't insert new block-level inline because we don't recognize the selected content type.");
      return false;
    }

    return true;
  }

  /// Inserts an image at the current selection extent.
  ///
  /// If the selection extent sits in an empty paragraph, that paragraph
  /// is converted into the desired image and a new empty paragraph is inserted
  /// after the image.
  ///
  /// If the selection extent sits at the end of a paragraph, the image is
  /// inserted as a new node after that paragraph, and then a new empty paragraph
  /// is inserted after the image.
  ///
  /// If the selection extent sits in the middle of a paragraph then the
  /// paragraph is split into two at that position, an image is inserted between
  /// the two paragraphs, the selection extent is placed at the beginning of the
  /// second paragraph.
  ///
  /// If the selection extent sits in any other kind of node, nothing happens.
  ///
  /// Returns `true` if an image was inserted, `false` if it wasn't.
  bool insertImage(String url) {
    if (composer.selection == null) {
      return false;
    }
    if (composer.selection!.base.documentPath != composer.selection!.extent.documentPath) {
      return false;
    }

    final node = document.getNodeById(composer.selection!.base.targetNodeId);
    if (node is! ParagraphNode) {
      return false;
    }

    return _insertBlockLevelContent(
      ImageNode(id: Editor.createNodeId(), imageUrl: url),
    );
  }

  /// Inserts horizontal rule at the current selection extent.
  ///
  /// If the selection extent sits in an empty paragraph, that paragraph
  /// is converted into the desired horizontal rule and a new empty paragraph
  /// is inserted after the horizontal rule.
  ///
  /// If the selection extent sits at the end of a paragraph, the horizontal
  /// rule is inserted as a new node after that paragraph, and then a new
  /// empty paragraph is inserted after the horizontal rule.
  ///
  /// If the selection extent sits in the middle of a paragraph then the
  /// paragraph is split into two at that position, a horizontal rule is
  /// inserted between the two paragraphs, the selection extent is placed
  /// at the beginning of the second paragraph.
  ///
  /// If the selection extent sits in any other kind of node, nothing happens.
  ///
  /// Returns [true] if a horizontal rule was inserted, [false] if it wasn't.
  bool insertHorizontalRule() {
    if (composer.selection == null) {
      return false;
    }
    if (composer.selection!.base.documentPath != composer.selection!.extent.documentPath) {
      return false;
    }

    final node = document.getNodeById(composer.selection!.base.targetNodeId);
    if (node is! ParagraphNode) {
      return false;
    }

    return _insertBlockLevelContent(
      HorizontalRuleNode(id: Editor.createNodeId()),
    );
  }

  /// Inserts the given [blockNode] after the caret.
  ///
  /// If the selection extent sits in an empty paragraph, that paragraph
  /// is converted into the given [blockNode] and a new empty paragraph
  /// is inserted after the [blockNode].
  ///
  /// If the selection extent sits at the beginning of a non-empty paragraph,
  /// the [blockNode] is inserted as a new node before that paragraph.
  ///
  /// If the selection extent sits at the end of a paragraph, the [blockNode]
  /// is inserted as a new node after that paragraph, and then a new
  /// empty paragraph is inserted after the [blockNode].
  ///
  /// If the selection extent sits in the middle of a paragraph then the
  /// paragraph is split into two at that position, the [blockNode] is
  /// inserted between the two paragraphs, the selection extent is placed
  /// at the beginning of the second paragraph.
  ///
  /// If the selection extent sits in any other kind of node, nothing happens.
  ///
  /// Returns `true` if the [blockNode] was inserted, `false` if it wasn't.
  bool _insertBlockLevelContent(DocumentNode blockNode) {
    if (composer.selection == null) {
      return false;
    }
    if (composer.selection!.base.documentPath != composer.selection!.extent.documentPath) {
      return false;
    }

    final nodeId = composer.selection!.base.targetNodeId;
    final node = document.getNodeById(nodeId);
    if (node is! ParagraphNode) {
      return false;
    }

    editor.execute([
      InsertNodeAtCaretRequest(node: blockNode),
    ]);

    return true;
  }

  /// Indents the list item at the current selection extent, if the entire
  /// selection sits within a [ListItemNode].
  ///
  /// Returns [true] if a list item was indented. Returns [false] if
  /// the selection extent did not sit in a list item, or if the selection
  /// included more than just a list item.
  bool indentListItem() {
    if (composer.selection == null) {
      return false;
    }

    final baseNode = document.getNodeById(composer.selection!.base.targetNodeId);
    final extentNode = document.getNodeById(composer.selection!.extent.targetNodeId);
    if (baseNode is! ListItemNode || extentNode is! ListItemNode) {
      return false;
    }

    editor.execute([
      IndentListItemRequest(nodeId: extentNode.id),
    ]);

    return true;
  }

  /// Indents the list item at the current selection extent, if the entire
  /// selection sits within a [ListItemNode].
  ///
  /// If the list item is not indented, the list item is converted to
  /// a [ParagraphNode].
  ///
  /// Returns [true] if a list item was un-indented. Returns [false] if
  /// the selection extent did not sit in a list item, or if the selection
  /// included more than just a list item.
  bool unindentListItem() {
    if (composer.selection == null) {
      return false;
    }

    final baseNode = document.getNodeById(composer.selection!.base.targetNodeId);
    final extentNode = document.getNodeById(composer.selection!.extent.targetNodeId);
    if (baseNode!.id != extentNode!.id) {
      return false;
    }

    if (baseNode is! ListItemNode) {
      return false;
    }

    editor.execute([
      UnIndentListItemRequest(nodeId: extentNode.id),
    ]);

    return true;
  }

  /// Converts the [TextNode] with the current [DocumentComposer] selection
  /// extent to a [ListItemNode] of the given [type], or does nothing if the
  /// current node is not a [TextNode], or if the current selection spans
  /// more than one node.
  ///
  /// Returns [true] if the selected node was converted to a [ListItemNode],
  /// or [false] if it wasn't.
  bool convertToListItem(ListItemType type, AttributedText text) {
    if (composer.selection == null) {
      return false;
    }
    if (composer.selection!.base.documentPath != composer.selection!.extent.documentPath) {
      return false;
    }

    final nodeId = composer.selection!.base.targetNodeId;
    final node = document.getNodeById(nodeId);
    if (node is! TextNode) {
      return false;
    }

    final newNode = ListItemNode(id: nodeId, itemType: type, text: text);

    editor.execute([
      ReplaceNodeRequest(existingNodeId: node.id, newNode: newNode),
    ]);

    return true;
  }

  /// Converts the [TextNode] with the current [DocumentComposer] selection
  /// extent to a [Paragraph] with a blockquote block type, or does nothing
  /// if the current node is not a [TextNode], or if the current selection
  /// spans more than one node.
  ///
  /// Returns [true] if the selected node was converted to a blockquote,
  /// or [false] if it wasn't.
  bool convertToBlockquote(AttributedText text) {
    if (composer.selection == null) {
      return false;
    }
    if (composer.selection!.base.documentPath != composer.selection!.extent.documentPath) {
      return false;
    }

    final nodeId = composer.selection!.base.targetNodeId;
    final node = document.getNodeById(nodeId);
    if (node is! TextNode) {
      return false;
    }

    final newNode = ParagraphNode(id: nodeId, metadata: {'blockType': blockquoteAttribution}, text: text);

    editor.execute([
      ReplaceNodeRequest(existingNodeId: node.id, newNode: newNode),
    ]);

    return true;
  }

  /// Converts the [TextNode] with the current [DocumentComposer] selection
  /// extent to a [Paragraph], or does nothing if the current node is not
  /// a [TextNode], or if the current selection spans more than one node.
  ///
  /// Returns [true] if the selected node was converted to a [ParagraphNode],
  /// or [false] if it wasn't.
  bool convertToParagraph({
    Map<String, Attribution>? newMetadata,
  }) {
    if (composer.selection == null) {
      return false;
    }

    final baseNode = document.getNodeById(composer.selection!.base.targetNodeId)!;
    final extentNode = document.getNodeById(composer.selection!.extent.targetNodeId)!;
    if (baseNode.id != extentNode.id) {
      return false;
    }
    if (extentNode is! TextNode) {
      return false;
    }
    if (extentNode is ParagraphNode && extentNode.getMetadataValue('blockType') == paragraphAttribution) {
      // This content is already a regular paragraph.
      return false;
    }

    editor.execute([
      ConvertTextNodeToParagraphRequest(nodeId: extentNode.id, newMetadata: newMetadata),
    ]);

    return true;
  }

  bool _isTextEntryNode({
    required Document document,
    required DocumentSelection selection,
  }) {
    final extentPosition = selection.extent;
    final extentNode = document.getNodeById(extentPosition.targetNodeId);
    return extentNode is TextNode;
  }

  /// Serializes the current selection to plain text, and adds it to the
  /// clipboard.
  void copy() {
    final textToCopy = _textInSelection(
      document: document,
      documentSelection: composer.selection!,
    );
    // TODO: figure out a general approach for asynchronous behaviors that
    //       need to be carried out in response to user input.
    _saveToClipboard(textToCopy);
  }

  /// Serializes the current selection to plain text, adds it to the
  /// clipboard, and then deletes the selected content.
  void cut() {
    final textToCut = _textInSelection(
      document: document,
      documentSelection: composer.selection!,
    );
    // TODO: figure out a general approach for asynchronous behaviors that
    //       need to be carried out in response to user input.
    _saveToClipboard(textToCut);

    deleteSelection(TextAffinity.downstream);
  }

  Future<void> _saveToClipboard(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }

  String _textInSelection({
    required Document document,
    required DocumentSelection documentSelection,
  }) {
    final selectedNodes = document.getNodesInside(
      documentSelection.base,
      documentSelection.extent,
    );

    final buffer = StringBuffer();
    for (int i = 0; i < selectedNodes.length; ++i) {
      final selectedNode = selectedNodes[i];
      dynamic nodeSelection;

      if (i == 0) {
        // This is the first node and it may be partially selected.
        final baseSelectionPosition = selectedNode.id == documentSelection.base.documentPath
            ? documentSelection.base.nodePosition
            : documentSelection.extent.nodePosition;

        final extentSelectionPosition =
            selectedNodes.length > 1 ? selectedNode.endPosition : documentSelection.extent.nodePosition;

        nodeSelection = selectedNode.computeSelection(
          base: baseSelectionPosition,
          extent: extentSelectionPosition,
        );
      } else if (i == selectedNodes.length - 1) {
        // This is the last node and it may be partially selected.
        final nodePosition = selectedNode.id == documentSelection.base.documentPath
            ? documentSelection.base.nodePosition
            : documentSelection.extent.nodePosition;

        nodeSelection = selectedNode.computeSelection(
          base: selectedNode.beginningPosition,
          extent: nodePosition,
        );
      } else {
        // This node is fully selected. Copy the whole thing.
        nodeSelection = selectedNode.computeSelection(
          base: selectedNode.beginningPosition,
          extent: selectedNode.endPosition,
        );
      }

      final nodeContent = selectedNode.copyContent(nodeSelection);
      if (nodeContent != null) {
        buffer.write(nodeContent);
        if (i < selectedNodes.length - 1) {
          buffer.writeln();
        }
      }
    }
    return buffer.toString();
  }

  /// Deletes all selected content, and then pastes the current clipboard
  /// content at the given location.
  ///
  /// The clipboard operation is asynchronous. As a result, if the user quickly
  /// moves the caret, it's possible that the clipboard content will be pasted
  /// at the wrong spot.
  void paste() {
    DocumentPosition? pastePosition = composer.selection!.extent;

    // Start a transaction so that we can capture both the initial deletion behavior,
    // and the clipboard content insertion, all as one transaction.
    editor.startTransaction();

    // Delete all currently selected content.
    if (!composer.selection!.isCollapsed) {
      pastePosition = CommonEditorOperations.getDocumentPositionAfterExpandedDeletion(
        document: document,
        selection: composer.selection!,
      );

      if (pastePosition == null) {
        // There are no deletable nodes in the selection. Do nothing.
        return;
      }

      // Delete the selected content.
      editor.execute([
        DeleteContentRequest(documentRange: composer.selection!),
        ChangeSelectionRequest(
          DocumentSelection.collapsed(position: pastePosition),
          SelectionChangeType.deleteContent,
          SelectionReason.userInteraction,
        ),
      ]);
    }

    // TODO: figure out a general approach for asynchronous behaviors that
    //       need to be carried out in response to user input.
    _paste(
      document: document,
      editor: editor,
      composer: composer,
      pastePosition: pastePosition,
    );

    editor.endTransaction();
  }

  Future<void> _paste({
    required Document document,
    required Editor editor,
    required DocumentComposer composer,
    required DocumentPosition pastePosition,
  }) async {
    final content = (await Clipboard.getData('text/plain'))?.text ?? '';

    editor.execute([
      PasteEditorRequest(
        content: content,
        pastePosition: pastePosition,
      ),
    ]);
  }
}

class PasteEditorRequest implements EditRequest {
  PasteEditorRequest({
    required this.content,
    required this.pastePosition,
  });

  final String content;
  final DocumentPosition pastePosition;
}

class PasteEditorCommand extends EditCommand {
  PasteEditorCommand({
    required String content,
    required DocumentPosition pastePosition,
  })  : _content = content,
        _pastePosition = pastePosition;

  final String _content;
  final DocumentPosition _pastePosition;

  // The [_content] as [DocumentNode]s so that we only generate node IDs one
  // time. This is critical for undo behavior to work as expected.
  List<DocumentNode>? _parsedContent;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    // Only parse the content if we haven't done it already. This command
    // might be run 2+ times if the user runs an undo operation.
    _parsedContent ??= _parseContent();

    // Assign locally so we don't have to use a "!" everywhere we reference it.
    final parsedContent = _parsedContent!.toList();
    if (parsedContent.isEmpty) {
      // No content to paste.
      return;
    }

    final document = context.document;
    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);
    final currentNodeWithSelection = document.getNodeById(_pastePosition.targetNodeId);
    if (currentNodeWithSelection is! TextNode) {
      throw Exception('Can\'t handle pasting text within node of type: $currentNodeWithSelection');
    }

    editorOpsLog.info("Pasting clipboard content in document.");

    final textNode = document.getNode(_pastePosition) as TextNode;
    final pasteTextOffset = (_pastePosition.nodePosition as TextPosition).offset;

    if (parsedContent.length > 1 && pasteTextOffset < textNode.endPosition.offset) {
      // There is more than 1 node of content being pasted. Therefore,
      // new nodes will need to be added, which means that the currently
      // selected text node will be split at the current text offset.
      // Configure a new node to be added at the end of the pasted content
      // which contains the trailing text from the currently selected
      // node.
      executor.executeCommand(
        SplitParagraphCommand(
          nodeId: currentNodeWithSelection.id,
          splitPosition: TextPosition(offset: pasteTextOffset),
          newNodeId: Editor.createNodeId(),
          replicateExistingMetadata: true,
        ),
      );
    }

    if (parsedContent.first is TextNode) {
      // Paste the first piece of attributed content into the existing selected TextNode.
      executor.executeCommand(
        InsertAttributedTextCommand(
          documentPosition: _pastePosition,
          textToInsert: (parsedContent.first as TextNode).text,
        ),
      );
    }

    // The first line of pasted text was added to the selected paragraph.
    // Now, add all remaining pasted nodes to the document..
    DocumentNode previousNode = document.getNodeById(_pastePosition.targetNodeId)!;
    // ^ re-query the node where the first paragraph was pasted because nodes are immutable.
    for (final pastedNode in parsedContent.sublist(1)) {
      document.insertNodeAfter(
        existingNodeId: previousNode.id,
        newNode: pastedNode,
      );
      previousNode = pastedNode;

      executor.logChanges([
        DocumentEdit(
          NodeInsertedEvent(pastedNode.id, document.getNodeIndexById(pastedNode.id)),
        )
      ]);
    }

    // Place the caret at the end of the pasted content.
    final pastedNode = document.getNodeById(previousNode.id)!;
    // ^ re-query the node where we pasted content because nodes are immutable.

    executor.executeCommand(
      ChangeSelectionCommand(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: document.getPathByNodeId(pastedNode.id)!,
            nodePosition: pastedNode.endPosition,
          ),
        ),
        SelectionChangeType.insertContent,
        SelectionReason.userInteraction,
      ),
    );
    editorOpsLog.fine('New selection after paste operation: ${composer.selection}');
    editorOpsLog.fine('Done with paste command.');
  }

  List<DocumentNode> _parseContent() {
    // Split the pasted content at newlines, and apply attributions based
    // on inspection of the pasted content, e.g., link attributions.
    final attributedLines = _inferAttributionsForLinesOfPastedText(_content);
    return _convertLinesToParagraphs(attributedLines).toList();
  }

  /// Breaks the given [content] at each newline, then applies any inferred
  /// attributions based on content analysis, e.g., surrounds URLs with
  /// [LinkAttribution]s.
  List<AttributedText> _inferAttributionsForLinesOfPastedText(String content) {
    // Split the pasted content by newlines, because each new line of content
    // needs to placed in its own ParagraphNode.
    final lines = content.split('\n');
    editorOpsLog.fine("Breaking pasted content into lines and adding attributions:");
    editorOpsLog.fine("Lines of content:");
    for (final line in lines) {
      editorOpsLog.fine(' - "$line"');
    }

    final attributedLines = <AttributedText>[];
    for (final line in lines) {
      attributedLines.add(
        AttributedText(
          line,
          _findUrlSpansInText(pastedText: line),
        ),
      );
    }
    return attributedLines;
  }

  /// Finds all URLs in the [pastedText] and returns an [AttributedSpans], which
  /// contains [LinkAttribution]s that span each URL.
  AttributedSpans _findUrlSpansInText({required String pastedText}) {
    final AttributedSpans linkAttributionSpans = AttributedSpans();

    final wordBoundaries = pastedText.calculateAllWordBoundaries();

    for (final wordBoundary in wordBoundaries) {
      final word = wordBoundary.textInside(pastedText);

      // The word is a single URL. Linkify it.
      final uri = tryToParseUrl(word);
      if (uri == null) {
        // This word isn't a URI.
        continue;
      }

      final startOffset = wordBoundary.start;
      // -1 because TextPosition's offset indexes the character after the
      // selection, not the final character in the selection.
      final endOffset = wordBoundary.end - 1;

      // Add link attribution.
      linkAttributionSpans.addAttribution(
        newAttribution: LinkAttribution.fromUri(uri),
        start: startOffset,
        end: endOffset,
      );
    }

    return linkAttributionSpans;
  }

  Iterable<ParagraphNode> _convertLinesToParagraphs(Iterable<AttributedText> attributedLines) {
    return attributedLines.map(
      // TODO: create nodes based on content inspection (e.g., image, list item).
      (pastedLine) => ParagraphNode(
        id: Editor.createNodeId(),
        text: pastedLine,
      ),
    );
  }
}

class DeleteUpstreamCharacterRequest implements EditRequest {
  const DeleteUpstreamCharacterRequest();
}

class DeleteUpstreamCharacterCommand extends EditCommand {
  const DeleteUpstreamCharacterCommand();

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;
    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);
    final selection = composer.selection;

    if (selection == null) {
      throw Exception("Tried to delete upstream character but there's no selection.");
    }
    if (!selection.isCollapsed) {
      throw Exception("Tried to delete upstream character but the selection isn't collapsed.");
    }
    if (document.getNodeById(selection.extent.targetNodeId) is! TextNode) {
      throw Exception("Tried to delete upstream character but the selected node isn't a TextNode.");
    }
    if (selection.isCollapsed && (selection.extent.nodePosition as TextNodePosition).offset <= 0) {
      throw Exception("Tried to delete upstream character but the caret is at the beginning of the text.");
    }

    final textNode = document.getNode(selection.extent) as TextNode;
    final currentTextPath = selection.extent.documentPath;
    final currentTextOffset = (selection.extent.nodePosition as TextNodePosition).offset;

    final previousCharacterOffset = getCharacterStartBounds(textNode.text.toPlainText(), currentTextOffset);

    // Delete the selected content.
    executor
      ..executeCommand(
        DeleteContentCommand(
          documentRange: textNode.selectionBetween(
            currentTextPath,
            currentTextOffset,
            previousCharacterOffset,
          ),
        ),
      )
      ..executeCommand(
        ChangeSelectionCommand(
          textNode.selectionAt(currentTextPath, previousCharacterOffset),
          SelectionChangeType.deleteContent,
          SelectionReason.userInteraction,
        ),
      );
  }
}

class DeleteDownstreamCharacterRequest implements EditRequest {
  const DeleteDownstreamCharacterRequest();
}

class DeleteDownstreamCharacterCommand extends EditCommand {
  const DeleteDownstreamCharacterCommand();

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;
    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);
    final selection = composer.selection;

    if (selection == null) {
      throw Exception("Tried to delete downstream character but there's no selection.");
    }
    if (!selection.isCollapsed) {
      throw Exception("Tried to delete downstream character but the selection isn't collapsed.");
    }
    if (document.getNodeById(selection.extent.targetNodeId) is! TextNode) {
      throw Exception("Tried to delete downstream character but the selected node isn't a TextNode.");
    }

    final textNode = document.getNode(selection.extent) as TextNode;
    final text = textNode.text;
    final currentTextPositionOffset = (selection.extent.nodePosition as TextNodePosition).offset;
    if (currentTextPositionOffset >= text.length) {
      throw Exception("Tried to delete downstream character but the caret is sitting at the end of the text.");
    }

    final nextCharacterOffset = getCharacterEndBounds(text.toPlainText(), currentTextPositionOffset);

    // Delete the selected content.
    executor.executeCommand(
      DeleteContentCommand(
        documentRange: textNode.selectionBetween(
          selection.extent.documentPath,
          currentTextPositionOffset,
          nextCharacterOffset,
        ),
      ),
    );
  }
}
