import 'dart:math';

import 'package:feather/infrastructure/popovers/color_selector.dart';
import 'package:feather/editor/editor.dart';
import 'package:feather/infrastructure/popovers/icon_selector.dart';
import 'package:feather/infrastructure/popovers/text_item_selector.dart';
import 'package:feather/theme.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:overlord/overlord.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_quill/super_editor_quill.dart';

class FormattingToolbar extends StatefulWidget {
  const FormattingToolbar({
    super.key,
    required this.editorFocusNode,
    required this.editor,
    required this.isShowingDeltas,
    required this.onShowDeltasChange,
  });

  final FocusNode editorFocusNode;
  final Editor editor;

  final bool isShowingDeltas;
  final void Function(bool showDeltas) onShowDeltasChange;

  @override
  State<FormattingToolbar> createState() => _FormattingToolbarState();
}

class _FormattingToolbarState extends State<FormattingToolbar> {
  static const _tapRegionGroupId = 'feather_toolbar';

  late DocumentComposer _composer;
  late Document _document;
  late final EditListener _editListener;

  final _fullySelectedTextFormats = <Attribution>{};

  final FocusNode _urlFocusNode = FocusNode();
  final PopoverController _linkPopoverController = PopoverController();
  ImeAttributedTextEditingController? _urlController;

  final FocusNode _imageFocusNode = FocusNode();
  final PopoverController _imagePopoverController = PopoverController();
  ImeAttributedTextEditingController? _imageController;

  @override
  void initState() {
    super.initState();

    _editListener = FunctionalEditListener(_onEdit);
    widget.editor.addListener(_editListener);

    _composer = widget.editor.composer;
    _composer.selectionNotifier.addListener(_onSelectionChange);
    _document = widget.editor.document;

    _urlController = ImeAttributedTextEditingController() //
      ..onPerformActionPressed = _onUrlFieldPerformAction
      ..text = AttributedText("https://");

    _imageController = ImeAttributedTextEditingController() //
      ..onPerformActionPressed = _onImageFieldPerformAction
      ..text = AttributedText("https://");
  }

  @override
  void didUpdateWidget(FormattingToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.editor != oldWidget.editor) {
      oldWidget.editor.removeListener(_editListener);
      widget.editor.addListener(_editListener);
    }

    final newComposer = widget.editor.composer;
    if (newComposer != _composer) {
      _composer.selectionNotifier.removeListener(_onSelectionChange);
      _composer = newComposer;
      _composer.selectionNotifier.addListener(_onSelectionChange);
    }

    _document = widget.editor.document;
  }

  @override
  void dispose() {
    _urlFocusNode.dispose();
    _linkPopoverController.dispose();

    _composer.selectionNotifier.removeListener(_onSelectionChange);
    widget.editor.removeListener(_editListener);

    super.dispose();
  }

  void _onEdit(List<EditEvent> changes) {
    if (changes.whereType<DocumentEdit>().isEmpty) {
      return;
    }

    // It's possible that even without a selection change, the document
    // styles changed out from under our selection. Re-compute the fully
    // selected text formats.
    _updateFormatButtonStates();
  }

  void _onSelectionChange() {
    _updateFormatButtonStates();
  }

  /// Inspects the selected text and updates all toolbar format buttons based on
  /// any formatting throughout the currently selected text.
  void _updateFormatButtonStates() {
    final selection = _composer.selection;
    final fullySelectedTextFormats = _findFullySelectedTextFormats(selection);

    setState(() {
      _fullySelectedTextFormats
        ..clear()
        ..addAll(fullySelectedTextFormats);
    });
  }

  Set<Attribution> _findFullySelectedTextFormats(DocumentSelection? selection) {
    if (selection == null) {
      return {};
    }
    if (selection.isCollapsed) {
      return {};
    }

    return _document.getAllAttributions(selection);
  }

  void _showUrlPopover() {
    _linkPopoverController.open();
    _urlFocusNode.requestFocus();
  }

  void _onUrlFieldPerformAction(TextInputAction action) {
    if (action == TextInputAction.done) {
      _applyLink();
    }
  }

  /// Applies the link entered on the URL textfield to the current
  /// selected range.
  void _applyLink() {
    final url = _urlController!.text.text;

    final selection = widget.editor.composer.selection!;
    final baseOffset = (selection.base.nodePosition as TextPosition).offset;
    final extentOffset = (selection.extent.nodePosition as TextPosition).offset;
    final selectionStart = min(baseOffset, extentOffset);
    final selectionEnd = max(baseOffset, extentOffset);
    final selectionRange = TextRange(start: selectionStart, end: selectionEnd - 1);

    final textNodePath = selection.extent.documentPath;
    final textNode = widget.editor.document.getNodeById(textNodePath.targetNodeId) as TextNode;
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

  void _showImagePopover() {
    _imagePopoverController.open();
    _imageFocusNode.requestFocus();
  }

  void _onImageFieldPerformAction(TextInputAction action) {
    if (action == TextInputAction.done) {
      _applyImageUrl();
    }
  }

  void _applyImageUrl() {
    final url = _imageController!.text.text;

    final selection = widget.editor.composer.selection;
    if (selection != null) {
      widget.editor.execute([
        if (!selection.isCollapsed) //
          DeleteContentRequest(documentRange: selection),
        InsertNodeAtCaretRequest(
          node: ImageNode(
            id: Editor.createNodeId(),
            imageUrl: url,
          ),
        ),
      ]);
    }

    // Clear the field and hide the URL bar
    _imageController!.clearTextAndSelection();
    _imageFocusNode.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
    _imagePopoverController.close();
    setState(() {});
  }

  /// Given [text] and a [range] within the [text], the [range] is
  /// shortened on both sides to remove any trailing whitespace and
  /// the new range is returned.
  SpanRange _trimTextRangeWhitespace(AttributedText text, TextRange range) {
    int startOffset = range.start;
    int endOffset = range.end;

    while (startOffset < range.end && text.text[startOffset] == ' ') {
      startOffset += 1;
    }
    while (endOffset > startOffset && text.text[endOffset] == ' ') {
      endOffset -= 1;
    }

    // Add 1 to the end offset because SpanRange treats the end offset to be exclusive.
    return SpanRange(startOffset, endOffset + 1);
  }

  void _indent() {
    final selection = _composer.selection;
    if (selection == null) {
      return;
    }

    final extentNode = _document.getNodeById(selection.extent.targetNodeId);
    if (extentNode is! TextNode) {
      return;
    }

    if (extentNode is ParagraphNode) {
      widget.editor.execute([
        IndentParagraphRequest(extentNode.id),
      ]);
    } else if (extentNode is ListItemNode) {
      widget.editor.execute([
        IndentListItemRequest(nodeId: extentNode.id),
      ]);
    } else if (extentNode is TaskNode) {
      widget.editor.execute([
        IndentTaskRequest(extentNode.id),
      ]);
    }
  }

  void _unindent() {
    final selection = _composer.selection;
    if (selection == null) {
      return;
    }

    final extentNode = _document.getNodeById(selection.extent.targetNodeId);
    if (extentNode is! TextNode) {
      return;
    }

    if (extentNode is ParagraphNode) {
      widget.editor.execute([
        UnIndentParagraphRequest(extentNode.id),
      ]);
    } else if (extentNode is ListItemNode) {
      widget.editor.execute([
        UnIndentListItemRequest(nodeId: extentNode.id),
      ]);
    } else if (extentNode is TaskNode) {
      widget.editor.execute([
        UnIndentTaskRequest(extentNode.id),
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = _composer.selection;
    DocumentNode? extentNode;
    FeatherTextBlock? selectedBlockFormat;
    if (selection != null) {
      extentNode = _document.getNodeById(selection.extent.targetNodeId);
      if (extentNode is TextNode) {
        selectedBlockFormat =
            selection.base.nodeId == selection.extent.nodeId ? FeatherTextBlock.fromNode(extentNode) : null;
      }
    }

    return IconTheme(
      data: const IconThemeData(
        size: 20,
      ),
      child: Wrap(
        children: [
          _ToggleInlineFormatButton(
            editor: widget.editor,
            icon: Icons.format_bold,
            format: boldAttribution,
            selectedFormats: _fullySelectedTextFormats,
          ),
          _ToggleInlineFormatButton(
            editor: widget.editor,
            icon: Icons.format_italic,
            format: italicsAttribution,
            selectedFormats: _fullySelectedTextFormats,
          ),
          _ToggleInlineFormatButton(
            editor: widget.editor,
            icon: Icons.format_underline,
            format: underlineAttribution,
            selectedFormats: _fullySelectedTextFormats,
          ),
          _ToggleInlineFormatButton(
            editor: widget.editor,
            icon: Icons.strikethrough_s,
            format: strikethroughAttribution,
            selectedFormats: _fullySelectedTextFormats,
          ),
          _buildSpacer(),
          _ToggleBlockFormatButton(
            editor: widget.editor,
            icon: Icons.format_quote,
            format: FeatherTextBlock.blockquote,
            selectedBlockFormat: selectedBlockFormat,
          ),
          _ToggleBlockFormatButton(
            editor: widget.editor,
            icon: Icons.code,
            format: FeatherTextBlock.code,
            selectedBlockFormat: selectedBlockFormat,
          ),
          _buildSpacer(),
          _buildLinkButton(),
          _buildImageButton(),
          const IconButton(
            icon: Icon(Icons.video_file),
            onPressed: null,
          ),
          const IconButton(
            icon: Icon(Symbols.function),
            onPressed: null,
          ),
          _buildSpacer(),
          _ToggleBlockFormatButton(
            editor: widget.editor,
            icon: Symbols.format_h1,
            format: FeatherTextBlock.header1,
            selectedBlockFormat: selectedBlockFormat,
          ),
          _ToggleBlockFormatButton(
            editor: widget.editor,
            icon: Symbols.format_h2,
            iconSize: 14,
            format: FeatherTextBlock.header2,
            selectedBlockFormat: selectedBlockFormat,
          ),
          _buildSpacer(),
          _ToggleBlockFormatButton(
            editor: widget.editor,
            icon: Icons.format_list_numbered,
            format: FeatherTextBlock.orderedListItem,
            selectedBlockFormat: selectedBlockFormat,
          ),
          _ToggleBlockFormatButton(
            editor: widget.editor,
            icon: Icons.format_list_bulleted,
            format: FeatherTextBlock.unorderedListItem,
            selectedBlockFormat: selectedBlockFormat,
          ),
          _ToggleBlockFormatButton(
            editor: widget.editor,
            icon: Icons.checklist,
            format: FeatherTextBlock.task,
            selectedBlockFormat: selectedBlockFormat,
          ),
          _buildSpacer(),
          _ToggleInlineFormatButton(
            editor: widget.editor,
            icon: Icons.subscript,
            format: subscriptAttribution,
            selectedFormats: _fullySelectedTextFormats,
          ),
          _ToggleInlineFormatButton(
            editor: widget.editor,
            icon: Icons.superscript,
            format: superscriptAttribution,
            selectedFormats: _fullySelectedTextFormats,
          ),
          _buildSpacer(),
          IconButton(
            onPressed: _unindent,
            icon: const Icon(Icons.format_indent_decrease),
          ),
          IconButton(
            onPressed: _indent,
            icon: const Icon(Icons.format_indent_increase),
          ),
          _buildSpacer(),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.format_textdirection_l_to_r),
          ),
          _buildSpacer(),
          _NamedTextSizeSelector(
            editorFocusNode: widget.editorFocusNode,
            editor: widget.editor,
          ),
          _buildSpacer(),
          _HeaderSelector(
            editorFocusNode: widget.editorFocusNode,
            editor: widget.editor,
          ),
          _buildSpacer(),
          _TextColorButton(
            editorFocusNode: widget.editorFocusNode,
            editor: widget.editor,
          ),
          _HighlightColorButton(
            editorFocusNode: widget.editorFocusNode,
            editor: widget.editor,
          ),
          _buildSpacer(),
          _FontFamilySelector(
            editorFocusNode: widget.editorFocusNode,
            editor: widget.editor,
          ),
          _buildSpacer(),
          _AlignmentButton(
            editorFocusNode: widget.editorFocusNode,
            editor: widget.editor,
          ),
          _buildSpacer(),
          IconButton(
            onPressed: () {
              widget.editor.execute([
                const ClearSelectedStylesRequest(),
              ]);
            },
            icon: const Icon(Icons.format_clear),
          ),
          _buildSpacer(),
          IconButton(
            icon: Icon(widget.isShowingDeltas ? Symbols.close : Symbols.menu_open),
            onPressed: () {
              widget.onShowDeltasChange(!widget.isShowingDeltas);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSpacer() => const SizedBox(width: 24);

  /// Builds the link button, which upon tap shows a popover for the user
  /// to enter a URL.
  Widget _buildLinkButton() {
    return PopoverScaffold(
      parentFocusNode: widget.editorFocusNode,
      tapRegionGroupId: _tapRegionGroupId,
      onTapOutside: (controller) => _linkPopoverController.close(),
      controller: _linkPopoverController,
      buttonBuilder: (context) => IconButton(
        onPressed: _showUrlPopover,
        icon: const Icon(Icons.link),
      ),
      popoverBuilder: (context) => _buildLinkPopover(),
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

  /// Builds the image button, which upon tap shows a popover for the user
  /// to enter a URL for an image.
  Widget _buildImageButton() {
    return PopoverScaffold(
      parentFocusNode: widget.editorFocusNode,
      tapRegionGroupId: _tapRegionGroupId,
      onTapOutside: (controller) => _imagePopoverController.close(),
      controller: _imagePopoverController,
      buttonBuilder: (context) => IconButton(
        onPressed: _showImagePopover,
        icon: const Icon(Icons.image),
      ),
      popoverBuilder: (context) => _buildImagePopover(),
    );
  }

  Widget _buildImagePopover() {
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
                focusNode: _imageFocusNode,
                textController: _imageController,
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
                  _imageFocusNode.unfocus();
                  _imageController!.clearTextAndSelection();
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleInlineFormatButton extends StatelessWidget {
  const _ToggleInlineFormatButton({
    required this.editor,
    required this.icon,
    required this.format,
    required this.selectedFormats,
  });

  final Editor editor;
  final IconData icon;
  final Attribution format;
  final Set<Attribution> selectedFormats;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      color: selectedFormats.contains(format) ? Colors.blue : Colors.black,
      onPressed: () {
        editor.execute([
          ToggleInlineFormatRequest(format),
        ]);
      },
    );
  }
}

class _ToggleBlockFormatButton extends StatelessWidget {
  const _ToggleBlockFormatButton({
    required this.editor,
    required this.icon,
    this.iconSize,
    required this.format,
    required this.selectedBlockFormat,
  });

  final Editor editor;
  final IconData icon;
  final double? iconSize;
  final FeatherTextBlock format;
  final FeatherTextBlock? selectedBlockFormat;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      iconSize: iconSize,
      color: format == selectedBlockFormat ? Colors.blue : Colors.black,
      onPressed: () {
        editor.execute([
          ToggleTextBlockFormatRequest(format),
        ]);
      },
    );
  }
}

class _NamedTextSizeSelector extends StatefulWidget {
  const _NamedTextSizeSelector({
    required this.editorFocusNode,
    required this.editor,
  });

  final FocusNode editorFocusNode;
  final Editor editor;

  @override
  State<StatefulWidget> createState() => _NamedTextSizeSelectorState();
}

class _NamedTextSizeSelectorState extends State<_NamedTextSizeSelector> {
  static const _defaultSizeName = "Normal";
  static const _sizeNames = ["Huge", "Large", _defaultSizeName, "Small"];

  void _onChangeSizeRequested(String? newSizeName) {
    if (newSizeName == null) {
      return;
    }

    final selection = widget.editor.composer.selection;
    if (selection == null) {
      return;
    }
    if (selection.base.nodeId != selection.extent.nodeId) {
      return;
    }

    final selectedNode = widget.editor.document.getNodeById(selection.extent.targetNodeId);
    if (selectedNode is! TextNode) {
      return;
    }

    widget.editor.execute([
      AddTextAttributionsRequest(
        documentRange: selection,
        attributions: {
          NamedFontSizeAttribution(newSizeName),
        },
      ),
    ]);

    // Rebuild to update the selected font on the toolbar.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selectedFontSizeName = _getAllAttributions(widget.editor.document, widget.editor.composer)
            .whereType<NamedFontSizeAttribution>()
            .firstOrNull
            ?.fontSizeName ??
        _defaultSizeName;
    final textItem = TextItem(id: selectedFontSizeName, label: selectedFontSizeName);

    return TextItemSelector(
      parentFocusNode: widget.editorFocusNode,
      tapRegionGroupId: "selector_font-size-name",
      selectedText: textItem,
      items: _sizeNames.map((name) => TextItem(id: name, label: name)).toList(),
      onSelected: (value) => _onChangeSizeRequested(value?.id),
      buttonSize: const Size(97, 30),
      popoverGeometry: const PopoverGeometry(
        constraints: BoxConstraints.tightFor(width: 247),
        aligner: FunctionalPopoverAligner(popoverAligner),
      ),
      itemBuilder: (context, item, isActive, onTap) {
        return DecoratedBox(
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
                    style: TextStyle(
                      color: Colors.black,
                      fontFamily: item.id,
                      fontSize: themeFontSizeByName[item.id],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeaderSelector extends StatefulWidget {
  const _HeaderSelector({
    required this.editorFocusNode,
    required this.editor,
  });

  final FocusNode editorFocusNode;
  final Editor editor;

  @override
  State<StatefulWidget> createState() => _HeaderSelectorState();
}

class _HeaderSelectorState extends State<_HeaderSelector> {
  static const _headingLevelNames = [
    "Heading 1",
    "Heading 2",
    "Heading 3",
    "Heading 4",
    "Heading 5",
    "Heading 6",
    "Normal",
  ];
  static const _headerLevelFormats = {
    "Heading 1": FeatherTextBlock.header1,
    "Heading 2": FeatherTextBlock.header2,
    "Heading 3": FeatherTextBlock.header3,
    "Heading 4": FeatherTextBlock.header4,
    "Heading 5": FeatherTextBlock.header5,
    "Heading 6": FeatherTextBlock.header6,
    "Normal": FeatherTextBlock.paragraph,
  };
  static final _headerLevelNames = {
    header1Attribution: "Heading 1",
    header2Attribution: "Heading 2",
    header3Attribution: "Heading 3",
    header4Attribution: "Heading 4",
    header5Attribution: "Heading 5",
    header6Attribution: "Heading 6",
    paragraphAttribution: "Normal",
    null: "Normal",
  };

  void _onChangeHeadingLevelRequested(String? newHeadingLevel) {
    final selection = widget.editor.composer.selection;
    if (selection == null) {
      return;
    }
    if (selection.base.nodeId != selection.extent.nodeId) {
      return;
    }

    final selectedNode = widget.editor.document.getNodeById(selection.extent.targetNodeId);
    if (selectedNode is! TextNode) {
      return;
    }

    widget.editor.execute([
      ConvertTextBlockToFormatRequest(_headerLevelFormats[newHeadingLevel]!),
    ]);

    // Rebuild to update the selected font on the toolbar.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final composer = widget.editor.composer;
    final selection = composer.selection;
    var selectedHeaderLevel = "Normal";
    if (selection != null && selection.base.nodeId == selection.extent.nodeId) {
      final selectedNode = widget.editor.document.getNodeById(selection.extent.targetNodeId);
      if (selectedNode is ParagraphNode) {
        selectedHeaderLevel = _headerLevelNames[selectedNode.getMetadataValue("blockType")] ?? "Normal";
      }
    }
    final textItem = TextItem(id: selectedHeaderLevel, label: selectedHeaderLevel);

    return TextItemSelector(
      parentFocusNode: widget.editorFocusNode,
      // tapRegionGroupId: _tapRegionGroupId,
      selectedText: textItem,
      items: _headingLevelNames.map((headingName) => TextItem(id: headingName, label: headingName)).toList(),
      onSelected: (value) => _onChangeHeadingLevelRequested(value?.id),
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
                  style: TextStyle(
                    color: Colors.black,
                    fontFamily: item.id,
                    fontSize: themeHeaderFontSizeByName[item.id],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TextColorButton extends StatefulWidget {
  const _TextColorButton({
    required this.editorFocusNode,
    required this.editor,
  });

  final FocusNode editorFocusNode;
  final Editor editor;

  @override
  State<_TextColorButton> createState() => _TextColorButtonState();
}

class _TextColorButtonState extends State<_TextColorButton> {
  void _onChangeTextColorRequested(Color? newColor) {
    final selection = widget.editor.composer.selection;
    if (selection == null) {
      return;
    }

    final colorAttributions = widget.editor.document.getAttributionsByType<ColorAttribution>(selection);

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

  @override
  Widget build(BuildContext context) {
    return ColorSelector(
      parentFocusNode: widget.editorFocusNode,
      // tapRegionGroupId: _tapRegionGroupId,
      onSelected: _onChangeTextColorRequested,
      showClearButton: true,
      colorButtonBuilder: (_, color) => _buildTextColorIcon(color),
    );
  }

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
}

class _HighlightColorButton extends StatefulWidget {
  const _HighlightColorButton({
    required this.editorFocusNode,
    required this.editor,
  });

  final FocusNode editorFocusNode;
  final Editor editor;

  @override
  State<_HighlightColorButton> createState() => _HighlightColorButtonState();
}

class _HighlightColorButtonState extends State<_HighlightColorButton> {
  void _onChangeHighlightColorRequested(Color? newColor) {
    final selection = widget.editor.composer.selection;
    if (selection == null) {
      return;
    }

    final colorAttributions = widget.editor.document.getAttributionsByType<BackgroundColorAttribution>(selection);

    widget.editor.execute([
      for (final existingAttribution in colorAttributions) //
        RemoveTextAttributionsRequest(documentRange: selection, attributions: {existingAttribution}),
      if (newColor != null) //
        AddTextAttributionsRequest(
          documentRange: selection,
          attributions: {BackgroundColorAttribution(newColor)},
        ),
    ]);

    // Rebuild to update the color on the toolbar button.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ColorSelector(
      parentFocusNode: widget.editorFocusNode,
      onSelected: _onChangeHighlightColorRequested,
      showClearButton: true,
      colorButtonBuilder: (_, color) => _buildHighlightColorIcon(color),
    );
  }

  Widget _buildHighlightColorIcon(Color? color) {
    return Stack(
      children: [
        const Icon(Icons.texture),
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
}

class _FontFamilySelector extends StatefulWidget {
  const _FontFamilySelector({
    required this.editorFocusNode,
    required this.editor,
  });

  final FocusNode editorFocusNode;
  final Editor editor;

  @override
  State<_FontFamilySelector> createState() => _FontFamilySelectorState();
}

class _FontFamilySelectorState extends State<_FontFamilySelector> {
  static const _availableFonts = ["Sans Serif", "Serif", "Monospace"];

  void _onChangeFontFamilyRequested(String? newFontFamily) {
    final selection = widget.editor.composer.selection;
    if (selection == null) {
      return;
    }

    final fontFamilyAttributions = widget.editor.document.getAttributionsByType<FontFamilyAttribution>(selection);

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

  @override
  Widget build(BuildContext context) {
    const defaultFont = 'Sans Serif';

    final selectedFont = _getAllAttributions(widget.editor.document, widget.editor.composer)
            .whereType<FontFamilyAttribution>()
            .firstOrNull
            ?.fontFamily ??
        defaultFont;
    final textItem = TextItem(id: selectedFont, label: selectedFont);

    return TextItemSelector(
      parentFocusNode: widget.editorFocusNode,
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
                  style: TextStyle(
                    color: Colors.black,
                    fontFamily: item.id,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlignmentButton extends StatefulWidget {
  const _AlignmentButton({
    required this.editorFocusNode,
    required this.editor,
  });

  final FocusNode editorFocusNode;
  final Editor editor;

  @override
  State<_AlignmentButton> createState() => _AlignmentButtonState();
}

class _AlignmentButtonState extends State<_AlignmentButton> {
  @override
  Widget build(BuildContext context) {
    final alignment = _getCurrentTextAlignment();

    return IconSelector(
      parentFocusNode: widget.editorFocusNode,
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
      onSelected: (selectedItem) {
        if (selectedItem == null) {
          return;
        }
        final newAlignment = TextAlign.values.firstWhere((e) => e.name == selectedItem.id);

        final composer = widget.editor.composer;
        final selection = composer.selection;
        if (selection == null) {
          return;
        }

        widget.editor.execute([
          ChangeParagraphAlignmentRequest(
            nodeId: selection.extent.targetNodeId,
            alignment: newAlignment,
          ),
        ]);
      },
    );
  }

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

  /// Returns the text alignment of the currently selected text node.
  ///
  /// Throws an exception if the currently selected node is not a text node.
  TextAlign _getCurrentTextAlignment() {
    final composer = widget.editor.composer;
    final selection = composer.selection;
    if (selection == null) {
      return TextAlign.left;
    }

    final document = widget.editor.document;
    final selectedNode = document.getNodeById(selection.extent.targetNodeId);
    if (selectedNode == null) {
      // Default to "left" when there's no selection. This only effects the
      // icon that's displayed on the toolbar.
      return TextAlign.left;
    }

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
  }
}

/// Returns all attributions of the currently selected range, if the selection is expanded,
/// or the current composer attributes, if the selection is collapsed.
Set<Attribution> _getAllAttributions(Document document, DocumentComposer composer) {
  final selection = composer.selection;
  if (selection == null) {
    return <Attribution>{};
  }

  if (selection.isCollapsed) {
    return composer //
        .preferences
        .currentAttributions;
  }

  return document.getAllAttributions(selection);
}
