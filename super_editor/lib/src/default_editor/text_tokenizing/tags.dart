import 'dart:math';

import 'package:attributed_text/attributed_text.dart';
import 'package:characters/characters.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/default_editor/text.dart';

/// A set of tools for finding tags within document text.
class TagFinder {
  /// Finds a tag that touches the given [expansionPosition] and returns that tag,
  /// indexed within the document, along with the [expansionPosition].
  static TagAroundPosition? findTagAroundPosition({
    required TagRule tagRule,
    required String nodeId,
    required AttributedText text,
    required TextNodePosition expansionPosition,
    required bool Function(Set<Attribution> tokenAttributions) isTokenCandidate,
  }) {
    final rawText = text.toPlainText();
    if (rawText.isEmpty) {
      return null;
    }

    int splitIndex = min(expansionPosition.offset, rawText.length);
    splitIndex = max(splitIndex, 0);

    // Create 2 splits of characters to navigate upstream and downstream the caret position.
    // ex: "this is a very|long string"
    // -> split around the caret into charactersBefore="this is a very" and charactersAfter="long string"
    final charactersBefore = rawText.substring(0, splitIndex).characters;
    final iteratorUpstream = charactersBefore.iteratorAtEnd;

    final charactersAfter = rawText.substring(splitIndex).characters;
    final iteratorDownstream = charactersAfter.iterator;

    if (charactersBefore.isNotEmpty && tagRule.excludedCharacters.contains(charactersBefore.last)) {
      // The character where we're supposed to begin our expansion is a
      // character that's not allowed in a tag. Therefore, no tag exists
      // around the search offset.
      return null;
    }

    // Move upstream until we find the trigger character or an excluded character.
    while (iteratorUpstream.moveBack()) {
      final currentCharacter = iteratorUpstream.current;
      if (tagRule.excludedCharacters.contains(currentCharacter)) {
        // The upstream character isn't allowed to appear in a tag. end the search.
        return null;
      }

      if (currentCharacter == tagRule.trigger) {
        // The character we are reading is the trigger.
        // We move the iteratorUpstream one last time to include the trigger in the tokenRange and stop looking any further upstream
        iteratorUpstream.moveBack();
        break;
      }
    }

    // Move downstream the caret position until we find excluded character or reach the end of the text.
    while (iteratorDownstream.moveNext()) {
      final current = iteratorDownstream.current;
      if (tagRule.excludedCharacters.contains(current)) {
        break;
      }
    }

    final tokenStartOffset = splitIndex - iteratorUpstream.stringAfterLength;
    final tokenRange = SpanRange(tokenStartOffset, splitIndex + iteratorDownstream.stringBeforeLength);

    final tagText = text.substringInRange(tokenRange);
    if (!tagText.startsWith(tagRule.trigger)) {
      return null;
    }

    final tokenAttributions = text.getAttributionSpansInRange(attributionFilter: (a) => true, range: tokenRange);
    if (!isTokenCandidate(tokenAttributions.map((span) => span.attribution).toSet())) {
      return null;
    }

    return TagAroundPosition(
      indexedTag: IndexedTag(
        Tag(tagRule.trigger, tagText.substring(1)),
        nodeId,
        tokenStartOffset,
      ),
      searchOffset: expansionPosition.offset,
    );
  }

  /// Finds and returns all tags in the given [textNode], which meet the given [rule].
  static Set<IndexedTag> findAllTagsInTextNode(TextNode textNode, TagRule rule) {
    final plainText = textNode.text.toPlainText();
    final tags = <IndexedTag>{};

    int characterIndex = 0;
    int? tagStartIndex;
    late StringBuffer tagBuffer;
    for (final character in plainText.characters) {
      if (character == rule.trigger) {
        if (tagStartIndex != null) {
          // We found a trigger, but we're still accumulating a tag from an earlier
          // trigger. End the tag we were accumulating.
          tags.add(IndexedTag(
            Tag.fromRaw(tagBuffer.toString()),
            textNode.id,
            tagStartIndex,
          ));
        }

        // Start accumulating a new tag, because we hit a trigger character.
        tagStartIndex = characterIndex;
        tagBuffer = StringBuffer();
      }

      if (tagStartIndex != null && rule.excludedCharacters.contains(character)) {
        // We're accumulating a tag and we hit a character that isn't allowed to
        // appear in a tag. End the tag we were accumulating.
        tags.add(IndexedTag(
          Tag.fromRaw(tagBuffer.toString()),
          textNode.id,
          tagStartIndex,
        ));

        tagStartIndex = null;
      } else if (tagStartIndex != null) {
        // We're accumulating a tag. Add this character to the tag.
        tagBuffer.write(character);
      }

      characterIndex += 1;
    }

    if (tagStartIndex != null) {
      // We were assembling a tag and it went to the end of the text. End the tag.
      tags.add(IndexedTag(
        Tag.fromRaw(tagBuffer.toString()),
        textNode.id,
        tagStartIndex,
      ));
    }

    return tags;
  }

  const TagFinder._();
}

/// An [IndexedTag], along with a text position about which the tag was found.
///
/// This data structure is useful for inspecting active typing into a token.
class TagAroundPosition {
  const TagAroundPosition({
    required this.indexedTag,
    required this.searchOffset,
  });

  /// The [IndexedTag] that surrounds the caret.
  final IndexedTag indexedTag;

  /// The text offset of the tag search position, from the start of the [TextNode] that
  /// contains the [indexedTag].
  final int searchOffset;

  /// The text offset of the tag search position from the start of the [indexedTag].
  int get searchOffsetInToken => searchOffset - indexedTag.startOffset;

  @override
  String toString() => "[TagAroundPosition] - indexedTag: '$indexedTag', search offset in tag: $searchOffsetInToken";

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagAroundPosition &&
          runtimeType == other.runtimeType &&
          indexedTag == other.indexedTag &&
          searchOffset == other.searchOffset;

  @override
  int get hashCode => indexedTag.hashCode ^ searchOffset.hashCode;
}

/// A rule for matching a text token to a tag.
///
/// A tag begins with a [trigger] character, and is then followed by one or more
/// non-whitespace characters, except for [excludedCharacters].
class TagRule {
  const TagRule({
    required this.trigger,
    this.excludedCharacters = const {},
  }) : assert(trigger.length == 1, "Trigger must be exactly one character long");

  final String trigger;
  final Set<String> excludedCharacters;

  /// Returns `true` if the entire [candidate] complies with this [TagRule].
  ///
  /// For example, assume "#" is the trigger and that "." is an excluded character.
  ///
  ///     "#flutter" returns `true`.
  ///
  ///     "#flut.ter" returns `false`.
  ///
  ///     "flutter" returns `false`.
  ///
  bool isTag(String candidate) {
    if (!candidate.startsWith(trigger)) {
      return false;
    }

    for (final excludedCharacter in excludedCharacters) {
      if (candidate.contains(excludedCharacter)) {
        return false;
      }
    }

    return true;
  }

  /// Extracts and returns a compliant tag from the beginning of the given [candidate], or `null` if
  /// the [candidate] doesn't begin with a compliant tag.
  ///
  ///     "#flutter" -> "#flutter"
  ///     "#flut.ter" -> "#flut"
  ///     "#flutter dash" -> "#flutter"
  ///     "#.flutter" -> `null`
  ///     "flutter" -> `null`
  ///
  String? findTagAtBeginning(String candidate) {
    if (!candidate.startsWith(trigger)) {
      return null;
    }

    final buffer = StringBuffer(trigger);
    for (final character in candidate.characters.toList().sublist(1)) {
      if (excludedCharacters.contains(character)) {
        break;
      }

      buffer.write(character);
    }

    if (buffer.length == 1) {
      // We didn't find any non-excluded characters after the trigger.
      return null;
    }

    return buffer.toString();
  }
}

/// A [Tag] and its position within a [Document].
///
/// A tag is a segment of text, which usually fits some kind of pattern, such "#flutter", which begins
/// with a "#" and is followed by some number of non-whitespace characters.
///
/// A tag may be attributed, but there's no requirement that the [tag] in a [IndexedTag] have any
/// particular attributions applied to it. Moreover, if an attribution is applied, it's possible
/// that the attribution is currently out of sync with the tag text bounds. It's the client's
/// responsibility to monitor the attribution bounds and keep them in sync with the content.
/// The [IndexedTag] data structure is a tool that makes such management easier.
class IndexedTag {
  IndexedTag(
    this.tag,
    String? nodeId,
    this.startOffset, {
    NodePath? nodePath,
  })  : assert(nodeId != null || nodePath != null, "You must provide a nodeId or a nodePath"),
        assert(nodeId == null || nodePath == null, "You can provide a nodeId or a nodePath, but not both"),
        nodeId = nodeId ?? nodePath!.targetNodeId,
        nodePath = nodePath ?? NodePath.forNode(nodeId!);

  /// The plain-text tag value.
  final Tag tag;

  /// The node ID of the [TextNode] that contains this tag.
  final String nodeId;

  /// The path in the `Document` from the root to the node that contains this tag.
  final NodePath nodePath;

  /// The text offset of the trigger symbol for this tag within the given [TextNode].
  final int startOffset;

  /// The fully-specified [DocumentPosition] associated with the tag's [startOffset].
  DocumentPosition get start =>
      DocumentPosition(documentPath: nodePath, nodePosition: TextNodePosition(offset: startOffset));

  /// The text offset immediately after the final character in this tag, within the given [TextNode].
  int get endOffset => startOffset + tag.raw.length;

  /// The fully-specified [DocumentPosition] associated with the tag's [endOffset].
  DocumentPosition get end =>
      DocumentPosition(documentPath: nodePath, nodePosition: TextNodePosition(offset: endOffset));

  /// The [DocumentRange] from [start] to [end].
  DocumentRange get range => DocumentRange(start: start, end: end);

  /// The length of the [tag]'s text.
  int get length => tag.raw.length;

  /// Collects and returns all attributions in this tag's [TextNode], between the
  /// [start] of the tag and the [end] of the tag.
  AttributedSpans computeTagSpans(Document document) =>
      (document.getNodeById(nodeId) as TextNode).text.copyText(startOffset, endOffset - 1).spans;

  /// Assuming that this tag begins with the given [attribution], this method returns
  /// the [SpanRange] for the given [attribution], beginning at the [start] of this tag.
  ///
  /// This is useful to determine whether a tag attribution fully spans the tag.
  SpanRange computeLeadingSpanForAttribution(Document document, Attribution attribution) {
    final text = (document.getNodeById(nodeId) as TextNode).text;
    if (!text.hasAttributionAt(startOffset, attribution: attribution)) {
      return SpanRange.empty;
    }

    return text.getAttributedRange({attribution}, startOffset);
  }

  @override
  String toString() => "[IndexedToken] - '${tag.raw}', $startOffset -> $endOffset, node: $nodeId";

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndexedTag &&
          runtimeType == other.runtimeType &&
          tag == other.tag &&
          nodeId == other.nodeId &&
          startOffset == other.startOffset &&
          endOffset == other.endOffset;

  @override
  int get hashCode => tag.hashCode ^ nodeId.hashCode ^ startOffset.hashCode ^ endOffset.hashCode;
}

/// A text tag, e.g., "@dash", "#flutter".
class Tag {
  factory Tag.fromRaw(String tag) => Tag(tag[0], tag.substring(1));

  const Tag(this.trigger, this.token);

  /// The character that triggered the tag, e.g., "@".
  final String trigger;

  /// The token within the tag, e.g., returns "dash" from the tag "@dash"
  final String token;

  /// The full trigger + token, e.g., "@dash".
  String get raw => "$trigger$token";

  @override
  String toString() => "[Tag] - '$raw'";

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tag && runtimeType == other.runtimeType && trigger == other.trigger && token == other.token;

  @override
  int get hashCode => trigger.hashCode ^ token.hashCode;
}
