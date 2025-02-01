import 'package:attributed_text/attributed_text.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/default_editor/common_editor_operations.dart';
import 'package:super_editor/src/default_editor/list_items.dart';
import 'package:super_editor/src/default_editor/multi_node_editing.dart';
import 'package:super_editor/src/default_editor/paragraph.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/flutter/flutter_scheduler.dart';
import 'package:super_editor/src/infrastructure/flutter/overlay_with_groups.dart';

import '../attributions.dart';

/// A mobile document editing toolbar, which is displayed in the application
/// [Overlay], and is mounted just above the software keyboard.
///
/// Despite displaying the toolbar in the application [Overlay], [KeyboardEditingToolbar]
/// also (optionally) inserts some blank space into the current subtree, which takes up
/// the same amount of height as the toolbar that appears in the [Overlay].
///
/// Provides document editing capabilities, like converting paragraphs to blockquotes
/// and list items, and inserting horizontal rules.
class KeyboardEditingToolbar extends StatefulWidget {
  const KeyboardEditingToolbar({
    Key? key,
    required this.editor,
    required this.document,
    required this.composer,
    required this.commonOps,
    this.brightness,
    this.takeUpSameSpaceAsToolbar = false,
  }) : super(key: key);

  final Editor editor;
  final Document document;
  final DocumentComposer composer;
  final CommonEditorOperations commonOps;

  @Deprecated("To change the brightness, wrap KeyboardEditingToolbar with a Theme, instead")
  final Brightness? brightness;

  /// Whether this widget should take up empty space in the current subtree that
  /// matches the space taken up by the toolbar in the application [Overlay].
  ///
  /// If `true`, space is taken up that's equivalent to the toolbar height. If
  /// `false`, no space is taken up by this widget at all.
  ///
  /// Taking up empty space is useful when this widget is positioned at the same
  /// location on the screen as the toolbar that's in the overlay. By adding extra
  /// space, other content in this subtree won't flow behind the toolbar in the
  /// [Overlay].
  final bool takeUpSameSpaceAsToolbar;

  @override
  State<KeyboardEditingToolbar> createState() => _KeyboardEditingToolbarState();
}

class _KeyboardEditingToolbarState extends State<KeyboardEditingToolbar> with WidgetsBindingObserver {
  late KeyboardEditingToolbarOperations _toolbarOps;

  final _portalController = GroupedOverlayPortalController(displayPriority: OverlayGroupPriority.windowChrome);

  double _toolbarHeight = 0;

  @override
  void initState() {
    super.initState();

    _toolbarOps = KeyboardEditingToolbarOperations(
      editor: widget.editor,
      document: widget.document,
      composer: widget.composer,
      commonOps: widget.commonOps,
    );

    WidgetsBinding.instance.runAsSoonAsPossible(() {
      _portalController.show();
    });
  }

  @override
  void didUpdateWidget(KeyboardEditingToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);

    _toolbarOps = KeyboardEditingToolbarOperations(
      editor: widget.editor,
      document: widget.document,
      composer: widget.composer,
      commonOps: widget.commonOps,
    );
  }

  @override
  void dispose() {
    if (_portalController.isShowing) {
      _portalController.hide();
    }
    super.dispose();
  }

  void _onToolbarLayout(double toolbarHeight) {
    if (toolbarHeight == _toolbarHeight) {
      return;
    }

    // The toolbar in the overlay changed its height. Our child needs to take up the
    // same amount of height so that content doesn't go behind our toolbar. Rebuild
    // with the latest toolbar height and take up an equal amount of height.
    setStateAsSoonAsPossible(() {
      _toolbarHeight = toolbarHeight;
    });
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: _buildToolbarOverlay,
      // Take up empty space that's as tall as the toolbar so that other content
      // doesn't layout behind it.
      child: SizedBox(height: widget.takeUpSameSpaceAsToolbar ? _toolbarHeight : 0),
    );
  }

  Widget _buildToolbarOverlay(BuildContext context) {
    final selection = widget.composer.selection;
    if (selection == null) {
      return const SizedBox();
    }

    return KeyboardHeightBuilder(builder: (context, keyboardHeight) {
      return Padding(
        // Add padding that takes up the height of the software keyboard so
        // that the toolbar sits just above the keyboard.
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: _buildTheming(
            child: Builder(
              // Add a Builder so that _buildToolbar() uses theming from _buildTheming().
              builder: (themedContext) {
                return _buildToolbar(themedContext);
              },
            ),
          ),
        ),
      );
    });
  }

  Widget _buildTheming({
    required Widget child,
  }) {
    final brightness = widget.brightness ?? MediaQuery.of(context).platformBrightness;

    return Theme(
      data: Theme.of(context).copyWith(
        brightness: brightness,
        disabledColor:
            brightness == Brightness.light ? Colors.black.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.5),
      ),
      child: IconTheme(
        data: IconThemeData(
          color: brightness == Brightness.light ? Colors.black : Colors.white,
        ),
        child: child,
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final selection = widget.composer.selection!;

    return Material(
      child: Container(
        width: double.infinity,
        height: 48,
        color: Theme.of(context).brightness == Brightness.light ? const Color(0xFFDDDDDD) : const Color(0xFF222222),
        child: LayoutBuilder(builder: (context, constraints) {
          _onToolbarLayout(constraints.maxHeight);

          return Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ListenableBuilder(
                      listenable: widget.composer,
                      builder: (context, _) {
                        final selectedNode = widget.document.getNodeById(selection.extent.nodeId);
                        final isSingleNodeSelected = selection.extent.nodeId == selection.base.nodeId;

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: selectedNode is TextNode ? _toolbarOps.toggleBold : null,
                              icon: const Icon(Icons.format_bold),
                              color: _toolbarOps.isBoldActive ? Theme.of(context).primaryColor : null,
                            ),
                            IconButton(
                              onPressed: selectedNode is TextNode ? _toolbarOps.toggleItalics : null,
                              icon: const Icon(Icons.format_italic),
                              color: _toolbarOps.isItalicsActive ? Theme.of(context).primaryColor : null,
                            ),
                            IconButton(
                              onPressed: selectedNode is TextNode ? _toolbarOps.toggleUnderline : null,
                              icon: const Icon(Icons.format_underline),
                              color: _toolbarOps.isUnderlineActive ? Theme.of(context).primaryColor : null,
                            ),
                            IconButton(
                              onPressed: selectedNode is TextNode ? _toolbarOps.toggleStrikethrough : null,
                              icon: const Icon(Icons.strikethrough_s),
                              color: _toolbarOps.isStrikethroughActive ? Theme.of(context).primaryColor : null,
                            ),
                            IconButton(
                              onPressed: isSingleNodeSelected &&
                                      (selectedNode is TextNode &&
                                          selectedNode.getMetadataValue('blockType') != header1Attribution)
                                  ? _toolbarOps.convertToHeader1
                                  : null,
                              icon: const Icon(Icons.title),
                            ),
                            IconButton(
                              onPressed: isSingleNodeSelected &&
                                      (selectedNode is TextNode &&
                                          selectedNode.getMetadataValue('blockType') != header2Attribution)
                                  ? _toolbarOps.convertToHeader2
                                  : null,
                              icon: const Icon(Icons.title),
                              iconSize: 18,
                            ),
                            IconButton(
                              onPressed: isSingleNodeSelected &&
                                      ((selectedNode is ParagraphNode && selectedNode.hasMetadataValue('blockType')) ||
                                          (selectedNode is TextNode && selectedNode is! ParagraphNode))
                                  ? _toolbarOps.convertToParagraph
                                  : null,
                              icon: const Icon(Icons.wrap_text),
                            ),
                            IconButton(
                              onPressed: isSingleNodeSelected &&
                                      (selectedNode is TextNode && selectedNode is! ListItemNode ||
                                          (selectedNode is ListItemNode && selectedNode.type != ListItemType.ordered))
                                  ? _toolbarOps.convertToOrderedListItem
                                  : null,
                              icon: const Icon(Icons.looks_one_rounded),
                            ),
                            IconButton(
                              onPressed: isSingleNodeSelected &&
                                      (selectedNode is TextNode && selectedNode is! ListItemNode ||
                                          (selectedNode is ListItemNode && selectedNode.type != ListItemType.unordered))
                                  ? _toolbarOps.convertToUnorderedListItem
                                  : null,
                              icon: const Icon(Icons.list),
                            ),
                            IconButton(
                              onPressed: isSingleNodeSelected &&
                                      selectedNode is TextNode &&
                                      (selectedNode is! ParagraphNode ||
                                          selectedNode.getMetadataValue('blockType') != blockquoteAttribution)
                                  ? _toolbarOps.convertToBlockquote
                                  : null,
                              icon: const Icon(Icons.format_quote),
                            ),
                            IconButton(
                              onPressed:
                                  isSingleNodeSelected && selectedNode is ParagraphNode && selectedNode.text.isEmpty
                                      ? _toolbarOps.convertToHr
                                      : null,
                              icon: const Icon(Icons.horizontal_rule),
                            ),
                          ],
                        );
                      }),
                ),
              ),
              Container(
                width: 1,
                height: 32,
                color: const Color(0xFFCCCCCC),
              ),
              IconButton(
                onPressed: _toolbarOps.closeKeyboard,
                icon: const Icon(Icons.keyboard_hide),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// Builds (and rebuilds) a [builder] with the current height of the software keyboard.
///
/// There's no explicit property for the software keyboard height. This builder uses
/// `EdgeInsets.fromViewPadding(View.of(context).viewInsets, View.of(context).devicePixelRatio).bottom`
/// as a proxy for the height of the software keyboard.
class KeyboardHeightBuilder extends StatefulWidget {
  const KeyboardHeightBuilder({
    super.key,
    required this.builder,
  });

  final Widget Function(BuildContext, double keyboardHeight) builder;

  @override
  State<KeyboardHeightBuilder> createState() => _KeyboardHeightBuilderState();
}

class _KeyboardHeightBuilderState extends State<KeyboardHeightBuilder> with WidgetsBindingObserver {
  double _keyboardHeight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final keyboardHeight =
        EdgeInsets.fromViewPadding(View.of(context).viewInsets, View.of(context).devicePixelRatio).bottom;
    if (keyboardHeight == _keyboardHeight) {
      return;
    }

    setState(() {
      _keyboardHeight = keyboardHeight;
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _keyboardHeight);
  }
}

@visibleForTesting
class KeyboardEditingToolbarOperations {
  KeyboardEditingToolbarOperations({
    required this.editor,
    required this.document,
    required this.composer,
    required this.commonOps,
    this.brightness,
  });

  final Editor editor;
  final Document document;
  final DocumentComposer composer;
  final CommonEditorOperations commonOps;
  final Brightness? brightness;

  bool get isBoldActive => _doesSelectionHaveAttributions({boldAttribution});
  void toggleBold() => _toggleAttributions({boldAttribution});

  bool get isItalicsActive => _doesSelectionHaveAttributions({italicsAttribution});
  void toggleItalics() => _toggleAttributions({italicsAttribution});

  bool get isUnderlineActive => _doesSelectionHaveAttributions({underlineAttribution});
  void toggleUnderline() => _toggleAttributions({underlineAttribution});

  bool get isStrikethroughActive => _doesSelectionHaveAttributions({strikethroughAttribution});
  void toggleStrikethrough() => _toggleAttributions({strikethroughAttribution});

  bool _doesSelectionHaveAttributions(Set<Attribution> attributions) {
    final selection = composer.selection;
    if (selection == null) {
      return false;
    }

    if (selection.isCollapsed) {
      return composer.preferences.currentAttributions.containsAll(attributions);
    }

    return document.doesSelectedTextContainAttributions(selection, attributions);
  }

  void _toggleAttributions(Set<Attribution> attributions) {
    final selection = composer.selection;
    if (selection == null) {
      return;
    }

    selection.isCollapsed
        ? commonOps.toggleComposerAttributions(attributions)
        : commonOps.toggleAttributionsOnSelection(attributions);
  }

  void convertToHeader1() {
    final selectedNode = document.getNodeById(composer.selection!.extent.nodeId);
    if (selectedNode is! TextNode) {
      return;
    }

    if (selectedNode is ListItemNode) {
      commonOps.convertToParagraph(
        newMetadata: {
          'blockType': header1Attribution,
        },
      );
    } else {
      editor.execute([
        ChangeParagraphBlockTypeRequest(
          nodeId: selectedNode.id,
          blockType: header1Attribution,
        ),
      ]);
    }
  }

  void convertToHeader2() {
    final selectedNode = document.getNodeById(composer.selection!.extent.nodeId);
    if (selectedNode is! TextNode) {
      return;
    }

    if (selectedNode is ListItemNode) {
      commonOps.convertToParagraph(
        newMetadata: {
          'blockType': header2Attribution,
        },
      );
    } else {
      editor.execute([
        ChangeParagraphBlockTypeRequest(
          nodeId: selectedNode.id,
          blockType: header2Attribution,
        ),
      ]);
    }
  }

  void convertToParagraph() {
    commonOps.convertToParagraph();
  }

  void convertToOrderedListItem() {
    final selectedNode = document.getNodeById(composer.selection!.extent.nodeId)! as TextNode;

    commonOps.convertToListItem(ListItemType.ordered, selectedNode.text);
  }

  void convertToUnorderedListItem() {
    final selectedNode = document.getNodeById(composer.selection!.extent.nodeId)! as TextNode;

    commonOps.convertToListItem(ListItemType.unordered, selectedNode.text);
  }

  void convertToBlockquote() {
    final selectedNode = document.getNodeById(composer.selection!.extent.nodeId)! as TextNode;

    commonOps.convertToBlockquote(selectedNode.text);
  }

  void convertToHr() {
    final selectedNode = document.getNodeById(composer.selection!.extent.nodeId)! as TextNode;

    editor.execute([
      ReplaceNodeRequest(
        existingNodeId: selectedNode.id,
        newNode: ParagraphNode(
          id: selectedNode.id,
          text: AttributedText('---'),
        ),
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: document.getPathByNodeId(selectedNode.id)!,
            nodePosition: const TextNodePosition(offset: 3),
          ),
        ),
        SelectionChangeType.insertContent,
        SelectionReason.userInteraction,
      ),
      InsertCharacterAtCaretRequest(character: " "),
    ]);
  }

  void closeKeyboard() {
    editor.execute([
      const ChangeSelectionRequest(
        null,
        SelectionChangeType.clearSelection,
        SelectionReason.userInteraction,
      ),
    ]);
  }
}
