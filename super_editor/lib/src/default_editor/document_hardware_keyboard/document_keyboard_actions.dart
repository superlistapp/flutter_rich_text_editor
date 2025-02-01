import 'dart:math';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/edit_context.dart';
import 'package:super_editor/src/default_editor/attributions.dart';
import 'package:super_editor/src/default_editor/paragraph.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/keyboard.dart';
import 'package:super_editor/src/infrastructure/platforms/platform.dart';

/// Scrolls up by the viewport height, or as high as possible,
/// when the user presses the Page Up key.
ExecutionInstruction scrollOnPageUpKeyPress({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey.keyId != LogicalKeyboardKey.pageUp.keyId) {
    return ExecutionInstruction.continueExecution;
  }

  final scroller = editContext.scroller;

  scroller.animateTo(
    max(scroller.scrollOffset - scroller.viewportDimension, scroller.minScrollExtent),
    duration: const Duration(milliseconds: 150),
    curve: Curves.decelerate,
  );

  return ExecutionInstruction.haltExecution;
}

/// Scrolls down by the viewport height, or as far as possible,
/// when the user presses the Page Down key.
ExecutionInstruction scrollOnPageDownKeyPress({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey.keyId != LogicalKeyboardKey.pageDown.keyId) {
    return ExecutionInstruction.continueExecution;
  }

  final scroller = editContext.scroller;

  scroller.animateTo(
    min(scroller.scrollOffset + scroller.viewportDimension, scroller.maxScrollExtent),
    duration: const Duration(milliseconds: 150),
    curve: Curves.decelerate,
  );

  return ExecutionInstruction.haltExecution;
}

/// Scrolls the viewport to the top of the content, when the user presses
/// CMD + HOME on Mac, or CTRL + HOME on all other platforms.
ExecutionInstruction scrollOnCtrlOrCmdAndHomeKeyPress({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.home) {
    return ExecutionInstruction.continueExecution;
  }

  if (CurrentPlatform.isApple && !HardwareKeyboard.instance.isMetaPressed) {
    return ExecutionInstruction.continueExecution;
  }

  if (!CurrentPlatform.isApple && !HardwareKeyboard.instance.isControlPressed) {
    return ExecutionInstruction.continueExecution;
  }

  final scroller = editContext.scroller;

  scroller.animateTo(
    scroller.minScrollExtent,
    duration: const Duration(milliseconds: 150),
    curve: Curves.decelerate,
  );

  return ExecutionInstruction.haltExecution;
}

/// Scrolls the viewport to the bottom of the content, when the user presses
/// CMD + END on Mac, or CTRL + END on all other platforms.
ExecutionInstruction scrollOnCtrlOrCmdAndEndKeyPress({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.end) {
    return ExecutionInstruction.continueExecution;
  }

  if (CurrentPlatform.isApple && !HardwareKeyboard.instance.isMetaPressed) {
    return ExecutionInstruction.continueExecution;
  }

  if (!CurrentPlatform.isApple && !HardwareKeyboard.instance.isControlPressed) {
    return ExecutionInstruction.continueExecution;
  }

  final scroller = editContext.scroller;

  if (!scroller.maxScrollExtent.isFinite) {
    // Can't scroll to infinity, but we technically handled the task.
    return ExecutionInstruction.haltExecution;
  }

  scroller.animateTo(
    scroller.maxScrollExtent,
    duration: const Duration(milliseconds: 150),
    curve: Curves.decelerate,
  );

  return ExecutionInstruction.haltExecution;
}

/// Halt execution of the current key event if the key pressed is one of
/// the functions keys (F1, F2, F3, etc.), or the Page Up/Down, Home/End key.
///
/// Without this action in place pressing one of the above mentioned keys
/// would display an unknown '?' character in the document.
ExecutionInstruction blockControlKeys({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey == LogicalKeyboardKey.escape ||
      keyEvent.logicalKey == LogicalKeyboardKey.pageUp ||
      keyEvent.logicalKey == LogicalKeyboardKey.pageDown ||
      keyEvent.logicalKey == LogicalKeyboardKey.home ||
      keyEvent.logicalKey == LogicalKeyboardKey.end ||
      (keyEvent.logicalKey.keyId >= LogicalKeyboardKey.f1.keyId &&
          keyEvent.logicalKey.keyId <= LogicalKeyboardKey.f23.keyId)) {
    return ExecutionInstruction.haltExecution;
  }

  return ExecutionInstruction.continueExecution;
}

ExecutionInstruction toggleInteractionModeWhenCmdOrCtrlPressed({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent.isPrimaryShortcutKeyPressed && !editContext.composer.isInInteractionMode.value) {
    editorKeyLog.fine("Activating editor interaction mode");
    editContext.editor.execute([
      const ChangeInteractionModeRequest(
        isInteractionModeDesired: true,
      ),
    ]);
  } else if (editContext.composer.isInInteractionMode.value) {
    editorKeyLog.fine("De-activating editor interaction mode");
    editContext.editor.execute([
      const ChangeInteractionModeRequest(
        isInteractionModeDesired: false,
      ),
    ]);
  }

  return ExecutionInstruction.continueExecution;
}

ExecutionInstruction doNothingWhenThereIsNoSelection({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (editContext.composer.selection == null) {
    return ExecutionInstruction.haltExecution;
  } else {
    return ExecutionInstruction.continueExecution;
  }
}

ExecutionInstruction sendKeyEventToMacOs({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (defaultTargetPlatform == TargetPlatform.macOS && !CurrentPlatform.isWeb) {
    // On macOS, we let the IME handle all key events. Then, the IME might generate
    // selectors which express the user intent, e.g, moveLeftAndModifySelection:.
    //
    // For the full list of selectors handled by SuperEditor, see the MacOsSelectors class.
    //
    // This is needed for the interaction with the accent panel to work.
    return ExecutionInstruction.blocked;
  }

  return ExecutionInstruction.continueExecution;
}

ExecutionInstruction deleteDownstreamCharacterWithCtrlDeleteOnMac({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (!CurrentPlatform.isApple) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.delete || !HardwareKeyboard.instance.isControlPressed) {
    return ExecutionInstruction.continueExecution;
  }

  final didDelete = editContext.commonOps.deleteDownstream();

  return didDelete ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction pasteWhenCmdVIsPressed({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.logicalKey != LogicalKeyboardKey.keyV) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  editContext.commonOps.paste();

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction selectAllWhenCmdAIsPressed({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.logicalKey != LogicalKeyboardKey.keyA) {
    return ExecutionInstruction.continueExecution;
  }

  final didSelectAll = editContext.commonOps.selectAll();
  return didSelectAll ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction copyWhenCmdCIsPressed({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.logicalKey != LogicalKeyboardKey.keyC) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection!.isCollapsed) {
    // Nothing to copy, but we technically handled the task.
    return ExecutionInstruction.haltExecution;
  }

  editContext.commonOps.copy();

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction cutWhenCmdXIsPressed({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.logicalKey != LogicalKeyboardKey.keyX) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection!.isCollapsed) {
    // Nothing to cut, but we technically handled the task.
    return ExecutionInstruction.haltExecution;
  }

  editContext.commonOps.cut();

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction cmdBToToggleBold({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.logicalKey != LogicalKeyboardKey.keyB) {
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
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.logicalKey != LogicalKeyboardKey.keyI) {
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
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (editContext.composer.selection == null || editContext.composer.selection!.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }

  // Do nothing if CMD or CTRL are pressed because this signifies an attempted
  // shortcut.
  if (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) {
    return ExecutionInstruction.continueExecution;
  }

  // Flutter reports a character for ESC, but we don't want to add a character
  // for ESC. Ignore this key press
  if (keyEvent.logicalKey == LogicalKeyboardKey.escape) {
    return ExecutionInstruction.continueExecution;
  }

  // Specifically exclude situations where shift is pressed because shift
  // needs to alter the selection, not delete content. We have to explicitly
  // look for this because when shift is pressed along with an arrow key,
  // Flutter reports a non-null character.
  if (HardwareKeyboard.instance.isShiftPressed) {
    return ExecutionInstruction.continueExecution;
  }

  final isDestructiveKey =
      keyEvent.logicalKey == LogicalKeyboardKey.backspace || keyEvent.logicalKey == LogicalKeyboardKey.delete;
  final isCharacterKey =
      keyEvent.character != null && keyEvent.character != '' && !isKeyEventCharacterBlacklisted(keyEvent.character);

  final shouldDeleteSelection = isDestructiveKey || isCharacterKey;
  if (!shouldDeleteSelection) {
    return ExecutionInstruction.continueExecution;
  }

  editContext.commonOps.deleteSelection(
    keyEvent.logicalKey == LogicalKeyboardKey.backspace ? TextAffinity.upstream : TextAffinity.downstream,
  );

  if (isCharacterKey) {
    // We continue handler execution even though we deleted the selection.
    // If the user pressed a character key, we want to let the character entry
    // behavior run.
    return ExecutionInstruction.continueExecution;
  }

  // We deleted a selection in response to an explicit deletion key, e.g.,
  // BACKSPACE or DELETE. We don't want any other handlers to respond to
  // this key.
  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction deleteUpstreamContentWithBackspace({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }

  final didDelete = editContext.commonOps.deleteUpstream();

  return didDelete ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction mergeNodeWithNextWhenDeleteIsPressed({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }
  if (keyEvent.logicalKey != LogicalKeyboardKey.delete) {
    return ExecutionInstruction.continueExecution;
  }

  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  final node = editContext.document.getNodeAtPath(editContext.composer.selection!.extent.documentPath);
  if (node is! TextNode) {
    return ExecutionInstruction.continueExecution;
  }

  final nextNode = editContext.document.getNodeAfter(node);
  if (nextNode == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (nextNode is! TextNode) {
    return ExecutionInstruction.continueExecution;
  }

  final currentParagraphLength = node.text.length;

  // Send edit command.
  editContext.editor.execute([
    CombineParagraphsRequest(
      firstNodeId: node.id,
      secondNodeId: nextNode.id,
    ),
    // Place the cursor at the point where the text came together.
    ChangeSelectionRequest(
      DocumentSelection.collapsed(
        position: DocumentPosition(
          documentPath: editContext.document.getPathByNodeId(nextNode.id)!,
          nodePosition: TextNodePosition(offset: currentParagraphLength),
        ),
      ),
      SelectionChangeType.deleteContent,
      SelectionReason.userInteraction,
    ),
  ]);

  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction moveUpAndDownWithArrowKeys({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  const arrowKeys = [
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
  ];
  if (!arrowKeys.contains(keyEvent.logicalKey)) {
    return ExecutionInstruction.continueExecution;
  }

  if (CurrentPlatform.isWeb && (editContext.composer.composingRegion.value != null)) {
    // We are composing a character on web. It's possible that a native element is being displayed,
    // like an emoji picker or a character selection panel.
    // We need to let the OS handle the key so the user can navigate
    // on the list of possible characters.
    // TODO: update this after https://github.com/flutter/flutter/issues/134268 is resolved.
    return ExecutionInstruction.blocked;
  }

  if (defaultTargetPlatform == TargetPlatform.windows && HardwareKeyboard.instance.isAltPressed) {
    return ExecutionInstruction.continueExecution;
  }

  if (defaultTargetPlatform == TargetPlatform.linux && HardwareKeyboard.instance.isAltPressed) {
    return ExecutionInstruction.continueExecution;
  }

  bool didMove = false;
  if (keyEvent.logicalKey == LogicalKeyboardKey.arrowUp) {
    if (CurrentPlatform.isApple && HardwareKeyboard.instance.isAltPressed) {
      didMove = editContext.commonOps.moveCaretUpstream(
        expand: HardwareKeyboard.instance.isShiftPressed,
        movementModifier: MovementModifier.paragraph,
      );
    } else if (CurrentPlatform.isApple && HardwareKeyboard.instance.isMetaPressed) {
      didMove =
          editContext.commonOps.moveSelectionToBeginningOfDocument(expand: HardwareKeyboard.instance.isShiftPressed);
    } else {
      didMove = editContext.commonOps.moveCaretUp(expand: HardwareKeyboard.instance.isShiftPressed);
    }
  } else {
    if (CurrentPlatform.isApple && HardwareKeyboard.instance.isAltPressed) {
      didMove = editContext.commonOps.moveCaretDownstream(
        expand: HardwareKeyboard.instance.isShiftPressed,
        movementModifier: MovementModifier.paragraph,
      );
    } else if (CurrentPlatform.isApple && HardwareKeyboard.instance.isMetaPressed) {
      didMove = editContext.commonOps.moveSelectionToEndOfDocument(expand: HardwareKeyboard.instance.isShiftPressed);
    } else {
      didMove = editContext.commonOps.moveCaretDown(expand: HardwareKeyboard.instance.isShiftPressed);
    }
  }

  return didMove ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction moveLeftAndRightWithArrowKeys({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  const arrowKeys = [
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  ];
  if (!arrowKeys.contains(keyEvent.logicalKey)) {
    return ExecutionInstruction.continueExecution;
  }

  if (CurrentPlatform.isWeb && (editContext.composer.composingRegion.value != null)) {
    // We are composing a character on web. It's possible that a native element is being displayed,
    // like an emoji picker or a character selection panel.
    // We need to let the OS handle the key so the user can navigate
    // on the list of possible characters.
    // TODO: update this after https://github.com/flutter/flutter/issues/134268 is resolved.
    return ExecutionInstruction.blocked;
  }

  if (defaultTargetPlatform == TargetPlatform.windows && HardwareKeyboard.instance.isAltPressed) {
    return ExecutionInstruction.continueExecution;
  }

  bool didMove = false;
  MovementModifier? movementModifier;
  if ((defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux) &&
      HardwareKeyboard.instance.isControlPressed) {
    movementModifier = MovementModifier.word;
  } else if (CurrentPlatform.isApple && HardwareKeyboard.instance.isMetaPressed) {
    movementModifier = MovementModifier.line;
  } else if (CurrentPlatform.isApple && HardwareKeyboard.instance.isAltPressed) {
    movementModifier = MovementModifier.word;
  }

  if (keyEvent.logicalKey == LogicalKeyboardKey.arrowLeft) {
    // Move the caret left/upstream.
    didMove = editContext.commonOps.moveCaretUpstream(
      expand: HardwareKeyboard.instance.isShiftPressed,
      movementModifier: movementModifier,
    );
  } else {
    // Move the caret right/downstream.
    didMove = editContext.commonOps.moveCaretDownstream(
      expand: HardwareKeyboard.instance.isShiftPressed,
      movementModifier: movementModifier,
    );
  }

  return didMove ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction doNothingWithLeftRightArrowKeysAtMiddleOfTextOnWeb({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (!CurrentPlatform.isWeb) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  const arrowKeys = [
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  ];
  if (!arrowKeys.contains(keyEvent.logicalKey)) {
    return ExecutionInstruction.continueExecution;
  }

  if ((defaultTargetPlatform == TargetPlatform.windows || CurrentPlatform.isApple) &&
      HardwareKeyboard.instance.isAltPressed) {
    return ExecutionInstruction.continueExecution;
  }

  if (defaultTargetPlatform == TargetPlatform.linux &&
      HardwareKeyboard.instance.isAltPressed &&
      (keyEvent.logicalKey == LogicalKeyboardKey.arrowUp || keyEvent.logicalKey == LogicalKeyboardKey.arrowDown)) {
    return ExecutionInstruction.continueExecution;
  }

  // On web, pressing left or right arrow keys generates non-text deltas.
  // We handle those deltas to change the selection. However, if the caret sits at the beginning
  // or end of a node, pressing these arrow keys doesn't generate any deltas.
  // Therefore, we need to handle the key events to move the selection to the previous/next node.

  final currentExtent = editContext.composer.selection!.extent;
  final nodeId = currentExtent.nodeId;
  final node = editContext.document.getNodeById(nodeId);
  if (node == null) {
    return ExecutionInstruction.continueExecution;
  }

  if (node is! TextNode) {
    return ExecutionInstruction.continueExecution;
  }

  if (currentExtent.nodePosition is! TextNodePosition) {
    return ExecutionInstruction.continueExecution;
  }

  final textNodePosition = currentExtent.nodePosition as TextNodePosition;
  if (keyEvent.logicalKey == LogicalKeyboardKey.arrowLeft && textNodePosition.offset > 0) {
    // We are not at the beginning of the node.
    // Let the IME handle the key event.
    return ExecutionInstruction.blocked;
  }

  if (keyEvent.logicalKey == LogicalKeyboardKey.arrowRight && textNodePosition.offset < node.text.length) {
    // We are not at the end of the node.
    // Let the IME handle the key event.
    return ExecutionInstruction.blocked;
  }

  return ExecutionInstruction.continueExecution;
}

ExecutionInstruction moveToStartOrEndOfLineWithArrowKeysOnWeb({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (!CurrentPlatform.isWeb) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  const arrowKeys = [
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  ];
  if (!arrowKeys.contains(keyEvent.logicalKey)) {
    return ExecutionInstruction.continueExecution;
  }

  if ((CurrentPlatform.isApple && !HardwareKeyboard.instance.isMetaPressed) ||
      (const [TargetPlatform.windows, TargetPlatform.linux].contains(defaultTargetPlatform) &&
          !HardwareKeyboard.instance.isControlPressed)) {
    // CMD or CTRL is not pressed.
    return ExecutionInstruction.continueExecution;
  }

  // Pressing the arrow keys generates non-text deltas on web. However, when pressing CMD + RIGHT
  // to move the selection to the end of the line, the selection change sometimes reports an offset which
  // isn't at the end of the line. This seems to be an issue where our text layout is different
  // from the browser's text layout. For example, the browser breaks the line at a different point
  // than we do, so pressing CMD + RIGHT moves the selection to where the browser thinks the end of
  // the line is.
  //
  // See https://github.com/superlistapp/super_editor/issues/2304 for more information.
  //
  // Move the selection mannually.

  bool didMove;
  if (keyEvent.logicalKey == LogicalKeyboardKey.arrowLeft) {
    // Move the caret left/upstream.
    didMove = editContext.commonOps.moveCaretUpstream(
      expand: HardwareKeyboard.instance.isShiftPressed,
      movementModifier: MovementModifier.line,
    );
  } else {
    // Move the caret right/downstream.
    didMove = editContext.commonOps.moveCaretDownstream(
      expand: HardwareKeyboard.instance.isShiftPressed,
      movementModifier: MovementModifier.line,
    );
  }

  return didMove ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction moveToLineStartOrEndWithCtrlAOrE({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return ExecutionInstruction.continueExecution;
  }

  if (!HardwareKeyboard.instance.isControlPressed) {
    return ExecutionInstruction.continueExecution;
  }
  bool didMove = false;

  if (keyEvent.logicalKey == LogicalKeyboardKey.keyA) {
    didMove = editContext.commonOps.moveCaretUpstream(
      expand: HardwareKeyboard.instance.isShiftPressed,
      movementModifier: MovementModifier.line,
    );
  }

  if (keyEvent.logicalKey == LogicalKeyboardKey.keyE) {
    didMove = editContext.commonOps.moveCaretDownstream(
      expand: HardwareKeyboard.instance.isShiftPressed,
      movementModifier: MovementModifier.line,
    );
  }

  return didMove ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction moveToLineStartWithHome({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (defaultTargetPlatform != TargetPlatform.windows && defaultTargetPlatform != TargetPlatform.linux) {
    return ExecutionInstruction.continueExecution;
  }

  bool didMove = false;
  if (keyEvent.logicalKey == LogicalKeyboardKey.home) {
    didMove = editContext.commonOps.moveCaretUpstream(
      expand: HardwareKeyboard.instance.isShiftPressed,
      movementModifier: MovementModifier.line,
    );
  }

  return didMove ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction moveToLineEndWithEnd({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (defaultTargetPlatform != TargetPlatform.windows && defaultTargetPlatform != TargetPlatform.linux) {
    return ExecutionInstruction.continueExecution;
  }

  bool didMove = false;
  if (keyEvent.logicalKey == LogicalKeyboardKey.end) {
    didMove = editContext.commonOps.moveCaretDownstream(
      expand: HardwareKeyboard.instance.isShiftPressed,
      movementModifier: MovementModifier.line,
    );
  }

  return didMove ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction deleteToStartOfLineWithCmdBackspaceOnMac({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (!CurrentPlatform.isApple) {
    return ExecutionInstruction.continueExecution;
  }
  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  bool didMove = false;

  didMove = editContext.commonOps.moveCaretUpstream(
    expand: true,
    movementModifier: MovementModifier.line,
  );

  if (didMove) {
    return editContext.commonOps.deleteSelection(TextAffinity.upstream)
        ? ExecutionInstruction.haltExecution
        : ExecutionInstruction.continueExecution;
  }
  return ExecutionInstruction.continueExecution;
}

ExecutionInstruction deleteToEndOfLineWithCmdDeleteOnMac({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (!CurrentPlatform.isApple) {
    return ExecutionInstruction.continueExecution;
  }
  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.logicalKey != LogicalKeyboardKey.delete) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  bool didMove = false;

  didMove = editContext.commonOps.moveCaretDownstream(
    expand: true,
    movementModifier: MovementModifier.line,
  );

  if (didMove) {
    return editContext.commonOps.deleteSelection(TextAffinity.downstream)
        ? ExecutionInstruction.haltExecution
        : ExecutionInstruction.continueExecution;
  }
  return ExecutionInstruction.continueExecution;
}

ExecutionInstruction deleteWordUpstreamWithAltBackspaceOnMac({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (!CurrentPlatform.isApple) {
    return ExecutionInstruction.continueExecution;
  }
  if (!HardwareKeyboard.instance.isAltPressed || keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  bool didMove = false;

  didMove = editContext.commonOps.moveCaretUpstream(
    expand: true,
    movementModifier: MovementModifier.word,
  );

  if (didMove) {
    return editContext.commonOps.deleteSelection(TextAffinity.upstream)
        ? ExecutionInstruction.haltExecution
        : ExecutionInstruction.continueExecution;
  }
  return ExecutionInstruction.continueExecution;
}

ExecutionInstruction deleteWordUpstreamWithControlBackspaceOnWindowsAndLinux({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (defaultTargetPlatform != TargetPlatform.windows && defaultTargetPlatform != TargetPlatform.linux) {
    return ExecutionInstruction.continueExecution;
  }
  if (!HardwareKeyboard.instance.isControlPressed || keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  bool didMove = false;

  didMove = editContext.commonOps.moveCaretUpstream(
    expand: true,
    movementModifier: MovementModifier.word,
  );

  if (didMove) {
    return editContext.commonOps.deleteSelection(TextAffinity.upstream)
        ? ExecutionInstruction.haltExecution
        : ExecutionInstruction.continueExecution;
  }
  return ExecutionInstruction.continueExecution;
}

ExecutionInstruction deleteWordDownstreamWithAltDeleteOnMac({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (!CurrentPlatform.isApple) {
    return ExecutionInstruction.continueExecution;
  }
  if (!HardwareKeyboard.instance.isAltPressed || keyEvent.logicalKey != LogicalKeyboardKey.delete) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  bool didMove = false;

  didMove = editContext.commonOps.moveCaretDownstream(
    expand: true,
    movementModifier: MovementModifier.word,
  );

  if (didMove) {
    return editContext.commonOps.deleteSelection(TextAffinity.downstream)
        ? ExecutionInstruction.haltExecution
        : ExecutionInstruction.continueExecution;
  }
  return ExecutionInstruction.continueExecution;
}

ExecutionInstruction deleteWordDownstreamWithControlDeleteOnWindowsAndLinux({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (defaultTargetPlatform != TargetPlatform.windows && defaultTargetPlatform != TargetPlatform.linux) {
    return ExecutionInstruction.continueExecution;
  }
  if (!HardwareKeyboard.instance.isControlPressed || keyEvent.logicalKey != LogicalKeyboardKey.delete) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  bool didMove = false;

  didMove = editContext.commonOps.moveCaretDownstream(
    expand: true,
    movementModifier: MovementModifier.word,
  );

  if (didMove) {
    return editContext.commonOps.deleteSelection(TextAffinity.downstream)
        ? ExecutionInstruction.haltExecution
        : ExecutionInstruction.continueExecution;
  }
  return ExecutionInstruction.continueExecution;
}

/// When the ESC key is pressed, the editor should collapse the expanded selection.
///
/// Do nothing if selection is already collapsed.
ExecutionInstruction collapseSelectionWhenEscIsPressed({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.escape) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null || editContext.composer.selection!.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }

  editContext.commonOps.collapseSelection();
  return ExecutionInstruction.haltExecution;
}
