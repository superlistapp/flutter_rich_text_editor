import 'package:example/demos/mobile_chat/giphy_keyboard_panel.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_keyboard/super_keyboard.dart';

/// A UI with a chat message editor at the bottom, and a fake chat conversation
/// behind it.
///
/// The following are some of the behaviors that should/need to exist in
/// this demo:
///
///  * Chat message editor is mounted to bottom of screen and sits in front of
///    chat content/messages.
///  * When the user taps on the chat editor, it raises the keyboard, and shows
///    a formatting toolbar above the keyboard.
///  * The user can open/close panels that replace the keyboard.
///  * While the keyboard/panel is up, the user can launch a modal, which closes
///    the keyboard/panel, then upon return from the modal, the keyboard/panel re-opens.
///  * The user can press a button on the toolbar to close the keyboard.
///  * The user can tap on the chat conversation to close the keyboard.
///  * While the keyboard/panel is up, the user can navigate to another tab, and the
///    keyboard/panel automatically close, and the safe area goes away.
///
class MobileChatDemo extends StatefulWidget {
  const MobileChatDemo({super.key});

  @override
  State<MobileChatDemo> createState() => _MobileChatDemoState();
}

class _MobileChatDemoState extends State<MobileChatDemo> {
  final FocusNode _screenFocusNode = FocusNode();

  final FocusNode _editorFocusNode = FocusNode();
  late final Editor _editor;

  late final KeyboardPanelController<_Panel> _keyboardPanelController;
  final SoftwareKeyboardController _softwareKeyboardController = SoftwareKeyboardController();

  final _imeConnectionNotifier = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();

    SuperKeyboard.initLogs();
    initLoggers(Level.ALL, {keyboardPanelLog});

    final document = MutableDocument.empty();
    final composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(document: document, composer: composer);

    _keyboardPanelController = KeyboardPanelController(_softwareKeyboardController);

    // Initially focus the overall screen so that the software keyboard isn't immediately
    // visible.
    _screenFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _imeConnectionNotifier.dispose();
    _keyboardPanelController.dispose();
    _editorFocusNode.dispose();
    _screenFocusNode.dispose();
    super.dispose();
  }

  void _openPanelFromAppBar() {
    // This action is here to verify that we can open keyboard panels
    // before opening the keyboard.

    // Focus the editor and place the caret.
    _editorFocusNode.requestFocus();
    final document = _editor.context.document;
    _editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: NodePath.forNode(document.last.id),
            nodePosition: document.last.endPosition,
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);

    // Open a panel.
    _keyboardPanelController.showKeyboardPanel(_Panel.panel1);
  }

  void _togglePanel(_Panel panel) {
    if (_keyboardPanelController.openPanel == panel) {
      _keyboardPanelController.showSoftwareKeyboard();
    } else {
      _keyboardPanelController.showKeyboardPanel(panel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardScaffoldSafeAreaScope(
      // ^ Share keyboard inset info throughout all subtrees. The insets will
      //   be reported by the subtree with the editor. Those insets might then
      //   be used by the subtree with page content, etc.
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: _buildAppBar(),
          body: TabBarView(children: [
            _buildChatPage(),
            _buildAccountPage(),
          ]),
          resizeToAvoidBottomInset: false,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      actions: [
        IconButton(
          icon: Icon(Icons.open_in_new),
          onPressed: _openPanelFromAppBar,
        ),
        IconButton(
          icon: Icon(Icons.settings),
          onPressed: () {
            Navigator.of(context).pushNamed("/second");
          },
        ),
      ],
      bottom: const TabBar(
        tabs: [
          Tab(icon: Icon(Icons.chat)),
          Tab(icon: Icon(Icons.account_circle)),
        ],
      ),
    );
  }

  Widget _buildChatPage() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    _screenFocusNode.requestFocus();
                    _keyboardPanelController.closeKeyboardAndPanel();
                  },
                  child: Focus(
                    focusNode: _screenFocusNode,
                    child: ColoredBox(
                      color: Colors.white,
                      child: KeyboardScaffoldSafeArea(
                        child: ListView.builder(
                          // TODO: we need a solution to ensure this chat list has bottom
                          //       padding large enough to account for the (dynamic) height
                          //       of the editor.
                          itemCount: 10,
                          itemBuilder: (context, index) {
                            return Container(
                              height: 150,
                              margin: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 16,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: KeyboardScaffoldSafeArea(
                  child: _buildCommentEditor(),
                ),
              ),
            ],
          ),
        ),
        // We build a small status area to ensure that things work correctly
        // when the chat editor isn't at the absolute bottom of the screen.
        // Our earlier bottom inset logic didn't account for this, and broke
        // in a client app, where that app had persistent bottom tabs.
        _buildChatStatus(context),
      ],
    );
  }

  Widget _buildCommentEditor() {
    return Opacity(
      // Opacity is here so we can easily check what's behind it.
      opacity: 1.0,
      child: KeyboardPanelScaffold<_Panel>(
        controller: _keyboardPanelController,
        isImeConnected: _imeConnectionNotifier,
        toolbarBuilder: _buildKeyboardToolbar,
        fallbackPanelHeight: MediaQuery.sizeOf(context).height / 3,
        keyboardPanelBuilder: (context, panel) {
          switch (panel) {
            case _Panel.panel1:
              return Container(
                color: Colors.blue,
                height: double.infinity,
              );
            case _Panel.panel2:
              return Container(
                color: Colors.red,
                height: double.infinity,
              );
            case _Panel.giphy:
              return GiphyKeyboardPanel(
                editor: _editor,
              );
            default:
              return const SizedBox();
          }
        },
        contentBuilder: (context, isKeyboardVisible) {
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 250),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                border: Border(
                  top: BorderSide(width: 1, color: Colors.grey),
                  left: BorderSide(width: 1, color: Colors.grey),
                  right: BorderSide(width: 1, color: Colors.grey),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.075),
                    blurRadius: 8,
                    spreadRadius: 4,
                  ),
                ],
              ),
              padding: const EdgeInsets.only(top: 16),
              child: CustomScrollView(
                shrinkWrap: true,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.only(
                      bottom: KeyboardScaffoldSafeAreaScope.of(context).geometry.bottomPadding,
                      // ^ Push the editor up above the OS bottom notch.
                    ),
                    sliver: SuperEditor(
                      editor: _editor,
                      focusNode: _editorFocusNode,
                      softwareKeyboardController: _softwareKeyboardController,
                      shrinkWrap: true,
                      stylesheet: _chatStylesheet,
                      selectionPolicies: const SuperEditorSelectionPolicies(
                        openKeyboardWhenTappingExistingSelection: false,
                        clearSelectionWhenEditorLosesFocus: true,
                        clearSelectionWhenImeConnectionCloses: false,
                      ),
                      imePolicies: SuperEditorImePolicies(
                        openKeyboardOnGainPrimaryFocus: false,
                        openKeyboardOnSelectionChange: false,
                        closeKeyboardOnSelectionLost: false,
                      ),
                      isImeConnected: _imeConnectionNotifier,
                      contentTapDelegateFactories: [
                        superEditorLaunchLinkTapHandlerFactory,
                        _tapToFocusEditor,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  ContentTapDelegate _tapToFocusEditor(SuperEditorContext editContext) {
    return _TapToFocusEditor(
      _editorFocusNode,
      _keyboardPanelController,
    );
  }

  Widget _buildKeyboardToolbar(BuildContext context, _Panel? openPanel) {
    return Row(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            height: 54,
            color: Colors.grey.shade100,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const SizedBox(width: 24),
                const Spacer(),
                _PanelButton(
                  icon: Icons.text_fields,
                  isActive: _keyboardPanelController.openPanel == _Panel.panel1,
                  onPressed: () => _togglePanel(_Panel.panel1),
                ),
                const SizedBox(width: 16),
                _PanelButton(
                  icon: Icons.align_horizontal_left,
                  isActive: _keyboardPanelController.openPanel == _Panel.panel2,
                  onPressed: () => _togglePanel(_Panel.panel2),
                ),
                const SizedBox(width: 16),
                _PanelButton(
                  icon: Icons.account_circle,
                  onPressed: () => _showBottomSheetWithOptions(context),
                ),
                const SizedBox(width: 16),
                _PanelButton(
                  icon: Icons.gif_box_outlined,
                  onPressed: () => _togglePanel(_Panel.giphy),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    _keyboardPanelController.closeKeyboardAndPanel();

                    // We need to explicitly unfocus so that the caret doesn't
                    // keep blinking in the editor.
                    _editorFocusNode.unfocus();
                  },
                  child: Icon(Icons.keyboard_hide),
                ),
                const SizedBox(width: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChatStatus(BuildContext context) {
    return DefaultTextStyle(
      style: DefaultTextStyle.of(context).style.copyWith(
            color: Colors.white.withValues(alpha: 0.5),
          ),
      child: Container(
        width: double.infinity,
        color: const Color(0xFF222222),
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Text(
              "There are 3 people online in this chat.",
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountPage() {
    return ColoredBox(
      color: Colors.grey.shade100,
      child: Center(
        child: Icon(Icons.account_circle),
      ),
    );
  }
}

class _TapToFocusEditor extends ContentTapDelegate {
  _TapToFocusEditor(
    this.editorFocusNode,
    this.keyboardPanelController,
  );

  final FocusNode editorFocusNode;
  final KeyboardPanelController keyboardPanelController;

  @override
  TapHandlingInstruction onTap(DocumentTapDetails details) {
    if (!keyboardPanelController.isSoftwareKeyboardOpen && !keyboardPanelController.isKeyboardPanelOpen) {
      // The user tapped on the editor and the software keyboard isn't up, nor is a panel.
      // Open the software keyboard.
      editorFocusNode.requestFocus();
      keyboardPanelController.showSoftwareKeyboard();
    }

    return TapHandlingInstruction.continueHandling;
  }
}

enum _Panel {
  panel1,
  panel2,
  giphy;
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.icon,
    this.isActive = false,
    required this.onPressed,
  });

  final IconData icon;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: isActive ? Colors.grey : Colors.transparent,
          ),
          child: Icon(icon),
        ),
      ),
    );
  }
}

Stylesheet get _chatStylesheet => defaultStylesheet.copyWith(
      addRulesBefore: [
        StyleRule(
          BlockSelector.all,
          (doc, docNode) {
            return {
              Styles.maxWidth: double.infinity,
              Styles.padding: const CascadingPadding.symmetric(horizontal: 24),
            };
          },
        ),
      ],
      addRulesAfter: [
        StyleRule(
          BlockSelector.all,
          (doc, docNode) {
            return {
              Styles.textStyle: TextStyle(
                fontSize: 18,
              ),
            };
          },
        ),
        StyleRule(
          BlockSelector.all.first(),
          (doc, docNode) {
            return {
              Styles.padding: const CascadingPadding.only(top: 12),
            };
          },
        ),
        StyleRule(
          BlockSelector.all.last(),
          (doc, docNode) {
            return {
              Styles.padding: const CascadingPadding.only(bottom: 12),
            };
          },
        ),
      ],
    );

Future<void> _showBottomSheetWithOptions(BuildContext context) async {
  return showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      return _BottomSheetWithoutButtonOptions();
    },
  );
}

class _BottomSheetWithoutButtonOptions extends StatefulWidget {
  const _BottomSheetWithoutButtonOptions();

  @override
  State<_BottomSheetWithoutButtonOptions> createState() => _BottomSheetWithoutButtonOptionsState();
}

class _BottomSheetWithoutButtonOptionsState extends State<_BottomSheetWithoutButtonOptions> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              "This bottom sheet represents a feature in which the user wants to temporarily leave the editor, and the toolbar, to review or select an option. We expect the keyboard or panel to close when this opens, and to re-open when this closes.",
              textAlign: TextAlign.left,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text("Some Options"),
          ),
        ],
      ),
    );
  }
}
