import 'dart:ui';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:overlord/follow_the_leader.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/edit_context.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/default_editor/super_editor.dart';
import 'package:super_editor/src/default_editor/text_tools.dart';
import 'package:super_editor/src/document_operations/selection_operations.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/content_layers.dart';
import 'package:super_editor/src/infrastructure/flutter/build_context.dart';
import 'package:super_editor/src/infrastructure/flutter/eager_pan_gesture_recognizer.dart';
import 'package:super_editor/src/infrastructure/flutter/flutter_scheduler.dart';
import 'package:super_editor/src/infrastructure/multi_tap_gesture.dart';
import 'package:super_editor/src/infrastructure/platforms/android/android_document_controls.dart';
import 'package:super_editor/src/infrastructure/platforms/android/drag_handle_selection.dart';
import 'package:super_editor/src/infrastructure/platforms/android/long_press_selection.dart';
import 'package:super_editor/src/infrastructure/platforms/android/magnifier.dart';
import 'package:super_editor/src/infrastructure/platforms/android/selection_handles.dart';
import 'package:super_editor/src/infrastructure/platforms/mobile_documents.dart';
import 'package:super_editor/src/infrastructure/signal_notifier.dart';
import 'package:super_editor/src/infrastructure/sliver_hybrid_stack.dart';
import 'package:super_editor/src/infrastructure/touch_controls.dart';

import '../infrastructure/document_gestures.dart';
import '../infrastructure/document_gestures_interaction_overrides.dart';
import 'selection_upstream_downstream.dart';

/// An [InheritedWidget] that provides shared access to a [SuperEditorAndroidControlsController],
/// which coordinates the state of Android controls like the caret, handles, magnifier, etc.
///
/// This widget and its associated controller exist so that [SuperEditor] has maximum freedom
/// in terms of where to implement Android gestures vs carets vs the magnifier vs the toolbar.
/// Each of these responsibilities have some unique differences, which make them difficult or
/// impossible to implement within a single widget. By sharing a controller, a group of independent
/// widgets can work together to cover those various responsibilities.
///
/// Centralizing a controller in an [InheritedWidget] also allows [SuperEditor] to share that
/// control with application code outside of [SuperEditor], by placing a [SuperEditorAndroidControlsScope]
/// above the [SuperEditor] in the widget tree. For this reason, [SuperEditor] should access
/// the [SuperEditorAndroidControlsScope] through [rootOf].
class SuperEditorAndroidControlsScope extends InheritedWidget {
  /// Finds the highest [SuperEditorAndroidControlsScope] in the widget tree, above the given
  /// [context], and returns its associated [SuperEditorAndroidControlsController].
  static SuperEditorAndroidControlsController rootOf(BuildContext context) {
    final data = maybeRootOf(context);

    if (data == null) {
      throw Exception(
          "Tried to depend upon the root SuperEditorAndroidControlsScope but no such ancestor widget exists.");
    }

    return data;
  }

  static SuperEditorAndroidControlsController? maybeRootOf(BuildContext context) {
    InheritedElement? root;

    context.visitAncestorElements((element) {
      if (element is! InheritedElement || element.widget is! SuperEditorAndroidControlsScope) {
        // Keep visiting.
        return true;
      }

      root = element;

      // Keep visiting, to ensure we get the root scope.
      return true;
    });

    if (root == null) {
      return null;
    }

    // Create build dependency on the Android controls context.
    context.dependOnInheritedElement(root!);

    // Return the current Android controls data.
    return (root!.widget as SuperEditorAndroidControlsScope).controller;
  }

  /// Finds the nearest [SuperEditorAndroidControlsScope] in the widget tree, above the given
  /// [context], and returns its associated [SuperEditorAndroidControlsController].
  static SuperEditorAndroidControlsController nearestOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SuperEditorAndroidControlsScope>()!.controller;

  static SuperEditorAndroidControlsController? maybeNearestOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SuperEditorAndroidControlsScope>()?.controller;

  const SuperEditorAndroidControlsScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final SuperEditorAndroidControlsController controller;

  @override
  bool updateShouldNotify(SuperEditorAndroidControlsScope oldWidget) {
    return controller != oldWidget.controller;
  }
}

/// A controller, which coordinates the state of various Android editor controls, including
/// the caret, handles, magnifier, and toolbar.
class SuperEditorAndroidControlsController {
  SuperEditorAndroidControlsController({
    this.controlsColor,
    LeaderLink? collapsedHandleFocalPoint,
    this.collapsedHandleBuilder,
    LeaderLink? upstreamHandleFocalPoint,
    LeaderLink? downstreamHandleFocalPoint,
    this.expandedHandlesBuilder,
    this.magnifierBuilder,
    this.toolbarBuilder,
    this.createOverlayControlsClipper,
  })  : collapsedHandleFocalPoint = collapsedHandleFocalPoint ?? LeaderLink(),
        upstreamHandleFocalPoint = upstreamHandleFocalPoint ?? LeaderLink(),
        downstreamHandleFocalPoint = downstreamHandleFocalPoint ?? LeaderLink();

  void dispose() {
    cancelCollapsedHandleAutoHideCountdown();
    _shouldCaretBlink.dispose();
    _shouldShowMagnifier.dispose();
    _shouldShowToolbar.dispose();
  }

  /// Whether the caret should blink right now.
  ValueListenable<bool> get shouldCaretBlink => _shouldCaretBlink;
  final _shouldCaretBlink = ValueNotifier<bool>(true);

  /// Tells the caret to blink by setting [shouldCaretBlink] to `true`.
  void blinkCaret() {
    _shouldCaretBlink.value = true;
  }

  /// Tells the caret to stop blinking by setting [shouldCaretBlink] to `false`.
  void doNotBlinkCaret() {
    _shouldCaretBlink.value = false;
  }

  /// Signal that's notified when the caret should return to fully opaque, such as
  /// when the user moves the caret.
  final caretJumpToOpaqueSignal = SignalNotifier();

  /// Immediately make the caret fully opaque.
  void jumpCaretToOpaque() {
    caretJumpToOpaqueSignal.notifyListeners();
  }

  /// Color of the caret and text selection drag handles on Android.
  ///
  /// The default handle builders honor this color. If custom handle builders are
  /// provided, its up to those handle builders to honor this color, or not.
  final Color? controlsColor;

  /// The focal point for the collapsed drag handle.
  ///
  /// The collapsed handle builder should place the handle near this focal point.
  final LeaderLink collapsedHandleFocalPoint;

  /// Whether the collapsed drag handle should be displayed right now.
  ///
  /// This value is enforced to be opposite of [shouldShowExpandedHandles].
  ValueListenable<bool> get shouldShowCollapsedHandle => _shouldShowCollapsedHandle;
  final _shouldShowCollapsedHandle = ValueNotifier<bool>(false);

  Timer? _collapsedHandleAutoHideCountdown;

  /// Shows the collapsed drag handle by setting [shouldShowCollapsedHandle] to `true`, and also
  /// hides the expanded handle by setting [shouldShowExpandedHandles] to `false`.
  void showCollapsedHandle() {
    cancelCollapsedHandleAutoHideCountdown();

    _shouldShowCollapsedHandle.value = true;
    _shouldShowExpandedHandles.value = false;
  }

  /// Starts a short countdown, after which the collapsed handle will be
  /// hidden (the caret will remain visible).
  void startCollapsedHandleAutoHideCountdown() {
    _collapsedHandleAutoHideCountdown?.cancel();

    _collapsedHandleAutoHideCountdown = Timer(const Duration(seconds: 5), () {
      hideCollapsedHandle();
    });
  }

  /// Cancels any on-going timer started by [startCollapsedHandleAutoHideCountdown].
  void cancelCollapsedHandleAutoHideCountdown() {
    _collapsedHandleAutoHideCountdown?.cancel();
    _collapsedHandleAutoHideCountdown = null;
  }

  /// Hides the collapsed drag handle by setting [shouldShowCollapsedHandle] to `false`.
  void hideCollapsedHandle() {
    cancelCollapsedHandleAutoHideCountdown();

    _shouldShowCollapsedHandle.value = false;
  }

  /// Toggles [shouldShowCollapsedHandle], and if necessary, hides the expanded handles.
  void toggleCollapsedHandle() {
    if (shouldShowCollapsedHandle.value) {
      hideCollapsedHandle();
    } else {
      showCollapsedHandle();
    }
  }

  /// (Optional) Builder to create the visual representation of all drag handles: collapsed,
  /// upstream, downstream.
  ///
  /// If [collapsedHandleBuilder] is `null`, a default Android handle is displayed.
  final DocumentCollapsedHandleBuilder? collapsedHandleBuilder;

  /// The focal point for the upstream drag handle, when the selection is expanded.
  ///
  /// The upstream handle builder should place its handle near this focal point.
  final LeaderLink upstreamHandleFocalPoint;

  /// The focal point for the downstream drag handle, when the selection is expanded.
  ///
  /// The downstream handle builder should place its handle near this focal point.
  final LeaderLink downstreamHandleFocalPoint;

  /// Whether the expanded drag handles should be displayed right now.
  ///
  /// This value is enforced to be opposite of [shouldShowCollapsedHandle].
  ValueListenable<bool> get shouldShowExpandedHandles => _shouldShowExpandedHandles;
  final _shouldShowExpandedHandles = ValueNotifier<bool>(false);

  /// Shows the expanded drag handles by setting [shouldShowExpandedHandles] to `true`, and also
  /// hides the collapsed handle by setting [shouldShowCollapsedHandle] to `false`.
  void showExpandedHandles() {
    _shouldShowExpandedHandles.value = true;
    _shouldShowCollapsedHandle.value = false;
  }

  /// Hides the expanded drag handles by setting [shouldShowExpandedHandles] to `false`.
  void hideExpandedHandles() => _shouldShowExpandedHandles.value = false;

  /// Toggles [shouldShowExpandedHandles], and if necessary, hides the collapsed handle.
  void toggleExpandedHandles() {
    if (shouldShowExpandedHandles.value) {
      hideCollapsedHandle();
    } else {
      showCollapsedHandle();
    }
  }

  /// {@template are_selection_handles_allowed}
  /// Whether or not the selection handles are allowed to be displayed.
  ///
  /// Typically, whenever the selection changes the drag handles are displayed. However,
  /// there are some cases where we want to select some content, but don't show the
  /// drag handles. For example, when the user taps a misspelled word, we might want to select
  /// the misspelled word without showing any handles.
  ///
  /// Defaults to `true`.
  /// {@endtemplate}
  ValueListenable<bool> get areSelectionHandlesAllowed => _areSelectionHandlesAllowed;
  final _areSelectionHandlesAllowed = ValueNotifier<bool>(true);

  /// Temporarily prevents any selection handles from being displayed.
  ///
  /// Call this when you want to select some content, but don't want to show the drag handles.
  /// [allowSelectionHandles] must be called to allow the drag handles to be displayed again.
  void preventSelectionHandles() => _areSelectionHandlesAllowed.value = false;

  /// Allows the selection handles to be displayed after they have been temporarily
  /// prevented by [preventSelectionHandles].
  void allowSelectionHandles() => _areSelectionHandlesAllowed.value = true;

  /// (Optional) Builder to create the visual representation of the expanded drag handles.
  ///
  /// If [expandedHandlesBuilder] is `null`, default Android handles are displayed.
  final DocumentExpandedHandlesBuilder? expandedHandlesBuilder;

  /// Whether the Android magnifier should be displayed right now.
  ValueListenable<bool> get shouldShowMagnifier => _shouldShowMagnifier;
  final _shouldShowMagnifier = ValueNotifier<bool>(false);

  /// Shows the magnifier by setting [shouldShowMagnifier] to `true`.
  void showMagnifier() => _shouldShowMagnifier.value = true;

  /// Hides the magnifier by setting [shouldShowMagnifier] to `false`.
  void hideMagnifier() => _shouldShowMagnifier.value = false;

  /// Toggles [shouldShowMagnifier].
  void toggleMagnifier() => _shouldShowMagnifier.value = !_shouldShowMagnifier.value;

  /// Link to a location where a magnifier should be focused.
  ///
  /// The magnifier builder should place the magnifier near this focal point.
  final magnifierFocalPoint = LeaderLink();

  /// (Optional) Builder to create the visual representation of the magnifier.
  ///
  /// If [magnifierBuilder] is `null`, a default Android magnifier is displayed.
  final DocumentMagnifierBuilder? magnifierBuilder;

  /// Whether the Android floating toolbar should be displayed right now.
  ValueListenable<bool> get shouldShowToolbar => _shouldShowToolbar;
  final _shouldShowToolbar = ValueNotifier<bool>(false);

  /// Shows the toolbar by setting [shouldShowToolbar] to `true`.
  void showToolbar() => _shouldShowToolbar.value = true;

  /// Hides the toolbar by setting [shouldShowToolbar] to `false`.
  void hideToolbar() => _shouldShowToolbar.value = false;

  /// Toggles [shouldShowToolbar].
  void toggleToolbar() => _shouldShowToolbar.value = !_shouldShowToolbar.value;

  /// Link to a location where a toolbar should be focused.
  ///
  /// This link probably points to a rectangle, such as a bounding rectangle
  /// around the user's selection. Therefore, the toolbar builder shouldn't
  /// assume that this focal point is a single pixel.
  final toolbarFocalPoint = LeaderLink();

  /// (Optional) Builder to create the visual representation of the floating
  /// toolbar.
  ///
  /// If [toolbarBuilder] is `null`, a default Android toolbar is displayed.
  final DocumentFloatingToolbarBuilder? toolbarBuilder;

  /// Creates a clipper that restricts where the toolbar and magnifier can
  /// appear in the overlay.
  ///
  /// If no clipper factory method is provided, then the overlay controls
  /// will be allowed to appear anywhere in the overlay in which they sit
  /// (probably the entire screen).
  final CustomClipper<Rect> Function(BuildContext overlayContext)? createOverlayControlsClipper;
}

/// A [SuperEditorDocumentLayerBuilder] that builds an [AndroidToolbarFocalPointDocumentLayer], which
/// positions a [Leader] widget around the document selection, as a focal point for an Android
/// floating toolbar.
class SuperEditorAndroidToolbarFocalPointDocumentLayerBuilder implements SuperEditorLayerBuilder {
  const SuperEditorAndroidToolbarFocalPointDocumentLayerBuilder({
    // TODO(srawlins): `unused_element`, when reporting a parameter, is being
    // renamed to `unused_element_parameter`. For now, ignore each; when the SDK
    // constraint is >= 3.6.0, just ignore `unused_element_parameter`.
    // ignore: unused_element, unused_element_parameter
    this.showDebugLeaderBounds = false,
  });

  /// Whether to paint colorful bounds around the leader widget.
  final bool showDebugLeaderBounds;

  @override
  ContentLayerWidget build(BuildContext context, SuperEditorContext editorContext) {
    if (defaultTargetPlatform != TargetPlatform.android ||
        SuperEditorAndroidControlsScope.maybeNearestOf(context) == null) {
      // There's no controls scope. This probably means SuperEditor is configured with
      // a non-Android gesture mode. Build nothing.
      return const ContentLayerProxyWidget(child: SizedBox());
    }

    return AndroidToolbarFocalPointDocumentLayer(
      document: editorContext.document,
      selection: editorContext.composer.selectionNotifier,
      toolbarFocalPointLink: SuperEditorAndroidControlsScope.rootOf(context).toolbarFocalPoint,
      showDebugLeaderBounds: showDebugLeaderBounds,
    );
  }
}

/// A [SuperEditorLayerBuilder], which builds an [AndroidHandlesDocumentLayer],
/// which displays Android-style caret and handles.
class SuperEditorAndroidHandlesDocumentLayerBuilder implements SuperEditorLayerBuilder {
  const SuperEditorAndroidHandlesDocumentLayerBuilder({
    this.caretColor,
    this.caretWidth = 2,
  });

  /// The (optional) color of the caret (not the drag handle), by default the color
  /// defers to the root [SuperEditorAndroidControlsScope], or the app theme if the
  /// controls controller has no preference for the color.
  final Color? caretColor;

  final double caretWidth;

  @override
  ContentLayerWidget build(BuildContext context, SuperEditorContext editContext) {
    if (defaultTargetPlatform != TargetPlatform.android ||
        SuperEditorAndroidControlsScope.maybeNearestOf(context) == null) {
      // There's no controls scope. This probably means SuperEditor is configured with
      // a non-Android gesture mode. Build nothing.
      return const ContentLayerProxyWidget(child: SizedBox());
    }

    return AndroidHandlesDocumentLayer(
      document: editContext.document,
      documentLayout: editContext.documentLayout,
      selection: editContext.composer.selectionNotifier,
      changeSelection: (newSelection, changeType, reason) {
        editContext.editor.execute([
          ChangeSelectionRequest(newSelection, changeType, reason),
          const ClearComposingRegionRequest(),
        ]);
      },
      caretWidth: caretWidth,
      caretColor: caretColor,
    );
  }
}

/// Document gesture interactor that's designed for Android touch input, e.g.,
/// drag to scroll, and handles to control selection.
class AndroidDocumentTouchInteractor extends StatefulWidget {
  const AndroidDocumentTouchInteractor({
    Key? key,
    required this.focusNode,
    required this.editor,
    required this.document,
    required this.getDocumentLayout,
    required this.selection,
    this.openKeyboardWhenTappingExistingSelection = true,
    required this.openSoftwareKeyboard,
    required this.scrollController,
    required this.fillViewport,
    this.contentTapHandlers,
    this.dragAutoScrollBoundary = const AxisOffset.symmetric(54),
    required this.dragHandleAutoScroller,
    this.showDebugPaint = false,
    required this.child,
  }) : super(key: key);

  final FocusNode focusNode;

  final Editor editor;
  final Document document;
  final DocumentLayout Function() getDocumentLayout;
  final ValueListenable<DocumentSelection?> selection;

  /// {@macro openKeyboardWhenTappingExistingSelection}
  final bool openKeyboardWhenTappingExistingSelection;

  /// A callback that should open the software keyboard when invoked.
  final VoidCallback openSoftwareKeyboard;

  /// Optional list of handlers that respond to taps on content, e.g., opening
  /// a link when the user taps on text with a link attribution.
  ///
  /// If a handler returns [TapHandlingInstruction.halt], no subsequent handlers
  /// nor the default tap behavior will be executed.
  final List<ContentTapDelegate>? contentTapHandlers;

  final ScrollController scrollController;

  /// The closest that the user's selection drag gesture can get to the
  /// document boundary before auto-scrolling.
  ///
  /// The default value is `54.0` pixels for both the leading and trailing
  /// edges.
  final AxisOffset dragAutoScrollBoundary;

  final ValueNotifier<DragHandleAutoScroller?> dragHandleAutoScroller;

  /// Whether the document gesture detector should fill the entire viewport
  /// even if the actual content is smaller.
  final bool fillViewport;

  final bool showDebugPaint;

  final Widget child;

  @override
  State createState() => _AndroidDocumentTouchInteractorState();
}

class _AndroidDocumentTouchInteractorState extends State<AndroidDocumentTouchInteractor>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  SuperEditorAndroidControlsController? _controlsController;

  // The ScrollPosition attached to the _ancestorScrollable, if there's an ancestor
  // Scrollable.
  ScrollPosition? _ancestorScrollPosition;

  Offset? _globalTapDownOffset;
  Offset? _globalStartDragOffset;
  Offset? _dragStartInDoc;
  Offset? _startDragPositionOffset;
  double? _dragStartScrollOffset;
  Offset? _globalDragOffset;

  final _magnifierGlobalOffset = ValueNotifier<Offset?>(null);

  Timer? _tapDownLongPressTimer;
  bool get _isLongPressInProgress => _longPressStrategy != null;
  AndroidDocumentLongPressSelectionStrategy? _longPressStrategy;

  bool _isCaretDragInProgress = false;

  // Cached view metrics to ignore unnecessary didChangeMetrics calls.
  Size? _lastSize;
  ViewPadding? _lastInsets;

  final _interactor = GlobalKey();

  @override
  void initState() {
    super.initState();

    widget.dragHandleAutoScroller.value = DragHandleAutoScroller(
      vsync: this,
      dragAutoScrollBoundary: widget.dragAutoScrollBoundary,
      getScrollPosition: () => scrollPosition,
      getViewportBox: () => viewportBox,
    );

    widget.document.addListener(_onDocumentChange);
    widget.selection.addListener(_onSelectionChange);

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final view = View.of(context);
    _lastSize = view.physicalSize;
    _lastInsets = view.viewInsets;

    _controlsController = SuperEditorAndroidControlsScope.rootOf(context);

    _ancestorScrollPosition = context.findAncestorScrollableWithVerticalScroll?.position;
  }

  @override
  void didUpdateWidget(AndroidDocumentTouchInteractor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.document != oldWidget.document) {
      oldWidget.document.removeListener(_onDocumentChange);
      widget.document.addListener(_onDocumentChange);
    }

    if (widget.selection != oldWidget.selection) {
      oldWidget.selection.removeListener(_onSelectionChange);
      widget.selection.addListener(_onSelectionChange);
    }
  }

  @override
  void didChangeMetrics() {
    // It is possible to get the notification even though the metrics for view are same.
    final view = View.of(context);
    final size = view.physicalSize;
    final insets = view.viewInsets;
    if (size == _lastSize &&
        _lastInsets?.left == insets.left &&
        _lastInsets?.right == insets.right &&
        _lastInsets?.top == insets.top &&
        _lastInsets?.bottom == insets.bottom) {
      return;
    }
    _lastSize = size;
    _lastInsets = insets;

    // The available screen dimensions may have changed, e.g., due to keyboard
    // appearance/disappearance. Reflow the layout. Use a post-frame callback
    // to give the rest of the UI a chance to reflow, first.
    onNextFrame((_) {
      _ensureSelectionExtentIsVisible();

      setState(() {
        // reflow document layout
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    widget.document.removeListener(_onDocumentChange);
    widget.selection.removeListener(_onSelectionChange);

    widget.dragHandleAutoScroller.value!.dispose();
    widget.dragHandleAutoScroller.value = null;

    super.dispose();
  }

  /// Returns the layout for the current document, which answers questions
  /// about the locations and sizes of visual components within the layout.
  DocumentLayout get _docLayout => widget.getDocumentLayout();

  /// Returns the `ScrollPosition` that controls the scroll offset of
  /// this widget.
  ///
  /// If this widget has an ancestor `Scrollable`, then the returned
  /// `ScrollPosition` belongs to that ancestor `Scrollable`, and this
  /// widget doesn't include a `ScrollView`.
  ///
  /// If this widget doesn't have an ancestor `Scrollable`, then this
  /// widget includes a `ScrollView` and the `ScrollView`'s position
  /// is returned.
  ScrollPosition get scrollPosition => _ancestorScrollPosition ?? widget.scrollController.position;

  /// Returns the `RenderBox` for the scrolling viewport.
  ///
  /// If this widget has an ancestor `Scrollable`, then the returned
  /// `RenderBox` belongs to that ancestor `Scrollable`.
  ///
  /// If this widget doesn't have an ancestor `Scrollable`, then this
  /// widget includes a `ScrollView` and this `State`'s render object
  /// is the viewport `RenderBox`.
  RenderBox get viewportBox => context.findViewportBox();

  Offset _getDocumentOffsetFromGlobalOffset(Offset globalOffset) {
    return _docLayout.getDocumentOffsetFromAncestorOffset(globalOffset);
  }

  Offset _documentOffsetToViewportOffset(Offset documentOffset) {
    final globalOffset = _docLayout.getGlobalOffsetFromDocumentOffset(documentOffset);
    return viewportBox.globalToLocal(globalOffset);
  }

  /// Returns the render box for the interactor gesture detector.
  RenderBox get interactorBox => _interactor.currentContext!.findRenderObject() as RenderBox;

  /// Maps the given [interactorOffset] within the interactor's coordinate space
  /// to the same screen position in the viewport's coordinate space.
  ///
  /// When this interactor includes it's own `ScrollView`, the [interactorOffset]
  /// is the same as the viewport offset.
  ///
  /// When this interactor defers to an ancestor `Scrollable`, then the
  /// [interactorOffset] is transformed into the ancestor coordinate space.
  Offset _interactorOffsetInViewport(Offset interactorOffset) {
    // Viewport might be our box, or an ancestor box if we're inside someone
    // else's Scrollable.
    return viewportBox.globalToLocal(
      interactorBox.localToGlobal(interactorOffset),
    );
  }

  void _ensureSelectionExtentIsVisible() {
    editorGesturesLog.fine("Ensuring selection extent is visible");
    final selection = widget.selection.value;
    if (selection == null) {
      // There's no selection. We don't need to take any action.
      return;
    }

    // Calculate the y-value of the selection extent side of the selected content so that we
    // can ensure they're visible.
    final selectionRectInDocumentLayout =
        widget.getDocumentLayout().getRectForSelection(selection.base, selection.extent)!;
    final extentOffsetInViewport = widget.document.getAffinityForSelection(selection) == TextAffinity.downstream
        ? _documentOffsetToViewportOffset(selectionRectInDocumentLayout.bottomCenter)
        : _documentOffsetToViewportOffset(selectionRectInDocumentLayout.topCenter);

    widget.dragHandleAutoScroller.value!.ensureOffsetIsVisible(extentOffsetInViewport);
  }

  void _onDocumentChange(_) {
    onNextFrame((_) {
      _ensureSelectionExtentIsVisible();
    });
  }

  void _onSelectionChange() {
    if (widget.selection.value == null) {
      _controlsController!
        ..hideCollapsedHandle()
        ..hideExpandedHandles()
        ..hideMagnifier()
        ..hideToolbar();
      return;
    }

    // Only scroll the editor to reveal the selection extent if the selection is
    // collapsed. If the selection is expanded, the user is likely dragging
    // a selection handle, which already causes auto-scrolling to reveal
    // the selection extent. If the selection is expanded because the user
    // double-tapped, the first tap will have already scrolled the editor to
    // reveal the selection.
    if (widget.selection.value?.isCollapsed == true) {
      onNextFrame((_) {
        _ensureSelectionExtentIsVisible();
      });
    }
  }

  void _onTapDown(TapDownDetails details) {
    final position = scrollPosition;
    if (position is ScrollPositionWithSingleContext) {
      position.goIdle();
    }

    _globalTapDownOffset = details.globalPosition;
    _tapDownLongPressTimer?.cancel();
    if (!disableLongPressSelectionForSuperlist) {
      _tapDownLongPressTimer = Timer(kLongPressTimeout, _onLongPressDown);
    }
  }

  void _onTapCancel() {
    _tapDownLongPressTimer?.cancel();
    _tapDownLongPressTimer = null;
  }

  // Runs when a tap down has lasted long enough to signify a long-press.
  void _onLongPressDown() {
    _longPressStrategy = AndroidDocumentLongPressSelectionStrategy(
      document: widget.document,
      documentLayout: _docLayout,
      select: _updateLongPressSelection,
    );

    final didLongPressSelectionStart = _longPressStrategy!.onLongPressStart(
      tapDownDocumentOffset: _getDocumentOffsetFromGlobalOffset(_globalTapDownOffset!),
    );
    if (!didLongPressSelectionStart) {
      _longPressStrategy = null;
      return;
    }

    // A long-press selection is in progress. Initially show the toolbar, but nothing else.
    _controlsController!
      ..hideCollapsedHandle()
      ..hideExpandedHandles()
      ..hideMagnifier()
      ..showToolbar();

    widget.focusNode.requestFocus();
  }

  void _onTapUp(TapUpDetails details) {
    // Stop waiting for a long-press to start.
    _tapDownLongPressTimer?.cancel();

    // Cancel any on-going long-press.
    if (_isLongPressInProgress) {
      _longPressStrategy = null;
      _magnifierGlobalOffset.value = null;
      _showAndHideEditingControlsAfterTapSelection(didTapOnExistingSelection: false);
      return;
    }

    editorGesturesLog.info("Tap down on document");
    final docOffset = _getDocumentOffsetFromGlobalOffset(details.globalPosition);
    editorGesturesLog.fine(" - document offset: $docOffset");

    if (widget.contentTapHandlers != null) {
      for (final handler in widget.contentTapHandlers!) {
        final result = handler.onTap(
          DocumentTapDetails(
            documentLayout: _docLayout,
            layoutOffset: docOffset,
            globalOffset: details.globalPosition,
          ),
        );
        if (result == TapHandlingInstruction.halt) {
          // The custom tap handler doesn't want us to react at all
          // to the tap.
          return;
        }
      }
    }

    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    editorGesturesLog.fine(" - tapped document position: $docPosition");

    bool didTapOnExistingSelection = false;
    if (docPosition != null) {
      final selection = widget.selection.value;
      didTapOnExistingSelection = selection != null &&
          selection.isCollapsed &&
          selection.extent.nodeId == docPosition.nodeId &&
          selection.extent.nodePosition.isEquivalentTo(docPosition.nodePosition);

      final tappedComponent = _docLayout.getComponentByNodeId(docPosition.nodeId)!;
      if (!tappedComponent.isVisualSelectionSupported()) {
        // The user tapped a non-selectable component.
        // Place the document selection at the nearest selectable node
        // to the tapped component.
        moveSelectionToNearestSelectableNode(
          editor: widget.editor,
          document: widget.document,
          documentLayoutResolver: widget.getDocumentLayout,
          currentSelection: widget.selection.value,
          startingNode: widget.document.getNodeById(docPosition.nodeId)!,
        );
      } else {
        // Place the document selection at the location where the
        // user tapped.
        _selectPosition(docPosition);
      }
    } else {
      _clearSelection();
    }

    _showAndHideEditingControlsAfterTapSelection(didTapOnExistingSelection: didTapOnExistingSelection);

    if (didTapOnExistingSelection && widget.openKeyboardWhenTappingExistingSelection) {
      // The user tapped on the existing selection. Show the software keyboard.
      //
      // If the user didn't tap on an existing selection, the software keyboard will
      // already be visible.
      widget.openSoftwareKeyboard();
    }

    widget.focusNode.requestFocus();
  }

  void _onDoubleTapDown(TapDownDetails details) {
    editorGesturesLog.info("Double tap down on document");
    final docOffset = _getDocumentOffsetFromGlobalOffset(details.globalPosition);
    editorGesturesLog.fine(" - document offset: $docOffset");

    if (widget.contentTapHandlers != null) {
      for (final handler in widget.contentTapHandlers!) {
        final result = handler.onDoubleTap(
          DocumentTapDetails(
            documentLayout: _docLayout,
            layoutOffset: docOffset,
            globalOffset: details.globalPosition,
          ),
        );
        if (result == TapHandlingInstruction.halt) {
          // The custom tap handler doesn't want us to react at all
          // to the tap.
          return;
        }
      }
    }

    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    editorGesturesLog.fine(" - tapped document position: $docPosition");

    if (docPosition != null) {
      final tappedComponent = _docLayout.getComponentByNodeId(docPosition.nodeId)!;
      if (!tappedComponent.isVisualSelectionSupported()) {
        // The user tapped a non-selectable component, so we can't select a word.
        // The editor will remain focused and selection will remain in the nearest
        // selectable component, as set in _onTapUp.
        return;
      }

      bool didSelectContent = _selectWordAt(
        docPosition: docPosition,
        docLayout: _docLayout,
      );

      if (!didSelectContent) {
        didSelectContent = _selectBlockAt(docPosition);
      }

      if (!didSelectContent) {
        // Place the document selection at the location where the
        // user tapped.
        _selectPosition(docPosition);
      }
    } else {
      _clearSelection();
    }

    _showAndHideEditingControlsAfterTapSelection(didTapOnExistingSelection: false);

    widget.focusNode.requestFocus();
  }

  bool _selectBlockAt(DocumentPosition position) {
    if (position.nodePosition is! UpstreamDownstreamNodePosition) {
      return false;
    }

    widget.editor.execute([
      ChangeSelectionRequest(
        DocumentSelection(
          base: DocumentPosition(
            documentPath: position.documentPath,
            nodePosition: const UpstreamDownstreamNodePosition.upstream(),
          ),
          extent: DocumentPosition(
            documentPath: position.documentPath,
            nodePosition: const UpstreamDownstreamNodePosition.downstream(),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
      const ClearComposingRegionRequest(),
    ]);

    return true;
  }

  void _onTripleTapDown(TapDownDetails details) {
    editorGesturesLog.info("Triple tap down on document");
    final docOffset = _getDocumentOffsetFromGlobalOffset(details.globalPosition);
    editorGesturesLog.fine(" - document offset: $docOffset");

    if (widget.contentTapHandlers != null) {
      for (final handler in widget.contentTapHandlers!) {
        final result = handler.onTripleTap(
          DocumentTapDetails(
            documentLayout: _docLayout,
            layoutOffset: docOffset,
            globalOffset: details.globalPosition,
          ),
        );
        if (result == TapHandlingInstruction.halt) {
          // The custom tap handler doesn't want us to react at all
          // to the tap.
          return;
        }
      }
    }

    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    editorGesturesLog.fine(" - tapped document position: $docPosition");
    if (docPosition != null) {
      // The user tapped a non-selectable component, so we can't select a paragraph.
      // The editor will remain focused and selection will remain in the nearest
      // selectable component, as set in _onTapUp.
      final tappedComponent = _docLayout.getComponentByNodeId(docPosition.nodeId)!;
      if (!tappedComponent.isVisualSelectionSupported()) {
        return;
      }

      final didSelectParagraph = _selectParagraphAt(
        docPosition: docPosition,
        docLayout: _docLayout,
      );
      if (!didSelectParagraph) {
        // Place the document selection at the location where the
        // user tapped.
        _selectPosition(docPosition);
      }
    } else {
      _clearSelection();
    }

    _showAndHideEditingControlsAfterTapSelection(didTapOnExistingSelection: false);

    widget.focusNode.requestFocus();
  }

  void _showAndHideEditingControlsAfterTapSelection({
    required bool didTapOnExistingSelection,
  }) {
    if (widget.selection.value == null) {
      // There's no selection. Hide all controls.
      _controlsController!
        ..hideCollapsedHandle()
        ..hideExpandedHandles()
        ..hideMagnifier()
        ..hideToolbar()
        ..doNotBlinkCaret();
    } else if (!widget.selection.value!.isCollapsed) {
      // The selection is expanded.
      _controlsController!
        ..hideCollapsedHandle()
        ..showExpandedHandles()
        ..showToolbar()
        ..hideMagnifier()
        ..doNotBlinkCaret();
    } else {
      // The selection is collapsed.
      _controlsController!
        ..showCollapsedHandle()
        // The collapsed handle should disappear after some inactivity. Start the
        // countdown (or restart an in-progress countdown).
        ..startCollapsedHandleAutoHideCountdown()
        ..hideExpandedHandles()
        ..hideMagnifier()
        ..blinkCaret();

      if (didTapOnExistingSelection && _isKeyboardOpen) {
        // Toggle the toolbar display when the user taps on the collapsed caret,
        // or on top of an existing selection.
        //
        // But we only do this when the keyboard is already open. This is because
        // we don't want to show the toolbar when the user taps simply to open
        // the keyboard. That would feel unintentional, like a bug.
        _controlsController!.toggleToolbar();
      } else {
        // The user tapped somewhere else in the document. Hide the toolbar.
        _controlsController!.hideToolbar();
      }
    }
  }

  /// Returns `true` if we *think* the software keyboard is currently open, or
  /// `false` otherwise.
  ///
  /// We say "think" because Flutter doesn't report this info to us. Instead, we
  /// inspect the bottom insets on the window, and we assume any insets greater than
  /// zero means a keyboard is visible.
  bool get _isKeyboardOpen {
    return MediaQuery.viewInsetsOf(context).bottom > 0;
  }

  void _onPanStart(DragStartDetails details) {
    // Stop waiting for a long-press to start, if a long press isn't already in-progress.
    _tapDownLongPressTimer?.cancel();

    _globalStartDragOffset = details.globalPosition;
    _dragStartInDoc = _getDocumentOffsetFromGlobalOffset(details.globalPosition);

    // We need to record the scroll offset at the beginning of
    // a drag for the case that this interactor is embedded
    // within an ancestor Scrollable. We need to use this value
    // to calculate a scroll delta on every scroll frame to
    // account for the fact that this interactor is moving within
    // the ancestor scrollable, despite the fact that the user's
    // finger/mouse position hasn't changed.
    _dragStartScrollOffset = scrollPosition.pixels;
    _startDragPositionOffset = _dragStartInDoc!;

    if (_isLongPressInProgress) {
      _onLongPressPanStart(details);
      return;
    }

    final isTapOverCaret = _isOverCaret(_globalTapDownOffset!);

    if (isTapOverCaret) {
      _onCaretDragPanStart(details);
      return;
    }
  }

  bool _isOverCaret(Offset globalOffset) {
    if (widget.selection.value?.isCollapsed != true) {
      return false;
    }

    final collapsedPosition = widget.selection.value?.extent;
    if (collapsedPosition == null) {
      return false;
    }

    final extentRect = _docLayout.getRectForPosition(collapsedPosition)!;
    final caretRect = Rect.fromLTWH(extentRect.left - 1, extentRect.center.dy, 1, 1).inflate(24);

    final tapDocumentOffset = widget.getDocumentLayout().getDocumentOffsetFromAncestorOffset(_globalTapDownOffset!);
    return caretRect.contains(tapDocumentOffset);
  }

  void _onLongPressPanStart(DragStartDetails details) {
    _longPressStrategy!.onLongPressDragStart(details);

    // Tell the overlay where to put the magnifier.
    _magnifierGlobalOffset.value = details.globalPosition;

    widget.dragHandleAutoScroller.value!.startAutoScrollHandleMonitoring();

    _controlsController!
      ..hideToolbar()
      ..showMagnifier();
  }

  void _onCaretDragPanStart(DragStartDetails details) {
    _isCaretDragInProgress = true;

    // Tell the overlay where to put the magnifier.
    _magnifierGlobalOffset.value = details.globalPosition;

    widget.dragHandleAutoScroller.value!.startAutoScrollHandleMonitoring();

    _controlsController!
      ..doNotBlinkCaret()
      ..hideToolbar()
      ..showMagnifier();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _globalDragOffset = details.globalPosition;

    if (_isLongPressInProgress) {
      _onLongPressPanUpdate(details);
      return;
    }

    if (_isCaretDragInProgress) {
      _onCaretDragPanUpdate(details);
      return;
    }
  }

  void _onLongPressPanUpdate(DragUpdateDetails details) {
    final fingerDragDelta = _globalDragOffset! - _globalStartDragOffset!;
    final scrollDelta = _dragStartScrollOffset! - scrollPosition.pixels;
    final fingerDocumentOffset = _docLayout.getDocumentOffsetFromAncestorOffset(details.globalPosition);
    final fingerDocumentPosition = _docLayout.getDocumentPositionNearestToOffset(
      _startDragPositionOffset! + fingerDragDelta - Offset(0, scrollDelta),
    );
    _longPressStrategy!.onLongPressDragUpdate(fingerDocumentOffset, fingerDocumentPosition);
  }

  void _onCaretDragPanUpdate(DragUpdateDetails details) {
    final fingerDragDelta = _globalDragOffset! - _globalStartDragOffset!;
    final scrollDelta = _dragStartScrollOffset! - scrollPosition.pixels;
    final fingerDocumentPosition = _docLayout.getDocumentPositionNearestToOffset(
      _startDragPositionOffset! + fingerDragDelta - Offset(0, scrollDelta),
    )!;
    if (fingerDocumentPosition != widget.selection.value!.extent) {
      HapticFeedback.lightImpact();
    }
    _selectPosition(fingerDocumentPosition);
  }

  void _updateLongPressSelection(DocumentSelection newSelection) {
    if (newSelection != widget.selection.value) {
      _select(newSelection);
      HapticFeedback.lightImpact();
    }

    // Note: this needs to happen even when the selection doesn't change, in case
    // some controls, like a magnifier, need to follower the user's finger.
    _updateOverlayControlsOnLongPressDrag();
  }

  void _updateOverlayControlsOnLongPressDrag() {
    final extentDocumentOffset = _docLayout.getRectForPosition(widget.selection.value!.extent)!.center;
    final extentGlobalOffset = _docLayout.getAncestorOffsetFromDocumentOffset(extentDocumentOffset);
    final extentInteractorOffset = interactorBox.globalToLocal(extentGlobalOffset);
    final extentViewportOffset = _interactorOffsetInViewport(extentInteractorOffset);
    widget.dragHandleAutoScroller.value!.updateAutoScrollHandleMonitoring(dragEndInViewport: extentViewportOffset);

    _magnifierGlobalOffset.value = extentGlobalOffset;
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isLongPressInProgress) {
      _onLongPressEnd();
      return;
    }

    if (_isCaretDragInProgress) {
      _onCaretDragEnd();
      return;
    }
  }

  void _onPanCancel() {
    // When _tapDownLongPressTimer is not null we're waiting for either tapUp or tapCancel,
    // which will deal with the long press.
    if (_tapDownLongPressTimer == null && _isLongPressInProgress) {
      _onLongPressEnd();
      return;
    }

    if (_isCaretDragInProgress) {
      _onCaretDragEnd();
      return;
    }
  }

  void _onLongPressEnd() {
    _longPressStrategy!.onLongPressEnd();

    // Cancel any on-going long-press.
    _longPressStrategy = null;
    _magnifierGlobalOffset.value = null;

    widget.dragHandleAutoScroller.value!.stopAutoScrollHandleMonitoring();

    _controlsController!.hideMagnifier();
    if (!widget.selection.value!.isCollapsed) {
      _controlsController!
        ..showExpandedHandles()
        ..showToolbar();
    }
  }

  void _onCaretDragEnd() {
    _isCaretDragInProgress = false;

    _magnifierGlobalOffset.value = null;

    widget.dragHandleAutoScroller.value!.stopAutoScrollHandleMonitoring();

    _controlsController!
      ..blinkCaret()
      ..hideMagnifier();
    if (!widget.selection.value!.isCollapsed) {
      _controlsController!
        ..showExpandedHandles()
        ..showToolbar();
    }
  }

  bool _selectWordAt({
    required DocumentPosition docPosition,
    required DocumentLayout docLayout,
  }) {
    final newSelection = getWordSelection(docPosition: docPosition, docLayout: docLayout);
    if (newSelection != null) {
      widget.editor.execute([
        ChangeSelectionRequest(
          newSelection,
          SelectionChangeType.expandSelection,
          SelectionReason.userInteraction,
        ),
        const ClearComposingRegionRequest(),
      ]);
      return true;
    } else {
      return false;
    }
  }

  bool _selectParagraphAt({
    required DocumentPosition docPosition,
    required DocumentLayout docLayout,
  }) {
    final newSelection = getParagraphSelection(docPosition: docPosition, docLayout: docLayout);
    if (newSelection != null) {
      widget.editor.execute([
        ChangeSelectionRequest(
          newSelection,
          SelectionChangeType.expandSelection,
          SelectionReason.userInteraction,
        ),
        const ClearComposingRegionRequest(),
      ]);
      return true;
    } else {
      return false;
    }
  }

  void _selectPosition(DocumentPosition position) {
    editorGesturesLog.fine("Setting document selection to $position");
    widget.editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: position,
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
      const ClearComposingRegionRequest(),
    ]);
  }

  void _select(DocumentSelection newSelection) {
    widget.editor.execute([
      ChangeSelectionRequest(
        newSelection,
        SelectionChangeType.expandSelection,
        SelectionReason.userInteraction,
      ),
      const ClearComposingRegionRequest(),
    ]);
  }

  void _clearSelection() {
    editorGesturesLog.fine("Clearing document selection");
    widget.editor.execute([
      const ClearSelectionRequest(),
      const ClearComposingRegionRequest(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final gestureSettings = MediaQuery.maybeOf(context)?.gestureSettings;
    // PanGestureRecognizer is above contents to have first pass at gestures, but it only accepts
    // gestures that are over caret or handles or when a long press is in progress.
    // TapGestureRecognizer is below contents so that it doesn't interferes with buttons and other
    // tappable widgets.
    return SliverHybridStack(
      fillViewport: widget.fillViewport,
      children: [
        // Layer below
        RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: <Type, GestureRecognizerFactory>{
            TapSequenceGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapSequenceGestureRecognizer>(
              () => TapSequenceGestureRecognizer(),
              (TapSequenceGestureRecognizer recognizer) {
                recognizer
                  ..onTapDown = _onTapDown
                  ..onTapCancel = _onTapCancel
                  ..onTapUp = _onTapUp
                  ..onDoubleTapDown = _onDoubleTapDown
                  ..onTripleTapDown = _onTripleTapDown
                  ..gestureSettings = gestureSettings;
              },
            ),
          },
        ),
        widget.child,
        // Layer above
        RawGestureDetector(
          key: _interactor,
          behavior: HitTestBehavior.translucent,
          gestures: <Type, GestureRecognizerFactory>{
            EagerPanGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerPanGestureRecognizer>(
              () => EagerPanGestureRecognizer(),
              (EagerPanGestureRecognizer instance) {
                instance
                  ..shouldAccept = () {
                    if (_globalTapDownOffset == null) {
                      return false;
                    }
                    return _isOverCaret(_globalTapDownOffset!) || _isLongPressInProgress;
                  }
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onStart = _onPanStart
                  ..onUpdate = _onPanUpdate
                  ..onEnd = _onPanEnd
                  ..onCancel = _onPanCancel
                  ..gestureSettings = gestureSettings;
              },
            ),
          },
        ),
      ],
    );
  }
}

/// Adds and removes an Android-style editor controls overlay, as dictated by an ancestor
/// [SuperEditorAndroidControlsScope].
class SuperEditorAndroidControlsOverlayManager extends StatefulWidget {
  const SuperEditorAndroidControlsOverlayManager({
    super.key,
    this.tapRegionGroupId,
    required this.document,
    required this.getDocumentLayout,
    required this.selection,
    required this.setSelection,
    required this.scrollChangeSignal,
    required this.dragHandleAutoScroller,
    this.defaultToolbarBuilder,
    this.showDebugPaint = false,
    this.child,
  });

  /// {@macro super_editor_tap_region_group_id}
  final String? tapRegionGroupId;

  final Document document;
  final DocumentLayoutResolver getDocumentLayout;
  final ValueListenable<DocumentSelection?> selection;
  final void Function(DocumentSelection?) setSelection;

  final SignalNotifier scrollChangeSignal;

  final ValueListenable<DragHandleAutoScroller?> dragHandleAutoScroller;

  final DocumentFloatingToolbarBuilder? defaultToolbarBuilder;

  /// Paints some extra visual ornamentation to help with
  /// debugging, when `true`.
  final bool showDebugPaint;

  final Widget? child;

  @override
  State<SuperEditorAndroidControlsOverlayManager> createState() => SuperEditorAndroidControlsOverlayManagerState();
}

@visibleForTesting
class SuperEditorAndroidControlsOverlayManagerState extends State<SuperEditorAndroidControlsOverlayManager> {
  final _overlayController = OverlayPortalController();

  SuperEditorAndroidControlsController? _controlsController;
  late FollowerAligner _toolbarAligner;

  // The selection bound that the user is dragging, e.g., base or extent.
  //
  // The drag selection bound varies independently from the drag handle type.
  SelectionBound? _dragHandleSelectionBound;

  // The type of handle that the user started dragging, e.g., upstream or downstream.
  //
  // The drag handle type varies independently from the drag selection bound.
  HandleType? _dragHandleType;
  AndroidTextFieldDragHandleSelectionStrategy? _dragHandleSelectionStrategy;

  final _dragHandleSelectionGlobalFocalPoint = ValueNotifier<Offset?>(null);
  final _magnifierFocalPoint = ValueNotifier<Offset?>(null);

  late final DocumentHandleGestureDelegate _collapsedHandleGestureDelegate;
  late final DocumentHandleGestureDelegate _upstreamHandleGesturesDelegate;
  late final DocumentHandleGestureDelegate _downstreamHandleGesturesDelegate;

  @override
  void initState() {
    super.initState();
    _overlayController.show();
    widget.selection.addListener(_onSelectionChange);
    _collapsedHandleGestureDelegate = DocumentHandleGestureDelegate(
      onTap: _toggleToolbarOnCollapsedHandleTap,
      onPanStart: (details) => _onHandlePanStart(details, HandleType.collapsed),
      onPanUpdate: _onHandlePanUpdate,
      onPanEnd: (details) => _onHandlePanEnd(details, HandleType.collapsed),
    );
    _upstreamHandleGesturesDelegate = DocumentHandleGestureDelegate(
      onTap: () {
        // Register tap down to win gesture arena ASAP.
      },
      onPanStart: (details) => _onHandlePanStart(details, HandleType.upstream),
      onPanUpdate: _onHandlePanUpdate,
      onPanEnd: (details) => _onHandlePanEnd(details, HandleType.upstream),
      onPanCancel: () => _onHandlePanCancel(HandleType.upstream),
    );
    _downstreamHandleGesturesDelegate = DocumentHandleGestureDelegate(
      onTap: () {
        // Register tap down to win gesture arena ASAP.
      },
      onPanStart: (details) => _onHandlePanStart(details, HandleType.downstream),
      onPanUpdate: _onHandlePanUpdate,
      onPanEnd: (details) => _onHandlePanEnd(details, HandleType.downstream),
      onPanCancel: () => _onHandlePanCancel(HandleType.downstream),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _controlsController = SuperEditorAndroidControlsScope.rootOf(context);
    // TODO: Replace Cupertino aligner with a generic aligner because this code runs on Android.
    _toolbarAligner = CupertinoPopoverToolbarAligner();
    widget.selection.addListener(_onSelectionChange);
  }

  @override
  void didUpdateWidget(SuperEditorAndroidControlsOverlayManager oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.scrollChangeSignal != oldWidget.scrollChangeSignal) {
      oldWidget.scrollChangeSignal.removeListener(_onDocumentScroll);
      if (_dragHandleType != null) {
        // The user is currently dragging a handle. Listen for scroll changes.
        widget.scrollChangeSignal.addListener(_onDocumentScroll);
      }
    }

    if (widget.selection != oldWidget.selection) {
      oldWidget.selection.removeListener(_onSelectionChange);
      widget.selection.addListener(_onSelectionChange);
    }
  }

  @override
  void dispose() {
    // In case we're disposed in the middle of auto-scrolling, stop auto-scrolling and
    // stop listening for document scroll changes.
    widget.dragHandleAutoScroller.value?.stopAutoScrollHandleMonitoring();
    widget.scrollChangeSignal.removeListener(_onDocumentScroll);
    widget.selection.removeListener(_onSelectionChange);

    super.dispose();
  }

  @visibleForTesting
  bool get wantsToDisplayToolbar => _controlsController!.shouldShowToolbar.value;

  @visibleForTesting
  bool get wantsToDisplayMagnifier => _controlsController!.shouldShowMagnifier.value;

  /// Returns the `RenderBox` for the scrolling viewport.
  ///
  /// If this widget has an ancestor `Scrollable`, then the returned
  /// `RenderBox` belongs to that ancestor `Scrollable`.
  ///
  /// If this widget doesn't have an ancestor `Scrollable`, then this
  /// widget includes a `ScrollView` and this `State`'s render object
  /// is the viewport `RenderBox`.
  RenderBox get viewportBox =>
      (context.findAncestorScrollableWithVerticalScroll?.context.findRenderObject() ?? context.findRenderObject())
          as RenderBox;

  void _onSelectionChange() {
    final selection = widget.selection.value;
    if (selection == null) {
      return;
    }

    if (selection.isCollapsed &&
        _controlsController!.shouldShowExpandedHandles.value == true &&
        _dragHandleType == null) {
      // The selection is collapsed, but the expanded handles are visible and the user isn't dragging a handle.
      // This can happen when the selection is expanded, and the user deletes the selected text. The only situation
      // where the expanded handles should be visible when the selection is collapsed is when the selection
      // collapses while the user is dragging an expanded handle, which isn't the case here. Hide the handles.
      _controlsController!
        ..hideCollapsedHandle()
        ..hideExpandedHandles()
        ..hideMagnifier()
        ..hideToolbar()
        ..blinkCaret();
    }

    if (!selection.isCollapsed && _controlsController!.shouldShowCollapsedHandle.value == true) {
      // The selection is expanded, but the collapsed handle is visible. This can happen when the
      // selection is collapsed and the user taps the "Select All" button. There isn't any situation
      // where the collapsed handle should be visible when the selection is expanded. Hide the collapsed
      // handle and show the expanded handles.
      _controlsController!
        ..hideCollapsedHandle()
        ..showExpandedHandles()
        ..hideMagnifier();
    }
  }

  void _toggleToolbarOnCollapsedHandleTap() {
    _controlsController!.toggleToolbar();
  }

  void _updateDragHandleSelection(DocumentSelection newSelection) {
    if (newSelection != widget.selection.value) {
      widget.setSelection(newSelection);
      HapticFeedback.lightImpact();
    }
  }

  void _onHandlePanStart(DragStartDetails details, HandleType handleType) {
    final selection = widget.selection.value;
    if (selection == null) {
      throw Exception("Tried to drag a collapsed Android handle when there's no selection.");
    }

    final isSelectionDownstream = widget.selection.value!.hasDownstreamAffinity(widget.document);
    _dragHandleType = handleType;
    late final DocumentPosition selectionBoundPosition;
    if (isSelectionDownstream) {
      _dragHandleSelectionBound = handleType == HandleType.upstream ? SelectionBound.base : SelectionBound.extent;
      selectionBoundPosition = handleType == HandleType.upstream ? selection.base : selection.extent;
    } else {
      _dragHandleSelectionBound = handleType == HandleType.upstream ? SelectionBound.extent : SelectionBound.base;
      selectionBoundPosition = handleType == HandleType.upstream ? selection.extent : selection.base;
    }

    // Find the global offset for the center of the caret as the selection focal point.
    final documentLayout = widget.getDocumentLayout();
    // FIXME: this logic makes sense for selecting characters, but what about images? Does it make sense to set the focal point at the center of the image?
    final centerOfContentAtOffset = documentLayout.getAncestorOffsetFromDocumentOffset(
      documentLayout.getRectForPosition(selectionBoundPosition)!.center,
    );
    _dragHandleSelectionGlobalFocalPoint.value = centerOfContentAtOffset;
    _magnifierFocalPoint.value = centerOfContentAtOffset;

    _dragHandleSelectionStrategy = AndroidTextFieldDragHandleSelectionStrategy(
      document: widget.document,
      documentLayout: widget.getDocumentLayout(),
      select: _updateDragHandleSelection,
    )..onHandlePanStart(details, selection, handleType);

    // Update the controls for handle dragging.
    _controlsController!
      ..cancelCollapsedHandleAutoHideCountdown()
      ..doNotBlinkCaret()
      ..showMagnifier()
      ..hideToolbar();

    // Start auto-scrolling based on the drag-handle offset.
    widget.dragHandleAutoScroller.value?.startAutoScrollHandleMonitoring();

    // Listen for scroll changes so that we can update the selection when the user's
    // finger is standing still, but the document is moving beneath it during auto scrolling.
    widget.scrollChangeSignal.addListener(_onDocumentScroll);
  }

  void _onHandlePanUpdate(DragUpdateDetails details) {
    if (_dragHandleSelectionGlobalFocalPoint.value == null) {
      throw Exception(
          "Tried to pan an Android drag handle but the focal point is null. The focal point is set when the drag begins. This shouldn't be possible.");
    }

    // Move the selection focal point by the given delta.
    _dragHandleSelectionGlobalFocalPoint.value = _dragHandleSelectionGlobalFocalPoint.value! + details.delta;

    _dragHandleSelectionStrategy!.onHandlePanUpdate(details);

    // Update the magnifier based on the latest drag handle offset.
    _moveMagnifierToDragHandleOffset(dragDx: details.delta.dx);
  }

  void _onHandlePanEnd(DragEndDetails details, HandleType handleType) {
    _dragHandleSelectionStrategy = null;
    _onHandleDragEnd(handleType);
  }

  void _onHandlePanCancel(HandleType handleType) {
    _dragHandleSelectionStrategy = null;
    _onHandleDragEnd(handleType);
  }

  void _onHandleDragEnd(HandleType handleType) {
    _dragHandleSelectionStrategy = null;
    _dragHandleType = null;
    _dragHandleSelectionGlobalFocalPoint.value = null;
    _magnifierFocalPoint.value = null;

    // Start blinking the caret again, and hide the magnifier.
    _controlsController!
      ..blinkCaret()
      ..hideMagnifier();

    if (widget.selection.value?.isCollapsed == true &&
        const [HandleType.upstream, HandleType.downstream].contains(handleType)) {
      // The user dragged an expanded handle until the selection collapsed and then released the handle.
      // While the user was dragging, the expanded handles were displayed.
      // Show the collapsed.
      _controlsController!
        ..hideExpandedHandles()
        ..showCollapsedHandle();
    }

    // Stop auto-scrolling based on the drag-handle offset.
    widget.dragHandleAutoScroller.value?.stopAutoScrollHandleMonitoring();
    widget.scrollChangeSignal.removeListener(_onDocumentScroll);

    if (widget.selection.value?.isCollapsed == false) {
      // The selection is expanded, show the toolbar.
      _controlsController!.showToolbar();
    } else {
      // The selection is collapsed, start the auto-hide countdown for the handle.
      _controlsController!.startCollapsedHandleAutoHideCountdown();
    }
  }

  void _onDocumentScroll() {
    if (_dragHandleType == null) {
      // The user isn't dragging anything. We don't care that the document moved. Return.
      return;
    }

    // Update the selection based on the handle's offset in the document, now that the
    // document has scrolled.
    _moveSelectionAndMagnifierToDragHandleOffset();
  }

  void _moveSelectionAndMagnifierToDragHandleOffset({
    double dragDx = 0,
  }) {
    _moveSelectionToDragHandleOffset();
    _moveMagnifierToDragHandleOffset(dragDx: dragDx);
  }

  void _moveMagnifierToDragHandleOffset({
    double dragDx = 0,
  }) {
    // Move the selection to the document position that's nearest the focal point.
    final documentLayout = widget.getDocumentLayout();
    final nearestPosition = documentLayout.getDocumentPositionNearestToOffset(
      documentLayout.getDocumentOffsetFromAncestorOffset(_dragHandleSelectionGlobalFocalPoint.value!),
    )!;

    final centerOfContentInContentSpace = documentLayout.getRectForPosition(nearestPosition)!.center;

    // Move the magnifier focal point to match the drag x-offset, but always remain focused on the vertical
    // center of the line.
    final centerOfContentAtNearestPosition =
        documentLayout.getAncestorOffsetFromDocumentOffset(centerOfContentInContentSpace);
    _magnifierFocalPoint.value = Offset(
      _magnifierFocalPoint.value!.dx + dragDx,
      centerOfContentAtNearestPosition.dy,
    );

    // Update the auto-scroll focal point so that the viewport scrolls if we're
    // close to the boundary.
    widget.dragHandleAutoScroller.value?.updateAutoScrollHandleMonitoring(
      dragEndInViewport: _contentOffsetInViewport(centerOfContentInContentSpace),
    );
  }

  void _moveSelectionToDragHandleOffset() {
    // Move the selection to the document position that's nearest the focal point.
    final documentLayout = widget.getDocumentLayout();
    final nearestPosition = documentLayout.getDocumentPositionNearestToOffset(
      documentLayout.getDocumentOffsetFromAncestorOffset(_dragHandleSelectionGlobalFocalPoint.value!),
    )!;

    switch (_dragHandleType!) {
      case HandleType.collapsed:
        widget.setSelection(DocumentSelection.collapsed(
          position: nearestPosition,
        ));
      case HandleType.upstream:
      case HandleType.downstream:
        switch (_dragHandleSelectionBound!) {
          case SelectionBound.base:
            widget.setSelection(DocumentSelection(
              base: nearestPosition,
              extent: widget.selection.value!.extent,
            ));
          case SelectionBound.extent:
            widget.setSelection(DocumentSelection(
              base: widget.selection.value!.base,
              extent: nearestPosition,
            ));
        }
    }
  }

  /// Converts the [offset] in content space to an offset in the viewport space.
  Offset _contentOffsetInViewport(Offset offset) {
    final documentLayout = widget.getDocumentLayout();
    final globalOffset = documentLayout.getGlobalOffsetFromDocumentOffset(offset);
    return viewportBox.globalToLocal(globalOffset);
  }

  @override
  Widget build(BuildContext context) {
    return SliverHybridStack(
      children: [
        widget.child!,
        OverlayPortal(
          controller: _overlayController,
          overlayChildBuilder: _buildOverlay,
          child: const SizedBox(),
        ),
      ],
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return TapRegion(
      groupId: widget.tapRegionGroupId,
      child: Stack(
        children: [
          _buildMagnifierFocalPoint(),
          if (widget.showDebugPaint) //
            _buildDebugSelectionFocalPoint(),
          _buildMagnifier(),
          // Handles and toolbar are built after the magnifier so that they don't appear in the magnifier.
          _buildCollapsedHandle(),
          ..._buildExpandedHandles(),
          _buildToolbar(),
        ],
      ),
    );
  }

  Widget _buildCollapsedHandle() {
    return ValueListenableBuilder(
      valueListenable: _controlsController!.shouldShowCollapsedHandle,
      builder: (context, shouldShow, child) {
        final selection = widget.selection.value;
        if (selection == null || !selection.isCollapsed) {
          // When the user double taps we first place a collapsed selection
          // and then an expanded selection.
          // Return a SizedBox to avoid flashing the collapsed drag handle.
          return const SizedBox();
        }

        if (_controlsController!.collapsedHandleBuilder != null) {
          return _controlsController!.collapsedHandleBuilder!(
            context,
            handleKey: DocumentKeys.androidCaretHandle,
            focalPoint: _controlsController!.collapsedHandleFocalPoint,
            shouldShow: shouldShow,
            gestureDelegate: _collapsedHandleGestureDelegate,
          );
        }

        // Note: If we pass this widget as the `child` property, it causes repeated starts and stops
        // of the pan gesture. By building it here, pan events work as expected.
        return Follower.withOffset(
          link: _controlsController!.collapsedHandleFocalPoint,
          leaderAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.topCenter,
          showWhenUnlinked: false,
          // Use the offset to account for the invisible expanded touch region around the handle.
          offset: -Offset(0, AndroidSelectionHandle.defaultTouchRegionExpansion.top) *
              MediaQuery.devicePixelRatioOf(context),
          child: AnimatedOpacity(
            // When the controller doesn't want the handle to be visible, hide it.
            opacity: shouldShow ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(
              // Don't let the handle respond to touch events when the handle shouldn't
              // be visible. This is needed because we don't remove the handle from the
              // tree, we just make it invisible. In theory, invisible widgets aren't
              // supposed to be hit-testable, but in tests I found that without this
              // explicit IgnorePointer, gestures were still being captured by this handle.
              ignoring: !shouldShow,
              child: GestureDetector(
                onTapDown: (_) {
                  // Register tap down to win gesture arena ASAP.
                },
                onTap: _collapsedHandleGestureDelegate.onTap,
                onPanStart: _collapsedHandleGestureDelegate.onPanStart,
                onPanUpdate: _collapsedHandleGestureDelegate.onPanUpdate,
                onPanEnd: _collapsedHandleGestureDelegate.onPanEnd,
                onPanCancel: _collapsedHandleGestureDelegate.onPanCancel,
                dragStartBehavior: DragStartBehavior.down,
                child: AndroidSelectionHandle(
                  key: DocumentKeys.androidCaretHandle,
                  handleType: HandleType.collapsed,
                  color: _controlsController!.controlsColor ?? Theme.of(context).primaryColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildExpandedHandles() {
    if (_controlsController!.expandedHandlesBuilder != null) {
      return [
        ValueListenableBuilder(
          valueListenable: _controlsController!.shouldShowExpandedHandles,
          builder: (context, shouldShow, child) {
            return _controlsController!.expandedHandlesBuilder!(
              context,
              upstreamHandleKey: DocumentKeys.upstreamHandle,
              upstreamFocalPoint: _controlsController!.upstreamHandleFocalPoint,
              upstreamGestureDelegate: _upstreamHandleGesturesDelegate,
              downstreamHandleKey: DocumentKeys.downstreamHandle,
              downstreamFocalPoint: _controlsController!.downstreamHandleFocalPoint,
              downstreamGestureDelegate: _downstreamHandleGesturesDelegate,
              shouldShow: shouldShow,
            );
          },
        )
      ];
    }

    return [
      ValueListenableBuilder(
        valueListenable: _controlsController!.shouldShowExpandedHandles,
        builder: (context, shouldShow, child) {
          if (!shouldShow) {
            return const SizedBox();
          }

          return Follower.withOffset(
            link: _controlsController!.upstreamHandleFocalPoint,
            leaderAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topRight,
            showWhenUnlinked: false,
            // Use the offset to account for the invisible expanded touch region around the handle.
            offset:
                -AndroidSelectionHandle.defaultTouchRegionExpansion.topRight * MediaQuery.devicePixelRatioOf(context),
            child: GestureDetector(
              onTapDown: _upstreamHandleGesturesDelegate.onTapDown,
              onPanStart: _upstreamHandleGesturesDelegate.onPanStart,
              onPanUpdate: _upstreamHandleGesturesDelegate.onPanUpdate,
              onPanEnd: _upstreamHandleGesturesDelegate.onPanEnd,
              onPanCancel: _upstreamHandleGesturesDelegate.onPanCancel,
              dragStartBehavior: DragStartBehavior.down,
              child: AndroidSelectionHandle(
                key: DocumentKeys.upstreamHandle,
                handleType: HandleType.upstream,
                color: _controlsController!.controlsColor ?? Theme.of(context).primaryColor,
              ),
            ),
          );
        },
      ),
      ValueListenableBuilder(
        valueListenable: _controlsController!.shouldShowExpandedHandles,
        builder: (context, shouldShow, child) {
          if (!shouldShow) {
            return const SizedBox();
          }

          return Follower.withOffset(
            link: _controlsController!.downstreamHandleFocalPoint,
            leaderAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topLeft,
            showWhenUnlinked: false,
            // Use the offset to account for the invisible expanded touch region around the handle.
            offset:
                -AndroidSelectionHandle.defaultTouchRegionExpansion.topLeft * MediaQuery.devicePixelRatioOf(context),
            child: GestureDetector(
              onTapDown: _downstreamHandleGesturesDelegate.onTapDown,
              onPanStart: _downstreamHandleGesturesDelegate.onPanStart,
              onPanUpdate: _downstreamHandleGesturesDelegate.onPanUpdate,
              onPanEnd: _downstreamHandleGesturesDelegate.onPanEnd,
              onPanCancel: _downstreamHandleGesturesDelegate.onPanCancel,
              dragStartBehavior: DragStartBehavior.down,
              child: AndroidSelectionHandle(
                key: DocumentKeys.downstreamHandle,
                handleType: HandleType.downstream,
                color: _controlsController!.controlsColor ?? Theme.of(context).primaryColor,
              ),
            ),
          );
        },
      ),
    ];
  }

  Widget _buildToolbar() {
    return ValueListenableBuilder(
      valueListenable: _controlsController!.shouldShowToolbar,
      builder: (context, shouldShow, child) {
        return shouldShow ? child! : const SizedBox();
      },
      child: Follower.withAligner(
        link: _controlsController!.toolbarFocalPoint,
        aligner: _toolbarAligner,
        boundary: ScreenFollowerBoundary(
          screenSize: MediaQuery.sizeOf(context),
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
        child: _toolbarBuilder(context, DocumentKeys.mobileToolbar, _controlsController!.toolbarFocalPoint),
      ),
    );
  }

  DocumentFloatingToolbarBuilder get _toolbarBuilder {
    return _controlsController!.toolbarBuilder ?? //
        widget.defaultToolbarBuilder ??
        (_, __, ___) => const SizedBox();
  }

  Widget _buildMagnifierFocalPoint() {
    return ValueListenableBuilder(
      valueListenable: _magnifierFocalPoint,
      builder: (context, focalPoint, child) {
        if (focalPoint == null) {
          return const SizedBox();
        }

        return Positioned(
          left: focalPoint.dx,
          top: focalPoint.dy,
          width: 1,
          height: 1,
          child: Leader(
            link: _controlsController!.magnifierFocalPoint,
          ),
        );
      },
    );
  }

  Widget _buildMagnifier() {
    return ValueListenableBuilder(
      valueListenable: _controlsController!.shouldShowMagnifier,
      builder: (context, shouldShow, child) {
        return _controlsController!.magnifierBuilder != null //
            ? _controlsController!.magnifierBuilder!(
                context,
                DocumentKeys.magnifier,
                _controlsController!.magnifierFocalPoint,
                shouldShow,
              )
            : _buildDefaultMagnifier(
                context,
                DocumentKeys.magnifier,
                _controlsController!.magnifierFocalPoint,
                shouldShow,
              );
      },
    );
  }

  Widget _buildDefaultMagnifier(BuildContext context, Key magnifierKey, LeaderLink focalPoint, bool isVisible) {
    if (!isVisible) {
      return const SizedBox();
    }

    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Follower.withOffset(
      link: _controlsController!.magnifierFocalPoint,
      offset: Offset(0, -54 * devicePixelRatio),
      leaderAnchor: Alignment.center,
      followerAnchor: Alignment.center,
      boundary: ScreenFollowerBoundary(
        screenSize: MediaQuery.sizeOf(context),
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      ),
      child: AndroidMagnifyingGlass(
        key: magnifierKey,
        magnificationScale: 1.5,
        offsetFromFocalPoint: const Offset(0, -54),
      ),
    );
  }

  Widget _buildDebugSelectionFocalPoint() {
    return ValueListenableBuilder(
      valueListenable: _dragHandleSelectionGlobalFocalPoint,
      builder: (context, focalPoint, child) {
        if (focalPoint == null) {
          return const SizedBox();
        }

        return Positioned(
          left: focalPoint.dx,
          top: focalPoint.dy,
          child: FractionalTranslation(
            translation: const Offset(-0.5, -0.5),
            child: Container(
              width: 5,
              height: 5,
              color: Colors.red,
            ),
          ),
        );
      },
    );
  }
}

enum SelectionHandleType {
  collapsed,
  upstream,
  downstream,
}

enum SelectionBound {
  base,
  extent,
}
