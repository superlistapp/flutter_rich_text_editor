import 'package:attributed_text/attributed_text.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/edit_context.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/default_editor/attributions.dart';
import 'package:super_editor/src/default_editor/blocks/indentation.dart';
import 'package:super_editor/src/default_editor/box_component.dart';
import 'package:super_editor/src/default_editor/multi_node_editing.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/attributed_text_styles.dart';
import 'package:super_editor/src/infrastructure/composable_text.dart';
import 'package:super_editor/src/infrastructure/key_event_extensions.dart';
import 'package:super_editor/src/infrastructure/keyboard.dart';
import 'package:super_editor/src/infrastructure/platforms/platform.dart';
import 'package:super_text_layout/super_text_layout.dart';

import 'layout_single_column/layout_single_column.dart';
import 'text_tools.dart';

@immutable
class ParagraphNode extends TextNode {
  ParagraphNode({
    required super.id,
    required super.text,
    this.indent = 0,
    super.metadata,
  }) {
    if (getMetadataValue("blockType") == null) {
      initAddToMetadata({
        "blockType": paragraphAttribution,
      });
    }
  }

  /// The indent level of this paragraph - `0` is no indent.
  final int indent;

  ParagraphNode copyParagraphWith({
    String? id,
    AttributedText? text,
    int? indent,
    Map<String, dynamic>? metadata,
  }) {
    return ParagraphNode(
      id: id ?? this.id,
      text: text ?? this.text,
      indent: indent ?? this.indent,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  ParagraphNode copyTextNodeWith({
    String? id,
    AttributedText? text,
    Map<String, dynamic>? metadata,
  }) {
    return copyParagraphWith(
      id: id,
      text: text,
      metadata: metadata,
    );
  }

  @override
  ParagraphNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return copyParagraphWith(
      metadata: newMetadata,
    );
  }

  @override
  ParagraphNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return copyParagraphWith(
      metadata: {
        ...metadata,
        ...newProperties,
      },
    );
  }

  @override
  ParagraphNode copy() {
    return ParagraphNode(id: id, text: text.copyText(0), metadata: Map.from(metadata));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is ParagraphNode && runtimeType == other.runtimeType && indent == other.indent;

  @override
  int get hashCode => super.hashCode ^ indent.hashCode;
}

class ParagraphComponentBuilder implements ComponentBuilder {
  const ParagraphComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
    List<ComponentBuilder> componentBuilders,
  ) {
    if (node is! ParagraphNode) {
      return null;
    }

    final textDirection = getParagraphDirection(node.text.toPlainText());

    TextAlign textAlign = (textDirection == TextDirection.ltr) ? TextAlign.left : TextAlign.right;
    final textAlignName = node.getMetadataValue('textAlign');
    switch (textAlignName) {
      case 'left':
        textAlign = TextAlign.left;
        break;
      case 'center':
        textAlign = TextAlign.center;
        break;
      case 'right':
        textAlign = TextAlign.right;
        break;
      case 'justify':
        textAlign = TextAlign.justify;
        break;
    }

    return ParagraphComponentViewModel(
      nodeId: node.id,
      blockType: node.getMetadataValue('blockType'),
      indent: node.indent,
      indentCalculator: defaultParagraphIndentCalculator,
      text: node.text,
      textStyleBuilder: noStyleBuilder,
      textDirection: textDirection,
      textAlignment: textAlign,
      selectionColor: const Color(0x00000000),
    );
  }

  @override
  ParagraphComponent? createComponent(
      SingleColumnDocumentComponentContext componentContext, SingleColumnLayoutComponentViewModel componentViewModel) {
    if (componentViewModel is! ParagraphComponentViewModel) {
      return null;
    }

    editorLayoutLog.fine("Building paragraph component for node: ${componentViewModel.nodeId}");

    if (componentViewModel.selection != null) {
      editorLayoutLog.finer(' - painting a text selection:');
      editorLayoutLog.finer('   base: ${componentViewModel.selection!.base}');
      editorLayoutLog.finer('   extent: ${componentViewModel.selection!.extent}');
    } else {
      editorLayoutLog.finer(' - not painting any text selection');
    }

    return ParagraphComponent(
      key: componentContext.componentKey,
      viewModel: componentViewModel,
    );
  }
}

class ParagraphComponentViewModel extends SingleColumnLayoutComponentViewModel with TextComponentViewModel {
  ParagraphComponentViewModel({
    required String nodeId,
    double? maxWidth,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    this.blockType,
    this.indent = 0,
    this.indentCalculator = defaultParagraphIndentCalculator,
    required this.text,
    required this.textStyleBuilder,
    this.inlineWidgetBuilders = const [],
    this.textDirection = TextDirection.ltr,
    this.textAlignment = TextAlign.left,
    this.textScaler,
    this.selection,
    required this.selectionColor,
    this.highlightWhenEmpty = false,
    TextRange? composingRegion,
    bool showComposingRegionUnderline = false,
    UnderlineStyle spellingErrorUnderlineStyle = const SquiggleUnderlineStyle(color: Colors.red),
    List<TextRange> spellingErrors = const <TextRange>[],
    UnderlineStyle grammarErrorUnderlineStyle = const SquiggleUnderlineStyle(color: Colors.blue),
    List<TextRange> grammarErrors = const <TextRange>[],
  }) : super(nodeId: nodeId, maxWidth: maxWidth, padding: padding) {
    this.composingRegion = composingRegion;
    this.showComposingRegionUnderline = showComposingRegionUnderline;

    this.spellingErrorUnderlineStyle = spellingErrorUnderlineStyle;
    this.spellingErrors = spellingErrors;

    this.grammarErrorUnderlineStyle = grammarErrorUnderlineStyle;
    this.grammarErrors = grammarErrors;
  }

  Attribution? blockType;

  int indent;
  TextBlockIndentCalculator indentCalculator;

  @override
  AttributedText text;
  @override
  AttributionStyleBuilder textStyleBuilder;
  @override
  InlineWidgetBuilderChain inlineWidgetBuilders;
  @override
  TextDirection textDirection;
  @override
  TextAlign textAlignment;

  /// The text scaling policy.
  ///
  /// Defaults to `MediaQuery.textScalerOf()`.
  TextScaler? textScaler;

  @override
  TextSelection? selection;
  @override
  Color selectionColor;
  @override
  bool highlightWhenEmpty;

  @override
  ParagraphComponentViewModel copy() {
    return ParagraphComponentViewModel(
      nodeId: nodeId,
      maxWidth: maxWidth,
      padding: padding,
      blockType: blockType,
      indent: indent,
      indentCalculator: indentCalculator,
      text: text,
      textStyleBuilder: textStyleBuilder,
      inlineWidgetBuilders: inlineWidgetBuilders,
      textDirection: textDirection,
      textAlignment: textAlignment,
      textScaler: textScaler,
      selection: selection,
      selectionColor: selectionColor,
      highlightWhenEmpty: highlightWhenEmpty,
      spellingErrorUnderlineStyle: spellingErrorUnderlineStyle,
      spellingErrors: List.from(spellingErrors),
      grammarErrorUnderlineStyle: grammarErrorUnderlineStyle,
      grammarErrors: List.from(grammarErrors),
      composingRegion: composingRegion,
      showComposingRegionUnderline: showComposingRegionUnderline,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is ParagraphComponentViewModel &&
          runtimeType == other.runtimeType &&
          nodeId == other.nodeId &&
          blockType == other.blockType &&
          indent == other.indent &&
          text == other.text &&
          textDirection == other.textDirection &&
          textAlignment == other.textAlignment &&
          textScaler == other.textScaler &&
          selection == other.selection &&
          selectionColor == other.selectionColor &&
          highlightWhenEmpty == other.highlightWhenEmpty &&
          spellingErrorUnderlineStyle == other.spellingErrorUnderlineStyle &&
          const DeepCollectionEquality().equals(spellingErrors, other.spellingErrors) &&
          grammarErrorUnderlineStyle == other.grammarErrorUnderlineStyle &&
          const DeepCollectionEquality().equals(grammarErrors, other.grammarErrors) &&
          composingRegion == other.composingRegion &&
          showComposingRegionUnderline == other.showComposingRegionUnderline;

  @override
  int get hashCode =>
      super.hashCode ^
      nodeId.hashCode ^
      blockType.hashCode ^
      indent.hashCode ^
      text.hashCode ^
      textDirection.hashCode ^
      textAlignment.hashCode ^
      textScaler.hashCode ^
      selection.hashCode ^
      selectionColor.hashCode ^
      highlightWhenEmpty.hashCode ^
      spellingErrorUnderlineStyle.hashCode ^
      spellingErrors.hashCode ^
      grammarErrorUnderlineStyle.hashCode ^
      grammarErrors.hashCode ^
      composingRegion.hashCode ^
      showComposingRegionUnderline.hashCode;
}

/// The standard [TextBlockIndentCalculator] used by paragraphs in `SuperEditor`.
double defaultParagraphIndentCalculator(TextStyle textStyle, int indent) {
  return ((textStyle.fontSize ?? 16) * 0.60) * 4 * indent;
}

/// A document component that displays a paragraph.
class ParagraphComponent extends StatefulWidget {
  const ParagraphComponent({
    Key? key,
    required this.viewModel,
    this.showDebugPaint = false,
  }) : super(key: key);

  final ParagraphComponentViewModel viewModel;
  final bool showDebugPaint;

  @override
  State<ParagraphComponent> createState() => _ParagraphComponentState();
}

class _ParagraphComponentState extends State<ParagraphComponent>
    with ProxyDocumentComponent<ParagraphComponent>, ProxyTextComposable {
  final _textKey = GlobalKey();

  @override
  GlobalKey<State<StatefulWidget>> get childDocumentComponentKey => _textKey;

  @override
  TextComposable get childTextComposable => childDocumentComponentKey.currentState as TextComposable;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: widget.viewModel.textDirection,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Indent spacing on left.
          SizedBox(
            width: widget.viewModel.indentCalculator(
              widget.viewModel.textStyleBuilder({}),
              widget.viewModel.indent,
            ),
          ),
          // The actual paragraph UI.
          Expanded(
            child: TextComponent(
              key: _textKey,
              text: widget.viewModel.text,
              textDirection: widget.viewModel.textDirection,
              textAlign: widget.viewModel.textAlignment,
              textScaler: widget.viewModel.textScaler,
              textStyleBuilder: widget.viewModel.textStyleBuilder,
              inlineWidgetBuilders: widget.viewModel.inlineWidgetBuilders,
              metadata: widget.viewModel.blockType != null
                  ? {
                      'blockType': widget.viewModel.blockType,
                    }
                  : {},
              textSelection: widget.viewModel.selection,
              selectionColor: widget.viewModel.selectionColor,
              highlightWhenEmpty: widget.viewModel.highlightWhenEmpty,
              underlines: widget.viewModel.createUnderlines(),
              showDebugPaint: widget.showDebugPaint,
            ),
          ),
        ],
      ),
    );
  }
}

class ChangeParagraphAlignmentRequest implements EditRequest {
  ChangeParagraphAlignmentRequest({
    required this.nodeId,
    required this.alignment,
  });

  final String nodeId;
  final TextAlign alignment;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChangeParagraphAlignmentRequest &&
          runtimeType == other.runtimeType &&
          nodeId == other.nodeId &&
          alignment == other.alignment;

  @override
  int get hashCode => nodeId.hashCode ^ alignment.hashCode;
}

class ChangeParagraphAlignmentCommand extends EditCommand {
  const ChangeParagraphAlignmentCommand({
    required this.nodeId,
    required this.alignment,
  });

  final String nodeId;
  final TextAlign alignment;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;

    final existingNode = document.getNodeById(nodeId)! as ParagraphNode;

    String? alignmentName;
    switch (alignment) {
      case TextAlign.left:
      case TextAlign.start:
        alignmentName = 'left';
        break;
      case TextAlign.center:
        alignmentName = 'center';
        break;
      case TextAlign.right:
      case TextAlign.end:
        alignmentName = 'right';
        break;
      case TextAlign.justify:
        alignmentName = 'justify';
        break;
    }

    document.replaceNodeById(
      existingNode.id,
      existingNode.copyParagraphWith(
        metadata: {
          ...existingNode.metadata,
          "textAlign": alignmentName,
        },
      ),
    );

    executor.logChanges([
      DocumentEdit(
        NodeChangeEvent(nodeId),
      ),
    ]);
  }
}

class ChangeParagraphBlockTypeRequest implements EditRequest {
  ChangeParagraphBlockTypeRequest({
    required this.nodeId,
    required this.blockType,
  });

  final String nodeId;
  final Attribution? blockType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChangeParagraphBlockTypeRequest &&
          runtimeType == other.runtimeType &&
          nodeId == other.nodeId &&
          blockType == other.blockType;

  @override
  int get hashCode => nodeId.hashCode ^ blockType.hashCode;
}

class ChangeParagraphBlockTypeCommand extends EditCommand {
  const ChangeParagraphBlockTypeCommand({
    required this.nodeId,
    required this.blockType,
  });

  final String nodeId;
  final Attribution? blockType;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;

    final existingNode = document.getNodeById(nodeId)! as ParagraphNode;
    document.replaceNodeById(
      existingNode.id,
      existingNode.copyParagraphWith(
        metadata: {
          ...existingNode.metadata,
          "blockType": blockType,
        },
      ),
    );

    executor.logChanges([
      DocumentEdit(
        NodeChangeEvent(nodeId),
      ),
    ]);
  }
}

/// [EditRequest] to combine the [ParagraphNode] with [firstNodeId] with the [ParagraphNode] after it, which
/// should have the [secondNodeId].
class CombineParagraphsRequest implements EditRequest {
  CombineParagraphsRequest({
    required this.firstNodeId,
    required this.secondNodeId,
  }) : assert(firstNodeId != secondNodeId);

  final String firstNodeId;
  final String secondNodeId;
}

/// Combines two consecutive `ParagraphNode`s, indicated by `firstNodeId`
/// and `secondNodeId`, respectively.
///
/// If the specified nodes are not sequential, or are sequential
/// in reverse order, the command fizzles.
///
/// If both nodes are not `ParagraphNode`s, the command fizzles.
class CombineParagraphsCommand extends EditCommand {
  CombineParagraphsCommand({
    required this.firstNodeId,
    required this.secondNodeId,
  }) : assert(firstNodeId != secondNodeId);

  final String firstNodeId;
  final String secondNodeId;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    editorDocLog.info('Executing CombineParagraphsCommand');
    editorDocLog.info(' - merging "$firstNodeId" <- "$secondNodeId"');
    final document = context.document;
    final secondNode = document.getNodeById(secondNodeId);
    if (secondNode is! TextNode) {
      editorDocLog.info('WARNING: Cannot merge node of type: $secondNode into node above.');
      return;
    }

    DocumentNode? nodeAbove = document.getNodeBefore(secondNode);
    if (nodeAbove == null) {
      editorDocLog.info('At top of document. Cannot merge with node above.');
      return;
    }

    // Search for a node above the second node that has the id equal to `firstNodeId`.
    //
    // A `CombineParagraphsRequest` might reference nodes that are not contiguous.
    // For example, we might have:
    // - Paragraph 1
    // - <hr> (non-selectable, non-deletable)
    // - Paragraph 2
    //
    // If this case, it's possible to combine Paragraph 1 and Paragraph 2.
    //
    // Because of this, we need to loop until we find the node instead of just
    // comparing with the node immediately above the second node.
    while (nodeAbove != null && nodeAbove.id != firstNodeId) {
      nodeAbove = document.getNodeBefore(nodeAbove);
    }

    if (nodeAbove == null) {
      editorDocLog.info('The specified `firstNodeId` is not the node before `secondNodeId`.');
      return;
    }
    if (nodeAbove is! TextNode) {
      editorDocLog.info('Cannot merge ParagraphNode into node of type: $nodeAbove');
      return;
    }

    // Combine the text and delete the currently selected node.
    final isTopNodeEmpty = nodeAbove.text.isEmpty;

    // Avoid overriding the metadata when the nodeAbove isn't a ParagraphNode.
    //
    // If we are combining different kinds of nodes, e.g., a list item and a paragraph,
    // overriding the metadata will cause the nodeAbove to end up with an incorrect blockType.
    // This will cause incorrect styles to be applied.
    if (isTopNodeEmpty && nodeAbove is ParagraphNode) {
      // If the top node was empty, we want to retain everything in the
      // bottom node, including the block attribution and styles.
      document.replaceNodeById(
        nodeAbove.id,
        nodeAbove.copyTextNodeWith(
          text: nodeAbove.text.copyAndAppend(secondNode.text),
          metadata: secondNode.metadata,
        ),
      );
    } else {
      document.replaceNodeById(
        nodeAbove.id,
        nodeAbove.copyTextNodeWith(
          text: nodeAbove.text.copyAndAppend(secondNode.text),
        ),
      );
    }

    bool didRemove = document.deleteNode(secondNode.id);
    if (!didRemove) {
      editorDocLog.info('ERROR: Failed to delete the currently selected node from the document.');
    }

    executor.logChanges([
      DocumentEdit(
        NodeRemovedEvent(secondNode.id, secondNode),
      ),
      DocumentEdit(
        NodeChangeEvent(nodeAbove.id),
      ),
    ]);
  }
}

class SplitParagraphRequest implements EditRequest {
  SplitParagraphRequest({
    required this.nodeId,
    required this.splitPosition,
    required this.newNodeId,
    required this.replicateExistingMetadata,
    this.attributionsToExtendToNewParagraph = defaultAttributionsToExtendToNewParagraph,
  });

  final String nodeId;
  final TextPosition splitPosition;
  final String newNodeId;
  final bool replicateExistingMetadata;
  // TODO: remove the attribution filter and move the decision to an EditReaction in #1296
  final AttributionFilter attributionsToExtendToNewParagraph;
}

/// The default [Attribution]s, which will be carried over from the end of a paragraph
/// to the beginning of a new paragraph, when splitting a paragraph at the very end.
///
/// In practice, this means that when a user places the caret at the end of paragraph
/// and presses ENTER, these [Attribution]s will be applied to the beginning of the
/// new paragraph.
// TODO: remove the attribution filter and move the decision to an EditReaction in #1296
bool defaultAttributionsToExtendToNewParagraph(Attribution attribution) {
  return _defaultAttributionsToExtend.contains(attribution);
}

final _defaultAttributionsToExtend = {
  boldAttribution,
  italicsAttribution,
  underlineAttribution,
  strikethroughAttribution,
};

/// Splits the `ParagraphNode` affiliated with the given `nodeId` at the
/// given `splitPosition`, placing all text after `splitPosition` in a
/// new `ParagraphNode` with the given `newNodeId`, inserted after the
/// original node.
class SplitParagraphCommand extends EditCommand {
  SplitParagraphCommand({
    required this.nodeId,
    required this.splitPosition,
    required this.newNodeId,
    required this.replicateExistingMetadata,
    this.attributionsToExtendToNewParagraph = defaultAttributionsToExtendToNewParagraph,
  });

  final String nodeId;
  final TextPosition splitPosition;
  final String newNodeId;
  final bool replicateExistingMetadata;
  // TODO: remove the attribution filter and move the decision to an EditReaction in #1296
  final AttributionFilter attributionsToExtendToNewParagraph;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    editorDocLog.info('Executing SplitParagraphCommand');

    final document = context.document;
    final node = document.getNodeById(nodeId);
    if (node is! ParagraphNode) {
      editorDocLog.info('WARNING: Cannot split paragraph for node of type: $node.');
      return;
    }

    final text = node.text;
    final startText = text.copyText(0, splitPosition.offset);
    final endText = text.copyText(splitPosition.offset);
    editorDocLog.info('Splitting paragraph:');
    editorDocLog.info(' - start text: "${startText.toPlainText()}"');
    editorDocLog.info(' - end text: "${endText.toPlainText()}"');

    if (splitPosition.offset == text.length) {
      // The paragraph was split at the very end, the user is creating a new,
      // empty paragraph. We should only extend desired attributions from the end
      // of one paragraph, to the beginning of a new paragraph.
      final newParagraphAttributions = endText.getAttributionSpansInRange(
        attributionFilter: (a) => true,
        range: const SpanRange(0, 0),
      );
      for (final attributionRange in newParagraphAttributions) {
        if (attributionsToExtendToNewParagraph(attributionRange.attribution)) {
          // This is an attribution that should continue into a new paragraph.
          // Letting it stay.
          continue;
        }

        // This attribution shouldn't extend from one paragraph to another. Remove it.
        endText.removeAttribution(
          attributionRange.attribution,
          attributionRange.range,
        );
      }
    }

    // Change the current nodes content to just the text before the caret.
    editorDocLog.info(' - changing the original paragraph text due to split');
    final updatedNode = node.copyParagraphWith(text: startText);
    document.replaceNodeById(
      node.id,
      updatedNode,
    );

    // Create a new node that will follow the current node. Set its text
    // to the text that was removed from the current node. And create a
    // new copy of the metadata if `replicateExistingMetadata` is true.
    final newNode = ParagraphNode(
      id: newNodeId,
      text: endText,
      indent: node.indent,
      metadata: replicateExistingMetadata ? node.copyMetadata() : {},
    );

    // Insert the new node after the current node.
    editorDocLog.info(' - inserting new node in document');
    document.insertNodeAfter(
      existingNodeId: updatedNode.id,
      newNode: newNode,
    );

    editorDocLog.info(' - inserted new node: ${newNode.id} after old one: ${node.id}');

    // Move the caret to the new node.
    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);
    final oldSelection = composer.selection;
    final oldComposingRegion = composer.composingRegion.value;
    final newSelection = DocumentSelection.collapsed(
      position: DocumentPosition(
        documentPath: document.getPathByNodeId(newNodeId)!,
        nodePosition: const TextNodePosition(offset: 0),
      ),
    );

    composer.setSelectionWithReason(newSelection, SelectionReason.userInteraction);
    composer.setComposingRegion(null);

    final documentChanges = [
      DocumentEdit(
        NodeChangeEvent(node.id),
      ),
      DocumentEdit(
        NodeInsertedEvent(newNodeId, document.getNodeIndexById(newNodeId)),
      ),
      SelectionChangeEvent(
        oldSelection: oldSelection,
        newSelection: newSelection,
        changeType: SelectionChangeType.insertContent,
        reason: SelectionReason.userInteraction,
      ),
      ComposingRegionChangeEvent(
        oldComposingRegion: oldComposingRegion,
        newComposingRegion: null,
      ),
    ];

    if (newNode.text.isEmpty) {
      executor.logChanges([
        SubmitParagraphIntention.start(),
        ...documentChanges,
        SubmitParagraphIntention.end(),
      ]);
    } else {
      executor.logChanges([
        SplitParagraphIntention.start(),
        ...documentChanges,
        SplitParagraphIntention.end(),
      ]);
    }
  }
}

class DeleteUpstreamAtBeginningOfParagraphCommand extends EditCommand {
  DeleteUpstreamAtBeginningOfParagraphCommand(this.node);

  final DocumentNode node;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    if (node is! ParagraphNode) {
      return;
    }

    final document = context.document;
    final deletionPosition = DocumentPosition(
      documentPath: document.getPathByNodeId(node.id)!,
      nodePosition: node.beginningPosition,
    );
    if (deletionPosition.nodePosition is! TextNodePosition) {
      return;
    }

    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);
    final documentLayoutEditable = context.find<DocumentLayoutEditable>(Editor.layoutKey);

    final paragraphNode = node as ParagraphNode;
    if (paragraphNode.metadata["blockType"] != paragraphAttribution) {
      executor.executeCommand(
        ChangeParagraphBlockTypeCommand(
          nodeId: node.id,
          blockType: paragraphAttribution,
        ),
      );
      return;
    }

    DocumentNode? nodeBefore = document.getNodeBefore(node);
    while (nodeBefore is BlockNode && !nodeBefore.isDeletable) {
      nodeBefore = document.getNodeBefore(nodeBefore);
    }

    if (nodeBefore == null) {
      return;
    }

    if (nodeBefore is TextNode) {
      // The caret is at the beginning of one TextNode and is preceded by
      // another TextNode. Merge the two TextNodes.
      mergeTextNodeWithUpstreamTextNode(executor, document, composer);
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

    if ((node as TextNode).text.isEmpty) {
      // The caret is at the beginning of an empty TextNode and the preceding
      // node is not a TextNode. Delete the current TextNode and move the
      // selection up to the preceding node if exist.
      executor.executeCommand(
        DeleteNodeCommand(nodeId: node.id),
      );
    }
  }

  /// Merges the selected [TextNode] with the upstream [TextNode].
  ///
  /// If there are non-deletable [BlockNode]s between the two [TextNode]s,
  /// the [BlockNode]s are retained without modification.
  bool mergeTextNodeWithUpstreamTextNode(
    CommandExecutor executor,
    MutableDocument document,
    MutableDocumentComposer composer,
  ) {
    final node = document.getNodeById(composer.selection!.extent.nodeId);
    if (node == null) {
      return false;
    }

    DocumentNode? nodeAbove = document.getNodeBefore(node);
    while (nodeAbove is BlockNode && !nodeAbove.isDeletable) {
      nodeAbove = document.getNodeBefore(nodeAbove);
    }

    if (nodeAbove == null) {
      return false;
    }
    if (nodeAbove is! TextNode) {
      return false;
    }

    final aboveParagraphLength = nodeAbove.text.length;

    // Send edit command.
    executor
      ..executeCommand(
        CombineParagraphsCommand(
          firstNodeId: nodeAbove.id,
          secondNodeId: node.id,
        ),
      )
      ..executeCommand(
        ChangeSelectionCommand(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              documentPath: document.getPathByNodeId(nodeAbove.id)!,
              nodePosition: TextNodePosition(offset: aboveParagraphLength),
            ),
          ),
          SelectionChangeType.deleteContent,
          SelectionReason.userInteraction,
        ),
      );

    return true;
  }

  void moveSelectionToEndOfPrecedingNode(
    CommandExecutor executor,
    MutableDocument document,
    MutableDocumentComposer composer,
  ) {
    if (composer.selection == null) {
      return;
    }

    final node = document.getNodeById(composer.selection!.extent.nodeId);
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

class Intention extends EditEvent {
  Intention.start() : _isStart = true;

  Intention.end() : _isStart = false;

  final bool _isStart;

  bool get isStart => _isStart;

  bool get isEnd => !_isStart;
}

class SplitParagraphIntention extends Intention {
  SplitParagraphIntention.start() : super.start();

  SplitParagraphIntention.end() : super.end();
}

class SubmitParagraphIntention extends Intention {
  SubmitParagraphIntention.start() : super.start();

  SubmitParagraphIntention.end() : super.end();
}

ExecutionInstruction anyCharacterToInsertInParagraph({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  // Do nothing if CMD or CTRL are pressed because this signifies an attempted
  // shortcut.
  if (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) {
    return ExecutionInstruction.continueExecution;
  }

  var character = keyEvent.character;
  if (character == null || character == '') {
    return ExecutionInstruction.continueExecution;
  }

  if (LogicalKeyboardKey.isControlCharacter(keyEvent.character!) || keyEvent.isArrowKeyPressed) {
    return ExecutionInstruction.continueExecution;
  }

  // On web, keys like shift and alt are sending their full name
  // as a character, e.g., "Shift" and "Alt". This check prevents
  // those keys from inserting their name into content.
  if (isKeyEventCharacterBlacklisted(character) && character != 'Tab') {
    return ExecutionInstruction.continueExecution;
  }

  // The web reports a tab as "Tab". Intercept it and translate it to a space.
  if (character == 'Tab') {
    character = ' ';
  }

  final didInsertCharacter = editContext.commonOps.insertCharacter(character);

  return didInsertCharacter ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

class DeleteParagraphCommand extends EditCommand {
  DeleteParagraphCommand({
    required this.nodeId,
  });

  final String nodeId;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    editorDocLog.info('Executing DeleteParagraphCommand');
    editorDocLog.info(' - deleting "$nodeId"');
    final document = context.document;
    final node = document.getNodeById(nodeId);
    if (node is! TextNode) {
      editorDocLog.shout('WARNING: Cannot delete node of type: $node.');
      return;
    }

    bool didRemove = document.deleteNode(node.id);
    if (!didRemove) {
      editorDocLog.shout('ERROR: Failed to delete node "$node" from the document.');
    }

    executor.logChanges([
      DocumentEdit(
        NodeRemovedEvent(node.id, node),
      )
    ]);
  }
}

/// When the caret is collapsed at the beginning of a ParagraphNode
/// and backspace is pressed, clear any existing block type, e.g.,
/// header 1, header 2, blockquote.
ExecutionInstruction backspaceToClearParagraphBlockType({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }

  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  if (!editContext.composer.selection!.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }

  final node = editContext.document.getNodeById(editContext.composer.selection!.extent.nodeId);
  if (node is! ParagraphNode) {
    return ExecutionInstruction.continueExecution;
  }

  final textPosition = editContext.composer.selection!.extent.nodePosition;
  if (textPosition is! TextNodePosition || textPosition.offset > 0) {
    return ExecutionInstruction.continueExecution;
  }

  final didClearBlockType = editContext.commonOps.convertToParagraph();
  return didClearBlockType ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

/// Un-indents the current paragraph if the paragraph is empty and the user
/// pressed Enter.
ExecutionInstruction enterToUnIndentParagraph({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.enter && keyEvent.logicalKey != LogicalKeyboardKey.numpadEnter) {
    return ExecutionInstruction.continueExecution;
  }

  final selection = editContext.composer.selection;
  if (selection == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (!selection.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }

  final paragraph = editContext.document.getNodeById(selection.extent.nodeId);
  if (paragraph is! ParagraphNode) {
    // This policy only applies to paragraphs.
    return ExecutionInstruction.continueExecution;
  }
  if (paragraph.indent == 0) {
    // Nothing to un-indent.
    return ExecutionInstruction.continueExecution;
  }
  if (paragraph.text.isNotEmpty) {
    // We only un-indent when the user presses Enter in an empty paragraph.
    return ExecutionInstruction.continueExecution;
  }

  // Un-indent the paragraph.
  editContext.editor.execute([
    UnIndentParagraphRequest(paragraph.id),
  ]);

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction enterToInsertBlockNewline({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.enter && keyEvent.logicalKey != LogicalKeyboardKey.numpadEnter) {
    return ExecutionInstruction.continueExecution;
  }

  editContext.editor.execute([
    InsertNewlineAtCaretRequest(Editor.createNodeId()),
  ]);

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction tabToIndentParagraph({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.tab) {
    return ExecutionInstruction.continueExecution;
  }

  if (HardwareKeyboard.instance.isShiftPressed) {
    // Don't indent if Shift is pressed - that's for un-indenting.
    return ExecutionInstruction.continueExecution;
  }

  final selection = editContext.composer.selection;
  if (selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  if (selection.base.nodeId != selection.extent.nodeId) {
    // Selection spans nodes, so even if this selection includes a paragraph,
    // it includes other stuff, too. So we can't treat this as a paragraph indentation.
    return ExecutionInstruction.continueExecution;
  }

  final node = editContext.document.getNodeById(editContext.composer.selection!.extent.nodeId);
  if (node is! ParagraphNode) {
    return ExecutionInstruction.continueExecution;
  }

  editContext.editor.execute([
    IndentParagraphRequest(node.id),
  ]);

  return ExecutionInstruction.haltExecution;
}

class SetParagraphIndentRequest implements EditRequest {
  const SetParagraphIndentRequest(
    this.nodeId, {
    required this.level,
  });

  final String nodeId;
  final int level;
}

class SetParagraphIndentCommand extends EditCommand {
  const SetParagraphIndentCommand(
    this.nodeId, {
    required this.level,
  });

  final String nodeId;
  final int level;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;

    final paragraph = document.getNodeById(nodeId);
    if (paragraph is! ParagraphNode) {
      // The specified node isn't a paragraph. Nothing for us to indent.
      return;
    }

    // Decrease the paragraph indentation of the desired paragraph.
    document.replaceNodeById(
      paragraph.id,
      paragraph.copyParagraphWith(
        indent: level,
      ),
    );

    // Log all changes.
    executor.logChanges([
      DocumentEdit(
        NodeChangeEvent(paragraph.id),
      ),
    ]);
  }
}

class IndentParagraphRequest implements EditRequest {
  const IndentParagraphRequest(this.nodeId);

  final String nodeId;
}

class IndentParagraphCommand extends EditCommand {
  const IndentParagraphCommand(this.nodeId);

  final String nodeId;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;

    final paragraph = document.getNodeById(nodeId);
    if (paragraph is! ParagraphNode) {
      // The specified node isn't a paragraph. Nothing for us to indent.
      return;
    }

    // Increase the paragraph indentation.
    document.replaceNodeById(
      paragraph.id,
      paragraph.copyParagraphWith(indent: paragraph.indent + 1),
    );

    executor.logChanges([
      DocumentEdit(
        NodeChangeEvent(paragraph.id),
      ),
    ]);
  }
}

ExecutionInstruction shiftTabToUnIndentParagraph({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.tab) {
    return ExecutionInstruction.continueExecution;
  }
  if (!HardwareKeyboard.instance.isShiftPressed) {
    return ExecutionInstruction.continueExecution;
  }

  final selection = editContext.composer.selection;
  if (selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  if (selection.base.nodeId != selection.extent.nodeId) {
    // Selection spans nodes, so even if this selection includes a paragraph,
    // it includes other stuff, too. So we can't treat this as a paragraph indentation.
    return ExecutionInstruction.continueExecution;
  }

  final node = editContext.document.getNodeById(editContext.composer.selection!.extent.nodeId);
  if (node is! ParagraphNode) {
    return ExecutionInstruction.continueExecution;
  }

  if (node.indent == 0) {
    // Can't un-indent any further.
    return ExecutionInstruction.continueExecution;
  }

  editContext.editor.execute([
    UnIndentParagraphRequest(node.id),
  ]);

  return ExecutionInstruction.haltExecution;
}

class UnIndentParagraphRequest implements EditRequest {
  const UnIndentParagraphRequest(this.nodeId);

  final String nodeId;
}

class UnIndentParagraphCommand extends EditCommand {
  const UnIndentParagraphCommand(this.nodeId);

  final String nodeId;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;

    final paragraph = document.getNodeById(nodeId);
    if (paragraph is! ParagraphNode) {
      // The specified node isn't a paragraph. Nothing for us to indent.
      return;
    }

    if (paragraph.indent == 0) {
      // This paragraph is already at minimum indent. Nothing to do.
      return;
    }

    // Decrease the paragraph indentation of the desired paragraph.
    document.replaceNodeById(
      paragraph.id,
      paragraph.copyParagraphWith(indent: paragraph.indent - 1),
    );

    // Log all changes.
    executor.logChanges([
      DocumentEdit(
        NodeChangeEvent(paragraph.id),
      ),
    ]);
  }
}

ExecutionInstruction backspaceToUnIndentParagraph({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }

  final selection = editContext.composer.selection;
  if (selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  if (selection.base.nodeId != selection.extent.nodeId) {
    // Selection spans nodes, so even if this selection includes a paragraph,
    // it includes other stuff, too. So we can't treat this as a paragraph indentation.
    return ExecutionInstruction.continueExecution;
  }

  final node = editContext.document.getNodeById(editContext.composer.selection!.extent.nodeId);
  if (node is! ParagraphNode) {
    return ExecutionInstruction.continueExecution;
  }
  if ((editContext.composer.selection!.extent.nodePosition as TextPosition).offset > 0) {
    // Backspace should only un-indent if the caret is at the start of the text.
    return ExecutionInstruction.continueExecution;
  }

  if (node.indent == 0) {
    // Can't un-indent any further.
    return ExecutionInstruction.continueExecution;
  }

  editContext.editor.execute([
    UnIndentParagraphRequest(node.id),
  ]);

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction moveParagraphSelectionUpWhenBackspaceIsPressed({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (!editContext.composer.selection!.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }

  final node = editContext.document.getNodeById(editContext.composer.selection!.extent.nodeId);
  if (node is! ParagraphNode) {
    return ExecutionInstruction.continueExecution;
  }

  if (node.text.isEmpty) {
    return ExecutionInstruction.continueExecution;
  }

  final nodeAbove = editContext.document.getNodeBeforeById(node.id);
  if (nodeAbove == null) {
    return ExecutionInstruction.continueExecution;
  }
  final newDocumentPosition = DocumentPosition(
    documentPath: editContext.document.getPathByNodeId(nodeAbove.id)!,
    nodePosition: nodeAbove.endPosition,
  );

  editContext.editor.execute([
    ChangeSelectionRequest(
      DocumentSelection.collapsed(
        position: newDocumentPosition,
      ),
      SelectionChangeType.deleteContent,
      SelectionReason.userInteraction,
    ),
  ]);

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction doNothingWithEnterOnWeb({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.enter && keyEvent.logicalKey != LogicalKeyboardKey.numpadEnter) {
    return ExecutionInstruction.continueExecution;
  }

  if (CurrentPlatform.isWeb) {
    // On web, pressing enter generates both a key event and a `TextInputAction.newline` action.
    // We handle the newline action and ignore the key event.
    // We return blocked so the OS can process it.
    return ExecutionInstruction.blocked;
  }

  return ExecutionInstruction.continueExecution;
}

ExecutionInstruction doNothingWithBackspaceOnWeb({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }

  if (CurrentPlatform.isWeb) {
    // On web, pressing backspace generates both a key event and a deletion delta.
    // We handle the deletion delta and ignore the key event.
    // We return blocked so the OS can process it.
    return ExecutionInstruction.blocked;
  }

  return ExecutionInstruction.continueExecution;
}

ExecutionInstruction doNothingWithCtrlOrCmdAndZOnWeb({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.keyZ) {
    return ExecutionInstruction.continueExecution;
  }

  if (CurrentPlatform.isApple && !HardwareKeyboard.instance.isMetaPressed) {
    return ExecutionInstruction.continueExecution;
  }

  if (!CurrentPlatform.isApple && !HardwareKeyboard.instance.isControlPressed) {
    return ExecutionInstruction.continueExecution;
  }

  if (CurrentPlatform.isWeb) {
    // On web, pressing Cmd + Z on Mac or Ctrl + Z on Windows and Linux
    // triggers the UNDO action of the HTML text input, which doesn't work for us.
    // Prevent the browser from handling the shortcut.
    return ExecutionInstruction.haltExecution;
  }

  return ExecutionInstruction.continueExecution;
}

ExecutionInstruction doNothingWithDeleteOnWeb({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.delete) {
    return ExecutionInstruction.continueExecution;
  }

  if (CurrentPlatform.isWeb) {
    // On web, pressing delete generates both a key event and a deletion delta.
    // We handle the deletion delta and ignore the key event.
    // We return blocked so the OS can process it.
    return ExecutionInstruction.blocked;
  }

  return ExecutionInstruction.continueExecution;
}
