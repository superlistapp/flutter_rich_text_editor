import 'dart:math';

import 'package:example_docs/infrastructure/icon_selector.dart';
import 'package:example_docs/infrastructure/color_selector.dart';
import 'package:example_docs/infrastructure/text_item_selector.dart';
import 'package:example_docs/infrastructure/increment_decrement_field.dart';
import 'package:example_docs/theme.dart';
import 'package:flutter/material.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:overlord/overlord.dart';
import 'package:super_editor/super_editor.dart';

/// The application toolbar that includes document editing options such as font family,
/// font size, text alignment, etc.
///
/// The toolbar is divided by groups of children. Depending on the size of the screen,
/// some of the groups are hidden and a button to show the hidden groups is displayed.
/// Upon tapping this button, a popover is displayed revealing the hidden groups.
///
/// All children of a visible group are displayed and no child is displayed for a
/// hidden group.
class DocsEditorToolbar extends StatefulWidget {
  const DocsEditorToolbar({
    super.key,
    required this.document,
    required this.editor,
    required this.composer,
    required this.editorFocusNode,
    required this.onZoomChange,
  });

  final Document document;
  final Editor editor;
  final MutableDocumentComposer composer;
  final FocusNode editorFocusNode;
  final void Function(int zoom) onZoomChange;

  @override
  State<DocsEditorToolbar> createState() => _DocsEditorToolbarState();
}

class _DocsEditorToolbarState extends State<DocsEditorToolbar> {
  /// Groups the additional toolbar options popover, which is shown by tapping
  /// the "more items" button with the popovers shown by the toolbar items,
  /// like the color picker.
  static const _tapRegionGroupId = 'docs_toolbar';

  final FocusNode _urlFocusNode = FocusNode();
  final PopoverController _linkPopoverController = PopoverController();
  ImeAttributedTextEditingController? _urlController;

  final PopoverController _searchPopoverController = PopoverController();
  final FocusNode _searchFocusNode = FocusNode();

  TextItem _selectedZoom = const TextItem(id: '100', label: '100%');

  @override
  void initState() {
    super.initState();
    widget.composer.selectionNotifier.addListener(_onSelectionChanged);

    _urlController = ImeAttributedTextEditingController() //
      ..onPerformActionPressed = _onUrlFieldPerformAction
      ..text = AttributedText("https://");
  }

  @override
  void didUpdateWidget(covariant DocsEditorToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composer.selectionNotifier != widget.composer.selectionNotifier) {
      oldWidget.composer.selectionNotifier.addListener(_onSelectionChanged);
      widget.composer.selectionNotifier.addListener(_onSelectionChanged);
    }
  }

  @override
  void dispose() {
    widget.composer.selectionNotifier.removeListener(_onSelectionChanged);
    _urlFocusNode.dispose();
    _linkPopoverController.dispose();
    _searchPopoverController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    // Rebuild to update the visuals, because information like which buttons are toggled
    // depends on the selection.
    setState(() {});
  }

  void _onUrlFieldPerformAction(TextInputAction action) {
    if (action == TextInputAction.done) {
      _applyLink();
    }
  }

  void _onChangeZoomLevelRequested(TextItem? zoomLevel) {
    if (zoomLevel == null) {
      return;
    }

    widget.onZoomChange(int.parse(zoomLevel.id));

    setState(() {
      _selectedZoom = zoomLevel;
    });
  }

  /// Converts the currently selected text node into a new type of
  /// text node, represented by [newType].
  ///
  /// For example: convert a paragraph to a blockquote, or a header
  /// to a list item.
  void _convertTextToNewType(String? newType) {
    final existingTextType = _getCurrentTextType();

    if (existingTextType == newType) {
      // The text is already the desired type. Return.
      return;
    }

    // Apply a new block type to an existing paragraph node.
    widget.editor.execute([
      ChangeParagraphBlockTypeRequest(
        nodeId: widget.composer.selection!.extent.documentPath.targetNodeId,
        blockType: _getBlockTypeAttribution(newType),
      ),
    ]);
  }

  /// Changes the font family of the current selected range to reflect [newFontFamily].
  ///
  /// If [newFontFamily] is `null`, the font family attributions are removed and
  /// the default font family is applied.
  void _onChangeFontFamilyRequested(String? newFontFamily) {
    final selection = widget.composer.selection;
    if (selection == null) {
      return;
    }

    final fontFamilyAttributions = widget.document.getAttributionsByType<FontFamilyAttribution>(selection);

    widget.editor.execute([
      for (final existingAttribution in fontFamilyAttributions) //
        RemoveTextAttributionsRequest(documentRange: selection, attributions: {existingAttribution}),
      if (newFontFamily != null) //
        AddTextAttributionsRequest(
          documentRange: selection,
          attributions: {FontFamilyAttribution(newFontFamily)},
        ),
    ]);

    // Rebuild to update the selected font on the toolbar.
    setState(() {});
  }

  /// Changes the font size of the current selected range to reflect [newFontSize].
  void _onChangeFontSizeRequested(int newFontSize) {
    final selection = widget.composer.selection;
    if (selection == null) {
      return;
    }

    final fontSizeAttributions = widget.document.getAttributionsByType<FontSizeAttribution>(selection);

    widget.editor.execute([
      for (final existingAttribution in fontSizeAttributions) //
        RemoveTextAttributionsRequest(documentRange: selection, attributions: {existingAttribution}),
      AddTextAttributionsRequest(
        documentRange: selection,
        attributions: {FontSizeAttribution(newFontSize.toDouble())},
      ),
    ]);

    // Rebuild to update the font size on the toolbar.
    setState(() {});
  }

  /// Toggles the bold attribution on the current selected range.
  void _onToggleBoldRequested() {
    _toggleAttribution(boldAttribution);
  }

  /// Toggles the italics attribution on the current selected range.
  void _onToggleItalicsRequested() {
    _toggleAttribution(italicsAttribution);
  }

  /// Toggles the underline attribution on the current selected range.
  void _onToggleUnderlineRequested() {
    _toggleAttribution(underlineAttribution);
  }

  /// Changes the color of the current selected range to reflect [newColor].
  ///
  /// If [newColor] is `null`, the color attributions are removed and
  /// the default color is applied.
  void _onChangeTextColorRequested(Color? newColor) {
    final selection = widget.composer.selection;
    if (selection == null) {
      return;
    }

    final colorAttributions = widget.document.getAttributionsByType<ColorAttribution>(selection);

    widget.editor.execute([
      for (final existingAttribution in colorAttributions) //
        RemoveTextAttributionsRequest(documentRange: selection, attributions: {existingAttribution}),
      if (newColor != null) //
        AddTextAttributionsRequest(
          documentRange: selection,
          attributions: {ColorAttribution(newColor)},
        ),
    ]);

    // Rebuild to update the color on the toolbar button.
    setState(() {});
  }

  /// Changes the background color of the current selected range to reflect [newColor].
  ///
  /// If [newColor] is `null`, the background color attributions are removed and
  /// the default color is applied.
  void _onChangeBackgroundColorRequested(Color? newColor) {
    final selection = widget.composer.selection;
    if (selection == null) {
      return;
    }

    final colorAttributions = widget.document.getAttributionsByType<BackgroundColorAttribution>(selection);

    widget.editor.execute([
      for (final existingAttribution in colorAttributions) //
        RemoveTextAttributionsRequest(documentRange: selection, attributions: {existingAttribution}),
      if (newColor != null) //
        AddTextAttributionsRequest(
          documentRange: selection,
          attributions: {BackgroundColorAttribution(newColor)},
        ),
    ]);

    // Rebuild to update the background color on the toolbar button.
    setState(() {});
  }

  /// Applies the link entered on the URL textfield to the current
  /// selected range.
  void _applyLink() {
    final url = _urlController!.text.toPlainText(includePlaceholders: false);

    final selection = widget.composer.selection!;
    final baseOffset = (selection.base.nodePosition as TextPosition).offset;
    final extentOffset = (selection.extent.nodePosition as TextPosition).offset;
    final selectionStart = min(baseOffset, extentOffset);
    final selectionEnd = max(baseOffset, extentOffset);
    final selectionRange = TextRange(start: selectionStart, end: selectionEnd - 1);

    final textNodePath = selection.extent.documentPath;
    final textNode = widget.document.getNodeById(textNodePath.targetNodeId) as TextNode;
    final text = textNode.text;

    final trimmedRange = _trimTextRangeWhitespace(text, selectionRange);

    final linkAttribution = LinkAttribution.fromUri(Uri.parse(url));

    widget.editor.execute([
      AddTextAttributionsRequest(
        documentRange: DocumentRange(
          start: DocumentPosition(
            documentPath: textNodePath,
            nodePosition: TextNodePosition(offset: trimmedRange.start),
          ),
          end: DocumentPosition(
            documentPath: textNodePath,
            nodePosition: TextNodePosition(offset: trimmedRange.end),
          ),
        ),
        attributions: {linkAttribution},
      ),
    ]);

    // Clear the field and hide the URL bar
    _urlController!.clearTextAndSelection();
    _urlFocusNode.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
    _linkPopoverController.close();
    setState(() {});
  }

  /// Changes the alignment of the current selected text node
  /// to reflect [newAlignment].
  void _changeAlignment(TextAlign? newAlignment) {
    if (widget.composer.selection == null || newAlignment == null) {
      return;
    }

    widget.editor.execute([
      ChangeParagraphAlignmentRequest(
        nodeId: widget.composer.selection!.extent.targetNodeId,
        alignment: newAlignment,
      ),
    ]);
  }

  /// Converts the selected node to a [TaskNode], or to a
  /// [ParagraphNode] if it's already a [TaskNode].
  void _onToggleTaskNodeRequested() {
    final selection = widget.composer.selection;
    if (selection == null) {
      return;
    }

    final node = widget.document.getNodeById(selection.extent.targetNodeId);
    if (node is TaskNode) {
      widget.editor.execute([
        DeleteUpstreamAtBeginningOfNodeRequest(node),
      ]);
    } else {
      widget.editor.execute([
        ConvertParagraphToTaskRequest(nodeId: selection.extent.targetNodeId),
      ]);
    }
  }

  /// Converts the selected node to a unordered [ListItemNode],
  /// or to a [ParagraphNode] if it's already a [ListItemNode].
  void _onToggleUnorderedListItemRequested() {
    final selection = widget.composer.selection;
    if (selection == null) {
      return;
    }

    final node = widget.document.getNodeById(selection.extent.targetNodeId);
    if (node is ListItemNode) {
      widget.editor.execute([
        ConvertListItemToParagraphRequest(nodeId: node.id, paragraphMetadata: node.metadata),
      ]);
    } else {
      widget.editor.execute([
        ConvertParagraphToListItemRequest(
          nodeId: selection.extent.targetNodeId,
          type: ListItemType.unordered,
        ),
      ]);
    }
  }

  /// Converts the selected node to a ordered [ListItemNode],
  /// or to a [ParagraphNode] if it's already a [ListItemNode].
  void _onToggleOrderedListItemRequested() {
    final selection = widget.composer.selection;
    if (selection == null) {
      return;
    }

    final node = widget.document.getNodeById(selection.extent.targetNodeId);
    if (node is ListItemNode) {
      widget.editor.execute([
        ConvertListItemToParagraphRequest(nodeId: node.id, paragraphMetadata: node.metadata),
      ]);
    } else {
      widget.editor.execute([
        ConvertParagraphToListItemRequest(
          nodeId: selection.extent.targetNodeId,
          type: ListItemType.ordered,
        ),
      ]);
    }
  }

  /// Removes all attributions from the selected range.
  void _onClearFormattingRequested() {
    final selection = widget.composer.selection;
    if (selection == null) {
      return;
    }
  }

  /// Shows a dialog with an alert that the selected feature
  /// isn't implemented yet.
  void _showNotImplementedAlert() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Docs Demo'),
          content: const Text('Feature not implemented yet'),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Toggles the given [attribution] on the selected range.
  void _toggleAttribution(Attribution attribution) {
    if (widget.composer.selection == null) {
      return;
    }

    widget.editor.execute([
      ToggleTextAttributionsRequest(
        documentRange: widget.composer.selection!,
        attributions: {attribution},
      ),
    ]);

    // Rebuild to update the toggled buttons on the toolbar.
    setState(() {});
  }

  /// Reacts to the change of the alignment on the toolbar.
  void _onChangeAlignmentRequested(IconItem? selectedItem) {
    if (selectedItem != null) {
      setState(() {
        _changeAlignment(TextAlign.values.firstWhere((e) => e.name == selectedItem.id));
      });
    }
  }

  /// Reacts to the change of the block type on the toolbar.
  void _onChangeBlockTypeRequested(TextItem? selectedItem) {
    if (selectedItem != null) {
      setState(() {
        _convertTextToNewType(selectedItem.id);
      });
    }
  }

  /// Given [text] and a [range] within the [text], the [range] is
  /// shortened on both sides to remove any trailing whitespace and
  /// the new range is returned.
  SpanRange _trimTextRangeWhitespace(AttributedText text, TextRange range) {
    int startOffset = range.start;
    int endOffset = range.end;

    final plainText = text.toPlainText();
    while (startOffset < range.end && plainText[startOffset] == ' ') {
      startOffset += 1;
    }
    while (endOffset > startOffset && plainText[endOffset] == ' ') {
      endOffset -= 1;
    }

    // Add 1 to the end offset because SpanRange treats the end offset to be exclusive.
    return SpanRange(startOffset, endOffset + 1);
  }

  bool _doesSelectionHaveAttributions(Set<Attribution> attributions) {
    final selection = widget.composer.selection;
    if (selection == null) {
      return false;
    }

    if (selection.isCollapsed) {
      return widget.composer.preferences.currentAttributions.containsAll(attributions);
    }

    return widget.document.doesSelectedTextContainAttributions(selection, attributions);
  }

  /// Returns the text alignment of the currently selected text node.
  ///
  /// Throws an exception if the currently selected node is not a text node.
  TextAlign _getCurrentTextAlignment() {
    if (widget.composer.selection == null) {
      return TextAlign.left;
    }
    final selectedNode = widget.document.getNodeById(widget.composer.selection!.extent.targetNodeId);
    if (selectedNode is ParagraphNode) {
      final align = selectedNode.getMetadataValue('textAlign');
      switch (align) {
        case 'left':
          return TextAlign.left;
        case 'center':
          return TextAlign.center;
        case 'right':
          return TextAlign.right;
        case 'justify':
          return TextAlign.justify;
        default:
          return TextAlign.left;
      }
    } else {
      throw Exception('Invalid node type: $selectedNode');
    }
  }

  /// Returns the text [Attribution] associated with the given
  /// block type, e.g., `"header1"` -> [header1Attribution].
  Attribution? _getBlockTypeAttribution(String? newType) {
    return switch (newType) {
      BlockTypes.header1 => header1Attribution,
      BlockTypes.header2 => header2Attribution,
      BlockTypes.header3 => header3Attribution,
      BlockTypes.blockquote => blockquoteAttribution,
      BlockTypes.paragraph => paragraphAttribution,
      _ => null,
    };
  }

  /// Returns whether or not the currently selected node is a paragraph.
  bool _isParagraphNode() {
    final selection = widget.composer.selection;

    if (selection == null) {
      return false;
    }

    if (selection.base.nodeId != selection.extent.nodeId) {
      return false;
    }

    final selectedNode = widget.document.getNodeById(selection.extent.targetNodeId);
    return selectedNode is ParagraphNode;
  }

  /// Returns the text type of the selected node, i.e, a header,
  /// a blockquote, etc.
  String? _getCurrentTextType() {
    final selection = widget.composer.selection;
    if (selection == null) {
      return null;
    }

    final selectedNode = widget.document.getNodeById(selection.extent.targetNodeId);
    if (selectedNode is ParagraphNode) {
      return (selectedNode.getMetadataValue('blockType') as NamedAttribution).id;
    }

    return null;
  }

  /// Returns all attributions of the currently selected range, if the selection is expanded,
  /// or the current composer attributes, if the selection is collapsed.
  Set<Attribution> _getAllAttributions() {
    final selection = widget.composer.selection;
    if (selection == null) {
      return <Attribution>{};
    }

    if (selection.isCollapsed) {
      return widget //
          .composer
          .preferences
          .currentAttributions;
    }

    return widget.document.getAllAttributions(selection);
  }

  TextStyle _getDefaultTextStyleForBlockType(TextItem item) {
    return switch (item.id) {
      BlockTypes.header1 => const TextStyle(
          color: Color(0xFF333333),
          fontSize: 38,
          fontWeight: FontWeight.bold,
        ),
      BlockTypes.header2 => const TextStyle(
          color: Color(0xFF333333),
          fontSize: 26,
          fontWeight: FontWeight.bold,
        ),
      BlockTypes.header3 => const TextStyle(
          color: Color(0xFF333333),
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      BlockTypes.paragraph => const TextStyle(
          color: Colors.black,
          fontSize: 18,
          height: 1.4,
        ),
      BlockTypes.blockquote => const TextStyle(
          color: Colors.grey,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          height: 1.4,
        ),
      _ => const TextStyle(
          color: Colors.black,
          fontSize: 18,
          height: 1.4,
        )
    };
  }

  void _showUrlPopover() {
    _linkPopoverController.open();
    _urlFocusNode.requestFocus();
  }

  /// Computes how many button groups should be visible for the given [width].
  int _computeVisibleGroupCount(double width) {
    return switch (width) {
      >= 1300 => 5,
      >= 1000 => 4,
      >= 900 => 3,
      >= 600 => 2,
      _ => 1,
    };
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final visibleGroupCount = _computeVisibleGroupCount(width);
    final attributions = _getAllAttributions();

    return Material(
      color: toolbarBackgroundColor,
      shape: const StadiumBorder(),
      child: SizedBox(
        width: double.infinity,
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 9.0),
          child: _GroupedToolbarItems(
            tapRegionGroupId: _tapRegionGroupId,
            visibleGroupCount: visibleGroupCount,
            groups: [
              _WidgetGroup(
                widgets: [
                  const SizedBox(width: 1),
                  _buildSearchPopoverButton(expanded: width > 1250),
                  const SizedBox(width: 7),
                  ToolbarImageButton(
                    onPressed: _showNotImplementedAlert,
                    hint: 'Undo',
                    child: const Icon(Icons.undo),
                  ),
                  const SizedBox(width: 1),
                  ToolbarImageButton(
                    onPressed: _showNotImplementedAlert,
                    hint: 'Redo',
                    child: const Icon(Icons.redo),
                  ),
                  const SizedBox(width: 1),
                  ToolbarImageButton(
                    onPressed: _showNotImplementedAlert,
                    hint: 'Print',
                    child: const Icon(Icons.print_outlined),
                  ),
                  const SizedBox(width: 1),
                  ToolbarImageButton(
                    onPressed: _showNotImplementedAlert,
                    hint: 'Spellcheck',
                    child: const Icon(Icons.spellcheck),
                  ),
                  const SizedBox(width: 1),
                  ToolbarImageButton(
                    onPressed: _showNotImplementedAlert,
                    hint: 'Paint Formating',
                    child: const Icon(Icons.format_paint_outlined),
                  ),
                  _buildZoomSelector(),
                ],
              ),
              _WidgetGroup(
                widgets: [
                  _buildBlockTypeSelector(),
                  _buildFontFamilySelector(attributions),
                ],
              ),
              _WidgetGroup(
                widgets: [
                  _buildFontSizeSelector(attributions),
                  ToolbarImageButton(
                    onPressed: _onToggleBoldRequested,
                    selected: _doesSelectionHaveAttributions({boldAttribution}),
                    hint: 'Bold',
                    child: const Icon(Icons.format_bold),
                  ),
                  const SizedBox(width: 2),
                  ToolbarImageButton(
                    onPressed: _onToggleItalicsRequested,
                    selected: _doesSelectionHaveAttributions({italicsAttribution}),
                    hint: 'Italic',
                    child: const Icon(Icons.format_italic),
                  ),
                  const SizedBox(width: 2),
                  ToolbarImageButton(
                    onPressed: _onToggleUnderlineRequested,
                    selected: _doesSelectionHaveAttributions({underlineAttribution}),
                    hint: 'Underline',
                    child: const Icon(Icons.format_underline),
                  ),
                  const SizedBox(width: 2),
                  _buildColorButton(attributions),
                  const SizedBox(width: 2),
                  _buildBackgroundColorButton(attributions),
                ],
              ),
              _WidgetGroup(
                widgets: [
                  _buildLinkButton(),
                  ToolbarImageButton(
                    onPressed: _showNotImplementedAlert,
                    hint: 'Add comment',
                    child: const Icon(Icons.add_comment_outlined),
                  ),
                  ToolbarImageButton(
                    onPressed: _showNotImplementedAlert,
                    hint: 'Add photo',
                    child: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                ],
              ),
              _WidgetGroup(
                widgets: [
                  if (_isParagraphNode()) //
                    _buildAlignmentSelector(),
                  ToolbarImageButton(
                    onPressed: _showNotImplementedAlert,
                    hint: 'Line spacing',
                    child: const Icon(Icons.format_line_spacing),
                  ),
                  ToolbarImageButton(
                    onPressed: _onToggleTaskNodeRequested,
                    hint: 'Checklist',
                    child: const Icon(Icons.checklist),
                  ),
                  ToolbarImageButton(
                    onPressed: _onToggleUnorderedListItemRequested,
                    hint: 'Bulleted list',
                    child: const Icon(Icons.format_list_bulleted),
                  ),
                  ToolbarImageButton(
                    onPressed: _onToggleOrderedListItemRequested,
                    hint: 'Numbered list',
                    child: const Icon(Icons.format_list_numbered),
                  ),
                  ToolbarImageButton(
                    onPressed: _showNotImplementedAlert,
                    hint: 'Decrease indent',
                    child: const Icon(Icons.format_indent_decrease),
                  ),
                  ToolbarImageButton(
                    onPressed: _showNotImplementedAlert,
                    hint: 'Increase indent',
                    child: const Icon(Icons.format_indent_increase),
                  ),
                  ToolbarImageButton(
                    onPressed: _onClearFormattingRequested,
                    hint: 'Clear formatting',
                    child: const Icon(Icons.format_clear),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the search button, which upon tap shows a popover with
  /// the available actions.
  Widget _buildSearchPopoverButton({required bool expanded}) {
    return PopoverScaffold(
      parentFocusNode: widget.editorFocusNode,
      popoverFocusNode: _searchFocusNode,
      tapRegionGroupId: _tapRegionGroupId,
      onTapOutside: (controller) => _searchPopoverController.close(),
      controller: _searchPopoverController,
      popoverGeometry: const PopoverGeometry(
        aligner: FunctionalPopoverAligner(_searchPopoverAligner),
      ),
      buttonBuilder: (context) => _buildSearchButton(expanded: expanded),
      popoverBuilder: (context) => _buildSearchPopover(),
    );
  }

  /// Builds the button that triggers the search popover.
  Widget _buildSearchButton({required bool expanded}) {
    if (!expanded) {
      return ToolbarImageButton(
        onPressed: () => _searchPopoverController.open(),
        hint: 'Search menus',
        size: const Size(44, 30),
        child: const Icon(Icons.search),
      );
    }

    return Tooltip(
      message: 'Search menus',
      waitDuration: _tooltipDelay,
      child: TextButton.icon(
        onPressed: () {
          _searchPopoverController.open();
          _searchFocusNode.requestFocus();
        },
        icon: const Icon(
          Icons.search,
          size: 18,
        ),
        label: const Text('Menus'),
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(Colors.white),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          foregroundColor: WidgetStateProperty.all(Colors.black),
          fixedSize: WidgetStateProperty.all(const Size(100, 30)),
          minimumSize: WidgetStateProperty.all(const Size(100, 30)),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w200),
          ),
          mouseCursor: WidgetStateProperty.all(SystemMouseCursors.text),
        ),
      ),
    );
  }

  /// Builds the search popover with the available actions.
  Widget _buildSearchPopover() {
    return Material(
      borderRadius: BorderRadius.circular(8.0),
      elevation: 5,
      color: Colors.white,
      child: SizedBox(
        width: 350,
        height: 160,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 18),
                  const SizedBox(width: 13),
                  SuperTextField(
                    hintBuilder: (context) => const Text('Menus (Options + /)'),
                    hintBehavior: HintBehavior.displayHintUntilTextEntered,
                  ),
                ],
              ),
            ),
            ItemSelectionList<_ActionMenu>(
              value: _ActionMenu(
                icon: Icons.format_bold,
                label: 'Bold',
              ),
              focusNode: _searchFocusNode,
              onCancel: () => _searchPopoverController.close(),
              items: [
                _ActionMenu(
                  icon: Icons.format_bold,
                  label: 'Bold',
                ),
                _ActionMenu(
                  icon: Icons.format_italic,
                  label: 'Italic',
                ),
                _ActionMenu(
                  icon: Icons.format_underline,
                  label: 'Underline',
                ),
              ],
              itemBuilder: (context, item, isActive, onTap) => SizedBox(
                height: 40,
                child: ColoredBox(
                  color: isActive ? Colors.grey.withValues(alpha: 0.2) : Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Icon(item.icon, size: 18),
                        const SizedBox(width: 13),
                        Expanded(child: Text(item.label)),
                      ],
                    ),
                  ),
                ),
              ),
              onItemSelected: (_) => _searchPopoverController.close(),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the zoom button, which upon tap shows a popover for the user
  /// to select the zoom.
  Widget _buildZoomSelector() {
    return Tooltip(
      message: 'Zoom',
      waitDuration: _tooltipDelay,
      child: TextItemSelector(
        parentFocusNode: widget.editorFocusNode,
        selectedText: _selectedZoom,
        buttonSize: const Size(77, 30),
        popoverGeometry: const PopoverGeometry(
          constraints: BoxConstraints.tightFor(width: 77),
          aligner: FunctionalPopoverAligner(popoverAligner),
        ),
        items: const [
          TextItem(id: '50', label: '50%'),
          TextItem(id: '75', label: '75%'),
          TextItem(id: '90', label: '90%'),
          TextItem(id: '100', label: '100%'),
          TextItem(id: '125', label: '125%'),
          TextItem(id: '150', label: '150%'),
          TextItem(id: '200', label: '200%'),
        ],
        onSelected: _onChangeZoomLevelRequested,
      ),
    );
  }

  /// Builds the block type button, which upon tap shows a popover for the user
  /// to change the block type of the currently selected node.
  Widget _buildBlockTypeSelector() {
    final currentBlockType = _getCurrentTextType();

    return Tooltip(
      message: 'Styles',
      waitDuration: _tooltipDelay,
      child: TextItemSelector(
        parentFocusNode: widget.editorFocusNode,
        selectedText: currentBlockType != null //
            ? _blockTypes.where((e) => e.id == currentBlockType).firstOrNull
            : null,
        buttonSize: const Size(122, 30),
        popoverGeometry: const PopoverGeometry(
          constraints: BoxConstraints.tightFor(width: 220),
          aligner: FunctionalPopoverAligner(popoverAligner),
        ),
        items: _blockTypes,
        onSelected: _onChangeBlockTypeRequested,
        itemBuilder: (context, item, isActive, onTap) => DecoratedBox(
          decoration: BoxDecoration(
            color: isActive ? Colors.grey.withValues(alpha: 0.2) : Colors.transparent,
          ),
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 71),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(right: 20.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    child: currentBlockType != null && item.id == currentBlockType
                        ? const Icon(
                            Icons.check,
                            size: 18,
                          )
                        : null,
                  ),
                  Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: _getDefaultTextStyleForBlockType(item),
                  ),
                ],
              ),
            ),
          ),
        ),
        separatorBuilder: (context, index) => const Divider(height: 1),
      ),
    );
  }

  /// Builds the font button, which upon tap shows a popover for the user
  /// to change the font family of the selection.
  Widget _buildFontFamilySelector(Set<Attribution> attributions) {
    const defaultFont = 'Roboto';

    final selectedFont = attributions.whereType<FontFamilyAttribution>().firstOrNull?.fontFamily ?? defaultFont;
    final textItem = TextItem(id: selectedFont, label: selectedFont);

    return Tooltip(
      message: 'Font',
      waitDuration: _tooltipDelay,
      child: TextItemSelector(
        parentFocusNode: widget.editorFocusNode,
        tapRegionGroupId: _tapRegionGroupId,
        selectedText: textItem,
        items: _availableFonts.map((fontFamily) => TextItem(id: fontFamily, label: fontFamily)).toList(),
        onSelected: (value) => _onChangeFontFamilyRequested(value?.id),
        buttonSize: const Size(97, 30),
        popoverGeometry: const PopoverGeometry(
          constraints: BoxConstraints.tightFor(width: 247),
          aligner: FunctionalPopoverAligner(popoverAligner),
        ),
        itemBuilder: (context, item, isActive, onTap) => DecoratedBox(
          decoration: BoxDecoration(
            color: isActive ? Colors.grey.withValues(alpha: 0.2) : Colors.transparent,
          ),
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 32),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(right: 20.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    child: item == textItem
                        ? const Icon(
                            Icons.check,
                            size: 18,
                          )
                        : null,
                  ),
                  Text(
                    item.id,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(
                      item.id,
                      textStyle: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the font size button, which upon tap shows a popover for the user
  /// to change the font size of the selection.
  Widget _buildFontSizeSelector(Set<Attribution> attributions) {
    const defaultFontSize = 18;

    final fontAttribution = attributions.whereType<FontSizeAttribution>().firstOrNull;
    return Tooltip(
      message: 'Font size',
      waitDuration: _tooltipDelay,
      child: IncrementDecrementField(
        value: fontAttribution?.fontSize.toInt() ?? defaultFontSize,
        onChange: _onChangeFontSizeRequested,
      ),
    );
  }

  /// Builds a color button, which changes the text color.
  Widget _buildColorButton(Set<Attribution> attributions) {
    final colorAttribution = attributions.whereType<ColorAttribution>().firstOrNull;

    return Tooltip(
      message: 'Text color',
      waitDuration: _tooltipDelay,
      child: ColorSelector(
        parentFocusNode: widget.editorFocusNode,
        tapRegionGroupId: _tapRegionGroupId,
        onSelected: _onChangeTextColorRequested,
        selectedColor: colorAttribution?.color ?? Colors.black,
        colorButtonBuilder: (_, color) => _buildTextColorIcon(color),
      ),
    );
  }

  /// Builds the button icon with a rectangle of the selected [color].
  Widget _buildTextColorIcon(Color? color) {
    return Stack(
      children: [
        const Icon(Icons.format_color_text),
        Positioned(
          bottom: 0,
          left: 1,
          child: Container(
            width: 16,
            height: 4,
            color: color ?? Colors.black,
          ),
        ),
      ],
    );
  }

  /// Builds a color button, which changes the text background color.
  Widget _buildBackgroundColorButton(Set<Attribution> attributions) {
    final colorAttribution = attributions.whereType<BackgroundColorAttribution>().firstOrNull;

    return Tooltip(
      message: 'Highlight color',
      waitDuration: _tooltipDelay,
      child: ColorSelector(
        parentFocusNode: widget.editorFocusNode,
        tapRegionGroupId: _tapRegionGroupId,
        onSelected: _onChangeBackgroundColorRequested,
        showClearButton: true,
        selectedColor: colorAttribution?.color ?? Colors.black,
        colorButtonBuilder: (_, color) => _buildBackgroundColorIcon(color),
      ),
    );
  }

  /// Builds the button icon with a rectangle of the selected [color].
  Widget _buildBackgroundColorIcon(Color? color) {
    return Stack(
      children: [
        const Icon(Icons.format_color_fill),
        Positioned(
          bottom: 0,
          left: 1,
          child: Container(
            width: 16,
            height: 4,
            color: color ?? Colors.black,
          ),
        ),
      ],
    );
  }

  /// Builds the link button, which upon tap shows a popover for the user
  /// to enter a URL.
  Widget _buildLinkButton() {
    return Tooltip(
      message: 'Insert Link',
      waitDuration: _tooltipDelay,
      child: PopoverScaffold(
        parentFocusNode: widget.editorFocusNode,
        tapRegionGroupId: _tapRegionGroupId,
        onTapOutside: (controller) => _linkPopoverController.close(),
        controller: _linkPopoverController,
        buttonBuilder: (context) => TextButton(
          onPressed: _showUrlPopover,
          style: defaultToolbarButtonStyle,
          child: const Icon(Icons.link),
        ),
        popoverBuilder: (context) => _buildLinkPopover(),
      ),
    );
  }

  Widget _buildLinkPopover() {
    return Material(
      shape: const StadiumBorder(),
      elevation: 5,
      clipBehavior: Clip.hardEdge,
      child: Container(
        width: 400,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: SuperTextField(
                focusNode: _urlFocusNode,
                textController: _urlController,
                minLines: 1,
                maxLines: 1,
                inputSource: TextInputSource.ime,
                hintBehavior: HintBehavior.displayHintUntilTextEntered,
                hintBuilder: (context) {
                  return const Text(
                    "enter a url...",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  );
                },
                textStyleBuilder: (_) {
                  return const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                  );
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              iconSize: 20,
              splashRadius: 16,
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(() {
                  _urlFocusNode.unfocus();
                  _urlController!.clearTextAndSelection();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the alignment button, which upon tap shows a popover for the user
  /// to change the paragraph alignment.
  Widget _buildAlignmentSelector() {
    final alignment = _getCurrentTextAlignment();
    return Tooltip(
      message: 'Alignment',
      waitDuration: _tooltipDelay,
      child: IconSelector(
        parentFocusNode: widget.editorFocusNode,
        tapRegionGroupId: _tapRegionGroupId,
        selectedIcon: IconItem(
          id: alignment.name,
          icon: _getTextAlignIcon(alignment),
        ),
        icons: const [TextAlign.left, TextAlign.center, TextAlign.right, TextAlign.justify]
            .map(
              (alignment) => IconItem(
                icon: _getTextAlignIcon(alignment),
                id: alignment.name,
              ),
            )
            .toList(),
        onSelected: _onChangeAlignmentRequested,
      ),
    );
  }
}

/// The content of a toolbar, divided by groups of widgets.
///
/// Only the groups with index less than [visibleGroupCount]
/// are displayed. When there is any hidden groups, a button is
/// displayed to show a popover with the remaining groups.
class _GroupedToolbarItems extends StatefulWidget {
  const _GroupedToolbarItems({
    required this.groups,
    required this.visibleGroupCount,
    this.tapRegionGroupId,
  });

  /// All of the groups available.
  final List<_WidgetGroup> groups;

  /// The number of groups to be displayed.
  ///
  /// All groups with an index greater of equal to [visibleGroupCount]
  /// are hidden.
  final int visibleGroupCount;

  /// A group ID for a tap region that is shared with the toolbar items
  /// that display popovers.
  ///
  /// When the popover of hidden groups is displayed, a [TapRegion] is used
  /// to close this popover upon tapping outside of it. If a popover child
  /// also displays other popovers, tapping on the child's popover triggers
  /// [TapRegion.onTapOutside] of the hidden groups popover, closing the popover.
  /// To prevent that, provide a [tapRegionGroupId] with the same value as
  /// child's [TapRegion] groupId.
  final String? tapRegionGroupId;

  @override
  State<_GroupedToolbarItems> createState() => _GroupedToolbarItemsState();
}

class _GroupedToolbarItemsState extends State<_GroupedToolbarItems> {
  final PopoverController _popoverController = PopoverController();

  @override
  void dispose() {
    _popoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GroupedRow(
          groups: widget.groups,
          visibleGroupCount: widget.visibleGroupCount,
        ),
        if (widget.visibleGroupCount < widget.groups.length) //
          PopoverScaffold(
            tapRegionGroupId: widget.tapRegionGroupId,
            onTapOutside: (controller) => _popoverController.close(),
            controller: _popoverController,
            popoverGeometry: PopoverGeometry(aligner: FunctionalPopoverAligner(_aditionalItensAligner)),
            buttonBuilder: (context) => TextButton(
              onPressed: () => _popoverController.open(),
              style: defaultToolbarButtonStyle,
              child: const Icon(Icons.more_vert),
            ),
            popoverBuilder: (context) => _buildAditionalOptionsPopover(),
          ),
      ],
    );
  }

  Widget _buildAditionalOptionsPopover() {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(4),
      color: toolbarBackgroundColor,
      child: SizedBox(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 9.0),
          child: Wrap(
            children: [
              for (int i = widget.visibleGroupCount; i < widget.groups.length; i++) //
                ...[
                ...widget.groups[i].widgets,
                if (i < widget.groups.length - 1) //
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Container(
                      height: 30,
                      width: 1,
                      color: toolbarDividerColor,
                    ),
                  )
              ]
            ],
          ),
        ),
      ),
    );
  }

  /// Aligns the "aditional items" popover top-right with the button bottom-right.
  FollowerAlignment _aditionalItensAligner(
      Rect globalLeaderRect, Size followerSize, Size screenSize, GlobalKey? boundaryKey) {
    return const FollowerAlignment(
      leaderAnchor: Alignment.bottomRight,
      followerAnchor: Alignment.topRight,
      followerOffset: Offset(0, 6),
    );
  }
}

/// A row that takes groups of widgets and displays a subset of them separated
/// by a vertical divider.
///
/// Only the groups with index less than [visibleGroupCount] are displayed.
/// When the visibility of a group changes, its opacity and size is animated.
///
/// A group is either entirely visible or entirely invisible.
class _GroupedRow extends StatelessWidget {
  const _GroupedRow({
    required this.groups,
    required this.visibleGroupCount,
  });

  /// The groups of widgets to be displayed.
  final List<_WidgetGroup> groups;

  /// The number of groups that should be visible.
  final int visibleGroupCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < groups.length; i++) //
          AnimatedOpacity(
            opacity: i < visibleGroupCount ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 250),
              child: SizedBox(
                width: i < visibleGroupCount ? null : 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...groups[i].widgets,
                    if (i < visibleGroupCount - 1 && i < groups.length - 1) //
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2.0),
                        child: VerticalDivider(
                          width: 1,
                          color: toolbarDividerColor,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A group of widgets that should be either all visible or all invisible.
///
/// This class is used to avoid passing lists of lists of Widgets around,
/// to represent lists of groups.
class _WidgetGroup {
  _WidgetGroup({
    required this.widgets,
  });

  final List<Widget> widgets;
}

/// A button that applies a default style and applies the `MaterialState.selected`
/// when [selected] is `true`.
class ToolbarImageButton extends StatefulWidget {
  const ToolbarImageButton({
    super.key,
    this.onPressed,
    this.selected = false,
    this.size,
    required this.hint,
    required this.child,
  });

  /// Called when the button is pressed.
  final VoidCallback? onPressed;

  /// Whether or not the internal button should contain the state
  /// `MaterialState.selected`.
  final bool selected;

  /// The desired size for the button.
  final Size? size;

  /// Hint text displayed when hovering the button.
  final String hint;

  final Widget child;

  @override
  State<ToolbarImageButton> createState() => _ToolbarImageButtonState();
}

class _ToolbarImageButtonState extends State<ToolbarImageButton> {
  final WidgetStatesController _statesController = WidgetStatesController();

  @override
  void initState() {
    super.initState();
    _statesController.update(WidgetState.selected, widget.selected);
  }

  @override
  void didUpdateWidget(covariant ToolbarImageButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _statesController.update(WidgetState.selected, widget.selected);
    }
  }

  @override
  void dispose() {
    _statesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size ?? const Size(30, 30);
    return Tooltip(
      message: widget.hint,
      waitDuration: _tooltipDelay,
      child: TextButton(
        onPressed: widget.onPressed,
        statesController: _statesController,
        style: defaultToolbarButtonStyle.copyWith(
          fixedSize: WidgetStateProperty.all(size),
          minimumSize: WidgetStateProperty.all(size),
          maximumSize: WidgetStateProperty.all(size),
        ),
        child: widget.child,
      ),
    );
  }
}

/// An option displayed on the "Search" button popover.
class _ActionMenu {
  _ActionMenu({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _ActionMenu && runtimeType == other.runtimeType && icon == other.icon;

  @override
  int get hashCode => icon.hashCode;
}

/// The fonts displayed on the font family selector.
final _availableFonts = [
  'Amatic SC',
  'Caveat',
  'Comfortaa',
  'Comic Neue',
  'Courier Prime',
  'EB Garamond',
  'Lexend',
  'Lobster',
  'Lora',
  'Merriweather',
  'Montserrat',
  'Nunito',
  'Oswald',
  'Pacifico',
  'Playfair Display',
  'Roboto',
  'Roboto Mono',
  'Roboto Serif',
  'Special Elite',
];

/// The block types displayed in the block type selector.
const _blockTypes = [
  TextItem(id: BlockTypes.header1, label: 'Header 1'),
  TextItem(id: BlockTypes.header2, label: 'Header 2'),
  TextItem(id: BlockTypes.header3, label: 'Header 3'),
  TextItem(id: BlockTypes.paragraph, label: 'Normal Text'),
  TextItem(id: BlockTypes.blockquote, label: 'Blockquote'),
];

const _tooltipDelay = Duration(milliseconds: 500);

IconData _getTextAlignIcon(TextAlign align) {
  switch (align) {
    case TextAlign.left:
    case TextAlign.start:
      return Icons.format_align_left;
    case TextAlign.center:
      return Icons.format_align_center;
    case TextAlign.right:
    case TextAlign.end:
      return Icons.format_align_right;
    case TextAlign.justify:
      return Icons.format_align_justify;
  }
}

/// Aligns the top-left of the leader with the top-left of the follower.
FollowerAlignment _searchPopoverAligner(
    Rect globalLeaderRect, Size followerSize, Size screenSize, GlobalKey? boundaryKey) {
  return const FollowerAlignment(
    leaderAnchor: Alignment.topLeft,
    followerAnchor: Alignment.topLeft,
  );
}

/// Common identifiers for the block types used in the app.
class BlockTypes {
  static const header1 = 'header1';
  static const header2 = 'header2';
  static const header3 = 'header3';
  static const blockquote = 'blockquote';
  static const paragraph = 'paragraph';
}
