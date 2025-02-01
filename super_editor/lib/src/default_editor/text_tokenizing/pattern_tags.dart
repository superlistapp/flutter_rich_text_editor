import 'package:attributed_text/attributed_text.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/default_editor/super_editor.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/default_editor/text_tokenizing/tags.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';

/// A [SuperEditorPlugin] that finds and attributes tags, based on patterns, in a document.
///
/// A pattern tag is a text token that begins with a trigger character, such as "#", and
/// is followed by characters that fit a given pattern. That pattern might be as simple as
/// "any character that isn't a space".
///
/// A [PatternTagPlugin] finds and attributes tags as the user types them into an [Editor].
/// Clients that wish to react to changes to pattern tags can use the [tagIndex] to query
/// existing tags.
///
/// To add pattern tag behaviors to a [SuperEditor] widget, provide a [PatternTagPlugin] in
/// the `plugins` property.
///
///   SuperEditor(
///     //...
///     plugins: {
///       patternTagPlugin,
///     },
///   );
///
/// To add pattern tag behaviors directly to an [Editor], without involving a [SuperEditor]
/// widget, call [attach] with the given [Editor]. When that [Editor] is no longer needed,
/// call [detach] to clean up all plugin references.
///
///   patternTagPlugin.attach(editor);
///
///
class PatternTagPlugin extends SuperEditorPlugin {
  /// The key used to access the [PatternTagIndex] in an attached [Editor].
  static const patternTagIndexKey = "patternTagIndex";

  PatternTagPlugin({
    TagRule tagRule = hashTagRule,
  })  : _tagRule = tagRule,
        tagIndex = PatternTagIndex() {
    _patternTagReaction = PatternTagReaction(
      tagRule: _tagRule,
    );
  }

  /// The rule for what this plugin considers to be a tag.
  final TagRule _tagRule;

  /// Index of all pattern tags in the document.
  final PatternTagIndex tagIndex;

  /// An [EditReaction] that finds and attributes all pattern tags.
  late EditReaction _patternTagReaction;

  @override
  void attach(Editor editor) {
    editor
      ..context.put(patternTagIndexKey, tagIndex)
      ..reactionPipeline.insert(0, _patternTagReaction);

    _initializePatternTagIndex(editor);
  }

  void _initializePatternTagIndex(Editor editor) {
    final document = editor.context.document;

    for (final node in document) {
      if (node is! TextNode) {
        continue;
      }

      final tagSpans = node.text.getAttributionSpansInRange(
        attributionFilter: (a) => a is PatternTagAttribution,
        range: SpanRange(0, node.text.length - 1),
      );

      final tags = <IndexedTag>{};
      for (final tagSpan in tagSpans) {
        IndexedTag(
          Tag.fromRaw(node.text.substring(tagSpan.start, tagSpan.end + 1)),
          node.id,
          tagSpan.start,
        );
      }
      tagIndex._setTagsInNode(node.id, tags);
    }
  }

  @override
  void detach(Editor editor) {
    editor
      ..context.remove(patternTagIndexKey)
      ..reactionPipeline.remove(_patternTagReaction);
  }
}

/// Default [TagRule] for hash tags.
///
/// Any rule can be used for pattern tags. This rule is provided as a convenience
/// due to the popularity of hash tags.
const hashTagRule = TagRule(trigger: "#", excludedCharacters: {" ", "."});

extension PatternTagIndexEditable on EditContext {
  /// Returns the [PatternTagIndex] that the [PatternTagPlugin] added to the attached [Editor].
  ///
  /// This accessor is provided as a convenience so that clients don't need to call `find()`
  /// on the [EditContext].
  PatternTagIndex get patternTagIndex => find<PatternTagIndex>(PatternTagPlugin.patternTagIndexKey);
}

/// Collects references to all pattern tags in a document for easy querying.
class PatternTagIndex with ChangeNotifier implements Editable {
  final _tags = <String, Set<IndexedTag>>{};

  Set<IndexedTag> getTagsInTextNode(String nodeId) => _tags[nodeId] ?? {};

  Set<IndexedTag> getAllTags() {
    final tags = <IndexedTag>{};
    for (final value in _tags.values) {
      tags.addAll(value);
    }
    return tags;
  }

  void _setTagsInNode(String nodeId, Set<IndexedTag> tags) {
    if (const DeepCollectionEquality().equals(_tags[nodeId], tags)) {
      return;
    }

    _tags[nodeId] ??= <IndexedTag>{};
    _tags[nodeId]!.addAll(tags);
    _onChange();
  }

  void _clearNode(String nodeId) {
    if (_tags[nodeId] == null || _tags[nodeId]!.isEmpty) {
      return;
    }

    _tags[nodeId]?.clear();
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
    _tags.clear();
  }
}

/// An [EditReaction] that creates, updates, and removes pattern tags.
///
/// A pattern tag is a token that begins with a trigger, such as "#", and is
/// followed by one or more characters. A pattern tag is terminated by a violating
/// character given the tag rule, the end of a text block, or another trigger ("#").
///
/// Examples of pattern tags, using the hash tag rule:
///
///     #flutter
///     #flutter #dart    (2 tags)
///     #flutter#dart     (2 tags)
///     I love #flutter.  (the period is excluded from the hash tag)
///
/// Examples of strings that aren't pattern tags, using the hash tag rule:
///
///     #
///     #.
///     ##
///
class PatternTagReaction extends EditReaction {
  PatternTagReaction({
    TagRule tagRule = hashTagRule,
  }) : _tagRule = tagRule;

  final TagRule _tagRule;

  @override
  void react(EditContext editContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    if (changeList.whereType<DocumentEdit>().isEmpty) {
      // If there are no document edits then there can't possibly be a change to
      // hash tags. This is a quick escape to avoid unnecessary logging and inspections.
      return;
    }

    editorPatternTagsLog.info("Reacting to possible hash tagging");
    editorPatternTagsLog.info("Incoming change list:");
    editorPatternTagsLog.info(changeList.map((event) => event.runtimeType).toList());
    editorPatternTagsLog.info(
        "Caret position: ${editContext.find<MutableDocumentComposer>(Editor.composerKey).selection?.extent.nodePosition}");

    _adjustTagAttributionsAroundAlteredTags(editContext, requestDispatcher, changeList);

    _findAndCreateNewTags(editContext, requestDispatcher, changeList);

    _splitBackToBackTags(editContext, requestDispatcher, changeList);

    _removeInvalidTags(editContext, requestDispatcher, changeList);

    _updateTagIndex(editContext, changeList);
  }

  /// Finds a pattern tag near the caret and adjusts the attribution bounds so that the
  /// tag content remains attributed.
  ///
  /// Examples:
  ///
  ///  - |#das|h      ->  |#dash|
  ///  - |#dash and|  ->  |#dash| and
  ///
  void _adjustTagAttributionsAroundAlteredTags(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
  ) {
    final document = editContext.document;

    final tag = _findTagAtCaret(editContext, (attributions) => attributions.contains(const PatternTagAttribution()));
    if (tag == null) {
      return;
    }

    final tagRange = SpanRange(tag.indexedTag.startOffset, tag.indexedTag.endOffset);
    final hasTagAttributionThroughout =
        tag.indexedTag.computeLeadingSpanForAttribution(document, const PatternTagAttribution()) == tagRange;
    if (hasTagAttributionThroughout) {
      // The tag is already fully attributed. No need to do anything.
      return;
    }

    // The token is only partially attributed. Expand the attribution around the token.
    requestDispatcher.execute([
      AddTextAttributionsRequest(
        documentRange: DocumentSelection(
          base: tag.indexedTag.start,
          extent: tag.indexedTag.end,
        ),
        attributions: {const PatternTagAttribution()},
      ),
    ]);
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

  /// Find any text near the caret that fits the tag pattern, and surround
  /// it with a hash tag attribution.
  void _findAndCreateNewTags(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
  ) {
    editorPatternTagsLog.fine("Looking for a pattern tag around the caret.");

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
    final selectedNode = document.getNodeById(selectionPosition.nodeId);
    if (selectedNode is! TextNode) {
      // Tagging only happens in the middle of text. The selected content isn't text. Return.
      return;
    }

    final tagAroundCaret = TagFinder.findTagAroundPosition(
      tagRule: _tagRule,
      nodeId: selectedNode.id,
      text: selectedNode.text,
      expansionPosition: caretPosition,
      isTokenCandidate: (tokenAttributions) =>
          !tokenAttributions.any((attribution) => attribution is PatternTagAttribution),
    );
    if (tagAroundCaret == null) {
      // There's no tag around the caret.
      editorPatternTagsLog.fine("There's no tag around the caret, fizzling");
      return;
    }
    if (!tagAroundCaret.indexedTag.tag.raw.startsWith(_tagRule.trigger)) {
      // Tags must start with the trigger, e.g., "#", but the preceding word doesn't. Return.
      editorPatternTagsLog.fine("Token doesn't start with ${_tagRule.trigger}, fizzling");
      return;
    }
    if (tagAroundCaret.indexedTag.tag.raw.length <= 1) {
      // The token only contains the trigger, e.g., "#". We require at least one valid character after
      // the trigger to consider it a hash tag.
      editorPatternTagsLog.fine("Token has no content after ${_tagRule.trigger}, fizzling");
      return;
    }

    editorPatternTagsLog.fine(
        "Found a pattern tag around caret: '${tagAroundCaret.indexedTag.tag}' - surrounding it with an attribution: ${tagAroundCaret.indexedTag.startOffset} -> ${tagAroundCaret.indexedTag.endOffset}");

    final nodePath = document.getPathByNodeId(selectedNode.id)!;
    requestDispatcher.execute([
      // Remove the old pattern tag attribution(s).
      RemoveTextAttributionsRequest(
        documentRange: selectedNode.selectionBetween(
          nodePath,
          tagAroundCaret.indexedTag.startOffset,
          tagAroundCaret.indexedTag.endOffset,
        ),
        attributions: {
          ...selectedNode.text
              .getAllAttributionsAt(tagAroundCaret.indexedTag.startOffset)
              .whereType<PatternTagAttribution>(),
        },
      ),
      // Add the new/updated pattern tag attribution.
      AddTextAttributionsRequest(
        documentRange: selectedNode.selectionBetween(
          nodePath,
          tagAroundCaret.indexedTag.startOffset,
          tagAroundCaret.indexedTag.endOffset,
        ),
        attributions: {
          const PatternTagAttribution(),
        },
      ),
    ]);
  }

  /// Finds any attributed pattern tag that spans multiple pattern tags, and breaks them up.
  ///
  /// For example, it's possible that we've gotten into a situation where two back-to-back
  /// pattern tags are currently attributed as one:
  ///
  ///     [#flutter#dart]
  ///
  /// This method breaks that one attribution into two:
  ///
  ///     [#flutter][#dart]
  ///
  void _splitBackToBackTags(EditContext editContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    final document = editContext.document;

    final textEdits = changeList
        .whereType<DocumentEdit>()
        .where((docEdit) => docEdit.change is NodeChangeEvent)
        .map((docEdit) => docEdit.change as NodeChangeEvent)
        .where((nodeChange) => document.getNodeById(nodeChange.nodeId) != null)
        .toList(growable: false);
    if (textEdits.isEmpty) {
      return;
    }

    editorPatternTagsLog.info("Checking edited text nodes for back-to-back pattern tags that need to be split apart");
    for (final textEdit in textEdits) {
      final nodePath = document.getPathByNodeId(textEdit.nodeId)!;
      final node = document.getNodeById(textEdit.nodeId) as TextNode;
      _splitBackToBackTagsInTextNode(requestDispatcher, nodePath, node);
    }
  }

  void _splitBackToBackTagsInTextNode(RequestDispatcher requestDispatcher, NodePath nodePath, TextNode node) {
    final patternTags = node.text.getAttributionSpansByFilter(
      (attribution) => attribution is PatternTagAttribution,
    );
    if (patternTags.isEmpty) {
      return;
    }

    final spanRemovals = <SpanRange>{};
    final spanCreations = <SpanRange>{};

    editorPatternTagsLog.finer("Found ${patternTags.length} pattern tag attributions in text node '${node.id}'");
    for (final patternTag in patternTags) {
      final tagContent = node.text.substring(patternTag.start, patternTag.end + 1);
      editorPatternTagsLog.finer("Inspecting $tagContent at ${patternTag.start} -> ${patternTag.end}");

      if (tagContent.lastIndexOf(_tagRule.trigger) == 0) {
        // There's only one trigger ("#") in this tag, and it's at the beginning. No need
        // to split the tag.
        editorPatternTagsLog.finer("No need to split this tag. Moving to next one.");
        continue;
      }

      // This tag has multiple triggers ("#") in it. We need to split this tag into multiple
      // pieces.
      editorPatternTagsLog.finer("There are multiple triggers in this tag. Splitting.");

      // Remove the existing attribution, which covers multiple pattern tags.
      spanRemovals.add(patternTag.range);
      editorPatternTagsLog.finer(
          "Removing multi-tag span: ${patternTag.start} -> ${patternTag.end}, '${node.text.substring(patternTag.start, patternTag.end + 1)}'");

      // Add a new attribution for each individual pattern tag.
      int triggerSymbolIndex = tagContent.indexOf(_tagRule.trigger);
      while (triggerSymbolIndex >= 0) {
        final nextTriggerSymbolIndex = tagContent.indexOf(_tagRule.trigger, triggerSymbolIndex + 1);
        final tagEnd = nextTriggerSymbolIndex > 0 ? nextTriggerSymbolIndex - 1 : tagContent.length - 1;

        if (tagEnd - triggerSymbolIndex > 0) {
          // There's a trigger, followed by at least one non-trigger character. Therefore, this
          // is a legitimate pattern tag. Give it an attribution.
          editorPatternTagsLog.finer(
              "Adding a split tag span: ${patternTag.start + triggerSymbolIndex} -> ${patternTag.start + tagEnd}, '${node.text.substring(patternTag.start + triggerSymbolIndex, patternTag.start + tagEnd + 1)}'");
          spanCreations.add(SpanRange(
            patternTag.start + triggerSymbolIndex,
            patternTag.start + tagEnd,
          ));
        }

        triggerSymbolIndex = nextTriggerSymbolIndex;
      }
    }

    if (spanRemovals.isEmpty) {
      // We didn't find any tags to break up. No need to submit change requests.
      return;
    }

    // Execute the attribution removals and additions.
    requestDispatcher.execute([
      // Remove the original multi-tag attribution spans.
      for (final removal in spanRemovals)
        RemoveTextAttributionsRequest(
          documentRange: node.selectionBetween(
            nodePath,
            removal.start,
            removal.end + 1,
          ),
          attributions: {const PatternTagAttribution()},
        ),

      // Add the new, narrowed attribution spans.
      for (final creation in spanCreations)
        AddTextAttributionsRequest(
          documentRange: node.selectionBetween(
            nodePath,
            creation.start,
            creation.end + 1,
          ),
          attributions: {const PatternTagAttribution()},
          autoMerge: false,
        ),
    ]);
  }

  /// Removes pattern tags that have become invalid, e.g., a hash tag that had content but
  /// the content was deleted, and now it's just a dangling "#".
  void _removeInvalidTags(
    EditContext editContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
  ) {
    editorPatternTagsLog.fine("Removing invalid tags.");
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

      // We only care about deleted text when the deleted text contains at least one tag.
      final tagsInDeletedText = change.deletedText.getAttributionSpansByFilter(
        (attribution) => attribution is PatternTagAttribution,
      );
      if (tagsInDeletedText.isEmpty) {
        continue;
      }

      nodesToInspect.add(change.nodeId);
    }
    editorPatternTagsLog.fine("Found ${nodesToInspect.length} impacted nodes with tags that might be invalid");

    // Inspect every TextNode where a text deletion impacted a tag. If a tag no longer contains
    // a trigger, or only contains a trigger, remove the attribution.
    final document = editContext.document;
    final removeTagRequests = <EditRequest>{};
    for (final nodeId in nodesToInspect) {
      final textNodePath = document.getPathByNodeId(nodeId)!;
      final textNode = document.getNodeById(nodeId) as TextNode;
      final allTags = textNode.text.getAttributionSpansInRange(
        attributionFilter: (attribution) => attribution is PatternTagAttribution,
        range: SpanRange(0, textNode.text.length - 1),
      );

      for (final tag in allTags) {
        final tagText = textNode.text.substring(tag.start, tag.end + 1);
        if (!tagText.startsWith(_tagRule.trigger) || tagText == _tagRule.trigger) {
          editorPatternTagsLog.info("Removing tag with value: '$tagText'");
          removeTagRequests.add(
            RemoveTextAttributionsRequest(
              documentRange: textNode.selectionBetween(
                textNodePath,
                tag.start,
                tag.end + 1,
              ),
              attributions: {const PatternTagAttribution()},
            ),
          );
        }
      }
    }

    // Run all the tag attribution removal requests that we queued up.
    for (final request in removeTagRequests) {
      requestDispatcher.execute([request]);
    }
  }

  void _updateTagIndex(EditContext editContext, List<EditEvent> changeList) {
    final document = editContext.document;
    final index = editContext.patternTagIndex;
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
        index._clearNode(change.nodeId);
      } else if (change is NodeInsertedEvent) {
        index._setTagsInNode(
          change.nodeId,
          _findAllTagsInNode(document, change.nodeId),
        );
      } else if (change is NodeChangeEvent) {
        index._clearNode(change.nodeId);
        index._setTagsInNode(
          change.nodeId,
          _findAllTagsInNode(document, change.nodeId),
        );
      }
    }
  }

  Set<IndexedTag> _findAllTagsInNode(Document document, String nodeId) {
    final textNode = document.getNodeById(nodeId) as TextNode;
    final allTags = textNode.text
        .getAttributionSpansInRange(
          attributionFilter: (attribution) => attribution is PatternTagAttribution,
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

/// An attribution for a pattern tag.
class PatternTagAttribution extends NamedAttribution {
  const PatternTagAttribution() : super("patternTag");

  @override
  bool canMergeWith(Attribution other) => other is PatternTagAttribution;

  @override
  String toString() {
    return '[PatternTagAttribution]';
  }
}
