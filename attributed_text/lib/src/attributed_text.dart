import 'package:collection/collection.dart';

import 'attributed_spans.dart';
import 'attribution.dart';
import 'logging.dart';
import 'span_range.dart';

final _log = attributionsLog;

/// Text with attributions applied to desired spans of text.
///
/// An attribution can be any subclass of [Attribution].
///
/// [AttributedText] is a convenient way to store and manipulate
/// text that might have overlapping styles and/or non-style
/// attributions. A common Flutter alternative is [TextSpan], but
/// [TextSpan] does not support overlapping styles, and [TextSpan]
/// is exclusively intended for visual text styles.
// TODO: there is a mixture of mutable and immutable behavior in this class.
//       Pick one or the other, or offer 2 classes: mutable and immutable (#113)
class AttributedText {
  /// The default character that's inserted in place of placeholders when converting
  /// an [AttributedText] to plain text.
  ///
  /// `\uFFFC` is the unicode character for "object replacement" and it looks
  /// like a regular space.
  ///
  /// `\uFFFD` is a similar character - it's the unicode character for replacing
  /// unknown characters, and looks like: �
  static const placeholderCharacter = '\uFFFC';

  /// Constructs an [AttributedText] whose content is comprised by a combination
  /// of [text] and [placeholders], covered by the given attributed [spans].
  ///
  /// [placeholders] is a map from character indices to desired placeholder objects.
  /// The character indices in [placeholders] refer to the final indices when the
  /// placeholders have been combined with the [text].
  ///
  /// Example:
  ///  - Full text: "�Hello � World!�"
  ///  - text: "Hello  World!"
  ///  - placeholders:
  ///    - 0:  MyPlaceholder
  ///    - 7:  MyPlaceholder
  ///    - 15: MyPlaceholder
  ///
  /// Notice in the example above that the final placeholder index is greater
  /// than the total length of the [text] `String`.
  AttributedText([
    String? text,
    AttributedSpans? spans,
    Map<int, Object>? placeholders,
  ])  : _text = text ?? "",
        spans = spans ?? AttributedSpans(),
        placeholders = placeholders ?? <int, Object>{} {
    assert(() {
      // ^ Run this in an assert with a callback so that the validation doesn't run in
      //   production and cost processor cycles.
      _validatePlaceholderIndices();
      return true;
    }());

    if (this.placeholders.isEmpty) {
      // There aren't any placeholders, so text with placeholders is the same as
      // text without placeholders.
      _textWithPlaceholders = _text;
    } else {
      // Create a 2nd plain text representation that includes stand-in characters
      // for placeholders.
      final buffer = StringBuffer();
      int start = 0;
      int insertedPlaceholders = 0;
      for (final entry in this.placeholders.entries) {
        final textSegment = _text.substring(start - insertedPlaceholders, entry.key - insertedPlaceholders);
        buffer.write(textSegment);
        start += textSegment.length;

        buffer.write(placeholderCharacter);
        start += 1;

        insertedPlaceholders += 1;
      }
      if (start - insertedPlaceholders < _text.length) {
        buffer.write(_text.substring(start - insertedPlaceholders, _text.length));
      }

      _textWithPlaceholders = buffer.toString();
    }
  }

  void _validatePlaceholderIndices() {
    // Ensure that none of the placeholders have negative indices.
    assert(
      placeholders.entries.where((entry) => entry.key < 0).isEmpty,
      "All placeholders must have indices >= 0",
    );

    // Ensure that none of the placeholders sit beyond the end of the text and other
    // placeholders.
    int maxAllowableIndex = _text.length;
    for (final entry in placeholders.entries) {
      if (entry.key > maxAllowableIndex) {
        throw AssertionError("Invalid placeholder index. The index is too large. ${entry.key} -> ${entry.value}.");
      }

      maxAllowableIndex += 1;
    }
  }

  void dispose() {
    _listeners.clear();
  }

  /// The text that this [AttributedText] attributes.
  @Deprecated("Use toPlainText() instead, so you can choose whether to include placeholder characters")
  String get text => _text;
  final String _text;

  late final String _textWithPlaceholders;

  /// Returns the character or placeholder at offset zero.
  Object get first => placeholders[0] ?? _textWithPlaceholders[0];

  /// Returns the character or placeholder at the given [offset].
  Object operator [](int offset) => placeholders[offset] ?? _textWithPlaceholders[offset];

  /// Returns the character or placeholder at the end of this `AttributedText`.
  Object get last => placeholders[length - 1] ?? _textWithPlaceholders[length - 1];

  /// Returns a plain-text version of this `AttributedText`.
  ///
  /// Plain text has no attributions or placeholder objects.
  ///
  /// If [includePlaceholders] is `true`, special characters will be inserted
  /// at every text offset where there is currently a placeholder object. By
  /// default, the special character is [placeholderCharacter]. To use a different
  /// character, provide a [replacementCharacter].
  ///
  /// if [includePlaceholders] is `false`, placeholders will be replaced
  /// with nothing. In that case, the returned `String` will be shorter than
  /// [length] with a difference equal to the number of placeholders in
  /// this [AttributedText].
  String toPlainText({
    bool includePlaceholders = true,
    String replacementCharacter = placeholderCharacter,
  }) {
    if (includePlaceholders) {
      if (replacementCharacter != placeholderCharacter) {
        // The caller wants to use a non-standard character to represent
        // placeholders. Do a replace-all and return the result.
        return _textWithPlaceholders.replaceAll(placeholderCharacter, replacementCharacter);
      }

      return _textWithPlaceholders;
    }

    return _text;
  }

  /// Placeholders that represent non-text content, e.g., inline images, that
  /// should appear in the rendered text.
  ///
  /// In terms of [length], each placeholder is treated as a single character.
  final Map<int, Object> placeholders;

  /// Returns the `length` of this [AttributedText], which includes the length
  /// of the plain text `String`, and the number of [placeholders].
  int get length => _text.length + placeholders.length;

  /// Returns `true` if the [length] of this [AttributedText] is zero.
  ///
  /// `isEmpty` is `true` if and only if both the plain text and the
  /// placeholders are empty.
  bool get isEmpty => _text.isEmpty && placeholders.isEmpty;

  /// Returns `true` if the [length] of this [AttributedText] is greater than zero.
  ///
  /// `isNotEmpty` is `true` if the plain text is non-empty, or if the
  /// placeholders are non-empty, or both.
  bool get isNotEmpty => _text.isNotEmpty || placeholders.isNotEmpty;

  /// The attributes applied across the plain text and [placeholders].
  final AttributedSpans spans;

  final _listeners = <VoidCallback>{};

  bool get hasListeners => _listeners.isNotEmpty;

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Returns true if the given [attribution] is applied at [offset].
  ///
  /// If the given [attribution] is [null], returns [true] if any attribution
  /// exists at the given [offset].
  bool hasAttributionAt(
    int offset, {
    Attribution? attribution,
  }) {
    return spans.hasAttributionAt(offset, attribution: attribution);
  }

  /// Returns true if this [AttributedText] contains at least one
  /// character with each of the given [attributions] within the
  /// given [range] (inclusive).
  bool hasAttributionsWithin({
    required Set<Attribution> attributions,
    required SpanRange range,
  }) {
    return spans.hasAttributionsWithin(
      attributions: attributions,
      start: range.start,
      end: range.end,
    );
  }

  /// Returns true if this [AttributedText] contains each of the
  /// given [attributions] throughout the given [range] (inclusive).
  bool hasAttributionsThroughout({
    required Set<Attribution> attributions,
    required SpanRange range,
  }) {
    for (int i = range.start; i <= range.end; i += 1) {
      for (final attribution in attributions) {
        if (!spans.hasAttributionAt(i, attribution: attribution)) {
          return false;
        }
      }
    }

    return true;
  }

  /// Returns all attributions applied to the given [offset].
  Set<Attribution> getAllAttributionsAt(int offset) {
    return spans.getAllAttributionsAt(offset);
  }

  /// Returns all attributions that appear throughout the entirety
  /// of the given [range].
  Set<Attribution> getAllAttributionsThroughout(SpanRange range) {
    final attributionsThroughout = spans.getAllAttributionsAt(range.start);
    int index = range.start + 1;

    while (index <= range.end && attributionsThroughout.isNotEmpty) {
      final missingAttributions = <Attribution>{};
      for (final attribution in attributionsThroughout) {
        if (!hasAttributionAt(index, attribution: attribution)) {
          missingAttributions.add(attribution);
        }
      }
      attributionsThroughout.removeAll(missingAttributions);
      index += 1;
    }

    return attributionsThroughout;
  }

  /// Returns all spans in this [AttributedText] for the given [attributions].
  Set<AttributionSpan> getAttributionSpans(Set<Attribution> attributions) => getAttributionSpansInRange(
        attributionFilter: (a) => attributions.contains(a),
        range: SpanRange(0, length),
      );

  /// Returns all spans in this [AttributedText], for attributions that are
  /// selected by the given [filter].
  Set<AttributionSpan> getAttributionSpansByFilter(AttributionFilter filter) => getAttributionSpansInRange(
        attributionFilter: filter,
        range: SpanRange(0, length),
      );

  /// Returns spans for each attribution that (at least partially) appear
  /// within the given [range], as selected by [attributionFilter].
  ///
  /// By default, the returned spans represent the full, contiguous span
  /// of each attribution. This means that if a portion of an attribution
  /// appears within the given [range], the entire attribution span is
  /// returned, including the area that sits outside the given [range].
  ///
  /// To obtain attribution spans that are cut down and limited to the
  /// given [range], pass `true` for [resizeSpansToFitInRange]. This setting
  /// only effects the returned spans, it does not alter the attributions
  /// within this [AttributedText].
  Set<AttributionSpan> getAttributionSpansInRange({
    required AttributionFilter attributionFilter,
    required SpanRange range,
    bool resizeSpansToFitInRange = false,
  }) {
    return spans.getAttributionSpansInRange(
      attributionFilter: attributionFilter,
      start: range.start,
      end: range.end,
      resizeSpansToFitInRange: resizeSpansToFitInRange,
    );
  }

  /// Returns the range about [offset], which is attributed with all given [attributions].
  ///
  /// [attributions] must not be empty.
  SpanRange getAttributedRange(Set<Attribution> attributions, int offset) {
    return spans.getAttributedRange(attributions, offset);
  }

  /// Adds the given [attribution] to all characters within the given
  /// [range], inclusive.
  ///
  /// The effect of adding an attribution is straight forward when the text doesn't
  /// contain any other attributions with the same ID. However, there are various
  /// situations where the [attribution] can't necessarily co-exist with other
  /// attribution spans that already exist in the text.
  ///
  /// Attribution overlaps can take one of two forms: mergeable or conflicting.
  ///
  /// ## Mergeable Attribution Spans
  /// An example of a mergeable overlap is where two bold spans overlap each
  /// other. All bold attributions are interchangeable, so when two bold spans
  /// overlap, those spans can be merged together into a single span.
  ///
  /// However, mergeable overlapping spans are not automatically merged. Instead,
  /// this decision is left to the user of this class. If you want [AttributedText] to
  /// merge overlapping mergeable spans, pass `true` for [autoMerge]. Otherwise,
  /// if [autoMerge] is `false`, an exception is thrown when two mergeable spans
  /// overlap each other.
  ///
  ///
  /// ## Conflicting Attribution Spans
  /// An example of a conflicting overlap is where a black text color overlaps a red
  /// text color. Text is either black, OR red, but never both. Therefore, the black
  /// attribution cannot co-exist with the red attribution. Something must be done
  /// to resolve this.
  ///
  /// There are two possible ways to handle conflicting overlaps. The new attribution
  /// can overwrite the existing attribution where they overlap. Or, an exception can be
  /// thrown. To overwrite the existing attribution with the new attribution, pass `true`
  /// for [overwriteConflictingSpans]. Otherwise, if [overwriteConflictingSpans]
  /// is `false`, an exception is thrown.
  void addAttribution(
    Attribution attribution,
    SpanRange range, {
    bool autoMerge = true,
    bool overwriteConflictingSpans = false,
  }) {
    spans.addAttribution(
      newAttribution: attribution,
      start: range.start,
      end: range.end,
      autoMerge: autoMerge,
      overwriteConflictingSpans: overwriteConflictingSpans,
    );
    _notifyListeners();
  }

  /// Removes the given [attribution] from all characters within the
  /// given [range], inclusive.
  void removeAttribution(Attribution attribution, SpanRange range) {
    spans.removeAttribution(attributionToRemove: attribution, start: range.start, end: range.end);
    _notifyListeners();
  }

  /// Returns a copy of this [AttributedText], replacing the existing
  /// [AttributedSpans] with the given [newSpans].
  AttributedText replaceAttributions(AttributedSpans newSpans) {
    return AttributedText(
      _text,
      newSpans,
      Map.from(placeholders),
    );
  }

  /// Removes all attributions within the given [range].
  void clearAttributions(SpanRange range) {
    // TODO: implement this capability within AttributedSpans
    //       This implementation uses existing round-about functionality
    //       to avoid adding new complexity to AttributedSpans while
    //       working on unrelated behavior (mobile text fields - Sept 17, 2021).
    //       Come back and implement clearAttributions in AttributedSpans
    //       in an efficient manner and add tests for it.
    final attributions = <Attribution>{};
    for (var i = range.start; i <= range.end; i += 1) {
      attributions.addAll(spans.getAllAttributionsAt(i));
    }
    for (final attribution in attributions) {
      spans.removeAttribution(attributionToRemove: attribution, start: range.start, end: range.end);
    }
  }

  /// If ALL of the text in [range], inclusive, contains the given [attribution],
  /// that [attribution] is removed from the text in [range], inclusive.
  /// Otherwise, all of the text in [range], inclusive, is given the [attribution].
  void toggleAttribution(Attribution attribution, SpanRange range) {
    spans.toggleAttribution(attribution: attribution, start: range.start, end: range.end);
    _notifyListeners();
  }

  /// Copies all text and attributions from [range.start] to [range.end] (exclusive),
  /// and returns them as a new [AttributedText].
  AttributedText copyTextInRange(SpanRange range) => copyText(range.start, range.end);

  /// Copies all text, attributions, and placeholders from [startOffset] to
  /// [endOffset], exclusive, and returns them as a new [AttributedText].
  AttributedText copyText(int startOffset, [int? endOffset]) {
    _log.fine('start: $startOffset, end: $endOffset');

    final placeholdersBeforeStartOffset = placeholders.entries.where((entry) => entry.key < startOffset);
    final textStartCopyOffset = startOffset - placeholdersBeforeStartOffset.length;

    final placeholdersAfterStartBeforeEndOffset = placeholders.entries.where(
      (entry) => startOffset <= entry.key && entry.key < (endOffset ?? length),
    );
    final textEndCopyOffset =
        (endOffset ?? length) - placeholdersBeforeStartOffset.length - placeholdersAfterStartBeforeEndOffset.length;

    // The span marker offsets are based on the text with placeholders, so we need
    // to copy the text with placeholders to ensure the span markers are correct.
    final textWithPlaceholders = toPlainText();

    // Note: -1 because copyText() uses an exclusive `start` and `end` but
    // _copyAttributionRegion() uses an inclusive `start` and `end`.
    final spansStartCopyOffset =
        startOffset < textWithPlaceholders.length ? startOffset : textWithPlaceholders.length - 1;
    int spansEndCopyOffset;
    if (endOffset == startOffset) {
      spansEndCopyOffset = spansStartCopyOffset;
    } else if (endOffset != null) {
      spansEndCopyOffset = endOffset - 1;
    } else {
      spansEndCopyOffset = textWithPlaceholders.length - 1;
    }
    _log.fine('offsets, start: $spansStartCopyOffset, end: $spansEndCopyOffset');

    // Create placeholders for the copied region. The indices of the placeholders
    // need to be reduced based on the text/placeholders cut out from the
    // beginning of this AttributedText.
    final copiedPlaceholders = <int, Object>{};
    for (final existingPlaceholder in placeholdersAfterStartBeforeEndOffset) {
      copiedPlaceholders[existingPlaceholder.key - startOffset] = existingPlaceholder.value;
    }

    return AttributedText(
      _text.substring(textStartCopyOffset, textEndCopyOffset),
      spans.copyAttributionRegion(spansStartCopyOffset, spansEndCopyOffset),
      copiedPlaceholders,
    );
  }

  /// Returns a plain-text substring, from [range.start] to [range.end] (exclusive).
  ///
  /// {@macro attributed_text_substring_range}
  String substringInRange(SpanRange range) => substring(range.start, range.end);

  /// Returns a plain-text substring, from [start] to [end] (exclusive), or the end of
  /// this [AttributedText] if [end] isn't provided.
  ///
  /// {@template attributed_text_substring_range}
  /// [AttributedText] can contain placeholders, each of which take up one character of length.
  /// The given [range] is interpreted as a range within this [AttributedText]. If placeholders
  /// appear within that range, then the length of the returned `String` will be less than the
  /// length of the range.
  /// {@endtemplate}
  String substring(int start, [int? end]) {
    final placeholdersBeforeStartOffset = placeholders.entries.where((entry) => entry.key < start);
    final textStartCopyOffset = start - placeholdersBeforeStartOffset.length;

    final placeholdersAfterStartBeforeEndOffset = placeholders.entries.where(
      (entry) => start <= entry.key && entry.key < (end ?? length),
    );
    final textEndCopyOffset =
        (end ?? length) - placeholdersBeforeStartOffset.length - placeholdersAfterStartBeforeEndOffset.length;

    return _text.substring(textStartCopyOffset, textEndCopyOffset);
  }

  /// Returns a copy of this [AttributedText] with the [other] text
  /// and attributions appended to the end.
  AttributedText copyAndAppend(AttributedText other) {
    _log.fine('our attributions before pushing them:');
    _log.fine(spans.toString());

    if (other.isEmpty) {
      _log.fine('`other` has no text. Returning a direct copy of ourselves.');
      return AttributedText(
        _text,
        spans.copy(),
        Map.from(placeholders),
      );
    }

    if (isEmpty) {
      _log.fine('our `text` is empty. Returning a direct copy of the `other` text.');
      return AttributedText(
        other._text,
        other.spans.copy(),
        Map.from(other.placeholders),
      );
    }

    return AttributedText(
      _text + other._text,
      spans.copy()..addAt(other: other.spans, index: length),
      {
        ...placeholders,
        ...other.placeholders.map((offset, placeholder) => MapEntry(offset + length, placeholder)),
      },
    );
  }

  /// Returns a copy of this [AttributedText] with [textToInsert] inserted
  /// at [startOffset], retaining whatever attributions are already applied
  /// to [textToInsert].
  AttributedText insert({
    required AttributedText textToInsert,
    required int startOffset,
  }) {
    final startText = copyText(0, startOffset);
    final endText = copyText(startOffset);
    return startText.copyAndAppend(textToInsert).copyAndAppend(endText);
  }

  /// Returns a copy of this [AttributedText] with [textToInsert]
  /// inserted at [startOffset].
  ///
  /// Any attributions that span [startOffset] are applied to all
  /// of the inserted text. All spans that start after [startOffset]
  /// are pushed back by the length of [textToInsert].
  AttributedText insertString({
    required String textToInsert,
    required int startOffset,
    Set<Attribution> applyAttributions = const {},
  }) {
    _log.fine('text: "$textToInsert", start: $startOffset, attributions: $applyAttributions');

    _log.fine('copying text to the left');
    final startText = copyText(0, startOffset);
    _log.fine('startText: $startText');

    _log.fine('copying text to the right');
    final endText = copyText(startOffset);
    _log.fine('endText: $endText');

    _log.fine('creating new attributed text for insertion');
    final insertedText = AttributedText(textToInsert);
    final insertTextRange = SpanRange(0, textToInsert.length - 1);
    for (dynamic attribution in applyAttributions) {
      insertedText.addAttribution(attribution, insertTextRange);
    }
    _log.fine('insertedText: $insertedText');

    _log.fine('combining left text, insertion text, and right text');
    return startText.copyAndAppend(insertedText).copyAndAppend(endText);
  }

  AttributedText insertPlaceholders(Map<int, Object> placeholders) {
    var finalText = this;
    for (final entry in placeholders.entries) {
      finalText = finalText.insertPlaceholder(entry.key, entry.value);
    }
    return finalText;
  }

  AttributedText insertPlaceholder(int index, Object placeholder) {
    return AttributedText(_text, spans.copy(), {
      // Insert existing placeholders that come before the new placeholder.
      ...Map.fromEntries(placeholders.entries.where((entry) => entry.key < index)),
      // Insert the new placeholder.
      index: placeholder,
      // Push back all later placeholders by 1 unit, because of the new placeholder.
      ...Map.fromEntries(
        placeholders.entries.where((entry) => entry.key >= index).map((entry) => MapEntry(entry.key + 1, entry.value)),
      ),
    });
  }

  /// Copies this [AttributedText] and removes  a region of text and attributions
  /// from [startOffset], inclusive, to [endOffset], exclusive.
  AttributedText removeRegion({
    required int startOffset,
    required int endOffset,
  }) {
    _log.fine('Removing text region from $startOffset to $endOffset');
    _log.fine('initial attributions:');
    _log.fine(spans.toString());
    final reducedText = substring(0, startOffset) + substring(endOffset, length);

    AttributedSpans contractedAttributions = spans.copy()
      ..contractAttributions(
        startOffset: startOffset,
        count: endOffset - startOffset,
      );
    _log.fine('reduced text length: ${reducedText.length}');
    _log.fine('remaining attributions:');
    _log.fine(contractedAttributions.toString());

    return AttributedText(
      reducedText,
      contractedAttributions,
      Map.fromEntries(
        placeholders.entries
            .where((entry) => entry.key < startOffset || endOffset <= entry.key) //
            .map(
              (entry) => entry.key >= endOffset //
                  ? MapEntry(entry.key - (endOffset - startOffset), entry.value)
                  : entry,
            ),
      ),
    );
  }

  /// Visits all attributions in this [AttributedText] by calling [visitor] whenever
  /// an attribution begins or ends.
  ///
  /// If multiple attributions begin or end at the same index, then all of those attributions
  /// are reported together.
  ///
  /// **Only Reports Beginnings and Endings:**
  ///
  /// This visitation method does not report all applied attributions at a given index. It
  /// only reports attributions that begin or end at a specific index.
  ///
  /// For example:
  ///
  /// Bold:         |xxxxxxxxxxxx|
  /// Italics:      |------xxxxxx|
  ///
  /// Bold is attributed throughout the range. Italics begins at index `6`. When [visitor]
  /// is notified about italics beginning at `6`, visitor is NOT notified that bold applies
  /// at that same index.
  void visitAttributions(AttributionVisitor visitor) {
    final startingAttributions = <Attribution>{};
    final endingAttributions = <Attribution>{};
    int currentIndex = -1;

    visitor.onVisitBegin();

    for (final marker in spans.markers) {
      // If the marker offset differs from the currentIndex it means
      // we already added all the attributions that start or end
      // at currentIndex.
      if (marker.offset != currentIndex) {
        if (currentIndex >= 0) {
          visitor.visitAttributions(this, currentIndex, startingAttributions, endingAttributions);
        }

        currentIndex = marker.offset;
        startingAttributions.clear();
        endingAttributions.clear();
      }

      if (marker.isStart) {
        startingAttributions.add(marker.attribution);
      } else {
        endingAttributions.add(marker.attribution);
      }
    }

    // Visit the final set of end markers.
    if (endingAttributions.isNotEmpty) {
      visitor.visitAttributions(this, currentIndex, startingAttributions, endingAttributions);
    }

    visitor.onVisitEnd();
  }

  /// Visits attributions in this [AttributedText], reporting every changing group of
  /// attributions to the given [visitor].
  ///
  /// See [computeAttributionSpans] for an example.
  ///
  /// See also:
  ///
  ///   * [visitAttributions], to visit attributions markers instead of attribution groups.
  ///   * [computeAttributionSpans], to work with a list of [MultiAttributionSpan]s instead
  ///     of visiting each span with a callback.
  void visitAttributionSpans(AttributionSpanVisitor visitor) {
    final collapsedSpans = computeAttributionSpans();
    for (final span in collapsedSpans) {
      visitor(span);
    }
  }

  /// Collapses all attribution markers down into a series of attribution groups,
  /// starting at the beginning of this [AttributedText], until the end.
  ///
  /// A new group of attributions begin wherever an attribution begins or ends.
  ///
  /// For example:
  ///
  /// Bold:         |----xxxxxxxxxxxx------------|
  /// Italics:      |-------xxxxxxxxxxxxx--------|
  /// Strikethru:   |-----------xxxxxxxxxxxxx----|
  ///
  /// Given the above attributions, the given [visitor] would be notified of the following
  /// groups:
  ///
  ///  1. [0, 4]   - No attributions
  ///  2. [5, 8]   - Bold
  ///  3. [9, 12]  - Bold, Italics
  ///  4. [13, 16] - Bold, Italics, Strikethru
  ///  5. [17, 20] - Italics, Strikethru
  ///  6. [21, 24] - Strikethru
  ///  7. [25, 28] - No attributions
  ///
  /// Attribution groups are useful when computing all style variations for [AttributedText].
  Iterable<MultiAttributionSpan> computeAttributionSpans() {
    return spans.collapseSpans(contentLength: length);
  }

  /// Returns a copy of this [AttributedText].
  AttributedText copy() {
    return AttributedText(
      _text,
      spans.copy(),
      Map.from(placeholders),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AttributedText &&
            runtimeType == other.runtimeType &&
            _text == other._text &&
            spans == other.spans &&
            (const DeepCollectionEquality()).equals(placeholders, other.placeholders);
  }

  @override
  int get hashCode => _text.hashCode ^ spans.hashCode ^ placeholders.hashCode;

  @override
  String toString() {
    return '[AttributedText] - "$_text"\n$spans\n$placeholders';
  }
}

typedef AttributionSpanVisitor = void Function(MultiAttributionSpan span);

/// Visits every [index] in the the given [AttributedText] which has at least
/// one start or end marker, passing the attributions that start or end at the [index].
///
/// Note: most range-based operations expect the
/// closing [index] to be exclusive, but that is not how this callback
/// works. Both the start and end [index]es are inclusive.
typedef VisitAttributionsCallback = void Function(
  AttributedText fullText,
  int index,
  Set<Attribution> startingAttributions,
  Set<Attribution> endingAttributions,
);

enum AttributionVisitEvent {
  start,
  end,
}

/// Visitor that visits every start and end attribution marker in an [AttributedText]
abstract class AttributionVisitor {
  /// Called before visiting attributions, so that implementers can perform any desired setup.
  void onVisitBegin() {}

  /// Visits all starting and ending attribution markers at the given [index] within [fullText].
  ///
  /// This method isn't called for indices that don't contain any attribution markers.
  void visitAttributions(
    AttributedText fullText,
    int index,
    Set<Attribution> startingAttributions,
    Set<Attribution> endingAttributions,
  );

  /// Called after all attribution markers have been visited by [visitAttributions].
  void onVisitEnd() {}
}

/// [AttributionVisitor] that delegates to given callbacks.
class CallbackAttributionVisitor implements AttributionVisitor {
  CallbackAttributionVisitor({
    VoidCallback? onVisitBegin,
    required VisitAttributionsCallback visitAttributions,
    VoidCallback? onVisitEnd,
  })  : _onVisitBegin = onVisitBegin,
        _onVisitAttributions = visitAttributions,
        _onVisitEnd = onVisitEnd;

  final VoidCallback? _onVisitBegin;
  final VisitAttributionsCallback _onVisitAttributions;
  final VoidCallback? _onVisitEnd;

  @override
  void onVisitBegin() {
    _onVisitBegin?.call();
  }

  @override
  void visitAttributions(
    AttributedText fullText,
    int index,
    Set<Attribution> startingAttributions,
    Set<Attribution> endingAttributions,
  ) {
    _onVisitAttributions(fullText, index, startingAttributions, endingAttributions);
  }

  @override
  void onVisitEnd() {
    _onVisitEnd?.call();
  }
}

/// A zero-parameter function that returns nothing.
///
/// This is the same as Flutter's `VoidCallback`. It's replicated in this
/// project to avoid depending on Flutter.
typedef VoidCallback = void Function();
