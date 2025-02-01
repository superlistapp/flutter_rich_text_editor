import 'package:flutter/material.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/default_editor/multi_node_editing.dart';
import 'package:super_editor/src/default_editor/selection_upstream_downstream.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/flutter/geometry.dart';

import '../core/document_layout.dart';

// ignore: unused_element
final _log = Logger(scope: 'box_component.dart');

/// Base implementation for a [DocumentNode] that only supports [UpstreamDownstreamNodeSelection]s.
@immutable
abstract class BlockNode extends DocumentNode {
  /// A factory method for a collapsed [DocumentSelection] within a [BlockNode]
  /// at the given [nodePath], on the upstream edge.
  ///
  /// This factory is provided as a convenience for less verbose code.
  static DocumentSelection caretAtUpstreamEdge(List<String> nodePath) {
    return DocumentSelection.collapsed(
      position: DocumentPosition(
        documentPath: NodePath(nodePath),
        nodePosition: const UpstreamDownstreamNodePosition.upstream(),
      ),
    );
  }

  /// A factory method for a collapsed [DocumentSelection] within a [BlockNode]
  /// at the given [nodePath], on the downstream edge.
  ///
  /// This factory is provided as a convenience for less verbose code.
  static DocumentSelection caretAtDownstreamEdge(List<String> nodePath) {
    return DocumentSelection.collapsed(
      position: DocumentPosition(
        documentPath: NodePath(nodePath),
        nodePosition: const UpstreamDownstreamNodePosition.downstream(),
      ),
    );
  }

  /// A factory method for a collapsed [DocumentSelection] within a [BlockNode]
  /// at the given [nodePath], on the edge with the given [affinity].
  ///
  /// This factory is provided as a convenience for less verbose code.
  static DocumentSelection caretAtEdge(List<String> nodePath, TextAffinity affinity) {
    return DocumentSelection.collapsed(
      position: DocumentPosition(
        documentPath: NodePath(nodePath),
        nodePosition: UpstreamDownstreamNodePosition(affinity),
      ),
    );
  }

  /// A factory method for a [DocumentSelection] that contains all of the
  /// [BlockNode] at the given [nodePath].
  ///
  /// This factory is provided as a convenience for less verbose code.
  static DocumentSelection selectNodeInDoc(List<String> nodePath) {
    return DocumentSelection(
      base: DocumentPosition(
        documentPath: NodePath(nodePath),
        nodePosition: const UpstreamDownstreamNodePosition.upstream(),
      ),
      extent: DocumentPosition(
        documentPath: NodePath(nodePath),
        nodePosition: const UpstreamDownstreamNodePosition.downstream(),
      ),
    );
  }

  BlockNode({
    Map<String, dynamic>? metadata,
  }) : super(metadata: metadata);

  @override
  UpstreamDownstreamNodePosition get beginningPosition => const UpstreamDownstreamNodePosition.upstream();

  @override
  UpstreamDownstreamNodePosition get endPosition => const UpstreamDownstreamNodePosition.downstream();

  @override
  bool containsPosition(Object position) => position is UpstreamDownstreamNodePosition;

  @override
  UpstreamDownstreamNodePosition selectUpstreamPosition(NodePosition position1, NodePosition position2) {
    if (position1 is! UpstreamDownstreamNodePosition) {
      throw Exception(
          'Expected a UpstreamDownstreamNodePosition for position1 but received a ${position1.runtimeType}');
    }
    if (position2 is! UpstreamDownstreamNodePosition) {
      throw Exception(
          'Expected a UpstreamDownstreamNodePosition for position2 but received a ${position2.runtimeType}');
    }

    if (position1.affinity == TextAffinity.upstream || position2.affinity == TextAffinity.upstream) {
      return const UpstreamDownstreamNodePosition.upstream();
    } else {
      return const UpstreamDownstreamNodePosition.downstream();
    }
  }

  @override
  UpstreamDownstreamNodePosition selectDownstreamPosition(NodePosition position1, NodePosition position2) {
    if (position1 is! UpstreamDownstreamNodePosition) {
      throw Exception(
          'Expected a UpstreamDownstreamNodePosition for position1 but received a ${position1.runtimeType}');
    }
    if (position2 is! UpstreamDownstreamNodePosition) {
      throw Exception(
          'Expected a UpstreamDownstreamNodePosition for position2 but received a ${position2.runtimeType}');
    }

    if (position1.affinity == TextAffinity.downstream || position2.affinity == TextAffinity.downstream) {
      return const UpstreamDownstreamNodePosition.downstream();
    } else {
      return const UpstreamDownstreamNodePosition.upstream();
    }
  }

  @override
  UpstreamDownstreamNodeSelection computeSelection({
    required NodePosition base,
    required NodePosition extent,
  }) {
    if (base is! UpstreamDownstreamNodePosition) {
      throw Exception('Expected a UpstreamDownstreamNodePosition for base but received a ${base.runtimeType}');
    }
    if (extent is! UpstreamDownstreamNodePosition) {
      throw Exception('Expected a UpstreamDownstreamNodePosition for extent but received a ${extent.runtimeType}');
    }

    return UpstreamDownstreamNodeSelection(base: base, extent: extent);
  }
}

/// Editor layout component that displays content that is either
/// entirely selected, or not selected, like an image or a
/// horizontal rule.
class BoxComponent extends StatefulWidget {
  const BoxComponent({
    Key? key,
    this.isVisuallySelectable = true,
    required this.child,
  }) : super(key: key);

  final bool isVisuallySelectable;
  final Widget child;

  @override
  State createState() => _BoxComponentState();
}

class _BoxComponentState extends State<BoxComponent> with DocumentComponent {
  @override
  UpstreamDownstreamNodePosition getBeginningPosition() {
    return const UpstreamDownstreamNodePosition.upstream();
  }

  @override
  UpstreamDownstreamNodePosition getBeginningPositionNearX(double x) {
    final width = (context.findRenderObject() as RenderBox).size.width;

    return x < width / 2
        ? const UpstreamDownstreamNodePosition.upstream()
        : const UpstreamDownstreamNodePosition.downstream();
  }

  @override
  UpstreamDownstreamNodePosition? movePositionLeft(NodePosition currentPosition, [MovementModifier? movementModifier]) {
    if (currentPosition == const UpstreamDownstreamNodePosition.upstream()) {
      // Can't move any further left.
      return null;
    }

    return const UpstreamDownstreamNodePosition.upstream();
  }

  @override
  UpstreamDownstreamNodePosition? movePositionRight(NodePosition currentPosition,
      [MovementModifier? movementModifier]) {
    if (currentPosition == const UpstreamDownstreamNodePosition.downstream()) {
      // Can't move any further right.
      return null;
    }

    return const UpstreamDownstreamNodePosition.downstream();
  }

  @override
  UpstreamDownstreamNodePosition? movePositionUp(NodePosition currentPosition) {
    // BoxComponents don't support vertical movement.
    return null;
  }

  @override
  UpstreamDownstreamNodePosition? movePositionDown(NodePosition currentPosition) {
    // BoxComponents don't support vertical movement.
    return null;
  }

  @override
  UpstreamDownstreamNodeSelection getCollapsedSelectionAt(nodePosition) {
    if (nodePosition is! UpstreamDownstreamNodePosition) {
      throw Exception('The given nodePosition ($nodePosition) is not compatible with BoxComponent');
    }

    return UpstreamDownstreamNodeSelection.collapsed(nodePosition);
  }

  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) {
    return null;
  }

  @override
  UpstreamDownstreamNodePosition getEndPosition() {
    return const UpstreamDownstreamNodePosition.downstream();
  }

  @override
  UpstreamDownstreamNodePosition getEndPositionNearX(double x) {
    final width = (context.findRenderObject() as RenderBox).size.width;

    return x < width / 2
        ? const UpstreamDownstreamNodePosition.upstream()
        : const UpstreamDownstreamNodePosition.downstream();
  }

  @override
  Offset getOffsetForPosition(NodePosition nodePosition) {
    if (nodePosition is! UpstreamDownstreamNodePosition) {
      throw Exception('Expected nodePosition of type UpstreamDownstreamNodePosition but received: $nodePosition');
    }

    final myBox = context.findRenderObject() as RenderBox;

    if (nodePosition.affinity == TextAffinity.upstream) {
      // Technically, we could return any offset in the left half of the component.
      // Arbitrary, we'll return the position at the center of the left half of
      // the component.
      return Offset(myBox.size.width / 4, myBox.size.height / 2);
    } else {
      // Technically, we could return any offset in the right half of the component.
      // Arbitrary, we'll return the position at the center of the right half of
      // the component.
      return Offset(3 * myBox.size.width / 4, myBox.size.height / 2);
    }
  }

  @override
  Rect getEdgeForPosition(NodePosition nodePosition) {
    final boundingBox = getRectForPosition(nodePosition);

    final boxPosition = nodePosition as UpstreamDownstreamNodePosition;
    if (boxPosition.affinity == TextAffinity.upstream) {
      return boundingBox.leftEdge;
    } else {
      return boundingBox.rightEdge;
    }
  }

  /// Returns a [Rect] that bounds this entire box component.
  ///
  /// The behavior of this method is the same, regardless of whether the given
  /// [nodePosition] is `upstream` or `downstream`.
  @override
  Rect getRectForPosition(NodePosition nodePosition) {
    if (nodePosition is! UpstreamDownstreamNodePosition) {
      throw Exception('Expected nodePosition of type UpstreamDownstreamNodePosition but received: $nodePosition');
    }

    final myBox = context.findRenderObject() as RenderBox;

    return Rect.fromLTWH(0, 0, myBox.size.width, myBox.size.height);
  }

  @override
  Rect getRectForSelection(NodePosition basePosition, NodePosition extentPosition) {
    if (basePosition is! UpstreamDownstreamNodePosition) {
      throw Exception('Expected nodePosition of type UpstreamDownstreamNodePosition but received: $basePosition');
    }
    if (extentPosition is! UpstreamDownstreamNodePosition) {
      throw Exception('Expected nodePosition of type UpstreamDownstreamNodePosition but received: $extentPosition');
    }

    final selection = UpstreamDownstreamNodeSelection(base: basePosition, extent: extentPosition);
    if (selection.isCollapsed) {
      return getRectForPosition(selection.extent);
    }

    // The whole component is selected.
    final myBox = context.findRenderObject() as RenderBox;
    return Offset.zero & myBox.size;
  }

  @override
  UpstreamDownstreamNodePosition getPositionAtOffset(Offset localOffset) {
    final myBox = context.findRenderObject() as RenderBox;

    if (localOffset.dx <= myBox.size.width / 2) {
      return const UpstreamDownstreamNodePosition.upstream();
    } else {
      return const UpstreamDownstreamNodePosition.downstream();
    }
  }

  @override
  UpstreamDownstreamNodeSelection getSelectionBetween({required basePosition, required extentPosition}) {
    if (basePosition is! UpstreamDownstreamNodePosition) {
      throw Exception('The given basePosition ($basePosition) is not compatible with BoxComponent');
    }
    if (extentPosition is! UpstreamDownstreamNodePosition) {
      throw Exception('The given extentPosition ($extentPosition) is not compatible with BoxComponent');
    }

    return UpstreamDownstreamNodeSelection(base: basePosition, extent: extentPosition);
  }

  @override
  UpstreamDownstreamNodeSelection getSelectionInRange(Offset localBaseOffset, Offset localExtentOffset) {
    return getSelectionBetween(
      basePosition: getPositionAtOffset(localBaseOffset),
      extentPosition: getPositionAtOffset(localExtentOffset),
    );
  }

  @override
  UpstreamDownstreamNodeSelection getSelectionOfEverything() {
    return const UpstreamDownstreamNodeSelection.all();
  }

  @override
  bool isVisualSelectionSupported() => widget.isVisuallySelectable;

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class SelectableBox extends StatelessWidget {
  const SelectableBox({
    Key? key,
    this.selection,
    required this.selectionColor,
    required this.child,
  }) : super(key: key);

  final UpstreamDownstreamNodeSelection? selection;
  final Color selectionColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isSelected = selection != null && !selection!.isCollapsed;

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSelected ? selectionColor.withValues(alpha: 0.5) : Colors.transparent,
          ),
          position: DecorationPosition.foreground,
          child: child,
        ),
      ),
    );
  }
}

class DeleteUpstreamAtBeginningOfBlockNodeCommand extends EditCommand {
  DeleteUpstreamAtBeginningOfBlockNodeCommand(this.node);

  final DocumentNode node;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;
    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);
    final documentLayoutEditable = context.find<DocumentLayoutEditable>(Editor.layoutKey);

    final deletionPosition = DocumentPosition(
      documentPath: document.getPathByNodeId(node.id)!,
      nodePosition: node.beginningPosition,
    );

    final nodePosition = deletionPosition.nodePosition as UpstreamDownstreamNodePosition;
    if (nodePosition.affinity == TextAffinity.downstream) {
      // The caret is sitting on the downstream edge of block-level content. Delete the
      // whole block by replacing it with an empty paragraph.
      executor.executeCommand(
        ReplaceNodeWithEmptyParagraphWithCaretCommand(
          nodeId: deletionPosition.documentPath.targetNodeId,
        ),
      );
      return;
    }

    // The caret is sitting on the upstream edge of block-level content and
    // the user is trying to delete upstream.
    //  * If the node above is an empty paragraph, delete it.
    //  * If the node above is non-selectable, delete it.
    //  * Otherwise, move the caret up to the node above.
    final nodeBefore = document.getNodeBefore(node);
    if (nodeBefore == null) {
      return;
    }

    if (nodeBefore is TextNode && nodeBefore.text.isEmpty) {
      executor.executeCommand(
        DeleteNodeCommand(nodeId: nodeBefore.id),
      );
      return;
    }

    final componentBefore = documentLayoutEditable.documentLayout.getComponentByNodeId(nodeBefore.id)!;
    if (!componentBefore.isVisualSelectionSupported()) {
      // The node/component above is not selectable. Delete it.
      executor.executeCommand(
        DeleteNodeCommand(nodeId: nodeBefore.id),
      );
      return;
    }

    moveSelectionToEndOfPrecedingNode(executor, document, composer);
  }

  void moveSelectionToEndOfPrecedingNode(
    CommandExecutor executor,
    MutableDocument document,
    MutableDocumentComposer composer,
  ) {
    if (composer.selection == null) {
      return;
    }

    final node = document.getNodeById(composer.selection!.extent.documentPath.targetNodeId);
    if (node == null) {
      return;
    }

    final nodeBefore = document.getNodeBefore(node);
    if (nodeBefore == null) {
      return;
    }

    executor.executeCommand(
      ChangeSelectionCommand(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: document.getPathByNodeId(nodeBefore.id)!,
            nodePosition: nodeBefore.endPosition,
          ),
        ),
        SelectionChangeType.collapseSelection,
        SelectionReason.userInteraction,
      ),
    );
  }
}
