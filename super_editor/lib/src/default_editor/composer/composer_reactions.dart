import 'dart:ui';

import 'package:attributed_text/attributed_text.dart';
import 'package:collection/collection.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/default_editor/attributions.dart';
import 'package:super_editor/src/default_editor/text.dart';

/// [EditReaction] that synchronizes the active composer styles with the caret's
/// position, when the caret moves in relevant ways.
///
/// When the user places the caret at a new position in a document, the caret might
/// sit immediately before or after some text with existing styles, e.g., bold,
/// italics, underline. Based on the situation, the user expects these styles to
/// be automatically applied to newly typed text. This reaction identifies these
/// situations and activates the desired styles in the [DocumentComposer].
///
/// Only the given [styleValuesToExtend], [styleTypesToExtend], [styleSelectorsToExtend]
/// are automatically activated.
///
/// Styles are activated when placing the caret at the beginning of a paragraph,
/// and the first character has a style:
///
///     **Hello, world**
///     |**Hello, world**
///     **F|Hello, world**
///
/// Styles are activated when placing the caret immediately after a style:
///
///     **Hello**, world
///     **Hello**|, world
///     **HelloF**|, world
///
/// The selection can change for many reasons. This reaction only activates
/// styles when it believes that the user explicitly moved the caret.
/// Conversely, if the caret moves due to the user typing a character, or
/// if the selection is expanded, then this reaction doesn't activate any
/// styles.
class UpdateComposerTextStylesReaction extends EditReaction {
  UpdateComposerTextStylesReaction({
    @Deprecated("Use styleValuesToExtend instead") //
    Set<Attribution>? stylesToExtend,
    Set<Attribution>? styleValuesToExtend,
    Set<Type> styleTypesToExtend = defaultExtendableTypes,
    Set<AttributionExtensionSelector> styleSelectorsToExtend = const {},
  })  : assert(
          stylesToExtend == null || styleValuesToExtend == null,
          "stylesToExtend and styleValuesToExtend are the same thing - you should only provide one",
        ),
        _styleValuesToExtend = styleValuesToExtend ?? stylesToExtend ?? defaultExtendableStyles,
        _styleTypesToExtend = styleTypesToExtend,
        _styleSelectorsToExtend = styleSelectorsToExtend;

  final Set<Attribution> _styleValuesToExtend;
  final Set<Type> _styleTypesToExtend;
  final Set<AttributionExtensionSelector> _styleSelectorsToExtend;

  DocumentSelection? _previousSelection;

  @override
  void react(EditContext editContext, RequestDispatcher requestDispatcher, List<EditEvent> changeList) {
    final lastSelectionChange =
        changeList.lastWhereOrNull((element) => element is SelectionChangeEvent) as SelectionChangeEvent?;
    if (lastSelectionChange == null) {
      // The selection didn't change in this transaction.
      return;
    }

    switch (lastSelectionChange.changeType) {
      case SelectionChangeType.placeCaret:
      case SelectionChangeType.pushCaret:
      case SelectionChangeType.collapseSelection:
      case SelectionChangeType.deleteContent:
        _updateComposerStylesAtCaret(editContext);
      default:
      // We don't want change the composer styles for the other types of selection changes.
    }

    // Update our internal accounting.
    final composer = editContext.find<MutableDocumentComposer>(Editor.composerKey);
    _previousSelection = composer.selection;
  }

  void _updateComposerStylesAtCaret(EditContext editContext) {
    final document = editContext.document;
    final composer = editContext.find<MutableDocumentComposer>(Editor.composerKey);

    if (composer.selection?.extent == _previousSelection?.extent && //
        // Ignore the attributions at the caret only if the previous selection
        // was already collapsed. If the selection was expanded and the user
        // placed the caret at the extent of the selection, we should update
        // the composer attributions.
        _previousSelection?.isCollapsed == true) {
      return;
    }

    final previousSelectionExtent = _previousSelection?.extent;
    final selectionExtent = composer.selection?.extent;
    if (selectionExtent != null &&
        selectionExtent.nodePosition is TextNodePosition &&
        previousSelectionExtent != null &&
        previousSelectionExtent.nodePosition is TextNodePosition) {
      // The current and previous selections are text positions. Check for the situation where the two
      // selections are functionally equivalent, but the affinity changed.
      final selectedNodePosition = selectionExtent.nodePosition as TextNodePosition;
      final previousSelectedNodePosition = previousSelectionExtent.nodePosition as TextNodePosition;

      // Ignore the attributions at the caret only if the previous selection
      // was already collapsed. If the selection was expanded and the user
      // placed the caret at the extent of the selection, we should update
      // the composer attributions.
      if (selectionExtent.nodeId == previousSelectionExtent.nodeId &&
          selectedNodePosition.offset == previousSelectedNodePosition.offset &&
          _previousSelection?.isCollapsed == true) {
        // The text selection changed, but only the affinity is different. An affinity change doesn't alter
        // the selection from the user's perspective, so don't alter any preferences. Return.
        return;
      }
    }

    _previousSelection = composer.selection;

    composer.preferences.clearStyles();

    if (composer.selection == null || !composer.selection!.isCollapsed) {
      return;
    }

    final node = document.getNodeAtPath(composer.selection!.extent.documentPath);
    if (node is! TextNode) {
      return;
    }

    final textPosition = composer.selection!.extent.nodePosition as TextPosition;

    if (textPosition.offset == 0 && node.text.isEmpty) {
      return;
    }

    late int offsetWithAttributionsToExtend;
    if (textPosition.offset == 0) {
      // The inserted text is at the very beginning of the text blob. Therefore, we should apply the
      // same attributions to the inserted text, as the text that immediately follows the inserted text.
      offsetWithAttributionsToExtend = textPosition.offset + 1;
    } else {
      // The inserted text is NOT at the very beginning of the text blob. Therefore, we should apply the
      // same attributions to the inserted text, as the text that immediately precedes the inserted text.
      offsetWithAttributionsToExtend = textPosition.offset - 1;
    }

    Set<Attribution> allAttributions = node.text.getAllAttributionsAt(offsetWithAttributionsToExtend);

    // Add desired expandable styles.
    final newStyles = {
      // Extend any attributions whose value matches a desired value.
      ...allAttributions.where((attribution) => _styleValuesToExtend.contains(attribution)).toSet(),
      // Extend any attribution whose class type matches a desired attribution type.
      if (_styleTypesToExtend.isNotEmpty) //
        ...allAttributions.where((attribution) => _styleTypesToExtend.contains(attribution.runtimeType)).toSet(),
      // Extend any attribution that's explicitly selected by a given selector.
      if (_styleSelectorsToExtend.isNotEmpty) //
        ...allAttributions
            .where(
                (attribution) => _styleSelectorsToExtend.firstWhereOrNull((selector) => selector(attribution)) != null)
            .toSet(),
    };

    // TODO: we shouldn't have such specific behavior in here. Figure out how to generalize this.
    // Add a link attribution only if the selection sits at the middle of the link.
    // As we are dealing with a collapsed selection, we shouldn't have more than one link.
    final linkAttribution = allAttributions.firstWhereOrNull((attribution) => attribution is LinkAttribution);
    if (linkAttribution != null) {
      final range = node.text.getAttributedRange({linkAttribution}, offsetWithAttributionsToExtend);

      if (textPosition.offset > 0 &&
          offsetWithAttributionsToExtend >= range.start &&
          offsetWithAttributionsToExtend < range.end) {
        newStyles.add(linkAttribution);
      }
    }

    composer.preferences.addStyles(newStyles);
  }
}

/// A function that returns `true` if the given [attribution] should be automatically
/// extended when the caret is placed after such an attributed character, and the
/// user continues to type - or `false` to ignore the [attribution] for future typing.
///
/// Example: Typically, when a user places the caret immediately following a bold character,
/// additional user typing also applies the bold attribution.
///
/// Example: Typically, when a user places the caret immediately following a link, the link
/// doesn't extend to include additional characters.
typedef AttributionExtensionSelector = bool Function(Attribution attribution);

final defaultExtendableStyles = Set.unmodifiable({
  boldAttribution,
  italicsAttribution,
  underlineAttribution,
  strikethroughAttribution,
  codeAttribution,
});

const defaultExtendableTypes = {
  FontSizeAttribution,
  ColorAttribution,
  BackgroundColorAttribution,
};
