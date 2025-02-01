// ignore_for_file: avoid_renaming_method_parameters

import 'dart:collection';
import 'dart:math';

import 'package:attributed_text/attributed_text.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart' hide SelectableText;
import 'package:flutter/services.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/edit_context.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/core/styles.dart';
import 'package:super_editor/src/default_editor/attributions.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/attributed_text_styles.dart';
import 'package:super_editor/src/infrastructure/composable_text.dart';
import 'package:super_editor/src/infrastructure/flutter/geometry.dart';
import 'package:super_editor/src/infrastructure/key_event_extensions.dart';
import 'package:super_editor/src/infrastructure/keyboard.dart';
import 'package:super_editor/src/infrastructure/strings.dart';
import 'package:super_text_layout/super_text_layout.dart';

import 'layout_single_column/layout_single_column.dart';
import 'list_items.dart';
import 'multi_node_editing.dart';
import 'paragraph.dart';
import 'selection_upstream_downstream.dart';
import 'text_tools.dart';

@immutable
class TextNode extends DocumentNode {
  static DocumentSelection selectionWithin(List<String> nodePath, int base, int extent) {
    return DocumentSelection(
      base: DocumentPosition(
        documentPath: NodePath(nodePath),
        nodePosition: TextNodePosition(offset: base),
      ),
      extent: DocumentPosition(
        documentPath: NodePath(nodePath),
        nodePosition: TextNodePosition(offset: extent),
      ),
    );
  }

  /// A factory method for a collapsed [DocumentSelection] within a [TextNode]
  /// at the given [nodePath], and the given [textOffset] within that node.
  ///
  /// This factory is provided as a convenience for less verbose code.
  static DocumentSelection caretAt(List<String> nodePath, int textOffset) {
    return DocumentSelection.collapsed(
      position: DocumentPosition(
        documentPath: NodePath(nodePath),
        nodePosition: TextNodePosition(offset: textOffset),
      ),
    );
  }

  TextNode({
    required this.id,
    required this.text,
    super.metadata,
  });

  @override
  final String id;

  /// The content text within this [TextNode].
  final AttributedText text;

  @override
  TextNodePosition get beginningPosition => const TextNodePosition(offset: 0);

  @override
  TextNodePosition get endPosition => TextNodePosition(offset: text.length);

  @override
  bool containsPosition(Object position) {
    if (position is! TextNodePosition) {
      return false;
    }

    if (position.offset < 0 || position.offset > text.length) {
      return false;
    }

    return true;
  }

  @override
  NodePosition selectUpstreamPosition(NodePosition position1, NodePosition position2) {
    if (position1 is! TextNodePosition) {
      throw Exception('Expected a TextNodePosition for position1 but received a ${position1.runtimeType}');
    }
    if (position2 is! TextNodePosition) {
      throw Exception('Expected a TextNodePosition for position2 but received a ${position2.runtimeType}');
    }

    return position1.offset < position2.offset ? position1 : position2;
  }

  @override
  NodePosition selectDownstreamPosition(NodePosition position1, NodePosition position2) {
    if (position1 is! TextNodePosition) {
      throw Exception('Expected a TextNodePosition for position1 but received a ${position1.runtimeType}');
    }
    if (position2 is! TextNodePosition) {
      throw Exception('Expected a TextNodePosition for position2 but received a ${position2.runtimeType}');
    }

    return position1.offset > position2.offset ? position1 : position2;
  }

  /// Returns a [DocumentSelection] within this [TextNode] from [startIndex] to [endIndex].
  DocumentSelection selectionBetween(NodePath nodePath, int startIndex, int endIndex) {
    return DocumentSelection(
      base: DocumentPosition(
        documentPath: nodePath,
        nodePosition: TextNodePosition(offset: startIndex),
      ),
      extent: DocumentPosition(
        documentPath: nodePath,
        nodePosition: TextNodePosition(offset: endIndex),
      ),
    );
  }

  /// Returns a collapsed [DocumentSelection], positioned within this [TextNode] at the
  /// given [collapsedIndex].
  DocumentSelection selectionAt(NodePath nodePath, int collapsedIndex) {
    return DocumentSelection.collapsed(
      position: positionAt(nodePath, collapsedIndex),
    );
  }

  /// Returns a [DocumentPosition] within this [TextNode] at the given text [index].
  DocumentPosition positionAt(NodePath nodePath, int index) {
    return DocumentPosition(
      documentPath: nodePath,
      nodePosition: TextNodePosition(offset: index),
    );
  }

  /// Returns a [DocumentRange] within this [TextNode] between [startIndex] and [endIndex].
  DocumentRange rangeBetween(NodePath nodePath, int startIndex, int endIndex) {
    return DocumentRange(
      start: DocumentPosition(
        documentPath: nodePath,
        nodePosition: TextNodePosition(offset: startIndex),
      ),
      end: DocumentPosition(
        documentPath: nodePath,
        nodePosition: TextNodePosition(offset: endIndex),
      ),
    );
  }

  @override
  TextNodeSelection computeSelection({
    required NodePosition base,
    required NodePosition extent,
  }) {
    assert(base is TextNodePosition);
    assert(extent is TextNodePosition);

    return TextNodeSelection(
      baseOffset: (base as TextNodePosition).offset,
      extentOffset: (extent as TextNodePosition).offset,
      affinity: extent.affinity,
    );
  }

  @override
  String copyContent(dynamic selection) {
    assert(selection is TextSelection);

    return (selection as TextSelection).textInside(text.toPlainText());
  }

  @override
  bool hasEquivalentContent(DocumentNode other) {
    return other is TextNode && text == other.text && super.hasEquivalentContent(other);
  }

  TextNode copyTextNodeWith({
    String? id,
    AttributedText? text,
    Map<String, dynamic>? metadata,
  }) {
    return TextNode(
      id: id ?? this.id,
      text: text ?? this.text,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return copyTextNodeWith(
      metadata: newMetadata,
    );
  }

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return copyTextNodeWith(
      metadata: {...metadata, ...newProperties},
    );
  }

  TextNode copy() {
    return TextNode(id: id, text: text.copyText(0), metadata: Map.from(metadata));
  }

  @override
  String toString() => '[TextNode] - text: $text, metadata: ${copyMetadata()}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is TextNode && runtimeType == other.runtimeType && id == other.id && text == other.text;

  @override
  int get hashCode => super.hashCode ^ id.hashCode ^ text.hashCode;
}

extension TextNodeExtensions on DocumentNode {
  TextNode get asTextNode => this as TextNode;
}

extension DocumentSelectionWithText on Document {
  /// Returns `true` if all the text within the given [selection] contains at least
  /// some characters with each of the given [attributions].
  ///
  /// All non-text content is ignored.
  bool doesSelectedTextContainAttributions(DocumentSelection selection, Set<Attribution> attributions) {
    final nodes = getNodesInside(selection.base, selection.extent);
    if (nodes.isEmpty) {
      return false;
    }

    // Calculate a DocumentRange so we know which DocumentPosition
    // belongs to the first node, and which belongs to the last node.
    final nodeRange = getRangeBetween(selection.base, selection.extent);

    for (final textNode in nodes) {
      if (textNode is! TextNode) {
        continue;
      }

      int startOffset = -1;
      int endOffset = -1;

      if (textNode == nodes.first && textNode == nodes.last) {
        // Handle selection within a single node
        final baseOffset = (selection.base.nodePosition as TextPosition).offset;
        final extentOffset = (selection.extent.nodePosition as TextPosition).offset;
        startOffset = baseOffset < extentOffset ? baseOffset : extentOffset;
        endOffset = baseOffset < extentOffset ? extentOffset : baseOffset;

        // -1 because TextPosition's offset indexes the character after the
        // selection, not the final character in the selection.
        endOffset -= 1;
      } else if (textNode == nodes.first) {
        // Handle partial node selection in first node.
        startOffset = (nodeRange.start.nodePosition as TextPosition).offset;
        endOffset = max(textNode.text.length - 1, 0);
      } else if (textNode == nodes.last) {
        // Handle partial node selection in last node.
        startOffset = 0;

        // -1 because TextPosition's offset indexes the character after the
        // selection, not the final character in the selection.
        endOffset = (nodeRange.end.nodePosition as TextPosition).offset - 1;
      } else {
        // Handle full node selection.
        startOffset = 0;
        endOffset = max(textNode.text.length - 1, 0);
      }

      final selectionRange = SpanRange(startOffset, endOffset);

      if (textNode.text.hasAttributionsWithin(
        attributions: attributions,
        range: selectionRange,
      )) {
        return true;
      }
    }

    return false;
  }

  /// Returns all attributions that appear throughout the entirety of the selected range.
  Set<Attribution> getAllAttributions(DocumentSelection selection) {
    final attributions = <Attribution>{};

    final nodes = getNodesInside(selection.base, selection.extent);
    if (nodes.isEmpty) {
      return attributions;
    }

    // Calculate a DocumentRange so we know which DocumentPosition
    // belongs to the first node, and which belongs to the last node.
    final nodeRange = getRangeBetween(selection.base, selection.extent);

    for (final textNode in nodes) {
      if (textNode is! TextNode) {
        continue;
      }

      int startOffset = -1;
      int endOffset = -1;

      if (textNode == nodes.first && textNode == nodes.last) {
        // Handle selection within a single node
        final baseOffset = (selection.base.nodePosition as TextPosition).offset;
        final extentOffset = (selection.extent.nodePosition as TextPosition).offset;
        startOffset = baseOffset < extentOffset ? baseOffset : extentOffset;
        endOffset = baseOffset < extentOffset ? extentOffset : baseOffset;

        // -1 because TextPosition's offset indexes the character after the
        // selection, not the final character in the selection.
        endOffset -= 1;
      } else if (textNode == nodes.first) {
        // Handle partial node selection in first node.
        startOffset = (nodeRange.start.nodePosition as TextPosition).offset;
        endOffset = max(textNode.text.length - 1, 0);
      } else if (textNode == nodes.last) {
        // Handle partial node selection in last node.
        startOffset = 0;

        // -1 because TextPosition's offset indexes the character after the
        // selection, not the final character in the selection.
        endOffset = (nodeRange.end.nodePosition as TextPosition).offset - 1;
      } else {
        // Handle full node selection.
        startOffset = 0;
        endOffset = max(textNode.text.length - 1, 0);
      }

      final selectionRange = SpanRange(startOffset, endOffset);

      final attributionsInRange = textNode //
          .text
          .getAllAttributionsThroughout(selectionRange);

      attributions.addAll(attributionsInRange);
    }
    return attributions;
  }

  /// Returns all attributions of type [T] that appear throughout the entirety of the selected range.
  Set<T> getAttributionsByType<T>(DocumentSelection selection) {
    final attributions = <T>{};

    final nodes = getNodesInside(selection.base, selection.extent);
    if (nodes.isEmpty) {
      return attributions;
    }

    // Calculate a DocumentRange so we know which DocumentPosition
    // belongs to the first node, and which belongs to the last node.
    final nodeRange = getRangeBetween(selection.base, selection.extent);

    for (final textNode in nodes) {
      if (textNode is! TextNode) {
        continue;
      }

      int startOffset = -1;
      int endOffset = -1;

      if (textNode == nodes.first && textNode == nodes.last) {
        // Handle selection within a single node
        final baseOffset = (selection.base.nodePosition as TextPosition).offset;
        final extentOffset = (selection.extent.nodePosition as TextPosition).offset;
        startOffset = baseOffset < extentOffset ? baseOffset : extentOffset;
        endOffset = baseOffset < extentOffset ? extentOffset : baseOffset;

        // -1 because TextPosition's offset indexes the character after the
        // selection, not the final character in the selection.
        endOffset -= 1;
      } else if (textNode == nodes.first) {
        // Handle partial node selection in first node.
        startOffset = (nodeRange.start.nodePosition as TextPosition).offset;
        endOffset = max(textNode.text.length - 1, 0);
      } else if (textNode == nodes.last) {
        // Handle partial node selection in last node.
        startOffset = 0;

        // -1 because TextPosition's offset indexes the character after the
        // selection, not the final character in the selection.
        endOffset = (nodeRange.end.nodePosition as TextPosition).offset - 1;
      } else {
        // Handle full node selection.
        startOffset = 0;
        endOffset = max(textNode.text.length - 1, 0);
      }

      final selectionRange = SpanRange(startOffset, endOffset);

      final attributionsInRange = textNode //
          .text
          .getAllAttributionsThroughout(selectionRange)
          .whereType<T>();

      attributions.addAll(attributionsInRange);
    }
    return attributions;
  }
}

extension Words on String {
  /// Returns a list of [TextRange]s, one that spans every word in the [String]
  /// ordered from upstream to downstream.
  List<TextRange> calculateAllWordBoundaries() {
    final List<TextRange> textSelections = [];
    var offset = 0;

    while (offset < length) {
      if (this[offset] == ' ') {
        offset++;
        continue;
      }

      final currentPosition = TextPosition(offset: offset);
      final textSelection = expandPositionToWord(text: this, textPosition: currentPosition);
      textSelections.add(textSelection);

      offset += textSelection.end - textSelection.start + 1;
    }
    return textSelections;
  }
}

/// A logical selection within a [TextNode].
///
/// The selection begins at [baseOffset] and ends at [extentOffset].
class TextNodeSelection extends TextSelection implements NodeSelection {
  TextNodeSelection.fromTextSelection(TextSelection textSelection)
      : super(
          baseOffset: textSelection.baseOffset,
          extentOffset: textSelection.extentOffset,
          affinity: textSelection.affinity,
          isDirectional: textSelection.isDirectional,
        );

  const TextNodeSelection.collapsed({
    required int offset,
    TextAffinity affinity = TextAffinity.downstream,
  }) : super(
          baseOffset: offset,
          extentOffset: offset,
          affinity: affinity,
        );

  const TextNodeSelection({
    required int baseOffset,
    required int extentOffset,
    TextAffinity affinity = TextAffinity.downstream,
    bool isDirectional = false,
  }) : super(
          baseOffset: baseOffset,
          extentOffset: extentOffset,
          affinity: affinity,
          isDirectional: isDirectional,
        );

  @override
  TextNodePosition get base => TextNodePosition(offset: baseOffset, affinity: affinity);

  @override
  TextNodePosition get extent => TextNodePosition(offset: extentOffset, affinity: affinity);
}

/// A logical position within a [TextNode].
class TextNodePosition extends TextPosition implements NodePosition {
  TextNodePosition.fromTextPosition(TextPosition position)
      : super(offset: position.offset, affinity: position.affinity);

  const TextNodePosition({
    required int offset,
    TextAffinity affinity = TextAffinity.downstream,
  }) : super(offset: offset, affinity: affinity);

  @override
  bool isEquivalentTo(NodePosition other) {
    if (other is! TextNodePosition) {
      return false;
    }

    // Equivalency is determined by text offset. Affinity is ignored, because
    // affinity doesn't alter the actual location in the text that a
    // TextNodePosition refers to.
    return offset == other.offset;
  }

  TextNodePosition copyWith({
    int? offset,
    TextAffinity? affinity,
  }) {
    return TextNodePosition(
      offset: offset ?? this.offset,
      affinity: affinity ?? this.affinity,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other && other is TextNodePosition && runtimeType == other.runtimeType && offset == other.offset;

  @override
  int get hashCode => super.hashCode ^ super.offset.hashCode;
}

/// Mixin for all [SingleColumnLayoutComponentViewModel]s that represent
/// a text-based block, e.g., paragraph, blockquote, list item.
///
/// This mixin enforces a consistent contract for all such view models.
/// Each view model can add more properties, but they must at least
/// support the properties in this mixin. Additionally, [applyStyles]
/// provides consistent application of text-based styling for all
/// view models that add this mixin.
mixin TextComponentViewModel on SingleColumnLayoutComponentViewModel {
  AttributedText get text;
  set text(AttributedText text);

  AttributionStyleBuilder get textStyleBuilder;
  set textStyleBuilder(AttributionStyleBuilder styleBuilder);

  InlineWidgetBuilderChain get inlineWidgetBuilders;
  set inlineWidgetBuilders(InlineWidgetBuilderChain inlineWidgetBuildChain);

  TextDirection get textDirection;
  set textDirection(TextDirection direction);

  TextAlign get textAlignment;
  set textAlignment(TextAlign alignment);

  TextSelection? get selection;
  set selection(TextSelection? selection);

  Color get selectionColor;
  set selectionColor(Color color);

  bool get highlightWhenEmpty;
  set highlightWhenEmpty(bool highlight);

  /// The span of text that's currently sitting in the IME's composing region,
  /// which is underlined by this component.
  TextRange? composingRegion;
  UnderlineStyle composingRegionUnderlineStyle = const StraightUnderlineStyle();

  /// Whether to underline the [composingRegion].
  ///
  /// Showing the underline is optional because the behavior differs between
  /// platforms, e.g., Mac shows an underline but Windows and Linux don't.
  bool showComposingRegionUnderline = true;

  List<TextRange> spellingErrors = [];
  UnderlineStyle spellingErrorUnderlineStyle = const SquiggleUnderlineStyle();

  List<TextRange> grammarErrors = [];
  UnderlineStyle grammarErrorUnderlineStyle = const SquiggleUnderlineStyle(color: Colors.blue);

  List<Underlines> createUnderlines() {
    return [
      if (composingRegion != null && showComposingRegionUnderline)
        Underlines(
          style: composingRegionUnderlineStyle,
          underlines: [composingRegion!],
        ),
      if (spellingErrors.isNotEmpty) //
        Underlines(
          style: spellingErrorUnderlineStyle,
          underlines: spellingErrors,
        ),
      if (grammarErrors.isNotEmpty) //
        Underlines(
          style: grammarErrorUnderlineStyle,
          underlines: grammarErrors,
        ),
    ];
  }

  @override
  void applyStyles(Map<String, dynamic> styles) {
    super.applyStyles(styles);

    textAlignment = styles[Styles.textAlign] ?? textAlignment;

    textStyleBuilder = (attributions) {
      final baseStyle = styles[Styles.textStyle] ?? noStyleBuilder({});
      final inlineTextStyler = styles[Styles.inlineTextStyler] as AttributionStyleAdjuster;

      return inlineTextStyler(attributions, baseStyle);
    };

    inlineWidgetBuilders = styles[Styles.inlineWidgetBuilders] ?? [];

    composingRegionUnderlineStyle = styles[Styles.composingRegionUnderlineStyle] ?? composingRegionUnderlineStyle;
    showComposingRegionUnderline = styles[Styles.showComposingRegionUnderline] ?? showComposingRegionUnderline;

    spellingErrorUnderlineStyle = styles[Styles.spellingErrorUnderlineStyle] ?? spellingErrorUnderlineStyle;
    grammarErrorUnderlineStyle = styles[Styles.grammarErrorUnderlineStyle] ?? grammarErrorUnderlineStyle;
  }
}

/// Document component that displays hint text when its content text
/// is empty.
///
/// Internally uses a [TextComponent] to display the content text.
class TextWithHintComponent extends StatefulWidget {
  const TextWithHintComponent({
    Key? key,
    required this.text,
    this.hintText,
    this.hintStyleBuilder,
    this.textAlign,
    this.textDirection,
    required this.textStyleBuilder,
    this.metadata = const {},
    this.textSelection,
    this.selectionColor = Colors.lightBlueAccent,
    this.highlightWhenEmpty = false,
    this.underlines = const [],
    this.showDebugPaint = false,
  }) : super(key: key);

  final AttributedText text;
  final AttributedText? hintText;
  final AttributionStyleBuilder? hintStyleBuilder;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final AttributionStyleBuilder textStyleBuilder;
  final Map<String, dynamic> metadata;
  final TextSelection? textSelection;
  final Color selectionColor;
  final bool highlightWhenEmpty;
  final List<Underlines> underlines;

  final bool showDebugPaint;

  @override
  State createState() => _TextWithHintComponentState();
}

class _TextWithHintComponentState extends State<TextWithHintComponent>
    with ProxyDocumentComponent<TextWithHintComponent>, ProxyTextComposable {
  final _childTextComponentKey = GlobalKey<TextComponentState>();

  @override
  GlobalKey get childDocumentComponentKey => _childTextComponentKey;

  @override
  TextComposable get childTextComposable => _childTextComponentKey.currentState!;

  TextStyle _styleBuilder(Set<Attribution> attributions) {
    final attributionsWithBlock = Set.of(attributions);
    final blockType = widget.metadata['blockType'];
    if (blockType != null && blockType is Attribution) {
      attributionsWithBlock.add(blockType);
    }

    final contentStyle = widget.textStyleBuilder(attributionsWithBlock);
    final hintStyle = contentStyle.merge(widget.hintStyleBuilder?.call(attributionsWithBlock) ?? const TextStyle());
    return hintStyle;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (widget.text.isEmpty)
          IgnorePointer(
            child: Text.rich(
              widget.hintText?.computeTextSpan(_styleBuilder) ?? const TextSpan(text: ''),
            ),
          ),
        TextComponent(
          key: _childTextComponentKey,
          text: widget.text,
          textAlign: widget.textAlign,
          textDirection: widget.textDirection,
          textStyleBuilder: widget.textStyleBuilder,
          metadata: widget.metadata,
          textSelection: widget.textSelection,
          selectionColor: widget.selectionColor,
          highlightWhenEmpty: widget.highlightWhenEmpty,
          underlines: widget.underlines,
          showDebugPaint: widget.showDebugPaint,
        ),
      ],
    );
  }
}

/// Displays text in a document.
///
/// This is the standard component for text display.
class TextComponent extends StatefulWidget {
  const TextComponent({
    Key? key,
    required this.text,
    this.textAlign,
    this.textDirection,
    this.textScaler,
    required this.textStyleBuilder,
    this.inlineWidgetBuilders = const [],
    this.metadata = const {},
    this.textSelection,
    this.selectionColor = Colors.lightBlueAccent,
    this.highlightWhenEmpty = false,
    this.underlines = const [],
    this.showDebugPaint = false,
  }) : super(key: key);

  final AttributedText text;

  final TextAlign? textAlign;

  final TextDirection? textDirection;

  /// The text scaling policy.
  ///
  /// Defaults to `MediaQuery.textScalerOf()`.
  final TextScaler? textScaler;

  final AttributionStyleBuilder textStyleBuilder;

  /// A Chain of Responsibility that's used to build inline widgets.
  ///
  /// The first builder in the chain to return a non-null `Widget` will be
  /// used for a given inline placeholder.
  final InlineWidgetBuilderChain inlineWidgetBuilders;

  final Map<String, dynamic> metadata;

  final TextSelection? textSelection;

  final Color selectionColor;

  final bool highlightWhenEmpty;

  /// Groups of underlines.
  ///
  /// Each [Underlines] group contains some number of underlines, along with a style that
  /// applies to those underlines. Multiple styles of underlines are displayed by providing
  /// multiple [Underlines].
  final List<Underlines> underlines;

  final bool showDebugPaint;

  @override
  TextComponentState createState() => TextComponentState();
}

class TextComponentState extends State<TextComponent> with DocumentComponent implements TextComposable {
  final _textKey = GlobalKey<ProseTextState>();

  @visibleForTesting
  ProseTextLayout get textLayout => _textKey.currentState!.textLayout;

  @override
  TextNodePosition? getPositionAtOffset(Offset localOffset) {
    // TODO: Change this implementation to use exact position instead of nearest position
    //       After extracting super_text, looking up the exact offset broke the
    //       ability to tap into empty TextWithHintComponents. To fix this, we
    //       switched to the nearest position. Add a different version of this
    //       API for nearest position and then let clients pick the one that's
    //       right for them.
    final textPosition = textLayout.getPositionNearestToOffset(localOffset);

    return TextNodePosition.fromTextPosition(textPosition);
  }

  @override
  Offset getOffsetForPosition(dynamic nodePosition) {
    if (nodePosition is! TextPosition) {
      throw Exception('Expected nodePosition of type TextPosition but received: $nodePosition');
    }
    return textLayout.getOffsetAtPosition(nodePosition);
  }

  @override
  Rect getEdgeForPosition(NodePosition nodePosition) {
    if (nodePosition is! TextPosition) {
      throw Exception('Expected nodePosition of type TextPosition but received: $nodePosition');
    }

    final textNodePosition = nodePosition as TextPosition;
    final characterBox = getRectForPosition(textNodePosition);

    return textNodePosition.affinity == TextAffinity.upstream ? characterBox.leftEdge : characterBox.rightEdge;
  }

  @override
  Rect getRectForPosition(dynamic nodePosition) {
    if (nodePosition is! TextPosition) {
      throw Exception('Expected nodePosition of type TextPosition but received: $nodePosition');
    }

    final offset = getOffsetForPosition(nodePosition);
    final lineHeight = textLayout.getHeightForCaret(nodePosition) ?? textLayout.getLineHeightAtPosition(nodePosition);
    return Rect.fromLTWH(offset.dx, offset.dy, 0, lineHeight);
  }

  @override
  Rect getRectForSelection(dynamic baseNodePosition, dynamic extentNodePosition) {
    if (baseNodePosition is! TextPosition) {
      throw Exception('Expected nodePosition of type TextPosition but received: $baseNodePosition');
    }
    if (extentNodePosition is! TextPosition) {
      throw Exception('Expected nodePosition of type TextPosition but received: $extentNodePosition');
    }

    final selection = TextSelection(
      baseOffset: baseNodePosition.offset,
      extentOffset: extentNodePosition.offset,
    );

    if (selection.isCollapsed) {
      // A collapsed selection reports no boxes, but we want to return a rect at the
      // selection's x-offset with a height that matches the text. Try to calculate
      // a selection rectangle based on the character that's either after, or before, the
      // collapsed selection position.
      final rectForPosition = getRectForPosition(extentNodePosition);
      if (rectForPosition.height > 0) {
        return rectForPosition;
      }

      TextBox? characterBox = textLayout.getCharacterBox(extentNodePosition);
      if (characterBox != null) {
        final rect = characterBox.toRect();
        return Rect.fromLTWH(rect.left, rect.top, 0, rect.height);
      }

      // We didn't find a character at the given offset. That offset might be at the end
      // of the text. Try looking one character upstream.
      characterBox = extentNodePosition.offset > 0
          ? textLayout.getCharacterBox(TextPosition(offset: extentNodePosition.offset - 1))
          : null;
      if (characterBox != null) {
        final rect = characterBox.toRect();
        // Use the right side of the character because this is the character that appears
        // BEFORE the position we want, which means the position we want is just after
        // this character box.
        return Rect.fromLTWH(rect.right, rect.top, 0, rect.height);
      }

      // We couldn't find a character box, which means the text is empty. Return
      // the caret height, or the estimated line height.
      final caretHeight = textLayout.getHeightForCaret(selection.extent);
      return caretHeight != null
          ? Rect.fromLTWH(0, 0, 0, caretHeight)
          : Rect.fromLTWH(0, 0, 0, textLayout.estimatedLineHeight);
    }

    final boxes = textLayout.getBoxesForSelection(selection);
    Rect boundingBox = boxes.isNotEmpty ? boxes.first.toRect() : Rect.zero;
    for (int i = 1; i < boxes.length; ++i) {
      boundingBox = boundingBox.expandToInclude(boxes[i].toRect());
    }

    return boundingBox;
  }

  @override
  TextNodePosition getBeginningPosition() {
    return const TextNodePosition(offset: 0);
  }

  @override
  TextNodePosition getBeginningPositionNearX(double x) {
    return TextNodePosition.fromTextPosition(
      textLayout.getPositionInFirstLineAtX(x),
    );
  }

  @override
  TextNodePosition? movePositionLeft(NodePosition textPosition, [MovementModifier? movementModifier]) {
    if (textPosition is! TextNodePosition) {
      // We don't know how to interpret a non-text position.
      return null;
    }

    if (textPosition.offset > widget.text.length) {
      // This text position does not represent a position within our text.
      return null;
    }

    if (textPosition.offset == 0) {
      // Can't move any further left.
      return null;
    }

    if (movementModifier == MovementModifier.line) {
      return getPositionAtStartOfLine(
        TextNodePosition(offset: textPosition.offset),
      );
    } else if (movementModifier == MovementModifier.word) {
      final newOffset = getAllText().moveOffsetUpstreamByWord(textPosition.offset);
      if (newOffset == null) {
        return textPosition;
      }

      return TextNodePosition(offset: newOffset);
    } else if (movementModifier == MovementModifier.paragraph) {
      return const TextNodePosition(offset: 0);
    }

    final newOffset = getAllText().moveOffsetUpstreamByCharacter(textPosition.offset);
    return newOffset != null ? TextNodePosition(offset: newOffset) : textPosition;
  }

  @override
  TextNodePosition? movePositionRight(NodePosition textPosition, [MovementModifier? movementModifier]) {
    if (textPosition is! TextNodePosition) {
      // We don't know how to interpret a non-text position.
      return null;
    }

    if (textPosition.offset >= widget.text.length) {
      // Can't move further right.
      return null;
    }

    if (movementModifier == MovementModifier.line) {
      final endOfLine = getPositionAtEndOfLine(
        TextNodePosition(offset: textPosition.offset),
      );

      final TextPosition endPosition = getEndPosition();

      // Note: we compare offset values because we don't care if the affinitys are equal
      final isAutoWrapLine =
          endOfLine.offset != endPosition.offset && (widget.text.toPlainText()[endOfLine.offset] != '\n');

      // Note: For lines that auto-wrap, moving the cursor to `offset` causes the
      //       cursor to jump to the next line because the cursor is placed after
      //       the final selected character. We don't want this, so in this case
      //       we `-1`.
      //
      //       However, if the line that is selected ends with an explicit `\n`,
      //       or if the line is the terminal line for the paragraph then we don't
      //       want to `-1` because that would leave a dangling character after the
      //       selection.
      // TODO: this is the concept of text affinity. Implement support for affinity.
      // TODO: with affinity, ensure it works as expected for right-aligned text
      // TODO: this logic fails for justified text - find a solution for that (#55)
      return isAutoWrapLine
          ? TextNodePosition(offset: endOfLine.offset - 1)
          : TextNodePosition.fromTextPosition(endOfLine);
    }
    if (movementModifier == MovementModifier.word) {
      final newOffset = getAllText().moveOffsetDownstreamByWord(textPosition.offset);
      if (newOffset == null) {
        return textPosition;
      }

      return TextNodePosition(offset: newOffset);
    } else if (movementModifier == MovementModifier.paragraph) {
      return TextNodePosition(offset: getAllText().length);
    }

    final newOffset = getAllText().moveOffsetDownstreamByCharacter(textPosition.offset);
    return newOffset != null ? TextNodePosition(offset: newOffset) : textPosition;
  }

  @override
  TextNodePosition? movePositionUp(NodePosition textNodePosition) {
    if (textNodePosition is! TextNodePosition) {
      // We don't know how to interpret a non-text position.
      return null;
    }

    if (textNodePosition.offset < 0 || textNodePosition.offset > widget.text.length) {
      // This text position does not represent a position within our text.
      return null;
    }

    final positionOneLineUp = getPositionOneLineUp(textNodePosition);
    if (positionOneLineUp == null) {
      return null;
    }
    return TextNodePosition.fromTextPosition(positionOneLineUp);
  }

  @override
  TextNodePosition? movePositionDown(NodePosition textNodePosition) {
    if (textNodePosition is! TextNodePosition) {
      // We don't know how to interpret a non-text position.
      return null;
    }

    if (textNodePosition.offset < 0 || textNodePosition.offset > widget.text.length) {
      // This text position does not represent a position within our text.
      return null;
    }

    final positionOneLineDown = getPositionOneLineDown(textNodePosition);
    if (positionOneLineDown == null) {
      return null;
    }
    return TextNodePosition.fromTextPosition(positionOneLineDown);
  }

  @override
  TextNodePosition getEndPosition() {
    return TextNodePosition(offset: widget.text.length);
  }

  @override
  TextNodePosition getEndPositionNearX(double x) {
    return TextNodePosition.fromTextPosition(textLayout.getPositionInLastLineAtX(x));
  }

  @override
  TextNodeSelection getSelectionInRange(Offset localBaseOffset, Offset localExtentOffset) {
    return TextNodeSelection.fromTextSelection(textLayout.getSelectionInRect(localBaseOffset, localExtentOffset));
  }

  @override
  TextNodeSelection getCollapsedSelectionAt(NodePosition textNodePosition) {
    if (textNodePosition is! TextNodePosition) {
      throw Exception('The given node position ($textNodePosition) is not compatible with TextComponent');
    }

    return TextNodeSelection.collapsed(offset: textNodePosition.offset);
  }

  @override
  TextNodeSelection getSelectionBetween({
    required NodePosition basePosition,
    required NodePosition extentPosition,
  }) {
    if (basePosition is! TextNodePosition) {
      throw Exception('Expected a basePosition of type TextNodePosition but received: $basePosition');
    }
    if (extentPosition is! TextNodePosition) {
      throw Exception('Expected an extentPosition of type TextNodePosition but received: $extentPosition');
    }

    return TextNodeSelection(
      baseOffset: basePosition.offset,
      extentOffset: extentPosition.offset,
    );
  }

  @override
  TextNodeSelection getSelectionOfEverything() {
    return TextNodeSelection(
      baseOffset: 0,
      extentOffset: widget.text.length,
    );
  }

  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) {
    return textLayout.isTextAtOffset(localOffset) ? SystemMouseCursors.text : null;
  }

  @override
  String getAllText() {
    return widget.text.toPlainText();
  }

  @override
  String getContiguousTextAt(TextNodePosition textPosition) {
    return getContiguousTextSelectionAt(textPosition).textInside(widget.text.toPlainText());
  }

  @override
  TextNodeSelection getWordSelectionAt(TextNodePosition textPosition) {
    return TextNodeSelection.fromTextSelection(
      textLayout.getWordSelectionAt(textPosition),
    );
  }

  @override
  TextNodeSelection getContiguousTextSelectionAt(TextNodePosition textPosition) {
    final text = widget.text.toPlainText();
    if (text.isEmpty) {
      return const TextNodeSelection.collapsed(offset: -1);
    }

    int start = min(textPosition.offset, text.length - 1);
    int end = min(textPosition.offset, text.length - 1);
    while (start > 0 && text[start - 1] != '\n') {
      start -= 1;
    }
    while (end < text.length && text[end] != '\n') {
      end += 1;
    }
    return TextNodeSelection(
      baseOffset: start,
      extentOffset: end,
    );
  }

  @override
  TextNodePosition? getPositionOneLineUp(NodePosition textPosition) {
    if (textPosition is! TextNodePosition) {
      throw Exception('Expected position of type NodePosition but received ${textPosition.runtimeType}');
    }

    final positionOneLineUp = textLayout.getPositionOneLineUp(textPosition);
    if (positionOneLineUp == null) {
      return null;
    }
    return TextNodePosition.fromTextPosition(positionOneLineUp);
  }

  @override
  TextNodePosition? getPositionOneLineDown(NodePosition textPosition) {
    if (textPosition is! TextNodePosition) {
      throw Exception('Expected position of type NodePosition but received ${textPosition.runtimeType}');
    }

    final positionOneLineDown = textLayout.getPositionOneLineDown(textPosition);
    if (positionOneLineDown == null) {
      return null;
    }
    return TextNodePosition.fromTextPosition(positionOneLineDown);
  }

  @override
  TextNodePosition getPositionAtEndOfLine(TextNodePosition textPosition) {
    return TextNodePosition.fromTextPosition(
      textLayout.getPositionAtEndOfLine(textPosition),
    );
  }

  @override
  TextNodePosition getPositionAtStartOfLine(TextNodePosition textNodePosition) {
    return TextNodePosition.fromTextPosition(
      textLayout.getPositionAtStartOfLine(textNodePosition),
    );
  }

  /// Return the [TextStyle] for the character at [offset].
  ///
  /// If the caret sits at the beginning of the text, the style
  /// of the first character is returned.
  ///
  /// If the caret sits at the end of the text, the style
  /// of the last character is returned.
  ///
  /// If the text is empty, the style computed by the widget's `textStyleBuilder`
  /// without any attributions is returned.
  TextStyle getTextStyleAt(int offset) {
    final attributions = widget.text.getAllAttributionsAt(offset < widget.text.length //
        ? offset
        : widget.text.length - 1);

    return _textStyleWithBlockType(attributions);
  }

  TextAlign? get textAlign => widget.textAlign;

  TextDirection? get textDirection => widget.textDirection;

  @override
  Widget build(BuildContext context) {
    editorLayoutLog.finer('Building a TextComponent with key: ${widget.key}');

    return IgnorePointer(
      child: SuperText(
        key: _textKey,
        richText: widget.text.computeInlineSpan(
          context,
          _textStyleWithBlockType,
          widget.inlineWidgetBuilders,
        ),
        textAlign: widget.textAlign ?? TextAlign.left,
        textDirection: widget.textDirection ?? TextDirection.ltr,
        textScaler: widget.textScaler ?? MediaQuery.textScalerOf(context),
        layerBeneathBuilder: (context, textLayout) {
          return Stack(
            children: [
              // Selection highlight beneath the text.
              if (widget.text.length > 0)
                TextLayoutSelectionHighlight(
                  textLayout: textLayout,
                  style: SelectionHighlightStyle(
                    color: widget.selectionColor,
                  ),
                  selection: widget.textSelection ?? const TextSelection.collapsed(offset: -1),
                )
              else if (widget.highlightWhenEmpty)
                TextLayoutEmptyHighlight(
                  textLayout: textLayout,
                  style: SelectionHighlightStyle(
                    color: widget.selectionColor,
                  ),
                ),
              for (final underlines in widget.underlines)
                TextUnderlineLayer(
                  textLayout: textLayout,
                  style: underlines.style,
                  underlines: [
                    for (final range in underlines.underlines) //
                      TextLayoutUnderline(range: range),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  /// Creates a `TextStyle` based on the given [attributions], plus any
  /// "block type" that's specified in [widget.metadata].
  TextStyle _textStyleWithBlockType(Set<Attribution> attributions) {
    final attributionsWithBlockType = Set<Attribution>.from(attributions);
    Attribution? blockType = widget.metadata['blockType'];
    if (blockType != null) {
      attributionsWithBlockType.add(blockType);
    }

    return widget.textStyleBuilder(attributionsWithBlockType);
  }
}

/// The default priority list of inline widget builders, which map [AttributedText]
/// placeholders to widgets.
const defaultInlineWidgetBuilderChain = [
  inlineNetworkImageBuilder,
  inlineAssetImageBuilder,
];

/// An inline widget builder that displays an image from the network.
Widget? inlineNetworkImageBuilder(BuildContext context, TextStyle textStyle, Object placeholder) {
  if (placeholder is! InlineNetworkImagePlaceholder) {
    return null;
  }

  return LineHeight(
    style: textStyle,
    child: Image.network(placeholder.url),
  );
}

/// An inline widget builder that displays an image from local assets.
Widget? inlineAssetImageBuilder(BuildContext context, TextStyle textStyle, Object placeholder) {
  if (placeholder is! InlineAssetImagePlaceholder) {
    return null;
  }

  return LineHeight(
    style: textStyle,
    child: Image.asset(placeholder.assetPath),
  );
}

/// A widget that sets its [child]'s height to the line-height of a given text [style].
class LineHeight extends StatefulWidget {
  const LineHeight({
    super.key,
    required this.style,
    required this.child,
  });

  final TextStyle style;
  final Widget child;

  @override
  State<LineHeight> createState() => _LineHeightState();
}

class _LineHeightState extends State<LineHeight> {
  late double _lineHeight;

  @override
  void initState() {
    super.initState();
    _calculateLineHeight();
  }

  @override
  void didUpdateWidget(LineHeight oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.style != oldWidget.style) {
      _calculateLineHeight();
    }
  }

  void _calculateLineHeight() {
    final textPainter = TextPainter(
      text: TextSpan(text: "a", style: widget.style),
      textDirection: TextDirection.ltr,
    )..layout();

    _lineHeight = textPainter.height;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _lineHeight,
      child: widget.child,
    );
  }
}

/// A widget that sets its [child]'s width and height to the line-height of a
/// given text [style].
class LineHeightSquare extends StatefulWidget {
  const LineHeightSquare({
    super.key,
    required this.style,
    required this.child,
  });

  final TextStyle style;
  final Widget child;

  @override
  State<LineHeightSquare> createState() => _LineHeightSquareState();
}

class _LineHeightSquareState extends State<LineHeightSquare> {
  late double _lineHeight;

  @override
  void initState() {
    super.initState();
    _calculateLineHeight();
  }

  @override
  void didUpdateWidget(LineHeightSquare oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.style != oldWidget.style) {
      _calculateLineHeight();
    }
  }

  void _calculateLineHeight() {
    final textPainter = TextPainter(
      text: TextSpan(text: "a", style: widget.style),
      textDirection: TextDirection.ltr,
    )..layout();

    _lineHeight = textPainter.height;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _lineHeight,
      height: _lineHeight,
      child: widget.child,
    );
  }
}

/// A [ProxyDocumentComponent] that adds [TextComposable] capabilities so
/// that simple text-based proxy components can meet their expected contract
/// without going through the work of defining a stateful widget that mixes in
/// the [ProxyDocumentComponent] methods.
///
/// Using a [ProxyTextDocumentComponent] is never technically necessary.
/// Custom [DocumentComponent]s can achieve a similar result by mixing in
/// [ProxyDocumentComponent] within a `State` object. This widget is provided
/// as a convenience so that some components can be defined as stateless
/// widgets while still providing access to component behaviors and text layout queries.
class ProxyTextDocumentComponent extends StatefulWidget {
  const ProxyTextDocumentComponent({
    super.key,
    required this.textComponentKey,
    required this.child,
  });

  final GlobalKey textComponentKey;

  /// The widget subtree, which must include a widget that implements `TextComposable`,
  /// and that `TextComposable` must be bound to the given [textComponentKey].
  final Widget child;

  @override
  State<ProxyTextDocumentComponent> createState() => _ProxyTextDocumentComponentState();
}

class _ProxyTextDocumentComponentState extends State<ProxyTextDocumentComponent>
    with ProxyDocumentComponent<ProxyTextDocumentComponent>, ProxyTextComposable {
  @override
  GlobalKey<State<StatefulWidget>> get childDocumentComponentKey => widget.textComponentKey;

  @override
  TextComposable get childTextComposable => childDocumentComponentKey.currentState as TextComposable;

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// A group of text ranges that should be displayed with underlines, along with the [style]
/// of those underlines.
class Underlines {
  const Underlines({
    required this.style,
    required this.underlines,
  });

  final UnderlineStyle style;
  final List<TextRange> underlines;
}

class AddTextAttributionsRequest implements EditRequest {
  AddTextAttributionsRequest({
    required this.documentRange,
    required this.attributions,
    this.autoMerge = true,
  });

  final DocumentRange documentRange;
  final Set<Attribution> attributions;
  final bool autoMerge;
}

// TODO: the add/remove/toggle commands are almost identical except for what they
//       do to ranges of text. Pull out the common range calculation behavior.
/// Applies the given `attributions` to the given `documentSelection`.
class AddTextAttributionsCommand extends EditCommand {
  AddTextAttributionsCommand({
    required this.documentRange,
    required this.attributions,
    this.autoMerge = true,
  });

  final DocumentRange documentRange;
  final Set<Attribution> attributions;
  final bool autoMerge;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    editorDocLog.info('Executing AddTextAttributionsCommand');
    final document = context.document;
    final nodes = document.getNodesInside(documentRange.start, documentRange.end);
    if (nodes.isEmpty) {
      editorDocLog.shout(' - Bad DocumentSelection. Could not get range of nodes. Selection: $documentRange');
      return;
    }

    // Calculate a normalized DocumentRange so we know which DocumentPosition
    // belongs to the first node, and which belongs to the last node.
    final normalRange = documentRange.normalize(document);
    editorDocLog.info(' - node range: $normalRange');

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
        editorDocLog.info(' - the selection is within a single node: ${textNode.id}');

        startOffset = (normalRange.start.nodePosition as TextPosition).offset;

        // -1 because TextPosition's offset indexes the character after the
        // selection, not the final character in the selection.
        endOffset = (normalRange.end.nodePosition as TextPosition).offset - 1;
      } else if (textNode == nodes.first) {
        // Handle partial node selection in first node.
        editorDocLog.info(' - selecting part of the first node: ${textNode.id}');
        startOffset = (normalRange.start.nodePosition as TextPosition).offset;
        endOffset = max(textNode.text.length - 1, 0);
      } else if (textNode == nodes.last) {
        // Handle partial node selection in last node.
        editorDocLog.info(' - adding part of the last node: ${textNode.id}');
        startOffset = 0;

        // -1 because TextPosition's offset indexes the character after the
        // selection, not the final character in the selection.
        endOffset = (normalRange.end.nodePosition as TextPosition).offset - 1;
      } else {
        // Handle full node selection.
        editorDocLog.info(' - adding full node: ${textNode.id}');
        startOffset = 0;
        endOffset = max(textNode.text.length - 1, 0);
      }

      final selectionRange = TextRange(start: startOffset, end: endOffset);

      nodesAndSelections.putIfAbsent(textNode, () => selectionRange);
    }

    // Add attributions.
    for (final entry in nodesAndSelections.entries) {
      for (Attribution attribution in attributions) {
        final node = entry.key;
        final range = entry.value.toSpanRange();
        editorDocLog.info(' - adding attribution: $attribution. Range: $range');

        // Create a new AttributedText with updated attribution spans, so that the presentation system can
        // see that we made a change, and re-renders the text in the document.
        document.replaceNodeById(
          node.id,
          node.copyTextNodeWith(
            text: AttributedText(
              node.text.toPlainText(),
              node.text.spans.copy()
                ..addAttribution(
                  newAttribution: attribution,
                  start: range.start,
                  end: range.end,
                  autoMerge: autoMerge,
                ),
              Map.from(node.text.placeholders),
            ),
          ),
        );

        executor.logChanges([
          DocumentEdit(
            AttributionChangeEvent(
              nodeId: node.id,
              change: AttributionChange.added,
              range: range,
              attributions: attributions,
            ),
          ),
        ]);
      }
    }

    editorDocLog.info(' - done adding attributions');
  }
}

class RemoveTextAttributionsRequest implements EditRequest {
  RemoveTextAttributionsRequest({
    required this.documentRange,
    required this.attributions,
  });

  final DocumentRange documentRange;
  final Set<Attribution> attributions;
}

/// Removes the given `attributions` from the given `documentSelection`.
class RemoveTextAttributionsCommand extends EditCommand {
  RemoveTextAttributionsCommand({
    required this.documentRange,
    required this.attributions,
  });

  final DocumentRange documentRange;
  final Set<Attribution> attributions;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    editorDocLog.info('Executing RemoveTextAttributionsCommand');
    final document = context.document;
    final nodes = document.getNodesInside(documentRange.start, documentRange.end);
    if (nodes.isEmpty) {
      editorDocLog.shout(' - Bad DocumentSelection. Could not get range of nodes. Selection: $documentRange');
      return;
    }

    // Normalize the DocumentRange so we know which DocumentPosition
    // belongs to the first node, and which belongs to the last node.
    final normalizedRange = documentRange.normalize(document);
    editorDocLog.info(' - node range: $normalizedRange');

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
        editorDocLog.info(' - the selection is within a single node: ${textNode.id}');

        startOffset = (normalizedRange.start.nodePosition as TextPosition).offset;

        endOffset = normalizedRange.start != normalizedRange.end
            // -1 because TextPosition's offset indexes the character after the
            // selection, not the final character in the selection.
            ? (normalizedRange.end.nodePosition as TextPosition).offset - 1
            // The selection is collapsed. Don't decrement the offset.
            : startOffset;
      } else if (textNode == nodes.first) {
        // Handle partial node selection in first node.
        editorDocLog.info(' - selecting part of the first node: ${textNode.id}');
        startOffset = (normalizedRange.start.nodePosition as TextPosition).offset;
        endOffset = max(textNode.text.length - 1, 0);
      } else if (textNode == nodes.last) {
        // Handle partial node selection in last node.
        editorDocLog.info(' - adding part of the last node: ${textNode.id}');
        startOffset = 0;

        // -1 because TextPosition's offset indexes the character after the
        // selection, not the final character in the selection.
        endOffset = (normalizedRange.end.nodePosition as TextPosition).offset - 1;
      } else {
        // Handle full node selection.
        editorDocLog.info(' - adding full node: ${textNode.id}');
        startOffset = 0;
        endOffset = max(textNode.text.length - 1, 0);
      }

      final selectionRange = TextRange(start: startOffset, end: endOffset);

      nodesAndSelections.putIfAbsent(textNode, () => selectionRange);
    }

    // Remove attributions.
    for (final entry in nodesAndSelections.entries) {
      var node = entry.key;
      final range = entry.value.toSpanRange();

      for (Attribution attribution in attributions) {
        editorDocLog.info(' - removing attribution: $attribution. Range: $range');

        // Create a new AttributedText with updated attribution spans, so that the presentation system can
        // see that we made a change, and re-renders the text in the document.
        node = node.copyTextNodeWith(
          text: AttributedText(
            node.text.toPlainText(),
            node.text.spans.copy()
              ..removeAttribution(
                attributionToRemove: attribution,
                start: range.start,
                end: range.end,
              ),
          ),
        );

        executor.logChanges([
          DocumentEdit(
            AttributionChangeEvent(
              nodeId: node.id,
              change: AttributionChange.removed,
              range: range,
              attributions: attributions,
            ),
          ),
        ]);
      }

      // Now that attribution changes are done for the given node, replace
      // the existing document node with the updated node.
      document.replaceNodeById(node.id, node);
    }

    editorDocLog.info(' - done adding attributions');
  }
}

class ToggleTextAttributionsRequest implements EditRequest {
  ToggleTextAttributionsRequest({
    required this.documentRange,
    required this.attributions,
  });

  final DocumentRange documentRange;
  final Set<Attribution> attributions;
}

/// Applies the given `attributions` to the given `documentSelection`,
/// if none of the content in the selection contains any of the
/// given `attributions`. Otherwise, all the given `attributions`
/// are removed from the content within the `documentSelection`.
class ToggleTextAttributionsCommand extends EditCommand {
  ToggleTextAttributionsCommand({
    required this.documentRange,
    required this.attributions,
  });

  final DocumentRange documentRange;
  final Set<Attribution> attributions;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  // TODO: The structure of this command looks nearly identical to the two other attribution
  // commands above. We collect nodes and then we loop through them to apply an operation.
  // Try to de-dup this code. Maybe use a private base class called ChangeTextAttributionsCommand
  // and provide a hook for the specific operation: add, remove, toggle.
  @override
  void execute(EditContext context, CommandExecutor executor) {
    editorDocLog.info('Executing ToggleTextAttributionsCommand');
    final document = context.document;
    final nodes = document.getNodesInside(documentRange.start, documentRange.end);
    if (nodes.isEmpty) {
      editorDocLog.shout(' - Bad DocumentSelection. Could not get range of nodes. Selection: $documentRange');
      return;
    }

    // Normalize DocumentRange so we know which DocumentPosition
    // belongs to the first node, and which belongs to the last node.
    final normalizedRange = documentRange.normalize(document);
    editorDocLog.info(' - node range: $normalizedRange');

    // ignore: prefer_collection_literals
    final nodesAndSelections = LinkedHashMap<TextNode, SpanRange>();

    bool alreadyHasAttributions = true;

    for (final textNode in nodes) {
      if (textNode is! TextNode) {
        continue;
      }

      int startOffset = -1;
      int endOffset = -1;

      if (textNode == nodes.first && textNode == nodes.last) {
        // Handle selection within a single node
        editorDocLog.info(' - the selection is within a single node: ${textNode.id}');

        startOffset = (normalizedRange.start.nodePosition as TextPosition).offset;

        // -1 because TextPosition's offset indexes the character after the
        // selection, not the final character in the selection.
        endOffset = (normalizedRange.end.nodePosition as TextPosition).offset - 1;
      } else if (textNode == nodes.first) {
        // Handle partial node selection in first node.
        editorDocLog.info(' - selecting part of the first node: ${textNode.id}');
        startOffset = (normalizedRange.start.nodePosition as TextPosition).offset;
        endOffset = max(textNode.text.length - 1, 0);

        if (startOffset >= textNode.text.length) {
          // The range spans multiple nodes, starting at the end of the first node of the
          // range. From the first node's perspective, this is equivalent to a collapsed
          // selection at the end of the node. There's no text to toggle any attributions.
          // Skip this node.
          continue;
        }
      } else if (textNode == nodes.last) {
        // Handle partial node selection in last node.
        editorDocLog.info(' - toggling part of the last node: ${textNode.id}');
        startOffset = 0;

        // -1 because TextPosition's offset indexes the character after the
        // selection, not the final character in the selection.
        endOffset = (normalizedRange.end.nodePosition as TextPosition).offset - 1;

        if (endOffset <= 0) {
          // The range spans multiple nodes, ending at the beginning of the last node of the
          // range. From the last node's perspective, this is equivalent to a collapsed
          // selection at the beginning of the node. There's no text to toggle any attributions.
          // Skip this node.
          continue;
        }
      } else {
        // Handle full node selection.
        editorDocLog.info(' - toggling full node: ${textNode.id}');
        startOffset = 0;
        endOffset = max(textNode.text.length - 1, 0);
      }

      final selectionRange = SpanRange(startOffset, endOffset);

      alreadyHasAttributions = alreadyHasAttributions &&
          textNode.text.hasAttributionsThroughout(
            attributions: attributions,
            range: selectionRange,
          );

      nodesAndSelections.putIfAbsent(textNode, () => selectionRange);
    }

    for (final entry in nodesAndSelections.entries) {
      var node = entry.key;
      final range = entry.value;

      for (Attribution attribution in attributions) {
        editorDocLog.info(' - toggling attribution: $attribution. Range: $range');

        if (alreadyHasAttributions) {
          // Attribution is present throughout the user selection. Remove attribution.
          editorDocLog.info(' - Removing attribution: $attribution. Range: $range');

          // Create a new AttributedText with updated attribution spans, so that the presentation system can
          // see that we made a change, and re-renders the text in the document.
          node = node.copyTextNodeWith(
            text: node.text.copy() //
              ..removeAttribution(
                attribution,
                range,
              ),
          );
        } else {
          // Attribution isn't present throughout the user selection. Apply attribution.
          editorDocLog.info(' - Adding attribution: $attribution. Range: $range');

          // Create a new AttributedText with updated attribution spans, so that the presentation system can
          // see that we made a change, and re-renders the text in the document.
          node = node.copyTextNodeWith(
            text: node.text.copy() //
              ..addAttribution(
                attribution,
                range,
                autoMerge: true,
                // FIXME: I noticed that the default value for overwriteConflictingSpans on
                //        AttributedText.addAttribution is `false`, but the default on AttributedSpans.addAttribution()
                //        is `true`. This seems like a likely bug. Should they actually be different? If not,
                //        update one of them. If so, add a comment to both places mentioning why.
                overwriteConflictingSpans: true,
              ),
          );
        }

        final wasAttributionAdded = node.text.hasAttributionAt(range.start, attribution: attribution);
        executor.logChanges([
          DocumentEdit(
            AttributionChangeEvent(
              nodeId: node.id,
              change: wasAttributionAdded ? AttributionChange.added : AttributionChange.removed,
              range: range,
              attributions: attributions,
            ),
          ),
        ]);
      }

      // Now that all attributions have been applied to the node, replace the
      // old node in the Document with the updated node.
      document.replaceNodeById(node.id, node);
    }

    editorDocLog.info(' - done toggling attributions');
  }
}

/// A [NodeChangeEvent] for the addition or removal of a set of attributions.
class AttributionChangeEvent extends NodeChangeEvent {
  AttributionChangeEvent({
    required String nodeId,
    required this.change,
    required this.range,
    required this.attributions,
  }) : super(nodeId);

  final AttributionChange change;
  final SpanRange range;
  final Set<Attribution> attributions;

  @override
  String describe() =>
      "${change == AttributionChange.added ? "Added" : "Removed"} attributions ($nodeId) - ${range.start} -> ${range.end}: $attributions";

  @override
  String toString() => "AttributionChangeEvent ('$nodeId' - ${range.start} -> ${range.end} ($change): '$attributions')";

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is AttributionChangeEvent &&
          runtimeType == other.runtimeType &&
          change == other.change &&
          range == other.range &&
          const DeepCollectionEquality().equals(attributions, other.attributions);

  @override
  int get hashCode => super.hashCode ^ change.hashCode ^ range.hashCode ^ attributions.hashCode;
}

enum AttributionChange {
  added,
  removed;
}

/// Changes layout styles, like padding and width, of a component within a [SingleColumnDocumentLayout].
class ChangeSingleColumnLayoutComponentStylesRequest implements EditRequest {
  const ChangeSingleColumnLayoutComponentStylesRequest({
    required this.nodeId,
    required this.styles,
  });

  final String nodeId;
  final SingleColumnLayoutComponentStyles styles;
}

class ChangeSingleColumnLayoutComponentStylesCommand extends EditCommand {
  ChangeSingleColumnLayoutComponentStylesCommand({
    required this.nodeId,
    required this.styles,
  });

  final String nodeId;
  final SingleColumnLayoutComponentStyles styles;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;
    final node = document.getNodeById(nodeId)!;

    document.replaceNodeById(
      nodeId,
      node.copyWithAddedMetadata(styles.toMetadata()),
    );

    executor.logChanges([
      DocumentEdit(
        NodeChangeEvent(node.id),
      ),
    ]);
  }
}

/// A request to insert the given [plainText] at the current caret position.
///
/// If the base of the selection isn't a [TextNode], this request does nothing.
///
/// If the selection is expanded, the selected content is deleted.
///
/// If the [plainText] contains any newlines, those newlines will be inserted
/// as characters. This request doesn't insert any new nodes.
class InsertPlainTextAtCaretRequest implements EditRequest {
  const InsertPlainTextAtCaretRequest(this.plainText);

  final String plainText;
}

class InsertPlainTextAtCaretCommand extends EditCommand {
  const InsertPlainTextAtCaretCommand(
    this.plainText, {
    this.attributions = const {},
  });

  final String plainText;
  final Set<Attribution> attributions;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final selection = context.composer.selection;
    if (selection == null) {
      // Can't insert at caret if there is no caret.
      return;
    }
    final range = selection.normalize(context.document);
    if (range.start.nodePosition is! TextNodePosition) {
      // The effective insertion position isn't a TextNode. Fizzle.
      return;
    }

    if (!range.isCollapsed) {
      executor.executeCommand(
        DeleteContentCommand(documentRange: range),
      );
    }

    executor.executeCommand(
      InsertTextCommand(
        documentPosition: range.start,
        textToInsert: plainText,
        attributions: attributions,
      ),
    );
  }
}

class InsertTextRequest implements EditRequest {
  InsertTextRequest({
    required this.documentPosition,
    required this.textToInsert,
    required this.attributions,
  }) : assert(documentPosition.nodePosition is TextPosition);

  final DocumentPosition documentPosition;
  final String textToInsert;
  final Set<Attribution> attributions;
}

class InsertTextCommand extends EditCommand {
  InsertTextCommand({
    required this.documentPosition,
    required this.textToInsert,
    required this.attributions,
  }) : assert(documentPosition.nodePosition is TextPosition);

  final DocumentPosition documentPosition;
  final String textToInsert;
  final Set<Attribution> attributions;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  String describe() =>
      "Insert text - ${documentPosition.nodeId} @ ${(documentPosition.nodePosition as TextNodePosition).offset} - '$textToInsert'";

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;

    var textNode = document.getNodeById(documentPosition.nodeId);
    if (textNode is! TextNode) {
      editorDocLog.shout('ERROR: can\'t insert text in a node that isn\'t a TextNode: $textNode');
      return;
    }

    final textPosition = documentPosition.nodePosition as TextPosition;
    final textOffset = textPosition.offset;

    textNode = textNode.copyTextNodeWith(
      text: textNode.text.insertString(
        textToInsert: textToInsert,
        startOffset: textOffset,
        applyAttributions: attributions,
      ),
    );
    document.replaceNodeById(
      textNode.id,
      textNode,
    );

    executor.logChanges([
      DocumentEdit(
        TextInsertionEvent(
          nodeId: textNode.id,
          offset: textOffset,
          text: AttributedText(textToInsert),
        ),
      ),
    ]);

    executor.executeCommand(
      ChangeSelectionCommand(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: document.getPathByNodeId(textNode.id)!,
            nodePosition: TextNodePosition(
              offset: textOffset + textToInsert.length,
              affinity: textPosition.affinity,
            ),
          ),
        ),
        SelectionChangeType.insertContent,
        SelectionReason.userInteraction,
        notifyListeners: false,
      ),
    );
  }
}

class TextInsertionEvent extends NodeChangeEvent {
  TextInsertionEvent({
    required String nodeId,
    required this.offset,
    required this.text,
  }) : super(nodeId);

  final int offset;
  final AttributedText text;

  @override
  String describe() => "Inserted text ($nodeId) @ $offset: '${text.toPlainText()}'";

  @override
  String toString() => "TextInsertionEvent ('$nodeId' - $offset -> '${text.toPlainText()}')";

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is TextInsertionEvent &&
          runtimeType == other.runtimeType &&
          offset == other.offset &&
          text == other.text;

  @override
  int get hashCode => super.hashCode ^ offset.hashCode ^ text.hashCode;
}

class TextDeletedEvent extends NodeChangeEvent {
  const TextDeletedEvent(
    String nodeId, {
    required this.offset,
    required this.deletedText,
  }) : super(nodeId);

  final int offset;
  final AttributedText deletedText;

  @override
  String describe() => "Deleted text ($nodeId) @ $offset: ${deletedText.toPlainText()}";

  @override
  String toString() => "TextDeletedEvent ('$nodeId' - $offset -> '${deletedText.toPlainText()}')";

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is TextDeletedEvent &&
          runtimeType == other.runtimeType &&
          offset == other.offset &&
          deletedText == other.deletedText;

  @override
  int get hashCode => super.hashCode ^ offset.hashCode ^ deletedText.hashCode;
}

/// A request to insert a newline at the current caret position.
///
/// The specific action taken depends on the type of content where the caret sits.
/// This request might be routed to different [EditCommand]s based on that position.
///
/// Regardless of how the newline is handled, if the selection is expanded, that
/// selection is deleted before inserting the newline.
class InsertNewlineAtCaretRequest implements EditRequest {
  InsertNewlineAtCaretRequest([String? newNodeId]) {
    // We let callers avoid giving us a `newNodeId`, if desired, because
    // callers may not understand that this ID is for undo/redo. Also,
    // callers may not be sure what value they're supposed to provide.
    // So if we don't get one, we create one.
    this.newNodeId = newNodeId ?? Editor.createNodeId();
  }

  /// {@template newNodeId}
  /// The ID to use for a new node, if a new node is created.
  ///
  /// This information is required so that undo/redo works. When requests
  /// are re-run, they need to use the same node IDs, so that following
  /// requests can repeat edits on those same nodes.
  /// {@endtemplate}
  late final String newNodeId;
}

/// An [EditCommand] that inserts a newline when the caret sits within a code block.
///
/// This command adds the following behaviors beyond the usual:
///  * When the caret is in the middle of a code block, a soft newline is inserted within
///    the code block instead of splitting the node.
///
///  * When the caret is at the end of a code block without a soft newline, inserts
///    a soft newline, so that users can keep writing more code in a code block.
///
///  * When the caret sits after an existing soft newline, deletes the soft newline
///    and inserts a new empty paragraph below the code block.
class InsertNewlineInCodeBlockAtCaretCommand extends BaseInsertNewlineAtCaretCommand {
  const InsertNewlineInCodeBlockAtCaretCommand(this.newNodeId);

  /// {@macro newNodeId}
  final String newNodeId;

  @override
  void doInsertNewline(
    EditContext context,
    CommandExecutor executor,
    DocumentPosition caretPosition,
    NodePosition caretNodePosition,
  ) {
    final node = context.document.getNodeById(caretPosition.nodeId);
    if (node is! TextNode || caretNodePosition is! TextNodePosition) {
      return;
    }
    if (node.metadata[NodeMetadata.blockType] != codeAttribution) {
      return;
    }

    // When inserting a newline in the middle of a code block, the
    // newline should be inserted within the code block, without
    // breaking the node into two.
    //
    // When inserting a newline at the end of a code block, immediately
    // after some content, the newline should appear within the code block.
    //
    // When inserting a newline after another newline, the existing
    // newline should be removed from the code block, and a new paragraph
    // should be inserted below the code block.
    final document = context.document;
    if (caretNodePosition.offset == node.text.length && node.text.last == "\n") {
      // The caret is at the end of a code block, following another newline.
      // Remove the existing newline.
      executor
        ..executeCommand(
          ReplaceNodeCommand(
            existingNodeId: node.id,
            newNode: node.copyTextNodeWith(
              text: node.text.removeRegion(
                startOffset: node.text.length - 1,
                endOffset: node.text.length,
              ),
            ),
          ),
        )
        // Insert a new empty paragraph after the code block.
        ..executeCommand(
          InsertNodeAfterNodeCommand(
            existingNodeId: node.id,
            newNode: ParagraphNode(
              id: newNodeId,
              text: AttributedText(),
            ),
          ),
        )
        ..executeCommand(
          ChangeSelectionCommand(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                documentPath: document.getPathByNodeId(newNodeId)!,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
            SelectionChangeType.insertContent,
            SelectionReason.userInteraction,
          ),
        );
    } else {
      // Insert a newline within the code block.
      executor.executeCommand(
        InsertTextCommand(
          documentPosition: DocumentPosition(
            documentPath: document.getPathByNodeId(node.id)!,
            nodePosition: node.endPosition,
          ),
          textToInsert: "\n",
          attributions: {},
        ),
      );
    }
  }
}

/// An [EditCommand] that handles a typical newline insertion.
///
/// If [documentSelection] is expanded, the selected content is first deleted.
/// The remaining behavior is then guaranteed to apply to a caret offset.
///
/// Newline insertion operates as follows:
///
///  * Caret in the middle of a paragraph, the paragraph is split in two, with
///    the same metadata applied to both paragraphs.
///
///  * Caret at the end of a paragraph, a new paragraph is inserted after the
///    current paragraph, using a standard "paragraph" block type.
///
///  * Caret on the leading edge of a block node, an empty paragraph is inserted
///    before the block node.
///
///  * Caret on the trailing edge of a block node, an empty paragraph is inserted
///    after the block node.
class DefaultInsertNewlineAtCaretCommand extends BaseInsertNewlineAtCaretCommand {
  const DefaultInsertNewlineAtCaretCommand(this.newNodeId);

  /// {@macro newNodeId}
  final String newNodeId;

  @override
  void doInsertNewline(
    EditContext context,
    CommandExecutor executor,
    DocumentPosition caretPosition,
    NodePosition caretNodePosition,
  ) {
    if (caretNodePosition is! UpstreamDownstreamNodePosition && caretNodePosition is! TextNodePosition) {
      // We don't know how to deal with this kind of node.
      return;
    }

    if (caretNodePosition is UpstreamDownstreamNodePosition) {
      // The caret is sitting at the edge of an upstream/downstream node.
      _insertNewlineInBinaryNode(context, executor, caretPosition, caretNodePosition);
      return;
    }

    final node = context.document.getNodeById(caretPosition.nodeId);
    if (caretNodePosition is TextNodePosition && node is TextNode) {
      _insertNewlineInTextNode(context, executor, node, caretPosition, caretNodePosition);
      return;
    }
  }

  void _insertNewlineInBinaryNode(
    EditContext context,
    CommandExecutor executor,
    DocumentPosition caretPosition,
    UpstreamDownstreamNodePosition caretNodePosition,
  ) {
    if (caretNodePosition.affinity == TextAffinity.upstream) {
      // Insert an empty paragraph before the block node.
      executor
        ..executeCommand(
          InsertNodeBeforeNodeCommand(
            existingNodeId: caretPosition.nodeId,
            newNode: ParagraphNode(
              id: newNodeId,
              text: AttributedText(),
            ),
          ),
        )
        ..executeCommand(
          ChangeSelectionCommand(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                documentPath: context.document.getPathByNodeId(newNodeId)!,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
            SelectionChangeType.insertContent,
            SelectionReason.userInteraction,
          ),
        );
    } else {
      // Insert an empty paragraph after the block node.
      executor
        ..executeCommand(
          InsertNodeAfterNodeCommand(
            existingNodeId: caretPosition.nodeId,
            newNode: ParagraphNode(
              id: newNodeId,
              text: AttributedText(),
            ),
          ),
        )
        ..executeCommand(
          ChangeSelectionCommand(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                documentPath: context.document.getPathByNodeId(newNodeId)!,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
            SelectionChangeType.insertContent,
            SelectionReason.userInteraction,
          ),
        );
    }
  }

  void _insertNewlineInTextNode(
    EditContext context,
    CommandExecutor executor,
    TextNode textNode,
    DocumentPosition caretPosition,
    TextNodePosition caretTextPosition,
  ) {
    // Split the paragraph into two. This includes headers, blockquotes, and
    // any other block-level paragraph.
    final endOfParagraph = textNode.endPosition;

    editorOpsLog.finer("Splitting paragraph in two.");
    executor
      ..executeCommand(
        SplitParagraphCommand(
          nodeId: caretPosition.nodeId,
          splitPosition: caretTextPosition,
          newNodeId: newNodeId,
          replicateExistingMetadata: caretTextPosition.offset != endOfParagraph.offset,
        ),
      )
      ..executeCommand(
        // Place the caret at the beginning of the new node.
        ChangeSelectionCommand(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              documentPath: context.document.getPathByNodeId(newNodeId)!,
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.insertContent,
          SelectionReason.userInteraction,
        ),
      );
  }
}

/// An abstract [EditCommand] that does some common accounting that's useful for various
/// implementations of commands that insert newlines.
///
/// Before delegating execution to subclasses, this base command fizzles if the selection
/// is `null`. It also deletes selected content, if the selection is expanded. After that,
/// subclasses receive the `non-null` caret position for easier processing.
abstract class BaseInsertNewlineAtCaretCommand extends EditCommand {
  const BaseInsertNewlineAtCaretCommand();

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final documentSelection = context.composer.selection;
    if (documentSelection == null) {
      return;
    }

    // Ensure selection doesn't include any non-deletable nodes.
    final selectedNodes = context.document.getNodesInside(documentSelection.base, documentSelection.extent);
    for (final node in selectedNodes) {
      if (!node.isDeletable) {
        // There's at least one non-deletable node. Fizzle.
        return;
      }
    }

    if (!documentSelection.isCollapsed) {
      // The selection is expanded. Delete the selected content.
      executor.executeCommand(DeleteSelectionCommand(affinity: TextAffinity.downstream));
    }
    assert(context.composer.selection!.isCollapsed);

    final caretPosition = context.composer.selection!.extent;
    final caretNodePosition = caretPosition.nodePosition;
    doInsertNewline(context, executor, caretPosition, caretNodePosition);
  }

  void doInsertNewline(
    EditContext context,
    CommandExecutor executor,
    DocumentPosition caretPosition,
    NodePosition caretNodePosition,
  );
}

/// Inserts a newline character "\n" at the current caret position, within
/// the current selected text node (doesn't insert a new node).
///
/// If a non-text node has the caret, nothing happens.
///
/// If the selection is expanded, the selected content is deleted before
/// the insertion.
class InsertSoftNewlineAtCaretRequest implements EditRequest {
  const InsertSoftNewlineAtCaretRequest();
}

class InsertSoftNewlineCommand extends EditCommand {
  const InsertSoftNewlineCommand();

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final documentSelection = context.composer.selection;
    if (documentSelection == null) {
      return;
    }
    if (documentSelection.base.nodePosition is! TextNodePosition) {
      // The effective insertion position isn't within a text node. Fizzle.
      return;
    }
    if (!documentSelection.isCollapsed) {
      // The selection is expanded. Delete the selected content.
      executor.executeCommand(DeleteSelectionCommand(affinity: TextAffinity.downstream));
    }
    assert(context.composer.selection!.isCollapsed);

    final caretPosition = context.composer.selection!.extent;
    executor.executeCommand(
      InsertTextCommand(
        documentPosition: caretPosition,
        textToInsert: "\n",
        attributions: {},
      ),
    );
  }
}

class ConvertTextNodeToParagraphRequest implements EditRequest {
  const ConvertTextNodeToParagraphRequest({
    required this.nodeId,
    this.newMetadata,
  });

  final String nodeId;
  final Map<String, dynamic>? newMetadata;
}

class ConvertTextNodeToParagraphCommand extends EditCommand {
  ConvertTextNodeToParagraphCommand({
    required this.nodeId,
    this.newMetadata,
  });

  final String nodeId;
  final Map<String, dynamic>? newMetadata;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;

    final extentNode = document.getNodeById(nodeId) as TextNode;
    late ParagraphNode newParagraphNode;
    if (extentNode is ParagraphNode) {
      newParagraphNode = extentNode.copyWithAddedMetadata({
        NodeMetadata.blockType: paragraphAttribution,
      });
    } else {
      newParagraphNode = ParagraphNode(
        id: extentNode.id,
        text: extentNode.text,
        metadata: newMetadata,
      );
    }
    document.replaceNodeById(
      extentNode.id,
      newParagraphNode,
    );

    executor.logChanges([
      DocumentEdit(
        NodeChangeEvent(extentNode.id),
      ),
    ]);
  }
}

class InsertAttributedTextRequest implements EditRequest {
  const InsertAttributedTextRequest(this.documentPosition, this.textToInsert);

  final DocumentPosition documentPosition;
  final AttributedText textToInsert;
}

class InsertAttributedTextCommand extends EditCommand {
  InsertAttributedTextCommand({
    required this.documentPosition,
    required this.textToInsert,
  }) : assert(documentPosition.nodePosition is TextPosition);

  final DocumentPosition documentPosition;
  final AttributedText textToInsert;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;
    final textNode = document.getNodeById(documentPosition.nodeId);
    if (textNode is! TextNode) {
      editorDocLog.shout('ERROR: can\'t insert text in a node that isn\'t a TextNode: $textNode');
      return;
    }

    final textOffset = (documentPosition.nodePosition as TextPosition).offset;

    document.replaceNodeById(
      textNode.id,
      textNode.copyTextNodeWith(
        text: textNode.text.insert(
          textToInsert: textToInsert,
          startOffset: textOffset,
        ),
      ),
    );

    executor.logChanges([
      DocumentEdit(
        TextInsertionEvent(
          nodeId: textNode.id,
          offset: textOffset,
          text: textToInsert,
        ),
      ),
    ]);
  }
}

class InsertStyledTextAtCaretRequest implements EditRequest {
  const InsertStyledTextAtCaretRequest(this.text);

  final AttributedText text;
}

class InsertStyledTextAtCaretCommand extends EditCommand {
  const InsertStyledTextAtCaretCommand(this.text);

  final AttributedText text;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final selection = context.composer.selection;
    if (selection == null) {
      // Can't insert at caret if there is no caret.
      return;
    }
    if (!selection.isCollapsed) {
      // The selection is expanded. There's no caret. Fizzle.
      // Maybe we want these commands to actually be "at selection" instead of
      // "at caret" and then delete the selected content.
      return;
    }

    executor
      ..executeCommand(
        InsertAttributedTextCommand(
          documentPosition: selection.extent,
          textToInsert: text,
        ),
      )
      ..executeCommand(
        ChangeSelectionCommand(
          DocumentSelection.collapsed(
            position: selection.extent.copyWith(
              nodePosition: TextNodePosition(
                offset: (selection.extent.nodePosition as TextNodePosition).offset + text.length,
              ),
            ),
          ),
          SelectionChangeType.insertContent,
          SelectionReason.userInteraction,
        ),
      );
  }
}

class InsertInlinePlaceholderAtCaretRequest implements EditRequest {
  const InsertInlinePlaceholderAtCaretRequest(this.placeholder);

  final Object placeholder;
}

class InsertInlinePlaceholderAtCaretCommand extends EditCommand {
  const InsertInlinePlaceholderAtCaretCommand(this.placeholder);

  final Object placeholder;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    executor.executeCommand(
      InsertStyledTextAtCaretCommand(
        AttributedText("", null, {
          0: placeholder,
        }),
      ),
    );
  }
}

ExecutionInstruction anyCharacterToInsertInTextContent({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  // Do nothing if CMD or CTRL are pressed because this signifies an attempted
  // shortcut.
  if (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (!editContext.composer.selection!.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }
  if (!_isTextEntryNode(
    document: editContext.document,
    selection: editContext.composer.selection!,
  )) {
    return ExecutionInstruction.continueExecution;
  }
  if (keyEvent.character == null || keyEvent.character == '') {
    return ExecutionInstruction.continueExecution;
  }
  if (LogicalKeyboardKey.isControlCharacter(keyEvent.character!) || keyEvent.isArrowKeyPressed) {
    return ExecutionInstruction.continueExecution;
  }

  String character = keyEvent.character!;

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

/// Inserts the given [character] at the current caret position.
///
/// If [ignoreComposerAttributions] is `false`, the current composer styles are applied
/// to the inserted character.
///
/// If the selection is expanded, the selection is deleted.
///
/// If the caret sits in a non-text node, a new paragraph is inserted below
/// that node.
class InsertCharacterAtCaretRequest implements EditRequest {
  InsertCharacterAtCaretRequest({
    required this.character,
    this.ignoreComposerAttributions = false,
  }) {
    // We generate a node ID just in case the caret sits in a binary
    // node, and we need to insert a new paragraph.
    // FIXME: Rework all uses of this request so that the caller ensures
    //        that the caret is in a text node. Or, fizzle in the command
    //        if we're not. It's probably not a good idea to hide the
    //        paragraph insertion in this request/command pair.
    newNodeId = Editor.createNodeId();
  }

  final String character;
  // FIXME: Document why we made this configurable, given that we're inserting
  //        at the caret. Maybe this was for undo/redo? If so, we probably need
  //        the composer styles to also activate/deactivate with history. It's
  //        not clear that users will always be in a position to toggle this property
  //        at the right times.
  //
  //        Another option is to require users to look up the styles from the composer
  //        when they create the request.
  final bool ignoreComposerAttributions;

  late final String newNodeId;
}

class InsertCharacterAtCaretCommand extends EditCommand {
  InsertCharacterAtCaretCommand({
    required this.character,
    required this.newNodeId,
    this.ignoreComposerAttributions = false,
  });

  final String character;
  final bool ignoreComposerAttributions;

  /// {@macro newNodeId}
  final String newNodeId;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.document;
    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);
    final selection = composer.selection;

    if (selection == null) {
      return;
    }

    if (!selection.isCollapsed) {
      _deleteExpandedSelection(
        context: context,
        executor: executor,
        document: document,
        composer: composer,
      );
    }

    final extentNodePosition = composer.selection!.extent.nodePosition;
    if (extentNodePosition is UpstreamDownstreamNodePosition) {
      editorOpsLog.fine("The selected position is an UpstreamDownstreamPosition. Inserting new paragraph first.");
      executor.executeCommand(
        DefaultInsertNewlineAtCaretCommand(newNodeId),
      );
    }

    final extentNode = document.getNodeById(composer.selection!.extent.nodeId)!;
    if (extentNode is! TextNode) {
      editorOpsLog.fine(
          "Couldn't insert character because Super Editor doesn't know how to handle a node of type: $extentNode");
      return;
    }

    // Insert the character.
    if (!_isTextEntryNode(document: document, selection: selection)) {
      return;
    }

    executor.executeCommand(
      InsertTextCommand(
        documentPosition: selection.extent,
        textToInsert: character,
        attributions: ignoreComposerAttributions ? {} : composer.preferences.currentAttributions,
      ),
    );
  }
}

void _deleteExpandedSelection({
  required EditContext context,
  required CommandExecutor executor,
  required Document document,
  required DocumentComposer composer,
}) {
  final newSelectionPosition = _getDocumentPositionAfterExpandedDeletion(
    document: document,
    selection: composer.selection!,
  );

  // Delete the selected content.
  executor.executeCommand(
    DeleteContentCommand(
      documentRange: composer.selection!,
    ),
  );

  executor.executeCommand(
    ChangeSelectionCommand(
      DocumentSelection.collapsed(position: newSelectionPosition),
      SelectionChangeType.deleteContent,
      SelectionReason.userInteraction,
    ),
  );
}

// FIXME: This method appears to be the same as CommonEditorOperations.getDocumentPositionAfterExpandedDeletion
//        De-dup this behavior in an appropriate place
DocumentPosition _getDocumentPositionAfterExpandedDeletion({
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

  final extentPosition = selection.extent;
  final extentNode = document.getNode(extentPosition);
  if (extentNode == null) {
    throw Exception('Failed to _getDocumentPositionAfterDeletion because the extent node no longer exists.');
  }

  final selectionAffinity = document.getAffinityForSelection(selection);
  final topPosition = selectionAffinity == TextAffinity.downstream //
      ? selection.base
      : selection.extent;
  final topNodePosition = topPosition.nodePosition;
  final topNode = document.getNodeById(topPosition.nodeId)!;

  final bottomPosition = selectionAffinity == TextAffinity.downstream //
      ? selection.extent
      : selection.base;
  final bottomNodePosition = bottomPosition.nodePosition;
  final bottomNode = document.getNodeById(bottomPosition.nodeId)!;

  DocumentPosition newSelectionPosition;

  if (topPosition.nodeId != bottomPosition.nodeId) {
    if (topNodePosition == topNode.beginningPosition && bottomNodePosition == bottomNode.endPosition) {
      // All nodes in the selection will be deleted. Assume that the base
      // node will be retained and converted into a paragraph, if it's not
      // already a paragraph.
      newSelectionPosition = DocumentPosition(
        documentPath: document.getPathByNodeId(baseNode.id)!,
        nodePosition: const TextNodePosition(offset: 0),
      );
    } else if (topNodePosition == topNode.beginningPosition) {
      // The top node will be deleted, but only part of the bottom node
      // will be deleted.
      newSelectionPosition = DocumentPosition(
        documentPath: document.getPathByNodeId(bottomNode.id)!,
        nodePosition: bottomNode.beginningPosition,
      );
    } else if (bottomNodePosition == bottomNode.endPosition) {
      // The bottom node will be deleted, but only part of the top node
      // will be deleted.
      newSelectionPosition = DocumentPosition(
        documentPath: document.getPathByNodeId(topNode.id)!,
        nodePosition: topNodePosition,
      );
    } else {
      // Part of the top and bottom nodes will be deleted, but both of
      // those nodes will remain.

      // The caret should end up at the base position
      newSelectionPosition = selectionAffinity == TextAffinity.downstream ? selection.base : selection.extent;
    }
  } else {
    // Selection is within a single node.
    //
    // If it's an upstream/downstream selection node, then the whole node
    // is selected, and it will be replaced by a Paragraph Node.
    //
    // Otherwise, it must be a TextNode, in which case we need to figure
    // out which DocumentPosition contains the earlier TextNodePosition.
    if (basePosition.nodePosition is UpstreamDownstreamNodePosition) {
      // Assume that the node was replace with an empty paragraph.
      newSelectionPosition = DocumentPosition(
        documentPath: document.getPathByNodeId(baseNode.id)!,
        nodePosition: const TextNodePosition(offset: 0),
      );
    } else if (basePosition.nodePosition is TextNodePosition) {
      final baseOffset = (basePosition.nodePosition as TextNodePosition).offset;
      final extentOffset = (extentPosition.nodePosition as TextNodePosition).offset;

      newSelectionPosition = DocumentPosition(
        documentPath: document.getPathByNodeId(baseNode.id)!,
        nodePosition: TextNodePosition(offset: min(baseOffset, extentOffset)),
      );
    } else {
      throw Exception(
          'Unknown selection position type: $basePosition, for node: $baseNode, within document selection: $selection');
    }
  }

  return newSelectionPosition;
}

ExecutionInstruction deleteCharacterWhenBackspaceIsPressed({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (!_isTextEntryNode(
    document: editContext.document,
    selection: editContext.composer.selection!,
  )) {
    return ExecutionInstruction.continueExecution;
  }
  if (!editContext.composer.selection!.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }
  if ((editContext.composer.selection!.extent.nodePosition as TextPosition).offset <= 0) {
    return ExecutionInstruction.continueExecution;
  }

  final didDelete = editContext.commonOps.deleteUpstream();

  return didDelete ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction deleteDownstreamContentWithDelete({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.delete) {
    return ExecutionInstruction.continueExecution;
  }

  final didDelete = editContext.commonOps.deleteDownstream();

  return didDelete ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction shiftEnterToInsertNewlineInBlock({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (keyEvent.logicalKey != LogicalKeyboardKey.enter && keyEvent.logicalKey != LogicalKeyboardKey.numpadEnter) {
    return ExecutionInstruction.continueExecution;
  }
  if (!HardwareKeyboard.instance.isShiftPressed) {
    return ExecutionInstruction.continueExecution;
  }

  editContext.editor.execute([
    const InsertSoftNewlineAtCaretRequest(),
  ]);

  return ExecutionInstruction.haltExecution;
}

bool _isTextEntryNode({
  required Document document,
  required DocumentSelection selection,
}) {
  final extentPosition = selection.extent;
  final extentNode = document.getNodeById(extentPosition.nodeId);
  return extentNode is TextNode;
}
