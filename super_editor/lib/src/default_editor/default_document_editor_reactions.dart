import 'dart:io';

import 'package:attributed_text/attributed_text.dart';
import 'package:characters/characters.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:linkify/linkify.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/default_editor/attributions.dart';
import 'package:super_editor/src/default_editor/horizontal_rule.dart';
import 'package:super_editor/src/default_editor/image.dart';
import 'package:super_editor/src/default_editor/list_items.dart';
import 'package:super_editor/src/default_editor/paragraph.dart';
import 'package:super_editor/src/default_editor/tasks.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/strings.dart';

import 'multi_node_editing.dart';

/// Converts a [ParagraphNode] from a regular paragraph to a header when the
/// user types "# " (or similar) at the start of the paragraph.
class HeaderConversionReaction extends ParagraphPrefixConversionReaction {
  static Attribution _getHeaderAttributionForLevel(int level) {
    switch (level) {
      case 1:
        return header1Attribution;
      case 2:
        return header2Attribution;
      case 3:
        return header3Attribution;
      case 4:
        return header4Attribution;
      case 5:
        return header5Attribution;
      case 6:
        return header6Attribution;
      default:
        throw Exception(
            "Tried to match a header pattern level ($level) to a header attribution, but there's no attribution for that level.");
    }
  }

  HeaderConversionReaction([
    this.maxLevel = 6,
    this.mapping = _getHeaderAttributionForLevel,
  ]) {
    _headerRegExp = RegExp("^#{1,$maxLevel}\\s+\$");
  }

  /// The highest level of header that this reaction will recognize, e.g., `3` -> "### ".
  final int maxLevel;

  /// The mapping from integer header levels to header [Attribution]s.
  final HeaderAttributionMapping mapping;

  @override
  RegExp get pattern => _headerRegExp;
  late final RegExp _headerRegExp;

  @override
  void onPrefixMatched(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
    ParagraphNode paragraph,
    String match,
  ) {
    final prefixLength = match.length - 1; // -1 for the space on the end
    late Attribution headerAttribution = _getHeaderAttributionForLevel(prefixLength);

    final paragraphPath = editContext.document.getPathByNodeId(paragraph.id)!;
    final paragraphPatternSelection = DocumentSelection(
      base: DocumentPosition(
        documentPath: paragraphPath,
        nodePosition: const TextNodePosition(offset: 0),
      ),
      extent: DocumentPosition(
        documentPath: paragraphPath,
        nodePosition: TextNodePosition(offset: paragraph.text.toPlainText().indexOf(" ") + 1),
      ),
    );

    requestDispatcher.execute([
      // Change the paragraph to a header.
      ChangeParagraphBlockTypeRequest(
        nodeId: paragraph.id,
        blockType: headerAttribution,
      ),
      // Delete the header pattern from the content.
      ChangeSelectionRequest(
        paragraphPatternSelection,
        SelectionChangeType.expandSelection,
        SelectionReason.contentChange,
      ),
      DeleteContentRequest(
        documentRange: paragraphPatternSelection,
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: editContext.document.getPathByNodeId(paragraph.id)!,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.deleteContent,
        SelectionReason.userInteraction,
      ),
    ]);
  }
}

typedef HeaderAttributionMapping = Attribution Function(int level);

/// Converts a [ParagraphNode] to an [UnorderedListItemNode] when the
/// user types "* " (or similar) at the start of the paragraph.
class UnorderedListItemConversionReaction extends ParagraphPrefixConversionReaction {
  static final _unorderedListItemPattern = RegExp(r'^\s*[*-]\s+$');

  const UnorderedListItemConversionReaction();

  @override
  RegExp get pattern => _unorderedListItemPattern;

  @override
  void onPrefixMatched(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
    ParagraphNode paragraph,
    String match,
  ) {
    // The user started a paragraph with an unordered list item pattern.
    // Convert the paragraph to an unordered list item.
    requestDispatcher.execute([
      ReplaceNodeRequest(
        existingNodeId: paragraph.id,
        newNode: ListItemNode.unordered(
          id: paragraph.id,
          text: AttributedText(),
        ),
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: editContext.document.getPathByNodeId(paragraph.id)!,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.contentChange,
      ),
    ]);
  }
}

/// Converts a [ParagraphNode] to an [OrderedListItemNode] when the
/// user types " 1. " (or similar) at the start of the paragraph.
class OrderedListItemConversionReaction extends ParagraphPrefixConversionReaction {
  /// Matches strings like ` 1. `, ` 2. `, ` 1) `, ` 2) `, etc.
  static final _orderedListPattern = RegExp(r'^\s*\d+[.)]\s+$');

  /// Matches one or more numbers.
  static final _numberRegex = RegExp(r'\d+');

  const OrderedListItemConversionReaction();

  @override
  RegExp get pattern => _orderedListPattern;

  @override
  void onPrefixMatched(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
    ParagraphNode paragraph,
    String match,
  ) {
    // Extract the number from the match.
    final numberMatch = _numberRegex.firstMatch(match)!;
    final numberTyped = int.parse(match.substring(numberMatch.start, numberMatch.end));

    if (numberTyped > 1) {
      // Check if the user typed a number that continues the sequence of an upstream
      // ordered list item. For example, the list has the items 1, 2, 3 and 4,
      // and the user types " 5. ".

      final document = editContext.document;

      final upstreamNode = document.getNodeBefore(paragraph);
      if (upstreamNode == null || upstreamNode is! ListItemNode || upstreamNode.type != ListItemType.ordered) {
        // There isn't an ordered list item immediately before this paragraph. Fizzle.
        return;
      }

      // The node immediately before this paragraph is an ordered list item. Compute its ordinal value,
      // so we can check if the user typed the next number in the sequence.
      int upstreamListItemOrdinalValue = computeListItemOrdinalValue(upstreamNode, document);
      if (numberTyped != upstreamListItemOrdinalValue + 1) {
        // The user typed a number that doesn't continue the sequence of the upstream ordered list item.
        return;
      }
    }

    // The user started a paragraph with an ordered list item pattern.
    // Convert the paragraph to an unordered list item.
    requestDispatcher.execute([
      ReplaceNodeRequest(
        existingNodeId: paragraph.id,
        newNode: ListItemNode.ordered(
          id: paragraph.id,
          text: AttributedText(),
        ),
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: editContext.document.getPathByNodeId(paragraph.id)!,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.contentChange,
      ),
    ]);
  }
}

/// Adjusts a [ParagraphNode] to use a blockquote block attribution when a
/// user types " > " (or similar) at the start of the paragraph.
class BlockquoteConversionReaction extends ParagraphPrefixConversionReaction {
  static final _blockquotePattern = RegExp(r'^>\s$');

  const BlockquoteConversionReaction();

  @override
  RegExp get pattern => _blockquotePattern;

  @override
  void onPrefixMatched(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
    ParagraphNode paragraph,
    String match,
  ) {
    // The user started a paragraph with blockquote pattern.
    // Convert the paragraph to a blockquote.
    requestDispatcher.execute([
      ReplaceNodeRequest(
        existingNodeId: paragraph.id,
        newNode: ParagraphNode(
          id: paragraph.id,
          text: AttributedText(),
          metadata: {
            "blockType": blockquoteAttribution,
          },
        ),
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: editContext.document.getPathByNodeId(paragraph.id)!,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.contentChange,
      ),
    ]);
  }
}

/// Converts node content that looks like "--- " or "—- " (an em-dash followed by a regular dash)
/// at the beginning of a paragraph into a horizontal rule.
///
/// The horizontal rule is inserted before the current node and the remainder of
/// the node's text is kept.
///
/// Applied only to all [TextNode]s.
class HorizontalRuleConversionReaction extends EditReaction {
  // Matches "---" or "—-" (an em-dash followed by a regular dash) at the beginning of a line,
  // followed by a space.
  static final _hrPattern = RegExp(r'^(---|—-)\s');

  const HorizontalRuleConversionReaction();

  @override
  void react(EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    if (changeList.length < 2) {
      // This reaction requires at least an insertion event and a selection change event.
      // There are less than two events in the the change list, therefore this reaction
      // shouldn't apply. Fizzle.
      return;
    }

    final document = editorContext.document;

    final didTypeSpace = EditInspector.didTypeSpace(document, changeList);
    if (!didTypeSpace) {
      return;
    }

    // final edit = changeList[changeList.length - 2] as DocumentEdit;
    final edit = changeList.reversed.firstWhere((edit) => edit is DocumentEdit) as DocumentEdit;
    if (edit.change is! TextInsertionEvent) {
      // This reaction requires that the two last events are an insertion event
      // followed by a selection change event.
      // The second to last event isn't a text insertion event, therefore this reaction
      // shouldn't apply. Fizzle.
    }

    final textInsertionEvent = edit.change as TextInsertionEvent;
    final paragraph = document.getNodeById(textInsertionEvent.nodeId) as TextNode;
    final match = _hrPattern.firstMatch(paragraph.text.toPlainText())?.group(0);
    if (match == null) {
      return;
    }

    // The user typed a horizontal rule pattern at the beginning of a paragraph.
    // - Remove the dashes and the space.
    // - Insert a horizontal rule before the paragraph.
    // - Place caret at the start of the paragraph.
    final paragraphPath = document.getPathByNodeId(paragraph.id)!;
    requestDispatcher.execute([
      DeleteContentRequest(
        documentRange: DocumentRange(
          start: DocumentPosition(documentPath: paragraphPath, nodePosition: const TextNodePosition(offset: 0)),
          end: DocumentPosition(documentPath: paragraphPath, nodePosition: TextNodePosition(offset: match.length)),
        ),
      ),
      InsertNodeAtIndexRequest(
        nodeIndex: document.getNodeIndexById(paragraph.id),
        newNode: HorizontalRuleNode(
          id: Editor.createNodeId(),
        ),
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: paragraphPath,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.contentChange,
      ),
    ]);
  }
}

/// Base class for [EditReaction]s that want to take action when the user types text at
/// the beginning of a paragraph, which matches a given [RegExp].
abstract class ParagraphPrefixConversionReaction extends EditReaction {
  const ParagraphPrefixConversionReaction({
    bool requireSpaceInsertion = true,
  }) : _requireSpaceInsertion = requireSpaceInsertion;

  /// Whether the [_prefixPattern] requires a trailing space.
  ///
  /// The [_prefixPattern] will always be honored. This hint provides a performance
  /// optimization so that the pattern expression is never evaluated in cases where the
  /// user didn't insert a space into the paragraph.
  final bool _requireSpaceInsertion;

  /// Pattern that is matched at the beginning of a paragraph and then passed to
  /// sub-classes for processing.
  RegExp get pattern;

  @override
  void react(EditContext editContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    final document = editContext.document;
    final typedText = EditInspector.findLastTextUserTyped(document, changeList);
    if (typedText == null) {
      return;
    }
    if (_requireSpaceInsertion && !typedText.text.toPlainText().endsWith(" ")) {
      return;
    }

    final paragraph = document.getNodeById(typedText.nodeId);
    if (paragraph is! ParagraphNode) {
      return;
    }

    final match = pattern.firstMatch(paragraph.text.toPlainText())?.group(0);
    if (match == null) {
      return;
    }

    // The user started a paragraph with the desired pattern. Delegate to the subclass
    // to do whatever it wants.
    onPrefixMatched(editContext, requestDispatcher, changeList, paragraph, match);
  }

  /// Hook, called by the superclass, when the user starts the given [paragraph] with
  /// the given [match], which fits the desired [pattern].
  @protected
  void onPrefixMatched(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
    ParagraphNode paragraph,
    String match,
  );
}

/// When the user creates a new node, and the previous node is just a URL
/// to an image, the replaces the previous node with the referenced image.
class ImageUrlConversionReaction extends EditReaction {
  const ImageUrlConversionReaction();

  @override
  void react(EditContext editContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    if (changeList.isEmpty) {
      return;
    }
    if (changeList.last is! SubmitParagraphIntention) {
      return;
    }

    editorOpsLog.finer("Checking for image URL after paragraph submission");

    // The user pressed "enter" at the end of a paragraph. Check if the
    // paragraph is comprised of a URL.
    final selectionChange =
        changeList.reversed.firstWhereOrNull((item) => item is SelectionChangeEvent) as SelectionChangeEvent?;
    if (selectionChange == null || selectionChange.oldSelection == null) {
      // There was no selection change. There should be a selection change when
      // a paragraph is inserted. We don't know what's going on. Bail out.
      editorOpsLog.finer("There was no selection change. Not an image URL.");
      return;
    }

    final document = editContext.document;
    final previousNode = document.getNodeById(selectionChange.oldSelection!.extent.nodeId);
    if (previousNode is! ParagraphNode) {
      // The intention indicated that the user pressed "enter" from a paragraph
      // but the previously selected node isn't a paragraph. We don't know why.
      // Bail out.
      editorOpsLog.finer("Previous node wasn't a paragraph. Bailing.");
      return;
    }

    // Check if the submitted paragraph is comprised of a single URL.
    final extractedLinks = linkify(
      previousNode.text.toPlainText(),
      options: const LinkifyOptions(
        humanize: false,
      ),
    );
    final int linkCount = extractedLinks.fold(0, (value, element) => element is UrlElement ? value + 1 : value);
    if (linkCount != 1) {
      // Either there aren't any URLs, or there are multiple. This reaction
      // doesn't apply.
      editorOpsLog.finer("Didn't find exactly 1 link. Found: $linkCount");
      return;
    }

    final url = extractedLinks.firstWhere((element) => element is UrlElement).text;
    if (url != previousNode.text.toPlainText().trim()) {
      // There's more in the paragraph than just a URL. This reaction
      // doesn't apply.
      editorOpsLog.finer("Paragraph had more than just a URL");
      return;
    }

    // The submitted paragraph consists of a single URL. Check if that
    // URL is an image. If it is, replace the submitted paragraph with
    // an image.
    // TODO: move the URL lookup into a behavior within the node. We don't want async reaction behaviors.
    final originalText = previousNode.text.toPlainText();
    _isImageUrl(url).then((isImage) {
      if (!isImage) {
        editorOpsLog.finer("Checked URL, but it's not an image");
        return;
      }

      // The URL is an image. Convert the node.
      editorOpsLog.finer('The URL is an image. Converting the ParagraphNode to an ImageNode.');
      final node = document.getNodeById(previousNode.id);
      if (node is! ParagraphNode) {
        editorOpsLog.finer('The node has become something other than a ParagraphNode ($node). Can\'t convert node.');
        return;
      }
      final currentText = node.text.toPlainText();
      if (currentText.trim() != originalText.trim()) {
        editorOpsLog.finer('The node content changed in a non-trivial way. Aborting node conversion.');
        return;
      }

      final imageNode = ImageNode(
        id: node.id,
        imageUrl: url,
      );

      requestDispatcher.execute([
        ReplaceNodeRequest(
          existingNodeId: node.id,
          newNode: imageNode,
        ),
      ]);
    });
  }

  Future<bool> _isImageUrl(String url) async {
    late http.Response response;

    // This function throws [SocketException] when the [url] is not valid.
    // For instance, when typing for https://f|, it throws
    // Unhandled Exception: SocketException: Failed host lookup: 'f'
    //
    // It doesn't affect any functionality, but it throws exception and preventing
    // any related test to pass
    try {
      response = await http.get(Uri.parse(url));
    } on SocketException catch (e) {
      editorOpsLog.fine('Failed to load URL: ${e.message}');
      return false;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      editorOpsLog.fine('Failed to load URL: ${response.statusCode} - ${response.reasonPhrase}');
      return false;
    }

    final contentType = response.headers['content-type'];
    if (contentType == null) {
      editorOpsLog.fine('Failed to determine URL content type.');
      return false;
    }
    if (!contentType.startsWith('image/')) {
      editorOpsLog.fine('URL is not an image. Ignoring');
      return false;
    }

    return true;
  }
}

/// An [EditReaction] which converts a URL into a styled link.
///
/// When the URL has characters added or removed, the [updatePolicy] determines
/// which action to take:
///
/// - [LinkUpdatePolicy.preserve] : the attribution remains unchanged.
/// - [LinkUpdatePolicy.update] : the attribution is updated to reflect the new URL.
/// - [LinkUpdatePolicy.remove] : the attribution is removed.
///
/// A plain text URL only has a link applied to it when the user enters a space " "
/// after a token that looks like a URL. If the user doesn't enter a trailing space,
/// or the preceding token doesn't look like a URL, then the link attribution isn't aplied.
class LinkifyReaction extends EditReaction {
  const LinkifyReaction({
    this.updatePolicy = LinkUpdatePolicy.preserve,
  });

  /// Configures how a change in a URL should be handled.
  final LinkUpdatePolicy updatePolicy;

  @override
  void react(EditContext editContext, RequestDispatcher requestDispatcher, List<EditEvent> edits) {
    final document = editContext.document;
    final composer = editContext.find<MutableDocumentComposer>(Editor.composerKey);
    final selection = composer.selection;

    bool didInsertSpace = false;

    TextInsertionEvent? linkifyCandidate;
    for (int i = 0; i < edits.length; i++) {
      final edit = edits[i];
      if (edit is DocumentEdit) {
        final change = edit.change;
        if (change is TextInsertionEvent && change.text.toPlainText() == " ") {
          // Every space insertion might appear after a URL.
          linkifyCandidate = change;
          didInsertSpace = true;
        }
      } else if (edit is SelectionChangeEvent) {
        if (linkifyCandidate == null) {
          // There was no text insertion to linkify.
          continue;
        }

        if (selection == null) {
          // The editor doesn't have a selection. Don't linkify.
          linkifyCandidate = null;
          continue;
        }

        if (!selection.isCollapsed) {
          // The selection is expanded. Don't linkify.
          linkifyCandidate = null;
          continue;
        }

        final caretPosition = selection.extent;
        if (caretPosition.nodeId != linkifyCandidate.nodeId) {
          // The selection moved to some other node. Don't linkify.
          linkifyCandidate = null;
          continue;
        }

        // +1 for the inserted space
        if ((caretPosition.nodePosition as TextNodePosition).offset != linkifyCandidate.offset + 1) {
          // The caret isn't sitting directly after the space. Whatever
          // these events represent, it doesn't represent the user typing
          // a URL and then press SPACE. Don't linkify.
          linkifyCandidate = null;
          continue;
        }

        // The caret sits directly after an inserted space. Get the word before
        // the space from the document, and linkify, if it fits a schema.
        final textNode = document.getNodeById(linkifyCandidate.nodeId) as TextNode;
        _extractUpstreamWordAndLinkify(textNode.text, linkifyCandidate.offset);
      } else if ((edit is SubmitParagraphIntention && edit.isStart) ||
          (edit is SplitParagraphIntention && edit.isStart) ||
          (edit is SplitListItemIntention && edit.isStart) ||
          (edit is SplitTaskIntention && edit.isStart)) {
        // The user is splitting a node or submit a paragraph. For example, by pressing ENTER.
        // Get the nodeId on the next change to try to linkify the text.

        if (i >= edits.length - 1) {
          // The current edit is the last on the list.
          // We can't get the node id.
          continue;
        }

        final nextEdit = edits[i + 1];
        if (nextEdit is DocumentEdit && nextEdit.change is NodeChangeEvent) {
          final editedNode = document.getNodeById((nextEdit.change as NodeChangeEvent).nodeId);
          if (editedNode is TextNode) {
            _extractUpstreamWordAndLinkify(editedNode.text, editedNode.text.length);
          }
        }
      }
    }

    if (!didInsertSpace) {
      // We didn't linkify any text. Check if we need to update an URL.
      _tryUpdateLinkAttribution(requestDispatcher, document, composer, edits);
    }
  }

  /// Extracts a word ending at [endOffset] tries to linkify it.
  void _extractUpstreamWordAndLinkify(AttributedText text, int endOffset) {
    final wordStartOffset = _moveOffsetByWord(text.toPlainText(), endOffset, true) ?? 0;
    final word = text.substring(wordStartOffset, endOffset);

    // Ensure that the preceding word doesn't already contain a full or partial
    // link attribution.
    if (text
        .getAttributionSpansInRange(
          attributionFilter: (attribution) => attribution is LinkAttribution,
          range: SpanRange(wordStartOffset, endOffset),
        )
        .isNotEmpty) {
      // There are link attributions in the preceding word. We don't want to mess with them.
      return;
    }

    // Try to linkify.
    final uri = tryToParseUrl(word);
    if (uri == null) {
      // No link in the word. Fizzle.
      return;
    }

    // We found a link. Attribute it.
    text.addAttribution(
      LinkAttribution.fromUri(uri),
      SpanRange(wordStartOffset, endOffset - 1),
    );
  }

  int? _moveOffsetByWord(String text, int textOffset, bool upstream) {
    if (textOffset < 0 || textOffset > text.length) {
      throw Exception("Index '$textOffset' is out of string range. Length: ${text.length}");
    }

    // Create a character range, initially with zero length
    // Note that the getter for this object is confusingly named: it is an iterator but includes lots of functionality
    // beyond that interface, most importantly for us a range over this string that can be manipulated in terms of
    // characters
    final range = text.characters.iterator;
    // Expand the range so it reaches from the start of the string to the initial text offset. The text offset is passed
    // to us in terms of code units but the iterator deals in grapheme clusters, so we need to manually count the length
    // of each cluster until we reach the desired offset
    var remainingOffset = textOffset;
    range.expandWhile((char) {
      remainingOffset -= char.length;
      return remainingOffset >= 0;
    });
    final moveWhile = upstream ? range.dropBackWhile : range.expandWhile;
    // Adjust the range in the requested direction as long it does not end in a word. This accounts for cases where the
    // text offset starts in between words. After this we know the range ends on a word character
    moveWhile((char) => char != " ");
    // Adjust the range in the requested direction until it reaches a non-word character. After this we know that the
    // range ends at the start of the next word upstream or end of the next word downstream from the initial text offset
    moveWhile((char) => char != " ");
    // The range now reaches from the start of the string to our new text offset. Calculate that offset using the
    // range's string length and return it
    return range.current.length;
  }

  /// Update or remove the link attributions if edits happen at the middle of a link.
  void _tryUpdateLinkAttribution(RequestDispatcher requestDispatcher, Document document,
      MutableDocumentComposer composer, List<EditEvent> changeList) {
    if (!const [LinkUpdatePolicy.remove, LinkUpdatePolicy.update].contains(updatePolicy)) {
      // We are configured to NOT change the attributions. Fizzle.
      return;
    }

    if (changeList.isEmpty) {
      // There aren't any changes, therefore no URL was changed, therefore we don't
      // need to update a URL. Fizzle.
      return;
    }

    late NodeChangeEvent insertionOrDeletionEvent;
    if (changeList.length == 1) {
      final editEvent = changeList.last;
      if (editEvent is! DocumentEdit || editEvent.change is! TextDeletedEvent) {
        // There's only a single event in the change list, and it's not a deletion
        // event. The only situation where a URL would change with a single
        // event is a deletion event. Therefore, we don't need to change a URL.
        // Fizzle.
        return;
      }

      insertionOrDeletionEvent = editEvent.change as NodeChangeEvent;
    } else {
      final lastSelectionEventIndex = changeList.lastIndexWhere((change) => change is SelectionChangeEvent);
      if (lastSelectionEventIndex < 1) {
        // There's no selection change event. We expect a URL change
        // to consist of an insertion or a deletion followed by a selection
        // change. This event list doesn't fit the pattern. Fizzle.
        return;
      }

      final edit = changeList[lastSelectionEventIndex - 1];
      if (edit is! DocumentEdit || //
          (edit.change is! TextInsertionEvent && edit.change is! TextDeletedEvent)) {
        // The event before the selection change isn't an insertion or deletion. We
        // expect a URL change to consist of an insertion or a deletion followed by
        // a selection change. This event list doesn't fit the pattern. Fizzle.
        return;
      }

      insertionOrDeletionEvent = edit.change as NodeChangeEvent;
    }

    // The change list includes an insertion or deletion followed by a selection
    // change, therefore a URL may have changed. Look for a URL around the
    // altered text.

    final changedNodeId = insertionOrDeletionEvent.nodeId;
    final changedNodeText = (document.getNodeById(changedNodeId) as TextNode).text;

    AttributionSpan? upstreamLinkAttribution;
    AttributionSpan? downstreamLinkAttribution;

    final insertionOrDeletionOffset = insertionOrDeletionEvent is TextInsertionEvent
        ? insertionOrDeletionEvent.offset
        : (insertionOrDeletionEvent as TextDeletedEvent).offset;
    if (insertionOrDeletionOffset > 0) {
      // Check if the upstream character has a link attribution.
      upstreamLinkAttribution = changedNodeText
          .getAttributionSpansInRange(
            attributionFilter: (attribution) => attribution is LinkAttribution,
            range: SpanRange(insertionOrDeletionOffset - 1, insertionOrDeletionOffset - 1),
          )
          .firstOrNull;
    }

    if ((insertionOrDeletionEvent is TextInsertionEvent && insertionOrDeletionOffset < changedNodeText.length - 1) ||
        (insertionOrDeletionEvent is TextDeletedEvent && insertionOrDeletionOffset < changedNodeText.length)) {
      // Check if the downstream character has a link attribution.
      final downstreamOffset = insertionOrDeletionEvent is TextInsertionEvent //
          ? insertionOrDeletionOffset + 1
          : insertionOrDeletionOffset;
      downstreamLinkAttribution = changedNodeText
          .getAttributionSpansInRange(
            attributionFilter: (attribution) => attribution is LinkAttribution,
            range: SpanRange(downstreamOffset, downstreamOffset),
          )
          .firstOrNull;
    }

    if (upstreamLinkAttribution == null && downstreamLinkAttribution == null) {
      // There isn't a link around the changed offset. Fizzle.
      return;
    }

    // We only want to update a URL if a change happened within an existing URL,
    // not at the edges. Determine whether this change reflects an insertion or
    // deletion within an existing URL by looking for identical link attributions
    // both upstream and downstream from the edited text offset.
    final isAtMiddleOfLink = upstreamLinkAttribution != null &&
        downstreamLinkAttribution != null &&
        upstreamLinkAttribution.attribution == downstreamLinkAttribution.attribution;

    if (!isAtMiddleOfLink && insertionOrDeletionEvent is TextInsertionEvent) {
      // An insertion happened at an edge of the link.
      // Insertion only updates the attribution when happening at the middle of a link. Fizzle.
      return;
    }

    final rangeToUpdate = isAtMiddleOfLink //
        ? SpanRange(upstreamLinkAttribution.start, downstreamLinkAttribution.end)
        : (upstreamLinkAttribution ?? downstreamLinkAttribution!).range;

    // Remove the existing link attributions.
    final attributionsToRemove = changedNodeText.getAttributionSpansInRange(
      attributionFilter: (attr) => attr is LinkAttribution,
      range: rangeToUpdate,
    );

    final changeNodePath = document.getPathByNodeId(changedNodeId)!;
    final linkRange = DocumentRange(
      start: DocumentPosition(
        documentPath: changeNodePath,
        nodePosition: TextNodePosition(offset: rangeToUpdate.start),
      ),
      end: DocumentPosition(
        documentPath: changeNodePath,
        nodePosition: TextNodePosition(offset: rangeToUpdate.end + 1),
      ),
    );

    final linkChangeRequests = <EditRequest>[
      RemoveTextAttributionsRequest(
        documentRange: linkRange,
        attributions: {attributionsToRemove.first.attribution},
      ),
    ];

    // A URL was changed and we have now removed the original link. Removing
    // the original link was a necessary step for both `LinkUpdatePolicy.remove`
    // and for `LinkUpdatePolicy.update`.
    //
    // If the policy is `LinkUpdatePolicy.update` then we need to add a new
    // link attribution that reflects the edited URL text. We do that below.
    if (updatePolicy == LinkUpdatePolicy.update) {
      final existingLinkAttribution =
          changedNodeText.getAllAttributionsAt(rangeToUpdate.start).whereType<LinkAttribution>().firstOrNull;
      assert(
        existingLinkAttribution != null,
        "Tried to update a LinkAttribution after the user added/deleted character, but we couldn't find the LinkAttribution. We searched at offset ${rangeToUpdate.start} in '${changedNodeText.toPlainText()}'",
      );

      // We expect the link attribution to be non-null, but we can't know for
      // sure until runtime. So only attempt an attribution update if we found
      // the attribution.
      if (existingLinkAttribution != null) {
        final newLinkText = changedNodeText.toPlainText().substring(rangeToUpdate.start, rangeToUpdate.end + 1);
        final newLinkUri = Uri.tryParse(newLinkText);
        final newScheme = newLinkUri?.scheme;

        late final LinkAttribution updatedAttribution;
        if (newLinkUri != null && newScheme != null && newScheme.isNotEmpty) {
          // The text includes a scheme - use that scheme.
          updatedAttribution = LinkAttribution.fromUri(newLinkUri);
        } else {
          // The text doesn't include a scheme.
          if (existingLinkAttribution.hasStructuredUri && existingLinkAttribution.uri!.scheme.isNotEmpty) {
            // The existing link attribution has a structured URI, and that URI has a scheme.
            // Retain the existing scheme.
            final scheme = existingLinkAttribution.uri!.scheme;
            updatedAttribution = LinkAttribution.fromUri(Uri.parse("$scheme://$newLinkText"));
          } else {
            // The existing link attribution doesn't have a structure URI,
            // so we can't ask what scheme to use. Use the literal text as
            // the full URL because that's the best we can do. It might even
            // be an invalid URL or URI.
            updatedAttribution = LinkAttribution(newLinkText);
          }
        }

        linkChangeRequests.add(
          // Switch out the old link attribution for the new one.
          AddTextAttributionsRequest(
            documentRange: linkRange,
            attributions: {
              updatedAttribution,
            },
          ),
        );
      }
    }

    linkChangeRequests.add(
      // When the caret is in the middle of a link then the composer will automatically
      // apply that style to the next character. Remove the current link style
      // from the composer's preferences, so that as the user types, he doesn't
      // immediately add the link attribution we just deleted.
      RemoveComposerPreferenceStylesRequest(
        attributionsToRemove.map((span) => span.attribution).toSet(),
      ),
    );

    requestDispatcher.execute(linkChangeRequests);
  }
}

/// Parses the [text] as [Uri], prepending "https://" if it doesn't start
/// with "http://" or "https://".
// TODO: Make this private again. It was private, but we have some split linkification between the reaction
//       and the paste behavior in common_editor_operations. Once we create a way for reactions to identify
//       paste behaviors, move the paste linkification into the linkify reaction and make this private again.
Uri? tryToParseUrl(String word) {
  // First, try extracting emails.
  final extractedEmails = linkify(
    word,
    options: const LinkifyOptions(
      humanize: false,
      looseUrl: true,
    ),
    linkifiers: [
      const EmailLinkifier(),
    ],
  );
  final int emailCount = extractedEmails.fold(0, (value, element) => element is EmailElement ? value + 1 : value);
  if (emailCount == 1) {
    // Found exactly one email. Create and return a link attribution.
    final emailElement = extractedEmails.first as EmailElement;
    return Uri(
      scheme: "mailto",
      path: emailElement.emailAddress,
    );
  }

  // Second, try extracting HTTP URLs.
  final extractedLinks = linkify(
    word,
    options: const LinkifyOptions(
      humanize: false,
      looseUrl: true,
    ),
    linkifiers: [
      const UrlLinkifier(),
    ],
  );
  final int linkCount = extractedLinks.fold(0, (value, element) => element is UrlElement ? value + 1 : value);
  if (linkCount == 1) {
    // Found exactly 1 URL. Create and return an attribution.
    try {
      // Try to parse the word as a link.
      final uri = Uri.parse(word);
      if (uri.hasScheme) {
        // URL is fully specified. Return it.
        return uri;
      }

      // The URL is missing a scheme. Add "https:" and re-parse.
      return Uri.parse("https://$word");
    } catch (exception) {
      // Something went wrong parsing the link. Fizzle.
      return null;
    }
  }

  // Third, try directly parsing a non-http URL.
  if (word.contains("://")) {
    return Uri.tryParse(word);
  }

  // Didn't find a URL in the given text.
  return null;
}

/// Configuration for the action that should happen when a text containing
/// a link attribution is modified, e.g., "google.com" becomes "gogle.com".
enum LinkUpdatePolicy {
  /// When a linkified URL has characters added or deleted, the link remains the same.
  preserve,

  /// When a linkified URL has characters added or removed, the link is updated to reflect the new URL value.
  update,

  /// When a linkified URL has characters added or removed, the link is completely removed.
  remove,
}

/// An [EditReaction] which converts two dashes (--) to an em-dash (—).
///
/// This reaction only applies when the user enters a dash (-) after
/// another dash in the same node. The upstream dash and the newly inserted
/// dash are removed and an em-dash (—) is inserted.
///
/// This reaction applies to all [TextNode]s in the document.
class DashConversionReaction extends EditReaction {
  const DashConversionReaction();

  @override
  void react(EditContext editorContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    final document = editorContext.document;
    final composer = editorContext.find<MutableDocumentComposer>(Editor.composerKey);

    if (changeList.length < 2) {
      // This reaction requires at least an insertion event and a selection change event.
      // There are less than two events in the the change list, therefore this reaction
      // shouldn't apply. Fizzle.
      return;
    }

    TextInsertionEvent? dashInsertionEvent;
    for (final event in changeList) {
      if (event is! DocumentEdit) {
        continue;
      }

      final change = event.change;
      if (change is! TextInsertionEvent) {
        continue;
      }
      if (change.text.toPlainText() != "-") {
        continue;
      }

      dashInsertionEvent = change;
      break;
    }
    if (dashInsertionEvent == null) {
      // The user didn't type a dash.
      return;
    }

    if (dashInsertionEvent.offset == 0) {
      // There's nothing upstream from this dash, therefore it can't
      // be a 2nd dash.
      return;
    }

    final insertionNode = document.getNodeById(dashInsertionEvent.nodeId) as TextNode;
    final upstreamCharacter = insertionNode.text.toPlainText()[dashInsertionEvent.offset - 1];
    if (upstreamCharacter != '-') {
      return;
    }

    // A dash was inserted after another dash.
    // Convert the two dashes to an em-dash.
    final insertionNodePath = document.getPathByNodeId(insertionNode.id)!;
    requestDispatcher.execute([
      DeleteContentRequest(
        documentRange: DocumentRange(
          start: DocumentPosition(
            documentPath: insertionNodePath,
            nodePosition: TextNodePosition(offset: dashInsertionEvent.offset - 1),
          ),
          end: DocumentPosition(
            documentPath: insertionNodePath,
            nodePosition: TextNodePosition(offset: dashInsertionEvent.offset + 1),
          ),
        ),
      ),
      InsertTextRequest(
        documentPosition: DocumentPosition(
          documentPath: insertionNodePath,
          nodePosition: TextNodePosition(
            offset: dashInsertionEvent.offset - 1,
          ),
        ),
        textToInsert: SpecialCharacters.emDash,
        attributions: composer.preferences.currentAttributions,
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: insertionNodePath,
            nodePosition: TextNodePosition(offset: dashInsertionEvent.offset),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.contentChange,
      ),
    ]);
  }
}

class EditInspector {
  /// Returns `true` if the given [edits] end with the user typing a space anywhere
  /// within a [TextNode], e.g., typing a " " between two words in a paragraph.
  static bool didTypeSpace(Document document, List<EditEvent> edits) {
    if (edits.length < 2) {
      // This reaction requires at least an insertion event and a selection change event.
      // There are less than two events in the the change list, therefore this reaction
      // shouldn't apply. Fizzle.
      return false;
    }

    // If the user typed a space, then the final document edit should be a text
    // insertion event with a space " ".
    DocumentEdit? lastDocumentEditEvent;
    SelectionChangeEvent? lastSelectionChangeEvent;
    for (int i = edits.length - 1; i >= 0; i -= 1) {
      if (edits[i] is DocumentEdit) {
        lastDocumentEditEvent = edits[i] as DocumentEdit;
      } else if (lastSelectionChangeEvent == null && edits[i] is SelectionChangeEvent) {
        lastSelectionChangeEvent = edits[i] as SelectionChangeEvent;
      }

      if (lastDocumentEditEvent != null) {
        break;
      }
    }
    if (lastDocumentEditEvent == null) {
      return false;
    }
    if (lastSelectionChangeEvent == null) {
      return false;
    }

    final textInsertionEvent = lastDocumentEditEvent.change;
    if (textInsertionEvent is! TextInsertionEvent) {
      return false;
    }
    if (textInsertionEvent.text.toPlainText() != " ") {
      return false;
    }

    if (lastSelectionChangeEvent.newSelection!.extent.nodeId != textInsertionEvent.nodeId) {
      return false;
    }

    final editedNode = document.getNodeById(textInsertionEvent.nodeId)!;
    if (editedNode is! TextNode) {
      return false;
    }

    // The inserted text was a space. We assume this means that the user just typed a space.
    return true;
  }

  /// Finds and returns the last text the user typed within the given [edit]s, or `null` if
  /// no text was typed.
  static UserTypedText? findLastTextUserTyped(Document document, List<EditEvent> edits) {
    final lastSpaceInsertion = edits.whereType<DocumentEdit>().lastWhereOrNull((edit) =>
        edit.change is TextInsertionEvent && (edit.change as TextInsertionEvent).text.toPlainText().endsWith(" "));
    if (lastSpaceInsertion == null) {
      // The user didn't insert any text segment that ended with a space.
      return null;
    }

    final spaceInsertionChangeIndex = edits.indexWhere((edit) => edit == lastSpaceInsertion);
    final selectionAfterInsertionIndex =
        edits.indexWhere((edit) => edit is SelectionChangeEvent, spaceInsertionChangeIndex);
    if (selectionAfterInsertionIndex < 0) {
      // The text insertion wasn't followed by a selection change. It's not clear what this
      // means, but we can't say with confidence that the user typed the space. Perhaps the
      // space was injected by some other means.
      return null;
    }

    final newSelection = (edits[selectionAfterInsertionIndex] as SelectionChangeEvent).newSelection;
    if (newSelection == null) {
      // There's no selection, which indicates something other than the user typing.
      return null;
    }
    if (!newSelection.isCollapsed) {
      // The selection is expanded, which indicates something other than the user typing.
      return null;
    }

    final textInsertionEvent = lastSpaceInsertion.change as TextInsertionEvent;
    if (textInsertionEvent.nodeId != newSelection.extent.nodeId) {
      // The selection is in a different node than where tex was inserted. This indicates
      // something other than a user typing.
      return null;
    }

    final newCaretOffset = (newSelection.extent.nodePosition as TextNodePosition).offset;
    if (textInsertionEvent.offset + textInsertionEvent.text.length != newCaretOffset) {
      return null;
    }

    return UserTypedText(
      textInsertionEvent.nodeId,
      textInsertionEvent.offset,
      textInsertionEvent.text,
    );
  }

  EditInspector._();
}

class UserTypedText {
  const UserTypedText(this.nodeId, this.offset, this.text);

  final String nodeId;
  final int offset;
  final AttributedText text;
}
