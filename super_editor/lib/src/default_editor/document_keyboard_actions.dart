import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/edit_context.dart';
import 'package:super_editor/src/default_editor/attributions.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/keyboard.dart';
import 'package:super_editor/super_editor.dart';

import 'document_interaction.dart';
import 'multi_node_editing.dart';
import 'paragraph.dart';
import 'text.dart';

final _log = Logger(scope: 'document_keyboard_actions.dart');

ExecutionInstruction doNothingWhenThereIsNoSelection({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (editContext.composer.selection == null) {
    _log.log('doNothingWhenThereIsNoSelection', ' - no selection. Returning.');
    return ExecutionInstruction.haltExecution;
  } else {
    return ExecutionInstruction.continueExecution;
  }
}

ExecutionInstruction pasteWhenCmdVIsPressed({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.character?.toLowerCase() != 'v') {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  _log.log('pasteWhenCmdVIsPressed', 'Pasting clipboard content...');
  DocumentPosition pastePosition = editContext.composer.selection!.extent;

  // Delete all currently selected content.
  if (!editContext.composer.selection!.isCollapsed) {
    pastePosition = _getDocumentPositionAfterDeletion(
      document: editContext.editor.document,
      selection: editContext.composer.selection!,
    );

    // Delete the selected content.
    editContext.editor.executeCommand(
      DeleteSelectionCommand(documentSelection: editContext.composer.selection!),
    );

    editContext.composer.selection = DocumentSelection.collapsed(position: pastePosition);
  }

  // TODO: figure out a general approach for asynchronous behaviors that
  //       need to be carried out in response to user input.
  _paste(
    document: editContext.editor.document,
    editor: editContext.editor,
    composer: editContext.composer,
    pastePosition: pastePosition,
  );

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction selectAllWhenCmdAIsPressed({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.character?.toLowerCase() != 'a') {
    return ExecutionInstruction.continueExecution;
  }

  final didSelectAll = editContext.commonOps.selectAll();
  return didSelectAll ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

Future<void> _paste({
  required Document document,
  required DocumentEditor editor,
  required DocumentComposer composer,
  required DocumentPosition pastePosition,
}) async {
  final content = (await Clipboard.getData('text/plain'))?.text ?? '';
  _log.log('_paste', 'Content from clipboard: $content');

  editor.executeCommand(
    _PasteEditorCommand(
      content: content,
      pastePosition: pastePosition,
      composer: composer,
    ),
  );
}

class _PasteEditorCommand implements EditorCommand {
  _PasteEditorCommand({
    required String content,
    required DocumentPosition pastePosition,
    required DocumentComposer composer,
  })  : _content = content,
        _pastePosition = pastePosition,
        _composer = composer;

  final String _content;
  final DocumentPosition _pastePosition;
  final DocumentComposer _composer;

  @override
  void execute(Document document, DocumentEditorTransaction transaction) {
    final splitContent = _content.split('\n\n');
    _log.log('_PasteEditorCommand', 'Split content:');
    for (final piece in splitContent) {
      _log.log('_PasteEditorCommand', ' - "$piece"');
    }

    final currentNodeWithSelection = document.getNodeById(_pastePosition.nodeId);

    DocumentPosition? newSelectionPosition;

    if (currentNodeWithSelection is TextNode) {
      final textNode = document.getNode(_pastePosition) as TextNode;
      final pasteTextOffset = (_pastePosition.nodePosition as TextPosition).offset;
      final attributionsAtPasteOffset = textNode.text.getAllAttributionsAt(pasteTextOffset);

      if (splitContent.length > 1 && pasteTextOffset < textNode.endPosition.offset) {
        // There is more than 1 node of content being pasted. Therefore,
        // new nodes will need to be added, which means that the currently
        // selected text node will be split at the current text offset.
        // Configure a new node to be added at the end of the pasted content
        // which contains the trailing text from the currently selected
        // node.
        if (currentNodeWithSelection is ParagraphNode) {
          SplitParagraphCommand(
            nodeId: currentNodeWithSelection.id,
            splitPosition: TextPosition(offset: pasteTextOffset),
            newNodeId: DocumentEditor.createNodeId(),
            replicateExistingMetdata: false,
          ).execute(document, transaction);
        } else {
          throw Exception('Can\'t handle pasting text within node of type: $currentNodeWithSelection');
        }
      }

      // Paste the first piece of content into the selected TextNode.
      InsertTextCommand(
        documentPosition: _pastePosition,
        textToInsert: splitContent.first,
        attributions: attributionsAtPasteOffset,
      ).execute(document, transaction);

      // At this point in the paste process, the document selection
      // position is at the end of the text that was just pasted.
      newSelectionPosition = DocumentPosition(
        nodeId: currentNodeWithSelection.id,
        nodePosition: TextNodePosition(
          offset: pasteTextOffset + splitContent.first.length,
        ),
      );

      // Remove the pasted text from the list of pieces of text
      // to paste.
      splitContent.removeAt(0);
    }

    final newNodes = splitContent
        .map(
          // TODO: create nodes based on content inspection.
          (nodeText) => ParagraphNode(
            id: DocumentEditor.createNodeId(),
            text: AttributedText(
              text: nodeText,
            ),
          ),
        )
        .toList();
    _log.log('_PasteEditorCommand', ' - new nodes: $newNodes');

    int newNodeToMergeIndex = 0;
    DocumentNode mergeAfterNode;

    final nodeWithSelection = document.getNodeById(_pastePosition.nodeId);
    if (nodeWithSelection == null) {
      throw Exception(
          'Failed to complete paste process because the node being pasted into disappeared from the document unexpectedly.');
    }
    mergeAfterNode = nodeWithSelection;

    for (int i = newNodeToMergeIndex; i < newNodes.length; ++i) {
      transaction.insertNodeAfter(
        previousNode: mergeAfterNode,
        newNode: newNodes[i],
      );
      mergeAfterNode = newNodes[i];

      newSelectionPosition = DocumentPosition(
        nodeId: mergeAfterNode.id,
        nodePosition: mergeAfterNode.endPosition,
      );
    }

    _composer.selection = DocumentSelection.collapsed(
      position: newSelectionPosition!,
    );
    _log.log('_PasteEditorCommand', ' - new selection: ${_composer.selection}');

    _log.log('_PasteEditorCommand', 'Done with paste command.');
  }
}

ExecutionInstruction copyWhenCmdCIsPressed({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.character?.toLowerCase() != 'c') {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection!.isCollapsed) {
    // Nothing to copy, but we technically handled the task.
    return ExecutionInstruction.haltExecution;
  }

  final textToCopy = _textInSelection(
    document: editContext.editor.document,
    documentSelection: editContext.composer.selection!,
  );
  // TODO: figure out a general approach for asynchronous behaviors that
  //       need to be carried out in response to user input.
  _saveToClipboard(textToCopy);

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction cutWhenCmdXIsPressed({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.character?.toLowerCase() != 'x') {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection!.isCollapsed) {
    // Nothing to cut, but we technically handled the task.
    return ExecutionInstruction.haltExecution;
  }

  final textToCut = _textInSelection(
    document: editContext.editor.document,
    documentSelection: editContext.composer.selection!,
  );
  // TODO: figure out a general approach for asynchronous behaviors that
  //       need to be carried out in response to user input.
  _saveToClipboard(textToCut);

  editContext.commonOps.deleteSelection();
  return ExecutionInstruction.haltExecution;
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
      final baseSelectionPosition = selectedNode.id == documentSelection.base.nodeId
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
      final nodePosition = selectedNode.id == documentSelection.base.nodeId
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

ExecutionInstruction cmdBToToggleBold({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.character?.toLowerCase() != 'b') {
    return ExecutionInstruction.continueExecution;
  }

  if (editContext.composer.selection!.isCollapsed) {
    editContext.commonOps.toggleComposerAttributions({boldAttribution});
    return ExecutionInstruction.haltExecution;
  } else {
    editContext.commonOps.toggleAttributionsOnSelection({boldAttribution});
    return ExecutionInstruction.haltExecution;
  }
}

ExecutionInstruction cmdIToToggleItalics({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.character?.toLowerCase() != 'i') {
    return ExecutionInstruction.continueExecution;
  }

  if (editContext.composer.selection!.isCollapsed) {
    editContext.commonOps.toggleComposerAttributions({italicsAttribution});
    return ExecutionInstruction.haltExecution;
  } else {
    editContext.commonOps.toggleAttributionsOnSelection({italicsAttribution});
    return ExecutionInstruction.haltExecution;
  }
}

ExecutionInstruction anyCharacterOrDestructiveKeyToDeleteSelection({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  _log.log('deleteExpandedSelectionWhenCharacterOrDestructiveKeyPressed', 'Running...');
  if (editContext.composer.selection == null || editContext.composer.selection!.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }

  // Specifically exclude situations where shift is pressed because shift
  // needs to alter the selection, not delete content. We have to explicitly
  // look for this because when shift is pressed along with an arrow key,
  // Flutter reports a non-null character.
  final isShiftPressed = keyEvent.isShiftPressed;

  final isDestructiveKey =
      keyEvent.logicalKey == LogicalKeyboardKey.backspace || keyEvent.logicalKey == LogicalKeyboardKey.delete;

  final shouldDeleteSelection = !isShiftPressed &&
      (isDestructiveKey ||
          (keyEvent.character != null &&
              keyEvent.character != '' &&
              !webBugBlacklistCharacters.contains(keyEvent.character)));
  if (!shouldDeleteSelection) {
    return ExecutionInstruction.continueExecution;
  }

  editContext.commonOps.deleteSelection();
  return ExecutionInstruction.haltExecution;
}

DocumentPosition _getDocumentPositionAfterDeletion({
  required Document document,
  required DocumentSelection selection,
}) {
  // Figure out where the caret should appear after the
  // deletion.
  // TODO: This calculation depends upon the first
  //       selected node still existing after the deletion. This
  //       is a fragile expectation and should be revisited.
  final basePosition = selection.base;
  final baseNode = document.getNode(basePosition);
  if (baseNode == null) {
    throw Exception('Failed to _getDocumentPositionAfterDeletion because the base node no longer exists.');
  }
  final baseNodeIndex = document.getNodeIndex(baseNode);

  final extentPosition = selection.extent;
  final extentNode = document.getNode(extentPosition);
  if (extentNode == null) {
    throw Exception('Failed to _getDocumentPositionAfterDeletion because the extent node no longer exists.');
  }
  final extentNodeIndex = document.getNodeIndex(extentNode);
  DocumentPosition newSelectionPosition;

  if (baseNodeIndex != extentNodeIndex) {
    // Place the caret at the current position within the
    // first node in the selection.
    newSelectionPosition = baseNodeIndex <= extentNodeIndex ? selection.base : selection.extent;

    // If it's a binary selection node then that node will
    // be replaced by a ParagraphNode with the same ID.
    if (newSelectionPosition.nodePosition is BinaryNodePosition) {
      // Assume that the node was replaced with an empty paragraph.
      newSelectionPosition = DocumentPosition(
        nodeId: newSelectionPosition.nodeId,
        nodePosition: const TextNodePosition(offset: 0),
      );
    }
  } else {
    // Selection is within a single node. If it's a binary
    // selection node then that node will be replaced by
    // a ParagraphNode with the same ID. Otherwise, it must
    // be a TextNode, in which case we need to figure out
    // which DocumentPosition contains the earlier TextPosition.
    if (basePosition.nodePosition is BinaryNodePosition) {
      // Assume that the node was replace with an empty paragraph.
      newSelectionPosition = DocumentPosition(
        nodeId: baseNode.id,
        nodePosition: const TextNodePosition(offset: 0),
      );
    } else if (basePosition.nodePosition is TextPosition) {
      final baseOffset = (basePosition.nodePosition as TextPosition).offset;
      final extentOffset = (extentPosition.nodePosition as TextPosition).offset;

      newSelectionPosition = DocumentPosition(
        nodeId: baseNode.id,
        nodePosition: TextNodePosition(offset: min(baseOffset, extentOffset)),
      );
    } else {
      throw Exception(
          'Unknown selection position type: $basePosition, for node: $baseNode, within document selection: $selection');
    }
  }

  return newSelectionPosition;
}

ExecutionInstruction backspaceToRemoveUpstreamContent({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }

  final didDelete = editContext.commonOps.deleteUpstream();

  return didDelete ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction mergeNodeWithNextWhenDeleteIsPressed({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey != LogicalKeyboardKey.delete) {
    return ExecutionInstruction.continueExecution;
  }

  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  final node = editContext.editor.document.getNodeById(editContext.composer.selection!.extent.nodeId);
  if (node is! TextNode) {
    _log.log('mergeNodeWithNextWhenDeleteIsPressed', 'WARNING: Cannot combine node of type: $node');
    return ExecutionInstruction.continueExecution;
  }

  final nextNode = editContext.editor.document.getNodeAfter(node);
  if (nextNode == null) {
    _log.log('mergeNodeWithNextWhenDeleteIsPressed', 'At bottom of document. Cannot merge with node above.');
    return ExecutionInstruction.continueExecution;
  }
  if (nextNode is! TextNode) {
    _log.log('mergeNodeWithNextWhenDeleteIsPressed', 'Cannot merge ParagraphNode into node of type: $nextNode');
    return ExecutionInstruction.continueExecution;
  }

  _log.log('mergeNodeWithNextWhenDeleteIsPressed', 'Combining node with next.');
  final currentParagraphLength = node.text.text.length;

  // Send edit command.
  editContext.editor.executeCommand(
    CombineParagraphsCommand(
      firstNodeId: node.id,
      secondNodeId: nextNode.id,
    ),
  );

  // Place the cursor at the point where the text came together.
  editContext.composer.selection = DocumentSelection.collapsed(
    position: DocumentPosition(
      nodeId: node.id,
      nodePosition: TextNodePosition(offset: currentParagraphLength),
    ),
  );

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction moveUpDownLeftAndRightWithArrowKeys({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  const arrowKeys = [
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
  ];
  if (!arrowKeys.contains(keyEvent.logicalKey)) {
    return ExecutionInstruction.continueExecution;
  }

  bool didMove = false;
  if (keyEvent.logicalKey == LogicalKeyboardKey.arrowLeft || keyEvent.logicalKey == LogicalKeyboardKey.arrowRight) {
    _log.log('moveUpDownLeftAndRightWithArrowKeys', ' - handling left arrow key');

    final movementModifiers = <MovementModifier>{};
    if (keyEvent.isPrimaryShortcutKeyPressed) {
      movementModifiers.add(MovementModifier.line);
    } else if (keyEvent.isAltPressed) {
      movementModifiers.add(MovementModifier.word);
    }

    if (keyEvent.logicalKey == LogicalKeyboardKey.arrowLeft) {
      // Move the caret left/upstream.
      didMove = editContext.commonOps.moveCaretUpstream(
        expand: keyEvent.isShiftPressed,
        movementModifiers: movementModifiers,
      );
    } else {
      // Move the caret right/downstream.
      didMove = editContext.commonOps.moveCaretDownstream(
        expand: keyEvent.isShiftPressed,
        movementModifiers: movementModifiers,
      );
    }
  } else if (keyEvent.logicalKey == LogicalKeyboardKey.arrowUp) {
    _log.log('moveUpDownLeftAndRightWithArrowKeys', ' - handling up arrow key');

    didMove = editContext.commonOps.moveCaretUp(expand: keyEvent.isShiftPressed);
  } else if (keyEvent.logicalKey == LogicalKeyboardKey.arrowDown) {
    _log.log('moveUpDownLeftAndRightWithArrowKeys', ' - handling down arrow key');

    didMove = editContext.commonOps.moveCaretDown(expand: keyEvent.isShiftPressed);
  }

  return didMove ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}
