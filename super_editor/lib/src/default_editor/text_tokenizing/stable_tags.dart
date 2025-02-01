import 'package:attributed_text/attributed_text.dart';
import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/edit_context.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/default_editor/document_hardware_keyboard/document_input_keyboard.dart';
import 'package:super_editor/src/default_editor/multi_node_editing.dart';
import 'package:super_editor/src/default_editor/super_editor.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/default_editor/text_tokenizing/tags.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/keyboard.dart';

/// A [SuperEditor] plugin that adds the ability to create stable tags, such as
/// persistent user references, e.g., "@dash".
///
/// Stable tagging includes three modes:
///  * Composing: a stable tag is being assembled, i.e., typed.
///  * Committed: a stable tag is done being assembled - it's now uneditable.
///  * Cancelled: a stable tag was being composed, but the composition was cancelled.
///
/// ## Composing Tags
/// The user initiates tag composition by typing the trigger symbol, e.g., "@". A
/// [stableTagComposingAttribution] is applied to the trigger symbol. As the user types,
/// the attribution expands with the new text content, surrounding the entire tag.
///
/// Eventually, the composing tag will either be committed, or cancelled. Those modes
/// are discussed below.
///
///     "@da|"    ->  "@das|"     - still composing
///     "@ds|"    ->  "@d|s"      -> "@da|s" - still composing
///     "@dash|"  ->  "@dash |"   - committed
///     "@|dash"  ->  "|@dash"    - committed
///     "@da|ash" ->  "@dash"     - committed
///
/// ## Committed Tags
/// Once a stable tag is finished being composed, it's committed. A tag can be committed
/// explicitly, or a tag is automatically committed once the user's selection moves outside
/// the tag.
///
/// A committed tag is non-editable. The user's selection is prevented from entering the
/// tag. If the user's selection is collapsed, the caret will be placed on one side of the
/// tag, or the other. If the user's selection is expanded, then the user will either select
/// the entire tag, or none of the tag.
///
/// ## Cancelled Tags
/// When the user presses ESCAPE while composing a tag, the composing [stableTagComposingAttribution]
/// is replaced with a [stableTagCancelledAttribution]. This ends the current composing behavior,
/// and also prevents composing from starting again, whenever the user happens to place the caret
/// in the given text.
class StableTagPlugin extends SuperEditorPlugin {
  /// The key used to access the [StableTagIndex] in an attached [Editor].
  static const stableTagIndexKey = "stableTagIndex";

  StableTagPlugin({
    TagRule tagRule = userTagRule,
  })  : _tagRule = tagRule,
        tagIndex = StableTagIndex() {
    _requestHandlers = <EditRequestHandler>[
      (editor, request) => request is FillInComposingStableTagRequest
          ? FillInComposingUserTagCommand(request.tag, request.tagRule)
          : null,
      (editor, request) => request is CancelComposingStableTagRequest //
          ? CancelComposingStableTagCommand(request.tagRule)
          : null,
    ];

    _reactions = [
      TagUserReaction(
        tagRule: tagRule,
        onUpdateComposingStableTag: tagIndex._onComposingStableTagFound,
      ),
      AdjustSelectionAroundTagReaction(tagRule),
    ];
  }

  final TagRule _tagRule;

  /// Index of all stable tags in the document, which changes as the user adds and removes tags.
  final StableTagIndex tagIndex;

  @override
  void attach(Editor editor) {
    editor
      ..context.put(StableTagPlugin.stableTagIndexKey, tagIndex)
      ..requestHandlers.insertAll(0, _requestHandlers)
      ..reactionPipeline.insertAll(0, _reactions);
  }

  @override
  void detach(Editor editor) {
    editor
      ..context.remove(StableTagPlugin.stableTagIndexKey)
      ..requestHandlers.removeWhere((item) => _requestHandlers.contains(item))
      ..reactionPipeline.removeWhere((item) => _reactions.contains(item));
  }

  late final List<EditRequestHandler> _requestHandlers;

  late final List<EditReaction> _reactions;

  @override
  List<DocumentKeyboardAction> get keyboardActions => [_cancelOnEscape];
  ExecutionInstruction _cancelOnEscape({
    required SuperEditorContext editContext,
    required KeyEvent keyEvent,
  }) {
    if (keyEvent is KeyDownEvent || keyEvent is KeyRepeatEvent) {
      return ExecutionInstruction.continueExecution;
    }

    if (keyEvent.logicalKey != LogicalKeyboardKey.escape) {
      return ExecutionInstruction.continueExecution;
    }

    editContext.editor.execute([
      CancelComposingStableTagRequest(_tagRule),
    ]);

    return ExecutionInstruction.haltExecution;
  }
}

/// [TagRule] for user tags.
///
/// Stable tags can use any [TagRule]. This rule is provided as a convenience due to
/// the popularity of user tagging.
const userTagRule = TagRule(trigger: "@", excludedCharacters: {" ", "."});

/// An [EditRequest] that replaces a composing stable tag with the given [tag]
/// and commits it.
///
/// For example, the user types "@da|", and then selects "dash" from a list of
/// matching users. This request replaces "@da|" with "@dash |" and converts the tag
/// from a composing user tag to a committed user tag.
///
/// For this request to have an effect, the user's selection must sit somewhere within
/// the composing user tag.
class FillInComposingStableTagRequest implements EditRequest {
  const FillInComposingStableTagRequest(
    this.tag,
    this.tagRule,
  );

  final String tag;
  final TagRule tagRule;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FillInComposingStableTagRequest &&
          runtimeType == other.runtimeType &&
          tag == other.tag &&
          tagRule == other.tagRule;

  @override
  int get hashCode => tag.hashCode ^ tagRule.hashCode;
}

class FillInComposingUserTagCommand extends EditCommand {
  const FillInComposingUserTagCommand(
    this._tag,
    this._tagRule,
  );

  final String _tag;
  final TagRule _tagRule;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;
    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);

    final selection = composer.selection;
    if (selection == null) {
      // There shouldn't be a composing stable tag without a selection. Either way,
      // we can't find the desired composing stable tag without a selection position
      // to guide us. Fizzle.
      editorStableTagsLog.warning("Tried to fill in a composing stable tag, but there's no user selection.");
      return;
    }

    // Look for a composing tag at the extent, or the base.
    final base = selection.base;
    final extent = selection.extent;
    TagAroundPosition? composingToken;
    late final NodePath textNodePath;
    TextNode? textNode;

    if (base.nodePosition is TextNodePosition) {
      textNodePath = document.getPathByNodeId(selection.base.nodeId)!;
      textNode = document.getNodeById(selection.base.nodeId) as TextNode;
      composingToken = TagFinder.findTagAroundPosition(
        tagRule: _tagRule,
        nodeId: textNode.id,
        text: textNode.text,
        expansionPosition: base.nodePosition as TextNodePosition,
        isTokenCandidate: (tokenAttributions) => tokenAttributions.contains(stableTagComposingAttribution),
      );
    }
    if (composingToken == null && extent.nodePosition is TextNodePosition) {
      textNodePath = document.getPathByNodeId(selection.extent.nodeId)!;
      textNode = document.getNodeById(selection.extent.nodeId) as TextNode;
      composingToken = TagFinder.findTagAroundPosition(
        tagRule: _tagRule,
        nodeId: textNode.id,
        text: textNode.text,
        expansionPosition: base.nodePosition as TextNodePosition,
        isTokenCandidate: (tokenAttributions) => tokenAttributions.contains(stableTagComposingAttribution),
      );
    }

    if (composingToken == null) {
      // There's no composing tag near either side of the user's selection. Fizzle.
      editorStableTagsLog.warning(
          "Tried to fill in a composing stable tag, but there's no composing stable tag near the user's selection.");
      return;
    }

    final stableTagAttribution = CommittedStableTagAttribution(_tag);

    // Delete the composing stable tag text.
    executor.executeCommand(
      DeleteContentCommand(
        documentRange: textNode!.selectionBetween(
          textNodePath,
          composingToken.indexedTag.startOffset,
          composingToken.indexedTag.endOffset,
        ),
      ),
    );
    // Insert a committed stable tag.
    executor.executeCommand(
      InsertAttributedTextCommand(
        documentPosition: textNode.positionAt(textNodePath, composingToken.indexedTag.startOffset),
        textToInsert: AttributedText(
          "${_tagRule.trigger}$_tag ",
          AttributedSpans(
            attributions: [
              SpanMarker(attribution: stableTagAttribution, offset: 0, markerType: SpanMarkerType.start),
              SpanMarker(attribution: stableTagAttribution, offset: _tag.length, markerType: SpanMarkerType.end),
            ],
          ),
        ),
      ),
    );
    // Place the caret at the end of the inserted text.
    executor.executeCommand(
      ChangeSelectionCommand(
        // +1 for trigger symbol, +1 for space after the token
        textNode.selectionAt(textNodePath, composingToken.indexedTag.startOffset + _tag.length + 2),
        SelectionChangeType.placeCaret,
        SelectionReason.contentChange,
      ),
    );
  }
}

/// An [EditRequest] that cancels an on-going stable tag composition near the user's selection.
///
/// When a user is in the process of composing a stable tag, that tag is given an attribution
/// to identify it. After this request is processed, that attribution will be removed from
/// the text, which will also remove any related UI, such as a suggested-value popover.
///
/// This request doesn't change the user's selection.
class CancelComposingStableTagRequest implements EditRequest {
  const CancelComposingStableTagRequest(this.tagRule);

  final TagRule tagRule;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CancelComposingStableTagRequest && runtimeType == other.runtimeType && tagRule == other.tagRule;

  @override
  int get hashCode => tagRule.hashCode;
}

class CancelComposingStableTagCommand extends EditCommand {
  const CancelComposingStableTagCommand(this._tagRule);

  final TagRule _tagRule;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;
    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);

    final selection = composer.selection;
    if (selection == null) {
      // There shouldn't be a composing stable tag without a selection. Either way,
      // we can't find the desired composing user tag without a selection position
      // to guide us. Fizzle.
      editorStableTagsLog.warning("Tried to cancel a composing stable tag, but there's no user selection.");
      return;
    }

    // Look for a composing tag at the extent, or the base.
    final base = selection.base;
    final extent = selection.extent;
    TagAroundPosition? composingToken;
    late final NodePath textNodePath;
    TextNode? textNode;

    if (base.nodePosition is TextNodePosition) {
      textNodePath = document.getPathByNodeId(selection.base.nodeId)!;
      textNode = document.getNodeById(selection.base.nodeId) as TextNode;
      composingToken = TagFinder.findTagAroundPosition(
        tagRule: _tagRule,
        nodeId: textNode.id,
        text: textNode.text,
        expansionPosition: base.nodePosition as TextNodePosition,
        isTokenCandidate: (tokenAttributions) => tokenAttributions.contains(stableTagComposingAttribution),
      );
    }
    if (composingToken == null && extent.nodePosition is TextNodePosition) {
      textNodePath = document.getPathByNodeId(selection.extent.nodeId)!;
      textNode = document.getNodeById(selection.extent.nodeId) as TextNode;
      composingToken = TagFinder.findTagAroundPosition(
        tagRule: _tagRule,
        nodeId: textNode.id,
        text: textNode.text,
        expansionPosition: base.nodePosition as TextNodePosition,
        isTokenCandidate: (tokenAttributions) => tokenAttributions.contains(stableTagComposingAttribution),
      );
    }

    if (composingToken == null) {
      // There's no composing tag near either side of the user's selection. Fizzle.
      editorStableTagsLog.warning(
          "Tried to cancel a composing stable tag, but there's no composing stable tag near the user's selection.");
      return;
    }

    // Remove the composing attribution.
    executor.executeCommand(
      RemoveTextAttributionsCommand(
        documentRange: textNode!.selectionBetween(
          textNodePath,
          composingToken.indexedTag.startOffset,
          composingToken.indexedTag.endOffset,
        ),
        attributions: {stableTagComposingAttribution},
      ),
    );
    executor.executeCommand(
      AddTextAttributionsCommand(
        documentRange: textNode.selectionBetween(
          textNodePath,
          composingToken.indexedTag.startOffset,
          composingToken.indexedTag.startOffset + 1,
        ),
        attributions: {stableTagCancelledAttribution},
      ),
    );
  }
}

extension StableTagIndexEditable on EditContext {
  /// Returns the [StableTagIndex] that the [StableTagPlugin] added to the attached [Editor].
  ///
  /// This accessor is provided as a convenience so that clients don't need to call `find()`
  /// on the [EditContext].
  StableTagIndex get stableTagIndex => find<StableTagIndex>(StableTagPlugin.stableTagIndexKey);
}

/// An [EditReaction] that creates, updates, and removes composing stable tags, and commits those
/// composing tags, causing them to become uneditable.
class TagUserReaction extends EditReaction {
  const TagUserReaction({
    required TagRule tagRule,
    this.onUpdateComposingStableTag,
  }) : _tagRule = tagRule;

  final TagRule _tagRule;

  final OnUpdateComposingStableTag? onUpdateComposingStableTag;

  @override
  void react(EditContext editContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    editorStableTagsLog.info("Reacting to possible stable tagging");
    editorStableTagsLog.info("Incoming change list:");
    editorStableTagsLog.info(changeList.map((event) => event.runtimeType).toList());
    editorStableTagsLog.info(
        "Caret position: ${editContext.find<MutableDocumentComposer>(Editor.composerKey).selection?.extent.nodePosition}");

    final document = editContext.document;
    _healCancelledTags(requestDispatcher, document, changeList);

    _adjustTagAttributionsAroundAlteredTags(editContext, requestDispatcher, changeList);

    _removeInvalidTags(editContext, requestDispatcher, changeList);

    _createNewComposingTag(editContext, requestDispatcher, changeList);

    // Run tag commits after updating tags, above, so that we don't commit an in-progress
    // tag when a new character is added to the end of the tag.
    _commitCompletedComposingTag(editContext, requestDispatcher, changeList);

    _updateTagIndex(editContext, changeList);
  }

  /// Finds all cancelled stable tags across all changed text nodes in [changeList] and corrects
  /// any invalid attribution bounds that may have been introduced by edits.
  void _healCancelledTags(RequestDispatcher requestDispatcher, MutableDocument document, List<EditEvent> changeList) {
    final healChangeRequests = <EditRequest>[];

    for (final event in changeList) {
      if (event is! DocumentEdit) {
        continue;
      }

      final change = event.change;
      if (change is! NodeChangeEvent) {
        continue;
      }

      final node = document.getNodeById(change.nodeId);
      if (node is! TextNode) {
        continue;
      }

      // The content in a TextNode changed. Check for the existence of any
      // out-of-sync cancelled tags and fix them.
      healChangeRequests.addAll(
        _healCancelledTagsInTextNode(
          requestDispatcher,
          document.getPathByNodeId(change.nodeId)!,
          node,
        ),
      );
    }

    // Run all the requests to heal the various cancelled tags.
    requestDispatcher.execute(healChangeRequests);
  }

  List<EditRequest> _healCancelledTagsInTextNode(
      RequestDispatcher requestDispatcher, NodePath nodePath, TextNode node) {
    final cancelledTagRanges = node.text.getAttributionSpansInRange(
      attributionFilter: (a) => a == stableTagCancelledAttribution,
      range: SpanRange(0, node.text.length - 1),
    );

    final changeRequests = <EditRequest>[];

    for (final range in cancelledTagRanges) {
      final cancelledText = node.text.substring(range.start, range.end + 1); // +1 because substring is exclusive
      if (cancelledText == _tagRule.trigger) {
        // This is a legitimate cancellation attribution.
        continue;
      }

      DocumentSelection? addedRange;
      if (cancelledText.contains(_tagRule.trigger)) {
        // This cancelled range includes more than just a trigger. Reduce it back
        // down to the trigger.
        final triggerIndex = cancelledText.indexOf(_tagRule.trigger);
        addedRange = node.selectionBetween(nodePath, triggerIndex, triggerIndex);
      }

      changeRequests.addAll([
        RemoveTextAttributionsRequest(
          documentRange: node.selectionBetween(nodePath, range.start, range.end),
          attributions: {stableTagCancelledAttribution},
        ),
        if (addedRange != null) //
          AddTextAttributionsRequest(
            documentRange: addedRange,
            attributions: {stableTagCancelledAttribution},
          ),
      ]);
    }

    return changeRequests;
  }

  /// Finds a composing stable tag near the caret and adjusts the attribution bounds so that
  /// the tag content remains attributed.
  ///
  /// Examples:
  ///
  ///  - |@joh|n      ->  |@john|
  ///  - |@john and|  ->  |@john| and
  ///
  void _adjustTagAttributionsAroundAlteredTags(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
  ) {
    final document = editContext.document;

    final composingToken = _findComposingTagAtCaret(editContext);
    if (composingToken != null) {
      final tagRange = SpanRange(composingToken.indexedTag.startOffset, composingToken.indexedTag.endOffset);
      final hasComposingThroughout =
          composingToken.indexedTag.computeLeadingSpanForAttribution(document, stableTagComposingAttribution) ==
              tagRange;

      if (hasComposingThroughout) {
        return;
      }

      // The token is only partially attributed. Expand the attribution around the token.
      requestDispatcher.execute([
        AddTextAttributionsRequest(
          documentRange: DocumentSelection(
            base: composingToken.indexedTag.start,
            extent: composingToken.indexedTag.end,
          ),
          attributions: {stableTagComposingAttribution},
        ),
      ]);

      return;
    }
  }

  /// Removes composing or cancelled stable tag attributions from any tag that no longer
  /// matches the pattern of a stable tag.
  ///
  /// Example:
  ///
  ///  - |@john|  ->  |john|  -> john
  void _removeInvalidTags(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
  ) {
    editorStableTagsLog.info("Removing invalid tags.");
    final document = editContext.document;
    final nodesToInspect = <String>{};
    for (final edit in changeList) {
      // We only care about deleted text, in case the deletion made an existing tag invalid.
      if (edit is! DocumentEdit) {
        continue;
      }
      final change = edit.change;
      if (change is! TextDeletedEvent) {
        continue;
      }
      if (document.getNodeById(change.nodeId) == null) {
        // This node was deleted sometime later. No need to consider it.
        continue;
      }

      // We only care about deleted text when the deleted text contains at least one tag.
      final tagsInDeletedText = change.deletedText.getAttributionSpansByFilter(
        (attribution) => attribution == stableTagComposingAttribution || attribution is CommittedStableTagAttribution,
      );
      if (tagsInDeletedText.isEmpty) {
        continue;
      }

      nodesToInspect.add(change.nodeId);
    }
    editorStableTagsLog.fine("Found ${nodesToInspect.length} impacted nodes with tags that might be invalid");

    // Inspect every TextNode where a text deletion impacted a tag.
    final removeTagRequests = <EditRequest>{};
    final deleteTagRequests = <EditRequest>{};
    for (final nodeId in nodesToInspect) {
      final nodePath = document.getPathByNodeId(nodeId)!;
      final textNode = document.getNodeById(nodeId) as TextNode;

      // If a composing tag no longer contains a trigger ("@"), remove the attribution.
      final allComposingTags = textNode.text.getAttributionSpansInRange(
        attributionFilter: (attribution) => attribution == stableTagComposingAttribution,
        range: SpanRange(0, textNode.text.length - 1),
      );

      for (final tag in allComposingTags) {
        final tagText = textNode.text.substring(tag.start, tag.end + 1);

        if (!tagText.startsWith(_tagRule.trigger)) {
          editorStableTagsLog.info("Removing tag with value: '$tagText'");

          onUpdateComposingStableTag?.call(null);

          removeTagRequests.add(
            RemoveTextAttributionsRequest(
              documentRange: textNode.selectionBetween(nodePath, tag.start, tag.end + 1),
              attributions: {stableTagComposingAttribution},
            ),
          );
        }
      }

      // If a stable tag's content no longer matches its attribution value, then
      // assume that the user tried to delete part of it. Delete the whole thing,
      // because we don't allow partial committed user tags.

      // Collect all the stable tags in this node. The list is sorted such that
      // later tags appear before earlier tags. This way, as we delete tags, each
      // deleted tag won't impact the character offsets of the following tags
      // that we delete.
      final allStableTags = textNode.text
          .getAttributionSpansInRange(
            attributionFilter: (attribution) => attribution is CommittedStableTagAttribution,
            range: SpanRange(0, textNode.text.length - 1),
          )
          .sorted((tag1, tag2) => tag2.start - tag1.start);

      // Track the impact of deletions on selection bounds, then update the selection
      // to reflect the deletions.
      final composer = editContext.find<MutableDocumentComposer>(Editor.composerKey);

      final baseBeforeDeletions = composer.selection!.base;
      int baseOffsetAfterDeletions = baseBeforeDeletions.nodePosition is TextNodePosition
          ? (baseBeforeDeletions.nodePosition as TextNodePosition).offset
          : -1;

      final extentBeforeDeletions = composer.selection!.extent;
      int extentOffsetAfterDeletions = extentBeforeDeletions.nodePosition is TextNodePosition
          ? (extentBeforeDeletions.nodePosition as TextNodePosition).offset
          : -1;

      for (final tag in allStableTags) {
        final tagText = textNode.text.substring(tag.start, tag.end + 1);
        final attribution = tag.attribution as CommittedStableTagAttribution;
        final containsTrigger = textNode.text.toPlainText()[tag.start] == _tagRule.trigger;

        if (tagText != "${_tagRule.trigger}${attribution.tagValue}" || !containsTrigger) {
          // The tag was partially deleted it. Delete the whole thing.
          final deleteFrom = tag.start;
          final deleteTo = tag.end + 1; // +1 because SpanRange is inclusive and text position is exclusive
          editorStableTagsLog.info("Deleting partial tag '$tagText': $deleteFrom -> $deleteTo");

          if (baseBeforeDeletions.nodeId == textNode.id) {
            if (baseOffsetAfterDeletions >= deleteTo) {
              // The base sits beyond the entire deletion region. Push the base up by the
              // length of the deletion region.
              baseOffsetAfterDeletions -= deleteTo - deleteFrom;
            } else if (baseOffsetAfterDeletions > deleteFrom) {
              // The base sits somewhere within the deletion region. Move it to the beginning
              // of the deletion region.
              baseOffsetAfterDeletions = deleteFrom;
            }
          }

          if (extentBeforeDeletions.nodeId == textNode.id) {
            if (extentOffsetAfterDeletions >= deleteTo) {
              // The extent sits beyond the entire deletion region. Push the extent up by the
              // length of the deletion region.
              extentOffsetAfterDeletions -= deleteTo - deleteFrom;
            } else if (extentOffsetAfterDeletions > deleteFrom) {
              // The extent sits somewhere within the deletion region. Move it to the beginning
              // of the deletion region.
              extentOffsetAfterDeletions = deleteFrom;
            }
          }

          deleteTagRequests.add(
            DeleteContentRequest(
              documentRange: textNode.selectionBetween(nodePath, deleteFrom, deleteTo),
            ),
          );
        }
      }

      if (deleteTagRequests.isNotEmpty) {
        deleteTagRequests.add(
          ChangeSelectionRequest(
            DocumentSelection(
              base: baseOffsetAfterDeletions >= 0
                  ? textNode.positionAt(nodePath, baseOffsetAfterDeletions)
                  : baseBeforeDeletions,
              extent: extentOffsetAfterDeletions >= 0
                  ? textNode.positionAt(nodePath, extentOffsetAfterDeletions)
                  : extentBeforeDeletions,
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.contentChange,
          ),
        );
      }
    }

    // Run all the tag attribution removal requests, and tag deletion requests,
    // that we queued up.
    requestDispatcher.execute([
      ...removeTagRequests,
      ...deleteTagRequests,
    ]);
  }

  /// Find any text near the caret that fits the pattern of a user tag and convert it into a
  /// composing tag.
  void _createNewComposingTag(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
  ) {
    editorStableTagsLog.fine("Looking for a tag around the caret.");
    final composer = editContext.find<MutableDocumentComposer>(Editor.composerKey);
    if (composer.selection == null || !composer.selection!.isCollapsed) {
      // We only tag when the selection is collapsed. Our selection is null or expanded. Return.
      return;
    }
    final selectionPosition = composer.selection!.extent;
    final caretPosition = selectionPosition.nodePosition;
    if (caretPosition is! TextNodePosition) {
      // Tagging only happens in the middle of text. The selected content isn't text. Return.
      return;
    }

    final document = editContext.document;
    final selectedNodePath = selectionPosition.documentPath;
    final selectedNode = document.getNodeById(selectionPosition.nodeId);
    if (selectedNode is! TextNode) {
      // Tagging only happens in the middle of text. The selected content isn't text. Return.
      return;
    }

    final existingComposingTag = TagFinder.findTagAroundPosition(
      tagRule: _tagRule,
      nodeId: selectedNode.id,
      text: selectedNode.text,
      expansionPosition: caretPosition,
      isTokenCandidate: (tokenAttributions) {
        return tokenAttributions.contains(stableTagComposingAttribution);
      },
    );
    if (existingComposingTag != null && caretPosition.offset > existingComposingTag.indexedTag.startOffset) {
      onUpdateComposingStableTag?.call(
        ComposingStableTag(
          selectedNode.rangeBetween(
            selectedNodePath,
            existingComposingTag.indexedTag.startOffset + 1,
            existingComposingTag.indexedTag.endOffset,
          ),
          existingComposingTag.indexedTag.tag.token,
        ),
      );
      return;
    }

    final nonAttributedTagAroundCaret = TagFinder.findTagAroundPosition(
        tagRule: _tagRule,
        nodeId: selectedNode.id,
        text: selectedNode.text,
        expansionPosition: caretPosition,
        isTokenCandidate: (tokenAttributions) {
          return !tokenAttributions.contains(stableTagComposingAttribution) &&
              !tokenAttributions.contains(stableTagCancelledAttribution) &&
              !tokenAttributions.any((attribution) => attribution is CommittedStableTagAttribution);
        });

    if (nonAttributedTagAroundCaret == null) {
      // There's no tag around the caret.
      editorStableTagsLog.fine("There's no tag around the caret, fizzling");
      onUpdateComposingStableTag?.call(null);
      return;
    }

    // We found a non-attributed stable tag near the caret. Give it a composing
    // attribution and report it as the composing tag.
    editorImeLog.fine("Found a stable token around caret: ${nonAttributedTagAroundCaret.indexedTag.tag}");
    onUpdateComposingStableTag?.call(
      ComposingStableTag(
        selectedNode.rangeBetween(
          selectedNodePath,
          // +1 to remove trigger symbol
          nonAttributedTagAroundCaret.indexedTag.startOffset + 1,
          nonAttributedTagAroundCaret.indexedTag.endOffset,
        ),
        nonAttributedTagAroundCaret.indexedTag.tag.token,
      ),
    );

    requestDispatcher.execute([
      AddTextAttributionsRequest(
        documentRange: selectedNode.selectionBetween(
          selectedNodePath,
          nonAttributedTagAroundCaret.indexedTag.startOffset,
          nonAttributedTagAroundCaret.indexedTag.endOffset,
        ),
        attributions: {
          stableTagComposingAttribution,
        },
      ),
    ]);
  }

  /// Find any composing tag that's no longer being composed, and commit it.
  void _commitCompletedComposingTag(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
  ) {
    editorStableTagsLog.fine("Looking for completed tags to commit.");
    final document = editContext.document;
    final composingTagNodeCandidates = <String>{};
    for (final edit in changeList) {
      if (edit is DocumentEdit && (edit.change is TextInsertionEvent || edit.change is TextDeletedEvent)) {
        composingTagNodeCandidates.add((edit.change as NodeChangeEvent).nodeId);
      } else if (edit is SelectionChangeEvent) {
        final oldSelection = edit.oldSelection;
        if (oldSelection == null) {
          continue;
        }

        if (oldSelection.base.nodePosition is TextNodePosition) {
          // The old selection might belong to a node that was removed. Make sure
          // the old node exists. If it does, add the node ID as a candidate.
          final nodeId = oldSelection.base.nodeId;
          if (document.getNodeById(nodeId) != null) {
            composingTagNodeCandidates.add(nodeId);
          }
        }
        if (oldSelection.extent.nodePosition is TextNodePosition) {
          // The old selection might belong to a node that was removed. Make sure
          // the old node exists. If it does, add the node ID as a candidate.
          final nodeId = oldSelection.extent.nodeId;
          if (document.getNodeById(nodeId) != null) {
            composingTagNodeCandidates.add(nodeId);
          }
        }
      } else if (edit is DocumentEdit && edit.change is NodeRemovedEvent) {
        // Make sure we don't try to track a node where text was edited, if that
        // node was later removed.
        final change = (edit).change as NodeRemovedEvent;
        composingTagNodeCandidates.remove(change.nodeId);
      }
    }
    if (composingTagNodeCandidates.isEmpty) {
      return;
    }

    final composer = editContext.find<MutableDocumentComposer>(Editor.composerKey);
    final selection = composer.selection;
    for (final textNodeId in composingTagNodeCandidates) {
      editorStableTagsLog.fine("Checking node $textNodeId for composing tags to commit");
      final textNodePath = document.getPathByNodeId(textNodeId)!;
      final textNode = document.getNodeById(textNodeId) as TextNode;
      final allTags = TagFinder.findAllTagsInTextNode(textNode, _tagRule);
      final composingTags =
          allTags.where((tag) => tag.computeLeadingSpanForAttribution(document, stableTagComposingAttribution).isValid);
      editorStableTagsLog.fine("Composing tags in node: $composingTags");

      for (final composingTag in composingTags) {
        if (selection == null || selection.extent.nodeId != textNodeId || selection.base.nodeId != textNodeId) {
          editorStableTagsLog
              .info("Committing tag because selection is null, or selection moved to different node: '$composingTag'");
          _commitTag(requestDispatcher, textNodePath, textNode, composingTag);
          continue;
        }

        final extentPosition = selection.extent.nodePosition as TextNodePosition;
        if (selection.isCollapsed &&
            (extentPosition.offset <= composingTag.startOffset || extentPosition.offset > composingTag.endOffset)) {
          editorStableTagsLog
              .info("Committing tag because the caret is out of range: '$composingTag', extent: $extentPosition");
          _commitTag(requestDispatcher, textNodePath, textNode, composingTag);
          continue;
        }

        editorStableTagsLog.fine("Allowing tag '$composingTag' to continue composing without committing it.");
      }
    }
  }

  void _commitTag(RequestDispatcher requestDispatcher, NodePath nodePath, TextNode textNode, IndexedTag tag) {
    onUpdateComposingStableTag?.call(null);

    final tagSelection = textNode.selectionBetween(nodePath, tag.startOffset, tag.endOffset);

    requestDispatcher
      // Remove composing tag attribution.
      ..execute([
        RemoveTextAttributionsRequest(
          documentRange: tagSelection,
          attributions: {stableTagComposingAttribution},
        )
      ])
      // Add stable tag attribution.
      ..execute([
        AddTextAttributionsRequest(
          documentRange: tagSelection,
          attributions: {
            CommittedStableTagAttribution(textNode.text.substring(
              tag.startOffset + 1, // +1 to remove the trigger ("@") from the value
              tag.endOffset,
            ))
          },
        )
      ]);
  }

  TagAroundPosition? _findComposingTagAtCaret(EditContext editContext) {
    return _findTagAtCaret(editContext, (attributions) => attributions.contains(stableTagComposingAttribution));
  }

  TagAroundPosition? _findTagAtCaret(
    EditContext editContext,
    bool Function(Set<Attribution> attributions) tagSelector,
  ) {
    final composer = editContext.find<MutableDocumentComposer>(Editor.composerKey);
    if (composer.selection == null || !composer.selection!.isCollapsed) {
      // We only tag when the selection is collapsed. Our selection is null or expanded. Return.
      return null;
    }
    final selectionPosition = composer.selection!.extent;
    final caretPosition = selectionPosition.nodePosition;
    if (caretPosition is! TextNodePosition) {
      // Tagging only happens in the middle of text. The selected content isn't text. Return.
      return null;
    }

    final document = editContext.document;
    final selectedNode = document.getNodeById(selectionPosition.nodeId);
    if (selectedNode is! TextNode) {
      // Tagging only happens in the middle of text. The selected content isn't text. Return.
      return null;
    }

    return TagFinder.findTagAroundPosition(
      tagRule: _tagRule,
      nodeId: selectedNode.id,
      text: selectedNode.text,
      expansionPosition: caretPosition,
      isTokenCandidate: tagSelector,
    );
  }

  void _updateTagIndex(EditContext editContext, List<EditEvent> changeList) {
    final document = editContext.document;
    final index = editContext.stableTagIndex;
    for (final event in changeList) {
      if (event is! DocumentEdit) {
        continue;
      }

      final change = event.change;
      if (change is! NodeDocumentChange) {
        return;
      }
      if (document.getNodeById(change.nodeId) is! TextNode) {
        return;
      }

      if (change is NodeRemovedEvent) {
        index._clearCommittedTagsInNode(change.nodeId);
        index._clearCancelledTagsInNode(change.nodeId);
      } else if (change is NodeInsertedEvent) {
        index._setCommittedTagsInNode(
          change.nodeId,
          _findAllTagsInNode(document, change.nodeId, (attribution) => attribution is CommittedStableTagAttribution),
        );
        index._setCancelledTagsInNode(
          change.nodeId,
          _findAllTagsInNode(document, change.nodeId, (attribution) => attribution == stableTagCancelledAttribution),
        );
      } else if (change is NodeChangeEvent) {
        index._setCommittedTagsInNode(
          change.nodeId,
          _findAllTagsInNode(document, change.nodeId, (attribution) => attribution is CommittedStableTagAttribution),
        );

        index._clearCancelledTagsInNode(change.nodeId);
        index._setCancelledTagsInNode(
          change.nodeId,
          _findAllTagsInNode(document, change.nodeId, (attribution) => attribution == stableTagCancelledAttribution),
        );
      }
    }
  }

  Set<IndexedTag> _findAllTagsInNode(Document document, String nodeId, AttributionFilter attributionFilter) {
    final textNode = document.getNodeById(nodeId) as TextNode;
    final allTags = textNode.text
        .getAttributionSpansInRange(
          attributionFilter: attributionFilter,
          range: SpanRange(0, textNode.text.length - 1),
        )
        .map(
          (span) => IndexedTag(
            Tag.fromRaw(textNode.text.substring(span.start, span.end + 1)),
            textNode.id,
            span.start,
          ),
        )
        .toSet();

    return allTags;
  }
}

typedef OnUpdateComposingStableTag = void Function(ComposingStableTag? composingStableTag);

/// Collects references to all stable tags in a document for easy querying.
class StableTagIndex with ChangeNotifier implements Editable {
  /// Returns the active [ComposingStableTag], if the user is currently composing a stable tag,
  /// or `null` if no stable tag is currently being composed.
  ValueListenable<ComposingStableTag?> get composingStableTag => _composingStableTag;
  final _composingStableTag = ValueNotifier<ComposingStableTag?>(null);

  void _onComposingStableTagFound(ComposingStableTag? tag) {
    _composingStableTag.value = tag;
  }

  final _committedTags = <String, Set<IndexedTag>>{};

  Set<IndexedTag> getCommittedTagsInTextNode(String nodeId) => _committedTags[nodeId] ?? {};

  Set<IndexedTag> getAllCommittedTags() {
    final tags = <IndexedTag>{};
    for (final value in _committedTags.values) {
      tags.addAll(value);
    }
    return tags;
  }

  void _setCommittedTagsInNode(String nodeId, Set<IndexedTag> tags) {
    _committedTags[nodeId] ??= <IndexedTag>{};

    if (const DeepCollectionEquality().equals(_committedTags[nodeId], tags)) {
      return;
    }

    _committedTags[nodeId]!
      ..clear()
      ..addAll(tags);
    _onChange();
  }

  void _clearCommittedTagsInNode(String nodeId) {
    if (_committedTags[nodeId] == null || _committedTags[nodeId]!.isEmpty) {
      return;
    }

    _committedTags[nodeId]?.clear();
    _onChange();
  }

  final _cancelledTags = <String, Set<IndexedTag>>{};

  Set<IndexedTag> getCancelledTagsInTextNode(String nodeId) => _cancelledTags[nodeId] ?? {};

  Set<IndexedTag> getAllCancelledTags() {
    final tags = <IndexedTag>{};
    for (final value in _cancelledTags.values) {
      tags.addAll(value);
    }
    return tags;
  }

  void _setCancelledTagsInNode(String nodeId, Set<IndexedTag> tags) {
    _cancelledTags[nodeId] ??= <IndexedTag>{};

    if (const DeepCollectionEquality().equals(_cancelledTags[nodeId], tags)) {
      return;
    }

    _cancelledTags[nodeId]!
      ..clear()
      ..addAll(tags);
    _onChange();
  }

  void _clearCancelledTagsInNode(String nodeId) {
    if (_cancelledTags[nodeId] == null || _cancelledTags[nodeId]!.isEmpty) {
      return;
    }

    _cancelledTags[nodeId]?.clear();
    _onChange();
  }

  bool _isInATransaction = false;
  bool _didChange = false;

  @override
  void onTransactionStart() {
    _isInATransaction = true;
    _didChange = false;
  }

  void _onChange() {
    if (!_isInATransaction) {
      return;
    }

    _didChange = true;
  }

  @override
  void onTransactionEnd(List<EditEvent> edits) {
    _isInATransaction = false;
    if (_didChange) {
      _didChange = false;
      notifyListeners();
    }
  }

  @override
  void reset() {
    _composingStableTag.value = null;
    _committedTags.clear();
    _cancelledTags.clear();
  }
}

class ComposingStableTag {
  const ComposingStableTag(this.contentBounds, this.token);

  final DocumentRange contentBounds;
  final String token;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComposingStableTag &&
          runtimeType == other.runtimeType &&
          contentBounds == other.contentBounds &&
          token == other.token;

  @override
  int get hashCode => contentBounds.hashCode ^ token.hashCode;

  @override
  String toString() => "[ComposingStableTag] - '$token', bounds: $contentBounds";
}

/// An [EditReaction] that prevents partial selection of a stable user tag.
class AdjustSelectionAroundTagReaction extends EditReaction {
  const AdjustSelectionAroundTagReaction(this._tagRule);

  final TagRule _tagRule;

  @override
  void react(EditContext editContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    editorStableTagsLog.info("KeepCaretOutOfTagReaction - react()");

    SelectionChangeEvent? selectionChangeEvent;
    bool hasNonSelectionOrComposingRegionChange = false;

    if (changeList.length == 2) {
      // Check if we have any event that isn't a selection or composing region change.
      hasNonSelectionOrComposingRegionChange =
          changeList.any((e) => e is! SelectionChangeEvent && e is! ComposingRegionChangeEvent);
      selectionChangeEvent = changeList.firstWhereOrNull((e) => e is SelectionChangeEvent) as SelectionChangeEvent?;
    } else if (changeList.length == 1 && changeList.first is SelectionChangeEvent) {
      selectionChangeEvent = changeList.first as SelectionChangeEvent;
    }

    if (hasNonSelectionOrComposingRegionChange || selectionChangeEvent == null) {
      // We only want to move the caret when we're confident about what changed. Therefore,
      // we only react to changes that are solely a selection or composing region change,
      // i.e., we ignore situations like text entry, text deletion, etc.
      editorStableTagsLog.info(" - change list isn't just a single SelectionChangeEvent: $changeList");
      return;
    }

    editorStableTagsLog.info(" - we received just one selection change event. Checking for user tag.");

    final document = editContext.document;

    final newCaret = selectionChangeEvent.newSelection?.extent;
    if (newCaret == null) {
      editorStableTagsLog.fine(" - there's no caret/extent. Fizzling.");
      return;
    }

    if (selectionChangeEvent.newSelection!.isCollapsed) {
      final textNode = document.getNodeById(newCaret.nodeId);
      if (textNode == null || textNode is! TextNode) {
        // The selected content isn't text. We don't need to worry about it.
        editorStableTagsLog.fine(" - selected content isn't text. Fizzling.");
        return;
      }

      _adjustCaretPosition(
        editContext: editContext,
        requestDispatcher: requestDispatcher,
        textNode: textNode,
        selectionChangeEvent: selectionChangeEvent,
        newCaret: newCaret,
      );
    } else {
      _adjustExpandedSelection(
        editContext: editContext,
        requestDispatcher: requestDispatcher,
        selectionChangeEvent: selectionChangeEvent,
        newCaret: newCaret,
      );
    }
  }

  void _adjustCaretPosition({
    required EditContext editContext,
    required RequestDispatcher requestDispatcher,
    required TextNode textNode,
    required SelectionChangeEvent selectionChangeEvent,
    required DocumentPosition newCaret,
  }) {
    editorStableTagsLog.fine("Adjusting the caret position to avoid stable tags.");

    final textNodePath = editContext.document.getPathByNodeId(textNode.id)!;
    final tagAroundCaret = _findTagAroundPosition(
      textNode.id,
      textNode.text,
      newCaret.nodePosition as TextNodePosition,
      (attribution) => attribution is CommittedStableTagAttribution,
    );
    if (tagAroundCaret == null) {
      // The caret isn't in a tag. We don't need to adjust anything.
      editorStableTagsLog
          .fine(" - the caret isn't in a tag. Fizzling. Selection:\n${selectionChangeEvent.newSelection}");
      return;
    }
    editorStableTagsLog.fine("Found tag around caret - $tagAroundCaret");

    // The new caret position sits inside of a tag. We need to move it outside the tag.
    editorStableTagsLog.fine("Selection change type: ${selectionChangeEvent.changeType}");
    switch (selectionChangeEvent.changeType) {
      case SelectionChangeType.insertContent:
        // It's not obvious how this would happen when inserting content. We'll play it
        // safe and do nothing in this case.
        return;
      case SelectionChangeType.placeCaret:
      case SelectionChangeType.collapseSelection:
      case SelectionChangeType.alteredContent:
      case SelectionChangeType.deleteContent:
        // Move the caret to the nearest edge of the tag.
        _moveCaretToNearestTagEdge(requestDispatcher, selectionChangeEvent, textNodePath, tagAroundCaret);
        break;
      case SelectionChangeType.pushCaret:
        // Move the caret to the side of the tag in the direction of push motion.
        _pushCaretToOppositeTagEdge(editContext, requestDispatcher, selectionChangeEvent, tagAroundCaret);
        break;
      case SelectionChangeType.placeExtent:
      case SelectionChangeType.pushExtent:
      case SelectionChangeType.expandSelection:
        throw AssertionError(
            "A collapsed selection reported a SelectionChangeType for an expanded selection: ${selectionChangeEvent.changeType}\n${selectionChangeEvent.newSelection}");
      case SelectionChangeType.clearSelection:
        throw AssertionError("Expected a collapsed selection but there was no selection.");
    }
  }

  void _adjustExpandedSelection({
    required EditContext editContext,
    required RequestDispatcher requestDispatcher,
    required SelectionChangeEvent selectionChangeEvent,
    required DocumentPosition newCaret,
  }) {
    editorStableTagsLog.fine("Adjusting an expanded selection to avoid a partial stable tag selection.");

    final document = editContext.document;
    final extentNodePath = document.getPathByNodeId(newCaret.nodeId)!;
    final extentNode = document.getNodeById(newCaret.nodeId);
    if (extentNode is! TextNode) {
      // The caret isn't sitting in text. Fizzle.
      return;
    }

    final tagAroundCaret = _findTagAroundPosition(
      extentNode.id,
      extentNode.text,
      newCaret.nodePosition as TextNodePosition,
      (attribution) => attribution is CommittedStableTagAttribution,
    );

    // The new caret position sits inside of a tag. We need to move it outside the tag.
    editorStableTagsLog.fine("Selection change type: ${selectionChangeEvent.changeType}");
    switch (selectionChangeEvent.changeType) {
      case SelectionChangeType.insertContent:
        // It's not obvious how this would happen when inserting content. We'll play it
        // safe and do nothing in this case.
        return;
      case SelectionChangeType.placeExtent:
      case SelectionChangeType.alteredContent:
      case SelectionChangeType.deleteContent:
        if (tagAroundCaret == null) {
          return;
        }

        // Move the caret to the nearest edge of the tag.
        _moveCaretToNearestTagEdge(requestDispatcher, selectionChangeEvent, extentNodePath, tagAroundCaret);
        break;
      case SelectionChangeType.pushExtent:
        if (tagAroundCaret == null) {
          return;
        }

        // Expand the selection by pushing the caret to the side of the tag in the direction of push motion.
        _pushCaretToOppositeTagEdge(
          editContext,
          requestDispatcher,
          selectionChangeEvent,
          tagAroundCaret,
          expand: true,
        );
        break;
      case SelectionChangeType.expandSelection:
        // Move the base or extent to the side of the tag in the direction of push motion.
        TextNode? baseNode;
        final basePosition = selectionChangeEvent.newSelection!.base;
        if (basePosition.nodePosition is TextNodePosition) {
          baseNode = document.getNodeById(basePosition.nodeId) as TextNode;
        }

        _pushExpandedSelectionAroundTags(
          editContext,
          requestDispatcher,
          selectionChangeEvent,
          baseNode: baseNode,
          extentNode: extentNode,
        );
        break;
      case SelectionChangeType.placeCaret:
      case SelectionChangeType.pushCaret:
      case SelectionChangeType.collapseSelection:
        throw AssertionError(
            "An expanded selection reported a SelectionChangeType for a collapsed selection: ${selectionChangeEvent.changeType}\n${selectionChangeEvent.newSelection}");
      case SelectionChangeType.clearSelection:
        throw AssertionError("Expected a collapsed selection but there was no selection.");
    }
  }

  TagAroundPosition? _findTagAroundPosition(
    String nodeId,
    AttributedText paragraphText,
    TextNodePosition position,
    bool Function(Attribution) attributionSelector,
  ) {
    final tagAroundCaret = TagFinder.findTagAroundPosition(
      tagRule: _tagRule,
      nodeId: nodeId,
      text: paragraphText,
      expansionPosition: position,
      isTokenCandidate: (tokenAttributions) => tokenAttributions.any(attributionSelector),
    );
    if (tagAroundCaret == null) {
      return null;
    }
    if (tagAroundCaret.searchOffsetInToken == 0 ||
        tagAroundCaret.searchOffsetInToken == tagAroundCaret.indexedTag.tag.raw.length) {
      // The token is either on the starting edge, e.g., "|@tag", or at the ending edge,
      // e.g., "@tag|". We don't care about those scenarios when looking for the caret
      // inside of the token.
      return null;
    }

    final tokenAttributions = paragraphText.getAllAttributionsThroughout(
      SpanRange(
        tagAroundCaret.indexedTag.startOffset,
        tagAroundCaret.indexedTag.endOffset - 1,
      ),
    );
    if (tokenAttributions.any((attribution) => attribution is CommittedStableTagAttribution)) {
      // This token is a user tag. Return it.
      return tagAroundCaret;
    }

    return null;
  }

  void _moveCaretToNearestTagEdge(
    RequestDispatcher requestDispatcher,
    SelectionChangeEvent selectionChangeEvent,
    NodePath textNodePath,
    TagAroundPosition tagAroundCaret,
  ) {
    DocumentSelection? newSelection;
    editorStableTagsLog.info("oldCaret is null. Pushing caret to end of tag.");
    // The caret was placed directly in the token without a previous selection. This might
    // be a user tap, or programmatic placement. Move the caret to the nearest edge of the
    // token.
    if ((tagAroundCaret.searchOffset - tagAroundCaret.indexedTag.startOffset).abs() <
        (tagAroundCaret.searchOffset - tagAroundCaret.indexedTag.endOffset).abs()) {
      // Move the caret to the start of the tag.
      newSelection = DocumentSelection.collapsed(
        position: DocumentPosition(
          documentPath: textNodePath,
          nodePosition: TextNodePosition(offset: tagAroundCaret.indexedTag.startOffset),
        ),
      );
    } else {
      // Move the caret to the end of the tag.
      newSelection = DocumentSelection.collapsed(
        position: DocumentPosition(
          documentPath: textNodePath,
          nodePosition: TextNodePosition(offset: tagAroundCaret.indexedTag.endOffset),
        ),
      );
    }

    requestDispatcher.execute([
      ChangeSelectionRequest(
        newSelection,
        newSelection.isCollapsed ? SelectionChangeType.pushCaret : SelectionChangeType.expandSelection,
        SelectionReason.contentChange,
      ),
    ]);
  }

  void _pushCaretToOppositeTagEdge(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    SelectionChangeEvent selectionChangeEvent,
    TagAroundPosition tagAroundCaret, {
    bool expand = false,
  }) {
    editorStableTagsLog.info("Pushing caret to other side of token - tag around caret: $tagAroundCaret");
    final Document document = editContext.document;

    final pushDirection = document.getAffinityBetween(
      base: selectionChangeEvent.oldSelection!.extent,
      extent: selectionChangeEvent.newSelection!.extent,
    );

    late int textOffset;
    switch (pushDirection) {
      case TextAffinity.upstream:
        // Move to starting edge.
        textOffset = tagAroundCaret.indexedTag.startOffset;
        break;
      case TextAffinity.downstream:
        // Move to ending edge.
        textOffset = tagAroundCaret.indexedTag.endOffset;
        break;
    }

    final newSelection = expand
        ? DocumentSelection(
            base: selectionChangeEvent.newSelection!.base,
            extent: DocumentPosition(
              documentPath: editContext.document.getPathByNodeId(selectionChangeEvent.newSelection!.extent.nodeId)!,
              nodePosition: TextNodePosition(
                offset: textOffset,
              ),
            ),
          )
        : DocumentSelection.collapsed(
            position: DocumentPosition(
              documentPath: editContext.document.getPathByNodeId(selectionChangeEvent.newSelection!.extent.nodeId)!,
              nodePosition: TextNodePosition(
                offset: textOffset,
              ),
            ),
          );

    requestDispatcher.execute([
      ChangeSelectionRequest(
        newSelection,
        SelectionChangeType.pushCaret,
        SelectionReason.contentChange,
      ),
    ]);
  }

  void _pushExpandedSelectionAroundTags(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    SelectionChangeEvent selectionChangeEvent, {
    required TextNode? baseNode,
    required TextNode? extentNode,
  }) {
    editorStableTagsLog.info("Pushing expanded selection to other side(s) of token(s)");

    final document = editContext.document;
    final selection = selectionChangeEvent.newSelection!;
    final selectionAffinity = document.getAffinityForSelection(selection);

    final tagAroundBase = baseNode != null
        ? _findTagAroundPosition(
            baseNode.id,
            baseNode.text,
            selectionChangeEvent.newSelection!.base.nodePosition as TextNodePosition,
            (attribution) => attribution is CommittedStableTagAttribution,
          )
        : null;

    DocumentPosition? newBasePosition;
    if (tagAroundBase != null) {
      newBasePosition = DocumentPosition(
        documentPath: document.getPathByNodeId(selection.base.nodeId)!,
        nodePosition: selectionAffinity == TextAffinity.downstream //
            ? TextNodePosition(offset: tagAroundBase.indexedTag.startOffset)
            : TextNodePosition(offset: tagAroundBase.indexedTag.endOffset),
      );
    }

    final tagAroundExtent = extentNode != null
        ? _findTagAroundPosition(
            extentNode.id,
            extentNode.text,
            selectionChangeEvent.newSelection!.extent.nodePosition as TextNodePosition,
            (attribution) => attribution is CommittedStableTagAttribution,
          )
        : null;

    DocumentPosition? newExtentPosition;
    if (tagAroundExtent != null) {
      newExtentPosition = DocumentPosition(
        documentPath: document.getPathByNodeId(selection.extent.nodeId)!,
        nodePosition: selectionAffinity == TextAffinity.downstream //
            ? TextNodePosition(offset: tagAroundExtent.indexedTag.endOffset)
            : TextNodePosition(offset: tagAroundExtent.indexedTag.startOffset),
      );
    }

    if (newBasePosition == null && newExtentPosition == null) {
      // No adjustment is needed.
      editorStableTagsLog.info("No selection adjustment is needed.");
      return;
    }

    requestDispatcher.execute([
      ChangeSelectionRequest(
        DocumentSelection(
          base: newBasePosition ?? selectionChangeEvent.newSelection!.base,
          extent: newExtentPosition ?? selectionChangeEvent.newSelection!.extent,
        ),
        SelectionChangeType.expandSelection,
        SelectionReason.contentChange,
      ),
    ]);
  }
}

/// An attribution for a stable tag that's currently being composed.
const stableTagComposingAttribution = NamedAttribution("stable-tag-composing");

/// An attribution for a stable tag that was being composed and then was cancelled.
///
/// This attribution is used to prevent automatically converting a cancelled composition
/// back to a composing tag.
const stableTagCancelledAttribution = NamedAttribution("stable-tag-cancelled");

/// An attribution for a committed tag, i.e., a stable tag that's done being composed and
/// shouldn't be partially selectable or editable.
class CommittedStableTagAttribution implements Attribution {
  const CommittedStableTagAttribution(this.tagValue);

  @override
  String get id => tagValue;

  final String tagValue;

  @override
  bool canMergeWith(Attribution other) {
    return this == other;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommittedStableTagAttribution && runtimeType == other.runtimeType && tagValue == other.tagValue;

  @override
  int get hashCode => tagValue.hashCode;

  @override
  String toString() {
    return '[CommittedStableTagAttribution]: $tagValue';
  }
}
