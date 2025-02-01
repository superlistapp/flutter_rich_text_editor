import 'package:attributed_text/attributed_text.dart';
import 'package:flutter/rendering.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/edit_context.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/default_editor/attributions.dart';
import 'package:super_editor/src/default_editor/multi_node_editing.dart';
import 'package:super_editor/src/default_editor/paragraph.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/document_gestures_interaction_overrides.dart';
import 'package:super_editor/src/infrastructure/links.dart';

typedef SuperEditorContentTapDelegateFactory = ContentTapDelegate Function(SuperEditorContext editContext);

SuperEditorLaunchLinkTapHandler superEditorLaunchLinkTapHandlerFactory(SuperEditorContext editContext) =>
    SuperEditorLaunchLinkTapHandler(editContext.document, editContext.composer);

/// A [ContentTapDelegate] that opens links when the user taps text with
/// a [LinkAttribution].
///
/// This delegate only opens links when [composer.isInInteractionMode] is
/// `true`.
class SuperEditorLaunchLinkTapHandler extends ContentTapDelegate {
  SuperEditorLaunchLinkTapHandler(this.document, this.composer) {
    composer.isInInteractionMode.addListener(notifyListeners);
  }

  @override
  void dispose() {
    composer.isInInteractionMode.removeListener(notifyListeners);
    super.dispose();
  }

  final Document document;
  final DocumentComposer composer;

  @override
  MouseCursor? mouseCursorForContentHover(DocumentPosition hoverPosition) {
    if (!composer.isInInteractionMode.value) {
      // The editor isn't in "interaction mode". We don't want a special cursor
      return null;
    }

    final link = _getLinkAtPosition(hoverPosition);
    return link != null ? SystemMouseCursors.click : null;
  }

  @override
  TapHandlingInstruction onTap(DocumentTapDetails details) {
    final tapPosition = details.documentLayout.getDocumentPositionNearestToOffset(details.layoutOffset);
    if (tapPosition == null) {
      return TapHandlingInstruction.continueHandling;
    }

    if (!composer.isInInteractionMode.value) {
      // The editor isn't in "interaction mode". We don't want to allow
      // users to open links by tapping on them.
      return TapHandlingInstruction.continueHandling;
    }

    final link = _getLinkAtPosition(tapPosition);
    if (link != null) {
      // The user tapped on a link. Launch it.
      UrlLauncher.instance.launchUrl(link);
      return TapHandlingInstruction.halt;
    } else {
      // The user didn't tap on a link.
      return TapHandlingInstruction.continueHandling;
    }
  }

  Uri? _getLinkAtPosition(DocumentPosition position) {
    final nodePosition = position.nodePosition;
    if (nodePosition is! TextNodePosition) {
      return null;
    }

    final textNode = document.getNodeById(position.nodeId);
    if (textNode is! TextNode) {
      editorGesturesLog
          .shout("Received a report of a tap on a TextNodePosition, but the node with that ID is a: $textNode");
      return null;
    }

    final tappedAttributions = textNode.text.getAllAttributionsAt(nodePosition.offset);
    for (final tappedAttribution in tappedAttributions) {
      if (tappedAttribution is LinkAttribution) {
        return tappedAttribution.launchableUri;
      }
    }

    return null;
  }
}

SuperEditorAddEmptyParagraphTapHandler superEditorAddEmptyParagraphTapHandlerFactory(SuperEditorContext editContext) =>
    SuperEditorAddEmptyParagraphTapHandler(editContext: editContext);

/// A [ContentTapDelegate] that adds an empty paragraph at the end of the document
/// when the user taps below the last node in the document.
///
/// Does nothing if the last node is a [TextNode].
class SuperEditorAddEmptyParagraphTapHandler extends ContentTapDelegate {
  SuperEditorAddEmptyParagraphTapHandler({
    required this.editContext,
  });

  final SuperEditorContext editContext;

  @override
  TapHandlingInstruction onTap(DocumentTapDetails details) {
    final tapPosition = details.documentLayout.getDocumentPositionNearestToOffset(details.layoutOffset);
    if (tapPosition == null) {
      return TapHandlingInstruction.continueHandling;
    }

    final editor = editContext.editor;
    final document = editContext.document;

    final node = document.getNodeById(tapPosition.nodeId)!;
    if (node is TextNode) {
      return TapHandlingInstruction.continueHandling;
    }

    if (!_isTapBelowLastNode(
      nodeId: tapPosition.nodeId,
      globalOffset: details.globalOffset,
    )) {
      return TapHandlingInstruction.continueHandling;
    }

    // The user tapped below a non-text node. Add a new paragraph
    // to the end of the document and place the caret there.
    final newNodeId = Editor.createNodeId();
    editor.execute([
      InsertNodeAfterNodeRequest(
        existingNodeId: node.id,
        newNode: ParagraphNode(
          id: newNodeId,
          text: AttributedText(),
        ),
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
      const ClearComposingRegionRequest(),
    ]);

    return TapHandlingInstruction.halt;
  }

  bool _isTapBelowLastNode({
    required String nodeId,
    required Offset globalOffset,
  }) {
    final documentLayout = editContext.documentLayout;
    final document = editContext.document;

    final tappedComponent = documentLayout.getComponentByNodeId(nodeId)!;
    final componentBox = tappedComponent.context.findRenderObject() as RenderBox;
    final localPosition = componentBox.globalToLocal(globalOffset);
    final node = document.getNodeById(nodeId);

    return (node == document.lastOrNull) && (localPosition.dy > componentBox.size.height);
  }
}
