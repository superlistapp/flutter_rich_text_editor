import 'package:attributed_text/attributed_text.dart';
import 'package:flutter/foundation.dart' show ValueListenable, defaultTargetPlatform;
import 'package:flutter/material.dart' hide SelectableText;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_debug_paint.dart';
import 'package:super_editor/src/core/document_interaction.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/edit_context.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/core/styles.dart';
import 'package:super_editor/src/default_editor/common_editor_operations.dart';
import 'package:super_editor/src/default_editor/composite_component.dart';
import 'package:super_editor/src/default_editor/debug_visualization.dart';
import 'package:super_editor/src/default_editor/document_gestures_touch_android.dart';
import 'package:super_editor/src/default_editor/document_gestures_touch_ios.dart';
import 'package:super_editor/src/default_editor/document_scrollable.dart';
import 'package:super_editor/src/default_editor/layout_single_column/_styler_composing_region.dart';
import 'package:super_editor/src/default_editor/list_items.dart';
import 'package:super_editor/src/default_editor/tap_handlers/tap_handlers.dart';
import 'package:super_editor/src/default_editor/tasks.dart';
import 'package:super_editor/src/infrastructure/content_layers.dart';
import 'package:super_editor/src/infrastructure/documents/document_scaffold.dart';
import 'package:super_editor/src/infrastructure/documents/document_scroller.dart';
import 'package:super_editor/src/infrastructure/documents/selection_leader_document_layer.dart';
import 'package:super_editor/src/infrastructure/flutter/build_context.dart';
import 'package:super_editor/src/infrastructure/platforms/android/toolbar.dart';
import 'package:super_editor/src/infrastructure/platforms/ios/toolbar.dart';
import 'package:super_editor/src/infrastructure/platforms/mac/mac_ime.dart';
import 'package:super_editor/src/infrastructure/platforms/platform.dart';
import 'package:super_editor/src/infrastructure/signal_notifier.dart';
import 'package:super_editor/src/infrastructure/text_input.dart';
import 'package:super_editor/src/undo_redo.dart';
import 'package:super_editor/src/infrastructure/render_sliver_ext.dart';
import 'package:super_text_layout/super_text_layout.dart';

import '../infrastructure/document_gestures_interaction_overrides.dart';
import '../infrastructure/platforms/ios/ios_system_context_menu.dart';
import '../infrastructure/platforms/mobile_documents.dart';
import 'attributions.dart';
import 'blockquote.dart';
import 'document_caret_overlay.dart';
import 'document_focus_and_selection_policies.dart';
import 'document_gestures_mouse.dart';
import 'document_hardware_keyboard/document_input_keyboard.dart';
import 'document_ime/document_input_ime.dart';
import 'horizontal_rule.dart';
import 'image.dart';
import 'layout_single_column/layout_single_column.dart';
import 'paragraph.dart';
import 'text.dart';
import 'unknown_component.dart';

/// A rich text editor that displays a document in a single-column layout.
///
/// A [SuperEditor] brings together the key pieces needed to display a user-editable document:
///  * An editor, which includes a document and a composer (which holds the user selection and styles).
///  * A document layout, which positions components for every piece of content in the document.
///  * User interactions with the document layout (tapping, dragging, typing, scrolling)
///
/// A [SuperEditor] applies visual styles based on:
///  * [stylesheet], which applies styles throughout the document layout,
///    including text styles and block padding.
///  * [selectionStyles], which dictates the color of the caret and the color of
///    selected text and components
///  * [componentStyles], which applies targeted styles to specific components
///    in the document layout.
///  * [componentBuilders], which produce every visual component [Widget] within the document layout.
///
/// [keyboardActions] decides how physical keyboard key presses alter the document within
/// a [SuperEditor].
///
/// [imePolicies], [imeConfiguration], and [softwareKeyboardController] decide how user interactions
/// with the operating system's Input Method Editor (IME) alters the document within a
/// [SuperEditor].
///
/// ## Deeper explanation of core artifacts:
///
/// A [Document] is responsible for holding the content of a document in a structured
/// and query-able manner.
///
/// A [DocumentComposer] is responsible for holding the user's selection, as well as any inline
/// text styles that should be applied as the user types.
///
/// An [Editor] is responsible for executing every request that alters a [Document] or
/// [DocumentComposer]. The [Editor] provides hooks for reactions, which can further alter
/// content after a command, such as parsing inline Markdown, or creating hash tags. The
/// [Editor] implements undo/redo control.
///
/// A [DocumentLayout] is responsible for positioning and rendering the various visual
/// components in the document. It's also responsible for linking logical document nodes
/// to visual document components to facilitate user interactions like tapping and dragging.
///
/// Document interaction is responsible for taking appropriate actions in response to user
/// taps, drags, and key presses.
class SuperEditor extends StatefulWidget {
  /// Creates a `Super Editor` with common (but configurable) defaults for
  /// visual components, text styles, and user interaction.
  SuperEditor({
    Key? key,
    this.focusNode,
    this.autofocus = false,
    this.tapRegionGroupId,
    required this.editor,
    @Deprecated(
        "The document is now retrieved from the Editor. You should remove this property from your SuperEditor widget.")
    this.document,
    @Deprecated(
        "The composer is now retrieved from the Editor. You should remove this property from your SuperEditor widget.")
    this.composer,
    this.scrollController,
    this.documentLayoutKey,
    Stylesheet? stylesheet,
    this.customStylePhases = const [],
    List<ComponentBuilder>? componentBuilders,
    SelectionStyles? selectionStyle,
    this.selectionPolicies = const SuperEditorSelectionPolicies(),
    this.inputSource,
    this.softwareKeyboardController,
    this.imePolicies = const SuperEditorImePolicies(),
    this.imeConfiguration,
    this.imeOverrides,
    this.isImeConnected,
    this.keyboardActions,
    this.selectorHandlers,
    this.gestureMode,
    this.contentTapDelegateFactories = const [superEditorLaunchLinkTapHandlerFactory],
    this.selectionLayerLinks,
    this.documentUnderlayBuilders = const [],
    this.documentOverlayBuilders = defaultSuperEditorDocumentOverlayBuilders,
    this.overlayController,
    this.androidHandleColor,
    this.androidToolbarBuilder,
    this.iOSHandleColor,
    this.iOSToolbarBuilder,
    this.createOverlayControlsClipper,
    this.plugins = const {},
    this.debugPaint = const DebugPaintConfig(),
    this.shrinkWrap = false,
  })  : stylesheet = stylesheet ?? defaultStylesheet,
        selectionStyles = selectionStyle ?? defaultSelectionStyle,
        componentBuilders = [
          for (final plugin in plugins) ...plugin.componentBuilders,
          if (componentBuilders != null)
            ...componentBuilders
          else ...[...defaultComponentBuilders, TaskComponentBuilder(editor)],
          const UnknownComponentBuilder(),
        ],
        super(key: key);

  /// [FocusNode] for the entire `SuperEditor`.
  final FocusNode? focusNode;

  /// Whether or not the [SuperEditor] should autofocus upon initial display.
  final bool autofocus;

  /// {@template super_editor_tap_region_group_id}
  /// A group ID for a tap region that surrounds the editor
  /// and also surrounds any related widgets, such as drag handles and a toolbar.
  ///
  /// When the editor is inside a [TapRegion], tapping at a drag handle causes
  /// [TapRegion.onTapOutside] to be called. To prevent that, provide a
  /// [tapRegionGroupId] with the same value as the ancestor [TapRegion] groupId.
  /// {@endtemplate}
  final String? tapRegionGroupId;

  /// The [ScrollController] that governs this `SuperEditor`'s scroll
  /// offset.
  ///
  /// `scrollController` is not used if this `SuperEditor` has an ancestor
  /// `Scrollable`.
  final ScrollController? scrollController;

  /// An editing pipeline, which is responsible for all changes made to a document from
  /// this [SuperEditor].
  ///
  /// All [SuperEditor] interactions apply changes to a document by submitting requests to
  /// this [editor]. The [editor] takes requests, runs corresponding commands, runs reactions
  /// to those commands (e.g., parsing Markdown), and then notifies listeners about what
  /// changed.
  ///
  /// The editing pipeline within the [editor] applies to a set of [Editable]s. These are the
  /// things that can be changed through editing. For example, every [editor] is expected to
  /// contain a [MutableDocument] and a [MutableDocumentComposer] within the set of [Editable]s.
  /// That way, edit commands can alter the document and the composer.
  ///
  /// See [Editor] for more details.
  final Editor editor;

  /// The [Document] that's edited by the [editor].
  @Deprecated(
      "The Document is now retrieved from the Editor. You should remove this property from your SuperEditor widget.")
  final Document? document;

  /// Owns the editor's current selection, the current attributions for
  /// text input, and other transitive editor configurations.
  @Deprecated(
      "The DocumentComposer is now retrieved from the Editor. You should remove this property from your SuperEditor widget.")
  final DocumentComposer? composer;

  /// [GlobalKey] that's bound to the [DocumentLayout] within
  /// this `SuperEditor`.
  ///
  /// This key can be used to lookup visual components in the document
  /// layout within this `SuperEditor`.
  final GlobalKey? documentLayoutKey;

  /// Style rules applied through the document presentation.
  final Stylesheet stylesheet;

  /// Styles applied to selected content.
  final SelectionStyles selectionStyles;

  /// Policies that determine how selection is modified by other factors, such as
  /// gaining or losing focus.
  final SuperEditorSelectionPolicies selectionPolicies;

  /// Custom style phases that are added to the standard style phases.
  ///
  /// Documents are styled in a series of phases. A number of such
  /// phases are applied, automatically, e.g., text styles, per-component
  /// styles, and content selection styles.
  ///
  /// [customStylePhases] are added after the standard style phases. You can
  /// use custom style phases to apply styles that aren't supported with
  /// [stylesheet]s.
  ///
  /// You can also use them to apply styles to your custom [DocumentNode]
  /// types that aren't supported by Super Editor. For example, Super Editor
  /// doesn't include support for tables within documents, but you could
  /// implement a `TableNode` for that purpose. You may then want to make your
  /// table styleable. To accomplish this, you add a custom style phase that
  /// knows how to interpret and apply table styles for your visual table component.
  final List<SingleColumnLayoutStylePhase> customStylePhases;

  /// The `SuperEditor` input source, e.g., keyboard or Input Method Engine.
  final TextInputSource? inputSource;

  /// Opens and closes the software keyboard.
  ///
  /// Typically, this controller should only be used when the keyboard is configured
  /// for manual control, e.g., [SuperEditorImePolicies.openKeyboardOnSelectionChange] and
  /// [SuperEditorImePolicies.clearSelectionWhenEditorLosesFocus] are `false`. Otherwise,
  /// the automatic behavior might conflict with commands to this controller.
  final SoftwareKeyboardController? softwareKeyboardController;

  /// Policies that dictate when and how [SuperEditor] should interact with the
  /// platform IME, such as automatically opening the software keyboard when
  /// [SuperEditor]'s selection changes.
  final SuperEditorImePolicies imePolicies;

  /// Preferences for how the platform IME should look and behave during editing.
  final SuperEditorImeConfiguration? imeConfiguration;

  /// Overrides for IME actions.
  ///
  /// When the user edits document content in IME mode, those edits and actions
  /// are reported to a [DeltaTextInputClient], which is then responsible for
  /// applying those changes to a document. [SuperEditor] includes an implementation
  /// for all relevant editing behaviors. However, some apps may wish to implement
  /// their own custom behavior, such as when the user presses the action button,
  /// such as "Next" or "Done".
  ///
  /// Provide a [DeltaTextInputClientDecorator], to override the default [SuperEditor]
  /// behaviors for various IME messages.
  final DeltaTextInputClientDecorator? imeOverrides;

  /// A (optional) notifier that's notified when the IME connection opens or closes.
  ///
  /// A `true` value means [SuperEditor] is connected to the platform's IME, a `false`
  /// value means [SuperEditor] isn't connected to the platforms IME.
  final ValueNotifier<bool>? isImeConnected;

  /// The `SuperEditor` gesture mode, e.g., mouse or touch.
  final DocumentGestureMode? gestureMode;

  /// List of factories that creates a [ContentTapDelegate], which is given an
  /// opportunity to respond to taps on content before the editor, itself.
  ///
  /// A [ContentTapDelegate] might be used, for example, to launch a URL
  /// when a user taps on a link.
  ///
  /// If a handler returns [TapHandlingInstruction.halt], no subsequent handlers
  /// nor the default tap behavior will be executed.
  final List<SuperEditorContentTapDelegateFactory>? contentTapDelegateFactories;

  /// Leader links that connect leader widgets near the user's selection
  /// to carets, handles, and other things that want to follow the selection.
  ///
  /// These links are always created and used within [SuperEditor]. By providing
  /// an explicit [selectionLayerLinks], external widgets can also follow the
  /// user's selection.
  final SelectionLayerLinks? selectionLayerLinks;

  /// Layers that are displayed under the document layout, aligned
  /// with the location and size of the document layout.
  final List<SuperEditorLayerBuilder> documentUnderlayBuilders;

  /// Layers that are displayed on top of the document layout, aligned
  /// with the location and size of the document layout.
  final List<SuperEditorLayerBuilder> documentOverlayBuilders;

  /// Priority list of widget factories that create instances of
  /// each visual component displayed in the document layout, e.g.,
  /// paragraph component, image component, horizontal rule component, etc.
  final List<ComponentBuilder> componentBuilders;

  /// All actions that this editor takes in response to key
  /// events, e.g., text entry, newlines, character deletion,
  /// copy, paste, etc.
  ///
  /// If [keyboardActions] is `null`, [SuperEditor] uses [defaultKeyboardActions]
  /// when the gesture mode is [TextInputSource.keyboard], and
  /// [defaultImeKeyboardActions] when the gesture mode is [TextInputSource.ime].
  final List<DocumentKeyboardAction>? keyboardActions;

  /// Handlers for all Mac OS "selectors" reported by the IME.
  ///
  /// The IME reports selectors as unique `String`s, therefore selector handlers are
  /// defined as a mapping from selector names to handler functions.
  final Map<String, SuperEditorSelectorHandler>? selectorHandlers;

  /// Shows, hides, and positions a floating toolbar and magnifier.
  @Deprecated(
      "To configure overlay controls, surround SuperEditor with a SuperEditorIosControlsScope and/or SuperEditorAndroidControlsScope")
  final MagnifierAndToolbarController? overlayController;

  /// Color of the text selection drag handles on Android.
  @Deprecated("To configure handle color, surround SuperEditor with a SuperEditorAndroidControlsScope, instead")
  final Color? androidHandleColor;

  /// Builder that creates a floating toolbar when running on Android.
  @Deprecated("To configure a toolbar builder, surround SuperEditor with a SuperEditorAndroidControlsScope, instead")
  final WidgetBuilder? androidToolbarBuilder;

  /// Color of the text selection drag handles on iOS.
  @Deprecated("To configure handle color, surround SuperEditor with a SuperEditorIosControlsScope, instead")
  final Color? iOSHandleColor;

  /// Builder that creates a floating toolbar when running on iOS.
  @Deprecated("To configure a toolbar builder, surround SuperEditor with a SuperEditorIosControlsScope, instead")
  final WidgetBuilder? iOSToolbarBuilder;

  /// Creates a clipper that applies to overlay controls, like drag
  /// handles, magnifiers, and popover toolbars, preventing the overlay
  /// controls from appearing outside the given clipping region.
  ///
  /// If no clipper factory method is provided, then the overlay controls
  /// will be allowed to appear anywhere in the overlay in which they sit
  /// (probably the entire screen).
  @Deprecated(
      "To configure an overlay clipper, surround SuperEditor with a SuperEditorIosControlsScope and/or a SuperEditorAndroidControlsScope")
  final CustomClipper<Rect> Function(BuildContext overlayContext)? createOverlayControlsClipper;

  /// Plugins that add sets of behaviors to the editing experience.
  final Set<SuperEditorPlugin> plugins;

  /// Paints some extra visual ornamentation to help with
  /// debugging.
  final DebugPaintConfig debugPaint;

  /// Whether the scroll view used by the editor should shrink-wrap its contents.
  /// Only used when editor is not inside an scrollable.
  final bool shrinkWrap;

  @override
  SuperEditorState createState() => SuperEditorState();
}

@visibleForTesting
class SuperEditorState extends State<SuperEditor> {
  // GlobalKey used to access the [DocumentLayoutState] to figure
  // out where in the document the user taps or drags.
  late GlobalKey _docLayoutKey;
  final _documentLayoutLink = LayerLink();
  SingleColumnLayoutPresenter? _docLayoutPresenter;
  late SingleColumnStylesheetStyler _docStylesheetStyler;
  late SingleColumnLayoutCustomComponentStyler _docLayoutPerComponentBlockStyler;
  late SingleColumnLayoutSelectionStyler _docLayoutSelectionStyler;

  @visibleForTesting
  FocusNode get focusNode => _focusNode;
  late FocusNode _focusNode;
  final _primaryFocusListener = ValueNotifier(false);

  late DocumentComposer _composer;

  DocumentScroller? _scroller;
  late ScrollController _scrollController;
  late AutoScrollController _autoScrollController;
  // Signal that's notified every time the scroll offset changes for SuperEditor,
  // including the cases where SuperEditor controls an ancestor Scrollable.
  final _scrollChangeSignal = SignalNotifier();

  @visibleForTesting
  late SuperEditorContext editContext;

  List<ContentTapDelegate>? _contentTapHandlers;

  final _dragHandleAutoScroller = ValueNotifier<DragHandleAutoScroller?>(null);

  // GlobalKey for the iOS editor controls scope so that the scope's controller doesn't
  // continuously replace itself every time we rebuild. We want to retain the same
  // controls because they're shared throughout a number of disconnected widgets.
  final _iosControlsContextKey = GlobalKey();
  final _iosControlsController = SuperEditorIosControlsController();

  // GlobalKey for the Android editor controls scope so that the scope's controller doesn't
  // continuously replace itself every time we rebuild. We want to retain the same
  // controls because they're shared throughout a number of disconnected widgets.
  final _androidControlsContextKey = GlobalKey();
  final _androidControlsController = SuperEditorAndroidControlsController();

  // Leader links that connect leader widgets near the user's selection
  // to carets, handles, and other things that want to follow the selection.
  late SelectionLayerLinks _selectionLinks;

  @visibleForTesting
  SingleColumnLayoutPresenter get presenter => _docLayoutPresenter!;

  late SoftwareKeyboardController _softwareKeyboardController;

  late ValueNotifier<bool> _isImeConnected;

  @override
  void initState() {
    super.initState();

    if (widget.editor.maybeDocument == null) {
      throw Exception(
          "No Document is available to SuperEditor. The Editor given to SuperEditor must contain a MutableDocument in the set of Editables.");
    }
    if (widget.editor.maybeComposer == null) {
      throw Exception(
          "No DocumentComposer is available to SuperEditor. The Editor given to SuperEditor must contain a MutableDocumentComposer in the set of Editables.");
    }

    _focusNode = (widget.focusNode ?? FocusNode())..addListener(_onFocusChange);

    _composer = widget.editor.composer;

    _scrollController = widget.scrollController ?? ScrollController();
    _autoScrollController = AutoScrollController();

    _docLayoutKey = widget.documentLayoutKey ?? GlobalKey();

    _selectionLinks = widget.selectionLayerLinks ?? SelectionLayerLinks();

    _softwareKeyboardController = widget.softwareKeyboardController ?? SoftwareKeyboardController();

    _isImeConnected = widget.isImeConnected ?? ValueNotifier(false);

    widget.editor.context.put(
      Editor.layoutKey,
      DocumentLayoutEditable(() => _docLayoutKey.currentState as DocumentLayout),
    );

    _createEditContext();
    _createLayoutPresenter();
  }

  @override
  void didUpdateWidget(SuperEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.focusNode != oldWidget.focusNode) {
      _focusNode = (widget.focusNode ?? FocusNode())..addListener(_onFocusChange);
    }

    if (widget.documentLayoutKey != oldWidget.documentLayoutKey) {
      _docLayoutKey = widget.documentLayoutKey ?? GlobalKey();
    }

    if (widget.selectionLayerLinks != oldWidget.selectionLayerLinks) {
      _selectionLinks = widget.selectionLayerLinks ?? SelectionLayerLinks();
    }

    if (widget.editor.maybeComposer != oldWidget.editor.composer) {
      if (widget.editor.maybeComposer == null) {
        throw Exception(
            "No DocumentComposer is available to SuperEditor. The Editor given to SuperEditor must contain a MutableDocumentComposer in the set of Editables.");
      }

      _composer = widget.editor.composer;
    }

    if (widget.editor != oldWidget.editor) {
      for (final plugin in oldWidget.plugins) {
        plugin.detach(oldWidget.editor);
      }

      oldWidget.editor.context.remove(Editor.layoutKey);
      widget.editor.context.put(
        Editor.layoutKey,
        DocumentLayoutEditable(() => _docLayoutKey.currentState as DocumentLayout),
      );

      _createEditContext();
      _createLayoutPresenter();
    } else {
      if (widget.selectionStyles != oldWidget.selectionStyles) {
        _docLayoutSelectionStyler.selectionStyles = widget.selectionStyles;
      }
      if (widget.stylesheet != oldWidget.stylesheet) {
        _createLayoutPresenter();
      }
    }

    if (widget.scrollController != oldWidget.scrollController) {
      _scrollController = widget.scrollController ?? ScrollController();
    }

    if (widget.softwareKeyboardController != oldWidget.softwareKeyboardController) {
      _softwareKeyboardController = widget.softwareKeyboardController ?? SoftwareKeyboardController();
    }

    if (widget.isImeConnected != oldWidget.isImeConnected) {
      _isImeConnected = widget.isImeConnected ?? ValueNotifier(false);
    }

    _recomputeIfLayoutShouldShowCaret();
  }

  @override
  void dispose() {
    if (_contentTapHandlers != null) {
      for (final handler in _contentTapHandlers!) {
        handler.dispose();
      }
    }

    _iosControlsController.dispose();
    _androidControlsController.dispose();

    widget.editor.context.remove(Editor.layoutKey);

    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      // We are using our own private FocusNode. Dispose it.
      _focusNode.dispose();
    }

    super.dispose();
  }

  void _createEditContext() {
    if (_scroller != null) {
      _scroller!.dispose();
    }
    _scroller = DocumentScroller()..addScrollChangeListener(_scrollChangeSignal.notifyListeners);

    editContext = SuperEditorContext(
      editorFocusNode: _focusNode,
      editor: widget.editor,
      document: widget.editor.document,
      composer: _composer,
      getDocumentLayout: () => _docLayoutKey.currentState as DocumentLayout,
      scroller: _scroller!,
      commonOps: CommonEditorOperations(
        editor: widget.editor,
        document: widget.editor.document,
        composer: _composer,
        documentLayoutResolver: () => _docLayoutKey.currentState as DocumentLayout,
      ),
    );

    for (final plugin in widget.plugins) {
      plugin.attach(widget.editor);
    }

    // The ContentTapDelegate depends upon the EditContext. Recreate the
    // handlers, now that we've created a new EditContext.
    if (_contentTapHandlers != null) {
      for (final handler in _contentTapHandlers!) {
        handler.dispose();
      }
    }
    _contentTapHandlers = widget.contentTapDelegateFactories?.map((factory) => factory.call(editContext)).toList();
  }

  void _createLayoutPresenter() {
    if (_docLayoutPresenter != null) {
      _docLayoutPresenter!.dispose();
    }

    final document = editContext.document;

    _docStylesheetStyler = SingleColumnStylesheetStyler(stylesheet: widget.stylesheet);

    _docLayoutPerComponentBlockStyler = SingleColumnLayoutCustomComponentStyler();

    _docLayoutSelectionStyler = SingleColumnLayoutSelectionStyler(
      document: document,
      selection: editContext.composer.selectionNotifier,
      selectionStyles: widget.selectionStyles,
      selectedTextColorStrategy: widget.stylesheet.selectedTextColorStrategy,
    );

    final showComposingUnderline = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;

    _docLayoutPresenter = SingleColumnLayoutPresenter(
      document: document,
      componentBuilders: widget.componentBuilders,
      pipeline: [
        _docStylesheetStyler,
        _docLayoutPerComponentBlockStyler,
        ...widget.customStylePhases,
        if (showComposingUnderline)
          SingleColumnLayoutComposingRegionStyler(
            document: document,
            composingRegion: editContext.composer.composingRegion,
            showComposingUnderline: true,
          ),
        // Selection changes are very volatile. Put that phase last,
        // just before the phases that the app wants to be at the end
        // to minimize view model recalculations.
        _docLayoutSelectionStyler,
        for (final plugin in widget.plugins) //
          ...plugin.appendedStylePhases,
      ],
    );

    _recomputeIfLayoutShouldShowCaret();
  }

  void _onFocusChange() {
    _recomputeIfLayoutShouldShowCaret();
    _primaryFocusListener.value = _focusNode.hasPrimaryFocus;
  }

  void _recomputeIfLayoutShouldShowCaret() {
    _docLayoutSelectionStyler.shouldDocumentShowCaret = _focusNode.hasFocus && gestureMode == DocumentGestureMode.mouse;
  }

  @visibleForTesting
  DocumentGestureMode get gestureMode {
    if (widget.gestureMode != null) {
      return widget.gestureMode!;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return DocumentGestureMode.android;
      case TargetPlatform.iOS:
        return DocumentGestureMode.iOS;
      default:
        return DocumentGestureMode.mouse;
    }
  }

  /// Returns the [TextInputSource] which should be used.
  ///
  /// If the `inputSource` is configured, it is used. Otherwise,
  /// the [TextInputSource] is chosen based on the platform.
  @visibleForTesting
  TextInputSource get inputSource => widget.inputSource ?? TextInputSource.ime;

  /// Returns the key handlers that respond to keyboard events within [SuperEditor].
  List<DocumentKeyboardAction> get _keyboardActions =>
      widget.keyboardActions ??
      (inputSource == TextInputSource.ime ? defaultImeKeyboardActions : defaultKeyboardActions);

  void _openSoftwareKeyboard() {
    if (!_softwareKeyboardController.hasDelegate) {
      // There is no IME connection. It isn't possible to request the keyboard.
      return;
    }

    _softwareKeyboardController.open();
  }

  @override
  Widget build(BuildContext context) {
    return _buildGestureControlsScope(
      // We add a Builder immediately beneath the gesture controls scope so that
      // all descendant widgets built within SuperEditor can access that scope.
      child: Builder(builder: (controlsScopeContext) {
        return SuperEditorFocusDebugVisuals(
          focusNode: _focusNode,
          child: EditorSelectionAndFocusPolicy(
            focusNode: _focusNode,
            editor: widget.editor,
            document: widget.editor.document,
            selection: _composer.selectionNotifier,
            isDocumentLayoutAvailable: () =>
                (_docLayoutKey.currentContext?.findRenderObject() as RenderSliver?)?.hasSize == true,
            getDocumentLayout: () => editContext.documentLayout,
            placeCaretAtEndOfDocumentOnGainFocus: widget.selectionPolicies.placeCaretAtEndOfDocumentOnGainFocus,
            restorePreviousSelectionOnGainFocus: widget.selectionPolicies.restorePreviousSelectionOnGainFocus,
            clearSelectionWhenEditorLosesFocus: widget.selectionPolicies.clearSelectionWhenEditorLosesFocus,
            child: DocumentScaffold(
              documentLayoutLink: _documentLayoutLink,
              documentLayoutKey: _docLayoutKey,
              viewportDecorationBuilder: _buildPlatformSpecificViewportDecorations,
              textInputBuilder: _buildTextInputSystem,
              gestureBuilder: _buildGestureInteractor,
              scrollController: _scrollController,
              autoScrollController: _autoScrollController,
              scroller: _scroller,
              presenter: presenter,
              componentBuilders: widget.componentBuilders,
              shrinkWrap: widget.shrinkWrap,
              underlays: [
                // Add all underlays from plugins.
                for (final plugin in widget.plugins) //
                  for (final underlayBuilder in plugin.documentUnderlayBuilders) //
                    (context) => underlayBuilder.build(context, editContext),
                // Add all underlays that the app wants.
                for (final underlayBuilder in widget.documentUnderlayBuilders) //
                  (context) => underlayBuilder.build(context, editContext),
              ],
              overlays: [
                // Layer that positions and sizes leader widgets at the bounds
                // of the users selection so that carets, handles, toolbars, and
                // other things can follow the selection.
                (context) {
                  return _SelectionLeadersDocumentLayerBuilder(
                    links: _selectionLinks,
                    showDebugLeaderBounds: false,
                  ).build(context, editContext);
                },
                // Add all overlays from plugins.
                for (final plugin in widget.plugins) //
                  for (final overlayBuilder in plugin.documentOverlayBuilders) //
                    (context) => overlayBuilder.build(context, editContext),
                // Add all overlays that the app wants.
                for (final overlayBuilder in widget.documentOverlayBuilders) //
                  (context) => overlayBuilder.build(context, editContext),
              ],
              debugPaint: widget.debugPaint,
            ),
          ),
        );
      }),
    );
  }

  /// Build an [InheritedWidget] that holds a shared controller scope for editor controls,
  /// e.g., caret, handles, magnifier, toolbar.
  ///
  /// This controller may be shared by multiple widgets within [SuperEditor]. It's also
  /// possible that a client app has wrapped [SuperEditor] with its own controller scope
  /// [InheritedWidget], in which case the controller is shared with widgets inside
  /// of [SuperEditor], and widgets outside of [SuperEditor].
  ///
  /// The specific scope that's added to the widget tree is selected by the given [gestureMode].
  Widget _buildGestureControlsScope({
    required Widget child,
  }) {
    switch (gestureMode) {
      case DocumentGestureMode.mouse:
        return child;
      case DocumentGestureMode.android:
        return SuperEditorAndroidControlsScope(
          key: _androidControlsContextKey,
          controller: _androidControlsController,
          child: child,
        );
      case DocumentGestureMode.iOS:
        return SuperEditorIosControlsScope(
          key: _iosControlsContextKey,
          controller: _iosControlsController,
          child: child,
        );
    }
  }

  /// Builds the widget tree that applies user input, e.g., key
  /// presses from a keyboard, or text deltas from the IME.
  Widget _buildTextInputSystem(
    BuildContext context, {
    required Widget child,
  }) {
    switch (inputSource) {
      case TextInputSource.keyboard:
        return SuperEditorHardwareKeyHandler(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          editContext: editContext,
          keyboardActions: [
            for (final plugin in widget.plugins) //
              ...plugin.keyboardActions,
            ..._keyboardActions,
          ],
          child: child,
        );
      case TextInputSource.ime:
        return SuperEditorImeInteractor(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          editContext: editContext,
          clearSelectionWhenEditorLosesFocus: widget.selectionPolicies.clearSelectionWhenEditorLosesFocus,
          clearSelectionWhenImeConnectionCloses: widget.selectionPolicies.clearSelectionWhenImeConnectionCloses,
          softwareKeyboardController: _softwareKeyboardController,
          imePolicies: widget.imePolicies,
          imeConfiguration: widget.imeConfiguration ??
              SuperEditorImeConfiguration(
                keyboardBrightness: Theme.of(context).brightness,
              ),
          imeOverrides: widget.imeOverrides,
          hardwareKeyboardActions: [
            for (final plugin in widget.plugins) //
              ...plugin.keyboardActions,
            ..._keyboardActions,
          ],
          selectorHandlers: widget.selectorHandlers ?? defaultEditorSelectorHandlers,
          isImeConnected: _isImeConnected,
          child: child,
        );
    }
  }

  /// Builds any widgets that a platform wants to wrap around the editor viewport,
  /// e.g., editor toolbar, floating cursor display for iOS.
  Widget _buildPlatformSpecificViewportDecorations(
    BuildContext context, {
    required Widget child,
  }) {
    switch (gestureMode) {
      case DocumentGestureMode.iOS:
        return SuperEditorIosToolbarOverlayManager(
          tapRegionGroupId: widget.tapRegionGroupId,
          defaultToolbarBuilder: (overlayContext, mobileToolbarKey, focalPoint) => defaultIosEditorToolbarBuilder(
            overlayContext,
            mobileToolbarKey,
            focalPoint,
            editContext.commonOps,
            SuperEditorIosControlsScope.rootOf(context),
          ),
          child: SuperEditorIosMagnifierOverlayManager(
            child: EditorFloatingCursor(
              editor: widget.editor,
              document: widget.editor.document,
              getDocumentLayout: () => _docLayoutKey.currentState as DocumentLayout,
              selection: widget.editor.composer.selectionNotifier,
              scrollChangeSignal: _scrollChangeSignal,
              child: child,
            ),
          ),
        );
      case DocumentGestureMode.android:
        return SuperEditorAndroidControlsOverlayManager(
          tapRegionGroupId: widget.tapRegionGroupId,
          document: editContext.document,
          getDocumentLayout: () => _docLayoutKey.currentState as DocumentLayout,
          selection: _composer.selectionNotifier,
          setSelection: (newSelection) => editContext.editor.execute([
            ChangeSelectionRequest(newSelection, SelectionChangeType.pushCaret, SelectionReason.userInteraction),
          ]),
          scrollChangeSignal: _scrollChangeSignal,
          dragHandleAutoScroller: _dragHandleAutoScroller,
          defaultToolbarBuilder: (overlayContext, mobileToolbarKey, focalPoint) => defaultAndroidEditorToolbarBuilder(
            overlayContext,
            mobileToolbarKey,
            editContext.commonOps,
            SuperEditorAndroidControlsScope.rootOf(context),
            editContext.composer.selectionNotifier,
          ),
          child: child,
        );
      case DocumentGestureMode.mouse:
        return child;
    }
  }

  Widget _buildGestureInteractor(BuildContext context, {required Widget child}) {
    // Ensure that gesture object fill entire viewport when not being
    // in user specified scrollable.
    final fillViewport = context.findAncestorScrollableWithVerticalScroll == null;
    switch (gestureMode) {
      case DocumentGestureMode.mouse:
        return DocumentMouseInteractor(
          focusNode: _focusNode,
          editor: editContext.editor,
          document: editContext.document,
          getDocumentLayout: () => editContext.documentLayout,
          selectionChanges: editContext.composer.selectionChanges,
          selectionNotifier: editContext.composer.selectionNotifier,
          contentTapHandlers: [
            ..._contentTapHandlers ?? [],
            for (final plugin in widget.plugins) //
              ...plugin.contentTapHandlers,
          ],
          autoScroller: _autoScrollController,
          fillViewport: fillViewport,
          showDebugPaint: widget.debugPaint.gestures,
          child: child,
        );
      case DocumentGestureMode.android:
        return AndroidDocumentTouchInteractor(
          focusNode: _focusNode,
          editor: editContext.editor,
          document: editContext.document,
          getDocumentLayout: () => editContext.documentLayout,
          selection: editContext.composer.selectionNotifier,
          openKeyboardWhenTappingExistingSelection: widget.selectionPolicies.openKeyboardWhenTappingExistingSelection,
          openSoftwareKeyboard: _openSoftwareKeyboard,
          contentTapHandlers: [
            ..._contentTapHandlers ?? [],
            for (final plugin in widget.plugins) //
              ...plugin.contentTapHandlers,
          ],
          scrollController: _scrollController,
          dragHandleAutoScroller: _dragHandleAutoScroller,
          fillViewport: fillViewport,
          showDebugPaint: widget.debugPaint.gestures,
          child: child,
        );
      case DocumentGestureMode.iOS:
        return IosDocumentTouchInteractor(
          focusNode: _focusNode,
          editor: editContext.editor,
          document: editContext.document,
          getDocumentLayout: () => editContext.documentLayout,
          selection: editContext.composer.selectionNotifier,
          openKeyboardWhenTappingExistingSelection: widget.selectionPolicies.openKeyboardWhenTappingExistingSelection,
          openSoftwareKeyboard: _openSoftwareKeyboard,
          isImeConnected: _isImeConnected,
          contentTapHandlers: [
            ..._contentTapHandlers ?? [],
            for (final plugin in widget.plugins) //
              ...plugin.contentTapHandlers,
          ],
          scrollController: _scrollController,
          dragHandleAutoScroller: _dragHandleAutoScroller,
          fillViewport: fillViewport,
          showDebugPaint: widget.debugPaint.gestures,
          child: child,
        );
    }
  }
}

/// A [DocumentFloatingToolbarBuilder] that displays the iOS system popover toolbar, if the version of
/// iOS is recent enough, otherwise builds [defaultIosEditorToolbarBuilder].
Widget iOSSystemPopoverEditorToolbarWithFallbackBuilder(
  BuildContext context,
  Key floatingToolbarKey,
  LeaderLink focalPoint,
  CommonEditorOperations editorOps,
  SuperEditorIosControlsController editorControlsController,
) {
  if (CurrentPlatform.isWeb) {
    // On web, we defer to the browser's internal overlay controls for mobile.
    return const SizedBox();
  }

  if (IOSSystemContextMenu.isSupported(context)) {
    return IOSSystemContextMenu(
      leaderLink: focalPoint,
    );
  }

  return defaultIosEditorToolbarBuilder(
    context,
    floatingToolbarKey,
    focalPoint,
    editorOps,
    editorControlsController,
  );
}

/// Builds a standard editor-style iOS floating toolbar.
Widget defaultIosEditorToolbarBuilder(
  BuildContext context,
  Key floatingToolbarKey,
  LeaderLink focalPoint,
  CommonEditorOperations editorOps,
  SuperEditorIosControlsController editorControlsController,
) {
  if (CurrentPlatform.isWeb) {
    // On web, we defer to the browser's internal overlay controls for mobile.
    return const SizedBox();
  }

  return DefaultIosEditorToolbar(
    floatingToolbarKey: floatingToolbarKey,
    focalPoint: focalPoint,
    editorOps: editorOps,
    editorControlsController: editorControlsController,
  );
}

/// An iOS floating toolbar, which includes standard buttons for an editor use-case.
class DefaultIosEditorToolbar extends StatelessWidget {
  const DefaultIosEditorToolbar({
    super.key,
    this.floatingToolbarKey,
    required this.focalPoint,
    required this.editorOps,
    required this.editorControlsController,
  });

  final Key? floatingToolbarKey;
  final LeaderLink focalPoint;
  final CommonEditorOperations editorOps;
  final SuperEditorIosControlsController editorControlsController;

  @override
  Widget build(BuildContext context) {
    return IOSTextEditingFloatingToolbar(
      floatingToolbarKey: floatingToolbarKey,
      focalPoint: focalPoint,
      onCutPressed: _cut,
      onCopyPressed: _copy,
      onPastePressed: _paste,
    );
  }

  void _cut() {
    editorOps.cut();
    editorControlsController.hideToolbar();
  }

  void _copy() {
    editorOps.copy();
    editorControlsController.hideToolbar();
  }

  void _paste() {
    editorOps.paste();
    editorControlsController.hideToolbar();
  }
}

/// Builds a standard editor-style Android floating toolbar.
Widget defaultAndroidEditorToolbarBuilder(
  BuildContext context,
  Key floatingToolbarKey,
  CommonEditorOperations editorOps,
  SuperEditorAndroidControlsController editorControlsController,
  ValueListenable<DocumentSelection?> selectionNotifier,
) {
  return DefaultAndroidEditorToolbar(
    floatingToolbarKey: floatingToolbarKey,
    editorOps: editorOps,
    editorControlsController: editorControlsController,
    selectionNotifier: selectionNotifier,
  );
}

/// An Android floating toolbar, which includes standard buttons for an editor use-case.
class DefaultAndroidEditorToolbar extends StatelessWidget {
  const DefaultAndroidEditorToolbar({
    super.key,
    this.floatingToolbarKey,
    required this.editorOps,
    required this.editorControlsController,
    required this.selectionNotifier,
  });

  final Key? floatingToolbarKey;
  final CommonEditorOperations editorOps;
  final SuperEditorAndroidControlsController editorControlsController;
  final ValueListenable<DocumentSelection?> selectionNotifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: selectionNotifier,
      builder: (context, selection, child) {
        return AndroidTextEditingFloatingToolbar(
          floatingToolbarKey: floatingToolbarKey,
          onCopyPressed: selection == null || !selection.isCollapsed //
              ? _copy
              : null,
          onCutPressed: selection == null || !selection.isCollapsed //
              ? _cut
              : null,
          onPastePressed: _paste,
          onSelectAllPressed: _selectAll,
        );
      },
    );
  }

  void _cut() {
    editorOps.cut();
    editorControlsController.hideToolbar();
  }

  void _copy() {
    editorOps.copy();
    editorControlsController.hideToolbar();
  }

  void _paste() {
    editorOps.paste();
    editorControlsController.hideToolbar();
  }

  void _selectAll() {
    editorOps.selectAll();
    editorControlsController.hideToolbar();
  }
}

/// A [SuperEditorLayerBuilder] that builds a [SelectionLeadersDocumentLayer], which positions
/// leader widgets at the base and extent of the user's selection, so that other widgets
/// can position themselves relative to the user's selection.
class _SelectionLeadersDocumentLayerBuilder implements SuperEditorLayerBuilder {
  const _SelectionLeadersDocumentLayerBuilder({
    required this.links,
    // TODO(srawlins): `unused_element`, when reporting a parameter, is being
    // renamed to `unused_element_parameter`. For now, ignore each; when the SDK
    // constraint is >= 3.6.0, just ignore `unused_element_parameter`.
    // ignore: unused_element, unused_element_parameter
    this.showDebugLeaderBounds = false,
  });

  /// Collections of [LayerLink]s, which are given to leader widgets that are
  /// positioned at the selection bounds, and around the full selection.
  final SelectionLayerLinks links;

  /// Whether to paint colorful bounds around the leader widgets, for debugging purposes.
  final bool showDebugLeaderBounds;

  @override
  ContentLayerWidget build(BuildContext context, SuperEditorContext editContext) {
    return SelectionLeadersDocumentLayer(
      document: editContext.document,
      selection: editContext.composer.selectionNotifier,
      links: links,
      showDebugLeaderBounds: showDebugLeaderBounds,
    );
  }
}

/// A [SuperEditor] plugin.
///
/// A [SuperEditorPlugin] can be thought of as a combination of two plugins.
///
/// First, there's the part that extends the behavior of an [Editor]. Those extensions
/// are added in [attach].
///
/// Second, there's the part that extends the behavior of a [SuperEditor] widget, directly.
/// Those behaviors are collected through various properties, such as [keyboardActions] and
/// [componentBuilders].
///
/// An [Editor] is a logical pipeline of requests, commands, and reactions. It has no direct
/// connection to a user interface.
///
/// A [SuperEditor] widget is a complete editor user interface. When a plugin is given to a
/// [SuperEditor] widget, the [SuperEditor] widget [attach]s the plugin to its [Editor], and
/// then the [SuperEditor] widget pulls out UI related behaviors from the plugin for things
/// like keyboard handlers and component builders.
///
/// [Editor] extensions are applied differently than the [SuperEditor] UI extensions, because
/// an [Editor] is mutable, meaning it can be altered. But a [SuperEditor] widget, like all other
/// widgets, is immutable, and must be rebuilt when properties change. As a result, each plugin
/// is instructed to alter an [Editor] as desired, but [SuperEditor] UI extensions are queried
/// from the plugin, so that the [SuperEditor] widget can pass those extensions as properties
/// during a widget build.
abstract class SuperEditorPlugin {
  const SuperEditorPlugin();

  /// Adds desired behaviors to the given [editor].
  void attach(Editor editor) {}

  /// Removes behaviors from the given [editor], which were added in [attach].
  void detach(Editor editor) {}

  /// Additional [DocumentKeyboardAction]s that will be added to a given [SuperEditor] widget.
  List<DocumentKeyboardAction> get keyboardActions => [];

  /// Additional [ComponentBuilder]s that will be added to a given [SuperEditor] widget.
  List<ComponentBuilder> get componentBuilders => [];

  /// Additional underlay [SuperEditorLayerBuilder]s that will be added to a given [SuperEditor].
  List<SuperEditorLayerBuilder> get documentUnderlayBuilders => [];

  /// Additional overlay [SuperEditorLayerBuilder]s that will be added to a given [SuperEditor].
  List<SuperEditorLayerBuilder> get documentOverlayBuilders => [];

  /// Optional handlers that respond to taps on content, e.g., opening
  /// a link when the user taps on text with a link attribution.
  ///
  /// If a handler returns [TapHandlingInstruction.halt], no subsequent handlers
  /// nor the default tap behavior will be executed.
  List<ContentTapDelegate> get contentTapHandlers => const [];

  /// Custom style phases that are added to the very end of the [SuperEditor] style phases.
  List<SingleColumnLayoutStylePhase> get appendedStylePhases => const [];
}

/// A collection of policies that dictate how a [SuperEditor]'s selection will change
/// based on other behaviors, such as focus changes.
class SuperEditorSelectionPolicies {
  const SuperEditorSelectionPolicies({
    this.placeCaretAtEndOfDocumentOnGainFocus = true,
    this.restorePreviousSelectionOnGainFocus = true,
    this.openKeyboardWhenTappingExistingSelection = true,
    this.clearSelectionWhenEditorLosesFocus = true,
    this.clearSelectionWhenImeConnectionCloses = true,
  });

  /// Whether the editor should automatically place the caret at the end of the document,
  /// if the editor receives focus without an existing selection.
  ///
  /// [restorePreviousSelectionOnGainFocus] takes priority over this policy.
  final bool placeCaretAtEndOfDocumentOnGainFocus;

  /// Whether the editor's previous selection should be restored when the editor re-gains
  /// focus, after having previous lost focus.
  final bool restorePreviousSelectionOnGainFocus;

  /// {@template openKeyboardWhenTappingExistingSelection}
  /// Whether the software keyboard should be opened when the user taps on the existing
  /// selection.
  ///
  /// Defaults to `true`.
  ///
  /// Typically, when an editor has a selection, the software keyboard is already open.
  /// However, in some cases, the user might want to temporarily close the keyboard. For
  /// example, the user might replace the keyboard with a custom emoji picker panel.
  ///
  /// When the user is done with the temporary keyboard replacement, the user then wants to
  /// open the keyboard again, so the user taps on the caret. If this property is `true`
  /// then tapping on the caret will open the keyboard again.
  ///
  /// In other, similar cases, the user might want to be able to tap on the editor without
  /// opening the keyboard. For example, the user might open a keyboard panel that can insert
  /// various types of content. In that case, the user might want to move the caret to then
  /// insert something from the panel. In this case, it's easy to accidentally tap on the
  /// existing caret, which would then close the panel and open the keyboard. To avoid this
  /// annoyance, this property can be set to `false`, in which case tapping on the caret won't
  /// automatically open the keyboard. It's left to the app to re-open the keyboard when desired.
  /// {@endtemplate}
  final bool openKeyboardWhenTappingExistingSelection;

  /// Whether the editor's selection should be removed when the editor loses
  /// all focus (not just primary focus).
  ///
  /// If `true`, when focus moves to a different subtree, such as a popup text
  /// field, or a button somewhere else on the screen, the editor will remove
  /// its selection. When focus returns to the editor, the previous selection can
  /// be restored, but that's controlled by other policies.
  ///
  /// If `false`, the editor will retain its selection, including a visual caret
  /// and selected content, even when the editor doesn't have any focus, and can't
  /// process any input.
  final bool clearSelectionWhenEditorLosesFocus;

  /// Whether the editor's selection should be removed when the editor closes or loses
  /// its IME connection.
  ///
  /// Defaults to `true`.
  ///
  /// Apps that include a custom input mode, such as an editing panel that sometimes
  /// replaces the software keyboard, should set this to `false` and instead control the
  /// IME connection manually.
  final bool clearSelectionWhenImeConnectionCloses;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuperEditorSelectionPolicies &&
          runtimeType == other.runtimeType &&
          placeCaretAtEndOfDocumentOnGainFocus == other.placeCaretAtEndOfDocumentOnGainFocus &&
          restorePreviousSelectionOnGainFocus == other.restorePreviousSelectionOnGainFocus &&
          clearSelectionWhenEditorLosesFocus == other.clearSelectionWhenEditorLosesFocus &&
          clearSelectionWhenImeConnectionCloses == other.clearSelectionWhenImeConnectionCloses;

  @override
  int get hashCode =>
      placeCaretAtEndOfDocumentOnGainFocus.hashCode ^
      restorePreviousSelectionOnGainFocus.hashCode ^
      clearSelectionWhenEditorLosesFocus.hashCode ^
      clearSelectionWhenImeConnectionCloses.hashCode;
}

/// Builds widgets that are displayed at the same position and size as
/// the document layout within a [SuperEditor].
abstract class SuperEditorLayerBuilder {
  ContentLayerWidget build(BuildContext context, SuperEditorContext editContext);
}

/// A [SuperEditorLayerBuilder] that's implemented with a given function, so
/// that simple use-cases don't need to sub-class [SuperEditorLayerBuilder].
class FunctionalSuperEditorLayerBuilder implements SuperEditorLayerBuilder {
  const FunctionalSuperEditorLayerBuilder(this._delegate);

  final ContentLayerWidget Function(BuildContext context, SuperEditorContext editContext) _delegate;

  @override
  ContentLayerWidget build(BuildContext context, SuperEditorContext editContext) => _delegate(context, editContext);
}

/// A [SuperEditorLayerBuilder] that paints a caret at the primary selection extent
/// in a [SuperEditor].
class DefaultCaretOverlayBuilder implements SuperEditorLayerBuilder {
  const DefaultCaretOverlayBuilder({
    this.caretStyle = const CaretStyle(
      width: 2,
      color: Colors.black,
    ),
    this.platformOverride,
    this.displayOnAllPlatforms = false,
    this.displayCaretWithExpandedSelection = true,
    this.blinkTimingMode = BlinkTimingMode.ticker,
  });

  /// Styles applied to the caret that's painted by this caret overlay.
  final CaretStyle caretStyle;

  /// The platform to use to determine caret behavior, defaults to [defaultTargetPlatform].
  final TargetPlatform? platformOverride;

  /// Whether to display a caret on all platforms, including mobile.
  ///
  /// By default, the caret is only displayed on desktop.
  final bool displayOnAllPlatforms;

  /// Whether to display the caret when the selection is expanded.
  ///
  /// Defaults to `true`.
  final bool displayCaretWithExpandedSelection;

  /// The timing mechanism used to blink, e.g., `Ticker` or `Timer`.
  ///
  /// `Timer`s are not expected to work in tests.
  final BlinkTimingMode blinkTimingMode;

  @override
  ContentLayerWidget build(BuildContext context, SuperEditorContext editContext) {
    return CaretDocumentOverlay(
      composer: editContext.composer,
      documentLayoutResolver: () => editContext.documentLayout,
      caretStyle: caretStyle,
      platformOverride: platformOverride,
      displayOnAllPlatforms: displayOnAllPlatforms,
      displayCaretWithExpandedSelection: displayCaretWithExpandedSelection,
      blinkTimingMode: blinkTimingMode,
    );
  }
}

/// Creates visual components for the standard [SuperEditor].
///
/// These builders are in priority order. The first builder
/// to return a non-null component is used.
const defaultComponentBuilders = <ComponentBuilder>[
  BlockquoteComponentBuilder(),
  ParagraphComponentBuilder(),
  ListItemComponentBuilder(),
  ImageComponentBuilder(),
  HorizontalRuleComponentBuilder(),
  CompositeComponentBuilder(),
];

/// Default list of document overlays that are displayed on top of the document
/// layout in a [SuperEditor].
const defaultSuperEditorDocumentOverlayBuilders = <SuperEditorLayerBuilder>[
  // Adds a Leader around the document selection at a focal point for the
  // iOS floating toolbar.
  SuperEditorIosToolbarFocalPointDocumentLayerBuilder(),
  // Displays caret and drag handles, specifically for iOS.
  SuperEditorIosHandlesDocumentLayerBuilder(),

  // Adds a Leader around the document selection at a focal point for the
  // Android floating toolbar.
  SuperEditorAndroidToolbarFocalPointDocumentLayerBuilder(),
  // Displays caret and drag handles, specifically for Android.
  SuperEditorAndroidHandlesDocumentLayerBuilder(),

  // Displays caret for typical desktop use-cases.
  DefaultCaretOverlayBuilder(),
];

/// Keyboard actions for the standard [SuperEditor].
final defaultKeyboardActions = <DocumentKeyboardAction>[
  toggleInteractionModeWhenCmdOrCtrlPressed,
  doNothingWhenThereIsNoSelection,
  scrollOnPageUpKeyPress,
  scrollOnPageDownKeyPress,
  scrollOnCtrlOrCmdAndHomeKeyPress,
  scrollOnCtrlOrCmdAndEndKeyPress,
  pasteWhenCmdVIsPressed,
  copyWhenCmdCIsPressed,
  cutWhenCmdXIsPressed,
  undoWhenCmdZOrCtrlZIsPressed,
  redoWhenCmdShiftZOrCtrlShiftZIsPressed,
  collapseSelectionWhenEscIsPressed,
  selectAllWhenCmdAIsPressed,
  moveLeftAndRightWithArrowKeys,
  moveUpAndDownWithArrowKeys,
  moveToLineStartWithHome,
  moveToLineEndWithEnd,
  tabToIndentListItem,
  shiftTabToUnIndentListItem,
  backspaceToUnIndentListItem,
  tabToIndentTask,
  shiftTabToUnIndentTask,
  backspaceToUnIndentTask,
  tabToIndentParagraph,
  shiftTabToUnIndentParagraph,
  backspaceToUnIndentParagraph,
  backspaceToConvertTaskToParagraph,
  backspaceToClearParagraphBlockType,
  cmdBToToggleBold,
  cmdIToToggleItalics,
  shiftEnterToInsertNewlineInBlock,
  enterToInsertNewTask,
  enterToUnIndentParagraph,
  enterToInsertBlockNewline,
  moveToLineStartOrEndWithCtrlAOrE,
  deleteToStartOfLineWithCmdBackspaceOnMac,
  deleteWordUpstreamWithAltBackspaceOnMac,
  deleteWordUpstreamWithControlBackspaceOnWindowsAndLinux,
  deleteUpstreamContentWithBackspace,
  deleteToEndOfLineWithCmdDeleteOnMac,
  deleteWordDownstreamWithAltDeleteOnMac,
  deleteWordDownstreamWithControlDeleteOnWindowsAndLinux,
  deleteDownstreamContentWithDelete,
  blockControlKeys,
  anyCharacterOrDestructiveKeyToDeleteSelection,
  anyCharacterToInsertInParagraph,
  anyCharacterToInsertInTextContent,
];

/// Keyboard actions for a [SuperEditor] running with IME on
/// desktop.
///
/// Using the IME on desktop involves partial input from the IME
/// and partial input from non-content keys, like arrow keys.
final defaultImeKeyboardActions = <DocumentKeyboardAction>[
  toggleInteractionModeWhenCmdOrCtrlPressed,
  pasteWhenCmdVIsPressed,
  copyWhenCmdCIsPressed,
  cutWhenCmdXIsPressed,
  undoWhenCmdZOrCtrlZIsPressed,
  redoWhenCmdShiftZOrCtrlShiftZIsPressed,
  selectAllWhenCmdAIsPressed,
  cmdBToToggleBold,
  cmdIToToggleItalics,
  // All handlers that use backspace should be placed before `doNothingWithBackspaceOnWeb`,
  // otherwise they will not run on web.
  backspaceToUnIndentListItem,
  backspaceToUnIndentParagraph,
  backspaceToUnIndentTask,
  backspaceToConvertTaskToParagraph,
  backspaceToClearParagraphBlockType,
  // We handled all shortcuts that care about backspace. Let the browser IME handle the
  // backspace to perform text deletion.
  doNothingWithBackspaceOnWeb,
  doNothingWithCtrlOrCmdAndZOnWeb,
  tabToIndentTask,
  shiftTabToUnIndentTask,
  tabToIndentParagraph,
  shiftTabToUnIndentParagraph,
  enterToUnIndentParagraph,
  deleteDownstreamCharacterWithCtrlDeleteOnMac,
  scrollOnCtrlOrCmdAndHomeKeyPress,
  scrollOnCtrlOrCmdAndEndKeyPress,
  shiftEnterToInsertNewlineInBlock,
  deleteToEndOfLineWithCmdDeleteOnMac,
  // WARNING: No keyboard handlers below this point will run on Mac. On Mac, most
  // common shortcuts are recognized by the OS. This line short circuits Super Editor
  // handlers, passing the key combo to the OS on Mac. Place all custom Mac key
  // combos above this handler.
  sendKeyEventToMacOs,
  doNothingWhenThereIsNoSelection,
  scrollOnPageUpKeyPress,
  scrollOnPageDownKeyPress,
  moveUpAndDownWithArrowKeys,
  moveToStartOrEndOfLineWithArrowKeysOnWeb,
  doNothingWithLeftRightArrowKeysAtMiddleOfTextOnWeb,
  moveLeftAndRightWithArrowKeys,
  moveToLineStartWithHome,
  moveToLineEndWithEnd,
  doNothingWithEnterOnWeb,
  enterToInsertNewTask,
  enterToInsertBlockNewline,
  tabToIndentListItem,
  shiftTabToUnIndentListItem,
  deleteToStartOfLineWithCmdBackspaceOnMac,
  deleteWordUpstreamWithAltBackspaceOnMac,
  deleteWordUpstreamWithControlBackspaceOnWindowsAndLinux,
  deleteUpstreamContentWithBackspace,
  deleteWordDownstreamWithAltDeleteOnMac,
  deleteWordDownstreamWithControlDeleteOnWindowsAndLinux,
  doNothingWithDeleteOnWeb,
  deleteDownstreamContentWithDelete,
];

/// Map selector names to its handlers.
///
/// Selectors are like system-level shortcuts for macOS.
///
/// For more information, see [MacOsSelectors].
const defaultEditorSelectorHandlers = <String, SuperEditorSelectorHandler>{
  // Caret movement.
  MacOsSelectors.moveLeft: moveLeft,
  MacOsSelectors.moveRight: moveRight,
  MacOsSelectors.moveUp: moveUp,
  MacOsSelectors.moveDown: moveDown,
  MacOsSelectors.moveForward: moveRight,
  MacOsSelectors.moveBackward: moveLeft,
  MacOsSelectors.moveWordLeft: moveWordLeft,
  MacOsSelectors.moveWordRight: moveWordRight,
  MacOsSelectors.moveToLeftEndOfLine: moveToLeftEndOfLine,
  MacOsSelectors.moveToRightEndOfLine: moveToRightEndOfLine,
  MacOsSelectors.moveToBeginningOfParagraph: moveToBeginningOfParagraph,
  MacOsSelectors.moveToEndOfParagraph: moveToEndOfParagraph,
  MacOsSelectors.moveToBeginningOfDocument: moveToBeginningOfDocument,
  MacOsSelectors.moveToEndOfDocument: moveToEndOfDocument,

  // Selection expanding.
  MacOsSelectors.moveLeftAndModifySelection: moveLeftAndModifySelection,
  MacOsSelectors.moveRightAndModifySelection: moveRightAndModifySelection,
  MacOsSelectors.moveUpAndModifySelection: moveUpAndModifySelection,
  MacOsSelectors.moveDownAndModifySelection: moveDownAndModifySelection,
  MacOsSelectors.moveWordLeftAndModifySelection: moveWordLeftAndModifySelection,
  MacOsSelectors.moveWordRightAndModifySelection: moveWordRightAndModifySelection,
  MacOsSelectors.moveToLeftEndOfLineAndModifySelection: moveToLeftEndOfLineAndModifySelection,
  MacOsSelectors.moveToRightEndOfLineAndModifySelection: moveToRightEndOfLineAndModifySelection,
  MacOsSelectors.moveParagraphBackwardAndModifySelection: moveParagraphBackwardAndModifySelection,
  MacOsSelectors.moveParagraphForwardAndModifySelection: moveParagraphForwardAndModifySelection,
  MacOsSelectors.moveToBeginningOfDocumentAndModifySelection: moveToBeginningOfDocumentAndModifySelection,
  MacOsSelectors.moveToEndOfDocumentAndModifySelection: moveToEndOfDocumentAndModifySelection,

  // Insertion.
  MacOsSelectors.insertTab: indentListItem,
  MacOsSelectors.insertBacktab: unIndentListItem,
  MacOsSelectors.insertNewLine: insertNewLine,

  // Deletion.
  MacOsSelectors.deleteBackward: deleteBackward,
  MacOsSelectors.deleteForward: deleteForward,
  MacOsSelectors.deleteWordBackward: deleteWordBackward,
  MacOsSelectors.deleteWordForward: deleteWordForward,
  MacOsSelectors.deleteToBeginningOfLine: deleteToBeginningOfLine,
  MacOsSelectors.deleteToEndOfLine: deleteToEndOfLine,
  MacOsSelectors.deleteBackwardByDecomposingPreviousCharacter: deleteBackward,

  // Scrolling.
  MacOsSelectors.scrollToBeginningOfDocument: scrollToBeginningOfDocument,
  MacOsSelectors.scrollToEndOfDocument: scrollToEndOfDocument,
  MacOsSelectors.scrollPageUp: scrollPageUp,
  MacOsSelectors.scrollPageDown: scrollPageDown,
};

/// Stylesheet applied to all [SuperEditor]s by default.
final defaultStylesheet = Stylesheet(
  rules: [
    StyleRule(
      BlockSelector.all,
      (doc, docNode) {
        return {
          Styles.maxWidth: 640.0,
          Styles.padding: const CascadingPadding.symmetric(horizontal: 24),
          Styles.textStyle: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            height: 1.4,
          ),
        };
      },
    ),
    StyleRule(
      const BlockSelector("header1"),
      (doc, docNode) {
        return {
          Styles.padding: const CascadingPadding.only(top: 40),
          Styles.textStyle: const TextStyle(
            color: Color(0xFF333333),
            fontSize: 38,
            fontWeight: FontWeight.bold,
          ),
        };
      },
    ),
    StyleRule(
      const BlockSelector("header2"),
      (doc, docNode) {
        return {
          Styles.padding: const CascadingPadding.only(top: 32),
          Styles.textStyle: const TextStyle(
            color: Color(0xFF333333),
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        };
      },
    ),
    StyleRule(
      const BlockSelector("header3"),
      (doc, docNode) {
        return {
          Styles.padding: const CascadingPadding.only(top: 28),
          Styles.textStyle: const TextStyle(
            color: Color(0xFF333333),
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        };
      },
    ),
    StyleRule(
      const BlockSelector("paragraph"),
      (doc, docNode) {
        return {
          Styles.padding: const CascadingPadding.only(top: 24),
        };
      },
    ),
    StyleRule(
      const BlockSelector("paragraph").after("header1"),
      (doc, docNode) {
        return {
          Styles.padding: const CascadingPadding.only(top: 0),
        };
      },
    ),
    StyleRule(
      const BlockSelector("paragraph").after("header2"),
      (doc, docNode) {
        return {
          Styles.padding: const CascadingPadding.only(top: 0),
        };
      },
    ),
    StyleRule(
      const BlockSelector("paragraph").after("header3"),
      (doc, docNode) {
        return {
          Styles.padding: const CascadingPadding.only(top: 0),
        };
      },
    ),
    StyleRule(
      const BlockSelector("listItem"),
      (doc, docNode) {
        return {
          Styles.padding: const CascadingPadding.only(top: 24),
        };
      },
    ),
    StyleRule(
      const BlockSelector("blockquote"),
      (doc, docNode) {
        return {
          Styles.textStyle: const TextStyle(
            color: Colors.grey,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            height: 1.4,
          ),
        };
      },
    ),
    StyleRule(
      BlockSelector.all.last(),
      (doc, docNode) {
        return {
          Styles.padding: const CascadingPadding.only(bottom: 96),
        };
      },
    ),
  ],
  inlineTextStyler: defaultInlineTextStyler,
  inlineWidgetBuilders: defaultInlineWidgetBuilderChain,
);

TextStyle defaultInlineTextStyler(Set<Attribution> attributions, TextStyle existingStyle) {
  return existingStyle.merge(defaultStyleBuilder(attributions));
}

/// Creates [TextStyles] for the standard [SuperEditor].
TextStyle defaultStyleBuilder(Set<Attribution> attributions) {
  TextStyle newStyle = const TextStyle();

  for (final attribution in attributions) {
    if (attribution == boldAttribution) {
      newStyle = newStyle.copyWith(
        fontWeight: FontWeight.bold,
      );
    } else if (attribution == italicsAttribution) {
      newStyle = newStyle.copyWith(
        fontStyle: FontStyle.italic,
      );
    } else if (attribution == underlineAttribution) {
      newStyle = newStyle.copyWith(
        decoration: newStyle.decoration == null
            ? TextDecoration.underline
            : TextDecoration.combine([TextDecoration.underline, newStyle.decoration!]),
      );
    } else if (attribution == strikethroughAttribution) {
      newStyle = newStyle.copyWith(
        decoration: newStyle.decoration == null
            ? TextDecoration.lineThrough
            : TextDecoration.combine([TextDecoration.lineThrough, newStyle.decoration!]),
      );
    } else if (attribution == superscriptAttribution) {
      newStyle = newStyle.copyWith(
        fontFeatures: [const FontFeature.superscripts()],
      );
    } else if (attribution == subscriptAttribution) {
      newStyle = newStyle.copyWith(
        fontFeatures: [const FontFeature.subscripts()],
      );
    } else if (attribution is ColorAttribution) {
      newStyle = newStyle.copyWith(
        color: attribution.color,
      );
    } else if (attribution is BackgroundColorAttribution) {
      newStyle = newStyle.copyWith(
        backgroundColor: attribution.color,
      );
    } else if (attribution is FontSizeAttribution) {
      newStyle = newStyle.copyWith(
        fontSize: attribution.fontSize,
      );
    } else if (attribution is FontFamilyAttribution) {
      newStyle = newStyle.copyWith(
        fontFamily: attribution.fontFamily,
      );
    } else if (attribution is LinkAttribution) {
      newStyle = newStyle.copyWith(
        color: Colors.lightBlue,
        decoration: TextDecoration.underline,
      );
    }
  }
  return newStyle;
}

/// Default visual styles related to content selection.
const defaultSelectionStyle = SelectionStyles(
  selectionColor: Color(0xFFACCEF7),
);
