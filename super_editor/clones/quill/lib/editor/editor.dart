import 'dart:collection';
import 'dart:math';

import 'package:feather/editor/blockquote_component.dart';
import 'package:feather/editor/code_component.dart';
import 'package:feather/editor/toolbar.dart';
import 'package:feather/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';

class FeatherEditor extends StatefulWidget {
  const FeatherEditor({
    super.key,
    required this.editor,
    required this.isShowingDeltas,
    required this.onShowDeltasChange,
  });

  final Editor editor;
  final bool isShowingDeltas;
  final void Function(bool showDeltas) onShowDeltasChange;

  @override
  State<FeatherEditor> createState() => _FeatherEditorState();
}

class _FeatherEditorState extends State<FeatherEditor> {
  final _editorFocusNode = FocusNode();

  @override
  void dispose() {
    _editorFocusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: _borderColor),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        children: [
          FormattingToolbar(
            editorFocusNode: _editorFocusNode,
            editor: widget.editor,
            isShowingDeltas: widget.isShowingDeltas,
            onShowDeltasChange: widget.onShowDeltasChange,
          ),
          const Divider(thickness: 1, height: 1, color: _borderColor),
          Expanded(
            child: _buildEditor(),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return ColoredBox(
      // TODO: Without transparent color, the tap gesture isn't picked up and the
      //       user can't place the caret. This should probably be handled in SuperEditor
      //       somewhere.
      color: Colors.transparent,
      child: SuperEditor(
        focusNode: _editorFocusNode,
        editor: widget.editor,
        stylesheet: featherStylesheet,
        componentBuilders: const [
          FeatherBlockquoteComponentBuilder(),
          FeatherCodeComponentBuilder(),
          ...defaultComponentBuilders,
        ],
        selectionPolicies: const SuperEditorSelectionPolicies(
          clearSelectionWhenEditorLosesFocus: false,
          clearSelectionWhenImeConnectionCloses: false,
        ),
        keyboardActions: [
          // When pressing Enter in a code block, insert a newline in the
          // code block instead of inserting a new empty paragraph.
          enterToInsertNewlineInCodeBlock,
          ...defaultImeKeyboardActions,
        ],
      ),
    );
  }
}

const _borderColor = Color(0xFFDDDDDD);

/// Clears styles applied to selected text.
///
/// If the selection is collapsed (just the caret), then the block-level styles
/// are cleared, e.g., Header 1.
///
/// If the selection is expanded, then text styles are removed only from the
/// selected text. The block styles are left as-is.
class ClearSelectedStylesRequest implements EditRequest {
  const ClearSelectedStylesRequest();
}

class ClearSelectedStylesCommand extends EditCommand {
  const ClearSelectedStylesCommand();

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);
    final selection = composer.selection;
    if (selection == null) {
      return;
    }

    final document = context.find<MutableDocument>(Editor.documentKey);
    if (selection.isCollapsed) {
      // Remove block style.
      final selectedNode = document.getNodeById(selection.extent.targetNodeId);
      if (selectedNode is! TextNode) {
        // Can't remove text block styles from a non-text node.
        return;
      }

      executor.executeCommand(
        ReplaceNodeCommand(
          existingNodeId: selectedNode.id,
          newNode: ParagraphNode(
            id: selectedNode.id,
            text: selectedNode.text,
            metadata: {}, // <-- empty metadata clears all block styles.
          ),
        ),
      );

      return;
    }

    // The selection is expanded. Remove text styles.
    executor.executeCommand(
      ClearTextAttributionsCommand(selection),
    );
  }
}

class ClearTextAttributionsRequest implements EditRequest {
  const ClearTextAttributionsRequest(this.documentRange);

  final DocumentRange documentRange;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClearTextAttributionsRequest && runtimeType == other.runtimeType && documentRange == other.documentRange;

  @override
  int get hashCode => documentRange.hashCode;
}

class ClearTextAttributionsCommand extends EditCommand {
  const ClearTextAttributionsCommand(this.documentRange);

  final DocumentRange documentRange;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.find<MutableDocument>(Editor.documentKey);
    final nodes = document.getNodesInside(documentRange.start, documentRange.end);
    if (nodes.isEmpty) {
      return;
    }

    // Normalize the DocumentRange so we know which DocumentPosition
    // belongs to the first node, and which belongs to the last node.
    final normalizedRange = documentRange.normalize(document);

    // ignore: prefer_collection_literals
    final nodesAndSelections = LinkedHashMap<TextNode, TextRange>();

    for (final textNode in nodes) {
      if (textNode is! TextNode) {
        continue;
      }

      int startOffset = -1;
      int endOffset = -1;

      if (textNode == nodes.first && textNode == nodes.last) {
        // Handle selection within a single node
        startOffset = (normalizedRange.start.nodePosition as TextPosition).offset;

        // -1 because TextPosition's offset indexes the character after the
        // selection, not the final character in the selection.
        endOffset = (normalizedRange.end.nodePosition as TextPosition).offset - 1;
      } else if (textNode == nodes.first) {
        // Handle partial node selection in first node.
        startOffset = (normalizedRange.start.nodePosition as TextPosition).offset;
        endOffset = max(textNode.text.length - 1, 0);
      } else if (textNode == nodes.last) {
        // Handle partial node selection in last node.
        startOffset = 0;

        // -1 because TextPosition's offset indexes the character after the
        // selection, not the final character in the selection.
        endOffset = (normalizedRange.end.nodePosition as TextPosition).offset - 1;
      } else {
        // Handle full node selection.
        startOffset = 0;
        endOffset = max(textNode.text.length - 1, 0);
      }

      final selectionRange = TextRange(start: startOffset, end: endOffset);

      nodesAndSelections.putIfAbsent(textNode, () => selectionRange);
    }

    // Remove attributions.
    for (final entry in nodesAndSelections.entries) {
      final node = entry.key;
      final range = entry.value.toSpanRange();

      final spans = node.text.getAttributionSpansInRange(
        attributionFilter: (a) => true,
        range: range,
        resizeSpansToFitInRange: true,
      );
      for (final span in spans) {
        document.replaceNode(
          oldNode: node,
          newNode: node.copyTextNodeWith(
            text: AttributedText(
              node.text.text,
              node.text.spans.copy()
                ..removeAttribution(
                  attributionToRemove: span.attribution,
                  start: span.start,
                  end: span.end,
                ),
            ),
          ),
        );

        executor.logChanges([
          DocumentEdit(
            AttributionChangeEvent(
              nodeId: node.id,
              change: AttributionChange.removed,
              range: range,
              attributions: {span.attribution},
            ),
          ),
        ]);
      }
    }
  }
}

class ToggleInlineFormatRequest implements EditRequest {
  const ToggleInlineFormatRequest(this.inlineFormat);

  final Attribution inlineFormat;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToggleInlineFormatRequest && runtimeType == other.runtimeType && inlineFormat == other.inlineFormat;

  @override
  int get hashCode => inlineFormat.hashCode;
}

class ToggleInlineFormatCommand extends EditCommand {
  const ToggleInlineFormatCommand(this.inlineFormat);

  final Attribution inlineFormat;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);
    final selection = composer.selection;
    if (selection == null) {
      // No selected content to toggle.
      return;
    }
    if (selection.isCollapsed) {
      // No selected content to toggle.
      return;
    }

    executor.executeCommand(
      ToggleTextAttributionsCommand(
        documentRange: selection,
        attributions: {inlineFormat},
      ),
    );
  }
}

class ToggleTextBlockFormatRequest implements EditRequest {
  const ToggleTextBlockFormatRequest(this.blockFormat);

  final FeatherTextBlock blockFormat;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToggleTextBlockFormatRequest && runtimeType == other.runtimeType && blockFormat == other.blockFormat;

  @override
  int get hashCode => blockFormat.hashCode;
}

class ToggleTextBlockFormatCommand extends EditCommand {
  ToggleTextBlockFormatCommand(this.blockFormat);

  final FeatherTextBlock blockFormat;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);
    final selection = composer.selection;
    if (selection == null) {
      // Nothing is selected.
      return;
    }
    if (selection.base.nodeId != selection.extent.nodeId) {
      // Selection spans multiple nodes. As a policy we only apply block formats
      // one at a time.
      return;
    }

    final document = context.find<MutableDocument>(Editor.documentKey);
    final selectedNode = document.getNodeById(selection.extent.targetNodeId);
    if (selectedNode is! TextNode) {
      // Can't apply a block level text format to a non-text node.
      return;
    }

    final selectedTextBlockType = FeatherTextBlock.fromNode(selectedNode);
    switch (selectedTextBlockType) {
      case FeatherTextBlock.header1:
      case FeatherTextBlock.header2:
      case FeatherTextBlock.header3:
      case FeatherTextBlock.header4:
      case FeatherTextBlock.header5:
      case FeatherTextBlock.header6:
      case FeatherTextBlock.paragraph:
      case FeatherTextBlock.blockquote:
      case FeatherTextBlock.code:
        // The selected node is a ParagraphNode. Toggle the desired block
        // format on that paragraph.
        _toggleFromParagraph(executor, selectedNode as ParagraphNode);
        return;
      case FeatherTextBlock.orderedListItem:
      case FeatherTextBlock.unorderedListItem:
        // The selected node is a ListItemNode.
        _toggleFromListItem(executor, selectedNode as ListItemNode);
        return;
      case FeatherTextBlock.task:
        // The selected node is a TaskNode.
        _toggleFromTask(executor, selectedNode as TaskNode);
        return;
    }
  }

  void _toggleFromParagraph(CommandExecutor executor, ParagraphNode selectedNode) {
    final desiredSuperEditorBlockAttribution = blockFormat.asAttribution;
    if (selectedNode.metadata["blockType"] == desiredSuperEditorBlockAttribution) {
      // The paragraph is already of the desired type. Remove the format because
      // this is a toggle command.
      executor.executeCommand(
        ChangeParagraphBlockTypeCommand(nodeId: selectedNode.id, blockType: null),
      );

      return;
    }

    if (desiredSuperEditorBlockAttribution != null) {
      // The desired block type is a paragraph block type. The selected node
      // is already a paragraph. Update the block type, as desired.
      executor.executeCommand(
        ChangeParagraphBlockTypeCommand(nodeId: selectedNode.id, blockType: desiredSuperEditorBlockAttribution),
      );
      return;
    }

    // The selected node is a ParagraphNode, but the desired block type is
    // a different node type, e.g., ListItemNode. Replace the ParagraphNode
    // with the desired node type.
    executor.executeCommand(
      ReplaceNodeCommand(
        existingNodeId: selectedNode.id,
        newNode: blockFormat.createNode(
          id: selectedNode.id,
          text: selectedNode.text,
          metadata: selectedNode.metadata,
        ),
      ),
    );
  }

  void _toggleFromListItem(CommandExecutor executor, ListItemNode selectedNode) {
    if (selectedNode.type == ListItemType.unordered && blockFormat == FeatherTextBlock.unorderedListItem) {
      // This node is already of the specified type. Therefore, we need to
      // toggle to a regular paragraph.
      executor.executeCommand(ConvertListItemToParagraphCommand(nodeId: selectedNode.id));
      return;
    }

    if (selectedNode.type == ListItemType.ordered && blockFormat == FeatherTextBlock.orderedListItem) {
      // This node is already of the specified type. Therefore, we need to
      // toggle to a regular paragraph.
      executor.executeCommand(ConvertListItemToParagraphCommand(nodeId: selectedNode.id));
      return;
    }

    if (blockFormat == FeatherTextBlock.orderedListItem || blockFormat == FeatherTextBlock.unorderedListItem) {
      // This node is already a list item, but it's not the desired type of list item.
      final newListItemType = blockFormat == FeatherTextBlock.orderedListItem //
          ? ListItemType.ordered
          : ListItemType.unordered;
      executor.executeCommand(ChangeListItemTypeCommand(nodeId: selectedNode.id, newType: newListItemType));
      return;
    }

    // This node is a ListItemNode, but the desired node type is different. Replace the existing
    // node with the desired type of node.
    executor.executeCommand(
      ReplaceNodeCommand(
        existingNodeId: selectedNode.id,
        newNode: blockFormat.createNode(
          id: selectedNode.id,
          text: selectedNode.text,
        ),
      ),
    );
  }

  void _toggleFromTask(CommandExecutor executor, TaskNode selectedNode) {
    if (blockFormat == FeatherTextBlock.task) {
      // The node is already a task node. Toggle it to a regular paragraph.
      executor.executeCommand(ConvertTaskToParagraphCommand(nodeId: selectedNode.id));
      return;
    }

    // This node is a TaskNode, but the desired format wants a different type of
    // node. Replace this node with the desired node.
    executor.executeCommand(
      ReplaceNodeCommand(
        existingNodeId: selectedNode.id,
        newNode: blockFormat.createNode(
          id: selectedNode.id,
          text: selectedNode.text,
        ),
      ),
    );
  }
}

class ConvertTextBlockToFormatRequest implements EditRequest {
  const ConvertTextBlockToFormatRequest(this.blockFormat);

  final FeatherTextBlock blockFormat;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConvertTextBlockToFormatRequest && runtimeType == other.runtimeType && blockFormat == other.blockFormat;

  @override
  int get hashCode => blockFormat.hashCode;
}

class ConvertTextBlockToFormatCommand extends EditCommand {
  ConvertTextBlockToFormatCommand(this.blockFormat);

  final FeatherTextBlock blockFormat;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);
    final selection = composer.selection;
    if (selection == null) {
      // Nothing is selected.
      return;
    }
    if (selection.base.nodeId != selection.extent.nodeId) {
      // Selection spans multiple nodes. As a policy we only apply block formats
      // one at a time.
      return;
    }

    final document = context.find<MutableDocument>(Editor.documentKey);
    final selectedNode = document.getNodeById(selection.extent.targetNodeId);
    if (selectedNode is! TextNode) {
      // Can't apply a block level text format to a non-text node.
      return;
    }

    final selectedTextBlockType = FeatherTextBlock.fromNode(selectedNode);
    switch (selectedTextBlockType) {
      case FeatherTextBlock.header1:
      case FeatherTextBlock.header2:
      case FeatherTextBlock.header3:
      case FeatherTextBlock.header4:
      case FeatherTextBlock.header5:
      case FeatherTextBlock.header6:
      case FeatherTextBlock.paragraph:
      case FeatherTextBlock.blockquote:
      case FeatherTextBlock.code:
        // The selected node is a ParagraphNode.
        _applyToParagraph(executor, selectedNode as ParagraphNode);
        return;
      case FeatherTextBlock.orderedListItem:
      case FeatherTextBlock.unorderedListItem:
        // The selected node is a ListItemNode.
        _applyToListItem(executor, selectedNode as ListItemNode);
        return;
      case FeatherTextBlock.task:
        // The selected node is a TaskNode.
        _applyToTask(executor, selectedNode as TaskNode);
        return;
    }
  }

  void _applyToParagraph(CommandExecutor executor, ParagraphNode selectedNode) {
    final desiredSuperEditorBlockAttribution = blockFormat.asAttribution;
    if (selectedNode.metadata["blockType"] == desiredSuperEditorBlockAttribution) {
      // The paragraph is already the desired type.
      return;
    }

    if (desiredSuperEditorBlockAttribution != null) {
      // The desired block type is a paragraph block type. The selected node
      // is already a paragraph. Update the block type, as desired.
      executor.executeCommand(
        ChangeParagraphBlockTypeCommand(nodeId: selectedNode.id, blockType: desiredSuperEditorBlockAttribution),
      );
      return;
    }

    // The selected node is a ParagraphNode, but the desired block type is
    // a different node type, e.g., ListItemNode. Replace the ParagraphNode
    // with the desired node type.
    executor.executeCommand(
      ReplaceNodeCommand(
        existingNodeId: selectedNode.id,
        newNode: blockFormat.createNode(
          id: selectedNode.id,
          text: selectedNode.text,
          metadata: selectedNode.metadata,
        ),
      ),
    );
  }

  void _applyToListItem(CommandExecutor executor, ListItemNode selectedNode) {
    if (blockFormat == FeatherTextBlock.orderedListItem || blockFormat == FeatherTextBlock.unorderedListItem) {
      // This node is already a list item, but it's not the desired type of list item.
      final newListItemType = blockFormat == FeatherTextBlock.orderedListItem //
          ? ListItemType.ordered
          : ListItemType.unordered;
      executor.executeCommand(ChangeListItemTypeCommand(nodeId: selectedNode.id, newType: newListItemType));
      return;
    }

    // This node is a ListItemNode, but the desired node type is different. Replace the existing
    // node with the desired type of node.
    executor.executeCommand(
      ReplaceNodeCommand(
        existingNodeId: selectedNode.id,
        newNode: blockFormat.createNode(
          id: selectedNode.id,
          text: selectedNode.text,
        ),
      ),
    );
  }

  void _applyToTask(CommandExecutor executor, TaskNode selectedNode) {
    // This node is a TaskNode, but the desired format wants a different type of
    // node. Replace this node with the desired node.
    executor.executeCommand(
      ReplaceNodeCommand(
        existingNodeId: selectedNode.id,
        newNode: blockFormat.createNode(
          id: selectedNode.id,
          text: selectedNode.text,
        ),
      ),
    );
  }
}

ExecutionInstruction enterToInsertNewlineInCodeBlock({
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
  if (selection == null || (selection.base.nodeId != selection.extent.nodeId)) {
    return ExecutionInstruction.continueExecution;
  }
  final selectedNode = editContext.document.getNodeById(selection.extent.targetNodeId)!;
  if (selectedNode is! ParagraphNode || selectedNode.metadata["blockType"] != codeAttribution) {
    return ExecutionInstruction.continueExecution;
  }

  editContext.editor.execute([
    InsertNewlineAtCaretRequest(),
  ]);

  return ExecutionInstruction.haltExecution;
}

enum FeatherTextBlock {
  header1,
  header2,
  header3,
  header4,
  header5,
  header6,
  paragraph,
  blockquote,
  code,
  orderedListItem,
  unorderedListItem,
  task;

  static FeatherTextBlock fromNode(TextNode node) {
    if (node is ParagraphNode) {
      switch (node.metadata["blockType"]) {
        case header1Attribution:
          return header1;
        case header2Attribution:
          return header2;
        case header3Attribution:
          return header3;
        case header4Attribution:
          return header4;
        case header5Attribution:
          return header5;
        case header6Attribution:
          return header6;
        case blockquoteAttribution:
          return blockquote;
        case codeAttribution:
          return code;
        default:
          return paragraph;
      }
    }

    if (node is ListItemNode) {
      switch (node.type) {
        case ListItemType.ordered:
          return orderedListItem;
        case ListItemType.unordered:
          return unorderedListItem;
      }
    }

    if (node is TaskNode) {
      return task;
    }

    throw Exception("Unknown text block type: $node");
  }

  TextNode createNode({
    required String id,
    required AttributedText text,
    Map<String, dynamic>? metadata,
  }) {
    switch (this) {
      case FeatherTextBlock.header1:
      case FeatherTextBlock.header2:
      case FeatherTextBlock.header3:
      case FeatherTextBlock.header4:
      case FeatherTextBlock.header5:
      case FeatherTextBlock.header6:
      case FeatherTextBlock.paragraph:
      case FeatherTextBlock.blockquote:
      case FeatherTextBlock.code:
        return ParagraphNode(
          id: id,
          text: text,
          metadata: Map.from(metadata ?? {})..["blockType"] = asAttribution,
        );
      case FeatherTextBlock.orderedListItem:
        return ListItemNode(
          id: id,
          itemType: ListItemType.ordered,
          text: text,
          metadata: Map.from(metadata ?? {})..["blockType"] = null,
        );
      case FeatherTextBlock.unorderedListItem:
        return ListItemNode(
          id: id,
          itemType: ListItemType.unordered,
          text: text,
          metadata: Map.from(metadata ?? {})..["blockType"] = null,
        );
      case FeatherTextBlock.task:
        return TaskNode(
          id: id,
          text: text,
          isComplete: false,
          metadata: Map.from(metadata ?? {})..["blockType"] = null,
        );
    }
  }

  Attribution? get asAttribution {
    switch (this) {
      case FeatherTextBlock.header1:
        return header1Attribution;
      case FeatherTextBlock.header2:
        return header2Attribution;
      case FeatherTextBlock.header3:
        return header3Attribution;
      case FeatherTextBlock.header4:
        return header4Attribution;
      case FeatherTextBlock.header5:
        return header5Attribution;
      case FeatherTextBlock.header6:
        return header6Attribution;
      case FeatherTextBlock.paragraph:
        return paragraphAttribution;
      case FeatherTextBlock.blockquote:
        return blockquoteAttribution;
      case FeatherTextBlock.code:
        return codeAttribution;
      case FeatherTextBlock.orderedListItem:
      case FeatherTextBlock.unorderedListItem:
      case FeatherTextBlock.task:
        // These block formats map to DocumentNode types, not paragraph
        // block-level attributions.
        return null;
    }
  }
}
