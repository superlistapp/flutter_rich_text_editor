import 'dart:io';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'keyboard_overlay_clipper.dart';

/// Mobile Android document editing demo.
///
/// This demo forces the editor into a mobile configuration,
/// no matter which platform or form factor you use.
class MobileEditingAndroidDemo extends StatefulWidget {
  @override
  State<MobileEditingAndroidDemo> createState() => _MobileEditingAndroidDemoState();
}

class _MobileEditingAndroidDemoState extends State<MobileEditingAndroidDemo> {
  final GlobalKey _docLayoutKey = GlobalKey();

  late MutableDocument _doc;
  final _docChangeSignal = SignalNotifier();
  late Editor _docEditor;
  late MutableDocumentComposer _composer;
  late CommonEditorOperations _docOps;
  late MagnifierAndToolbarController _overlayController;

  FocusNode? _editorFocusNode;
  SuperEditorImeConfiguration _imeConfiguration = const SuperEditorImeConfiguration();

  @override
  void initState() {
    super.initState();
    _doc = _createInitialDocument()..addListener(_onDocumentChange);
    _composer = MutableDocumentComposer()..addListener(_configureImeActionButton);
    _docEditor = createDefaultDocumentEditor(document: _doc, composer: _composer);
    _docOps = CommonEditorOperations(
      editor: _docEditor,
      document: _doc,
      composer: _composer,
      documentLayoutResolver: () => _docLayoutKey.currentState as DocumentLayout,
    );
    _editorFocusNode = FocusNode();
    _overlayController = MagnifierAndToolbarController();
  }

  @override
  void dispose() {
    _editorFocusNode!.dispose();
    _composer.dispose();
    _doc.removeListener(_onDocumentChange);
    super.dispose();
  }

  void _onDocumentChange(_) => _docChangeSignal.notifyListeners();

  void _configureImeActionButton() {
    if (_composer.selection == null || !_composer.selection!.isCollapsed) {
      setState(() {
        _imeConfiguration = _imeConfiguration.copyWith(
          keyboardActionButton: TextInputAction.newline,
        );
      });
      return;
    }

    final selectedNode = _doc.getNodeById(_composer.selection!.extent.targetNodeId);
    if (selectedNode is ListItemNode) {
      setState(() {
        _imeConfiguration = _imeConfiguration.copyWith(
          keyboardActionButton: TextInputAction.done,
        );
      });
      return;
    }

    setState(() {
      _imeConfiguration = _imeConfiguration.copyWith(
        keyboardActionButton: TextInputAction.newline,
      );
    });
  }

  void _cut() {
    _docOps.cut();
    _overlayController.hideToolbar();
  }

  void _copy() {
    _docOps.copy();
    _overlayController.hideToolbar();
  }

  void _paste() {
    _docOps.paste();
    _overlayController.hideToolbar();
  }

  @override
  Widget build(BuildContext context) {
    return _buildScaffold(
      child: Column(
        children: [
          Expanded(
            child: SuperEditor(
              focusNode: _editorFocusNode,
              documentLayoutKey: _docLayoutKey,
              editor: _docEditor,
              overlayController: _overlayController,
              gestureMode: DocumentGestureMode.android,
              inputSource: TextInputSource.ime,
              imeConfiguration: _imeConfiguration,
              androidToolbarBuilder: (_) => AndroidTextEditingFloatingToolbar(
                onCutPressed: _cut,
                onCopyPressed: _copy,
                onPastePressed: _paste,
                onSelectAllPressed: () => _docOps.selectAll(),
              ),
              stylesheet: defaultStylesheet.copyWith(
                documentPadding: const EdgeInsets.all(16),
              ),
              createOverlayControlsClipper: (_) => const KeyboardToolbarClipper(),
            ),
          ),
          MultiListenableBuilder(
            listenables: <Listenable>{
              _docChangeSignal,
              _composer.selectionNotifier,
            },
            builder: (_) => _buildMountedToolbar(),
          ),
        ],
      ),
    );
  }

  Widget _buildMountedToolbar() {
    final selection = _composer.selection;

    if (selection == null) {
      return const SizedBox();
    }

    return KeyboardEditingToolbar(
      editor: _docEditor,
      document: _doc,
      composer: _composer,
      commonOps: CommonEditorOperations(
        editor: _docEditor,
        document: _doc,
        composer: _composer,
        documentLayoutResolver: () => _docLayoutKey.currentState as DocumentLayout,
      ),
    );
  }

  Widget _buildScaffold({
    required Widget child,
  }) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isPortrait = constraints.maxHeight / constraints.maxWidth > 1;

          if (Platform.isAndroid || Platform.isIOS || isPortrait) {
            return child;
          } else {
            return _buildPhoneSizedArea(
              child: child,
            );
          }
        },
      ),
    );
  }

  /// Builds an area at the center of the screen that's roughly the size
  /// of a mobile phone screen, with the given [child] constrained to that
  /// area.
  ///
  /// This simulates a layout that's similar to a mobile device.
  Widget _buildPhoneSizedArea({
    required Widget child,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(left: 56, right: 56, bottom: 24),
        child: AspectRatio(
          aspectRatio: 9 / 19.5,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      ),
    );
  }
}

MutableDocument _createInitialDocument() {
  return MutableDocument(
    nodes: [
      ImageNode(
        id: Editor.createNodeId(),
        imageUrl: 'https://i.imgur.com/fSZwM7G.jpg',
      ),
      ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText('Example Document'),
        metadata: {
          'blockType': header1Attribution,
        },
      ),
      HorizontalRuleNode(id: Editor.createNodeId()),
      ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText(
          'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus sed sagittis urna. Aenean mattis ante justo, quis sollicitudin metus interdum id. Aenean ornare urna ac enim consequat mollis. In aliquet convallis efficitur. Phasellus convallis purus in fringilla scelerisque. Ut ac orci a turpis egestas lobortis. Morbi aliquam dapibus sem, vitae sodales arcu ultrices eu. Duis vulputate mauris quam, eleifend pulvinar quam blandit eget.',
        ),
      ),
      ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText('This is a blockquote!'),
        metadata: {
          'blockType': blockquoteAttribution,
        },
      ),
      ListItemNode.unordered(
        id: Editor.createNodeId(),
        text: AttributedText('This is an unordered list item'),
      ),
      ListItemNode.unordered(
        id: Editor.createNodeId(),
        text: AttributedText('This is another list item'),
      ),
      ListItemNode.unordered(
        id: Editor.createNodeId(),
        text: AttributedText('This is a 3rd list item'),
      ),
      ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText(
          'Cras vitae sodales nisi. Vivamus dignissim vel purus vel aliquet. Sed viverra diam vel nisi rhoncus pharetra. Donec gravida ut ligula euismod pharetra. Etiam sed urna scelerisque, efficitur mauris vel, semper arcu. Nullam sed vehicula sapien. Donec id tellus volutpat, eleifend nulla eget, rutrum mauris.',
        ),
      ),
      ListItemNode.ordered(
        id: Editor.createNodeId(),
        text: AttributedText('First thing to do'),
      ),
      ListItemNode.ordered(
        id: Editor.createNodeId(),
        text: AttributedText('Second thing to do'),
      ),
      ListItemNode.ordered(
        id: Editor.createNodeId(),
        text: AttributedText('Third thing to do'),
      ),
      ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText(
          'Nam hendrerit vitae elit ut placerat. Maecenas nec congue neque. Fusce eget tortor pulvinar, cursus neque vitae, sagittis lectus. Duis mollis libero eu scelerisque ullamcorper. Pellentesque eleifend arcu nec augue molestie, at iaculis dui rutrum. Etiam lobortis magna at magna pellentesque ornare. Sed accumsan, libero vel porta molestie, tortor lorem eleifend ante, at egestas leo felis sed nunc. Quisque mi neque, molestie vel dolor a, eleifend tempor odio.',
        ),
      ),
      ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText(
          'Etiam id lacus interdum, efficitur ex convallis, accumsan ipsum. Integer faucibus mollis mauris, a suscipit ante mollis vitae. Fusce justo metus, congue non lectus ac, luctus rhoncus tellus. Phasellus vitae fermentum orci, sit amet sodales orci. Fusce at ante iaculis nunc aliquet pharetra. Nam placerat, nisl in gravida lacinia, nisl nibh feugiat nunc, in sagittis nisl sapien nec arcu. Nunc gravida faucibus massa, sit amet accumsan dolor feugiat in. Mauris ut elementum leo.',
        ),
      ),
    ],
  );
}
