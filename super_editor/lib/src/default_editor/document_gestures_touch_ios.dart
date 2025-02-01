import 'dart:ui';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/core/edit_context.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/default_editor/super_editor.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/default_editor/text_tools.dart';
import 'package:super_editor/src/document_operations/selection_operations.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/content_layers.dart';
import 'package:super_editor/src/infrastructure/flutter/eager_pan_gesture_recognizer.dart';
import 'package:super_editor/src/infrastructure/flutter/build_context.dart';
import 'package:super_editor/src/infrastructure/flutter/flutter_scheduler.dart';
import 'package:super_editor/src/infrastructure/multi_tap_gesture.dart';
import 'package:super_editor/src/infrastructure/platforms/ios/floating_cursor.dart';
import 'package:super_editor/src/infrastructure/platforms/ios/ios_document_controls.dart';
import 'package:super_editor/src/infrastructure/platforms/ios/long_press_selection.dart';
import 'package:super_editor/src/infrastructure/platforms/ios/magnifier.dart';
import 'package:super_editor/src/infrastructure/platforms/ios/selection_heuristics.dart';
import 'package:super_editor/src/infrastructure/platforms/mobile_documents.dart';
import 'package:super_editor/src/infrastructure/platforms/platform.dart';
import 'package:super_editor/src/infrastructure/signal_notifier.dart';
import 'package:super_editor/src/infrastructure/sliver_hybrid_stack.dart';
import 'package:super_editor/src/infrastructure/touch_controls.dart';

import '../infrastructure/document_gestures.dart';
import '../infrastructure/document_gestures_interaction_overrides.dart';
import 'selection_upstream_downstream.dart';

/// An [InheritedWidget] that provides shared access to a [SuperEditorIosControlsController],
/// which coordinates the state of iOS controls like the caret, handles, magnifier, etc.
///
/// This widget and its associated controller exist so that [SuperEditor] has maximum freedom
/// in terms of where to implement iOS gestures vs carets vs the floating cursor vs the
/// magnifier vs the toolbar. Each of these responsibilities have some unique differences,
/// which make them difficult or impossible to implement within a single widget. By sharing
/// a controller, a group of independent widgets can work together to cover those various
/// responsibilities.
///
/// Centralizing a controller in an [InheritedWidget] also allows [SuperEditor] to share that
/// control with application code outside of [SuperEditor], by placing an [SuperEditorIosControlsScope]
/// above the [SuperEditor] in the widget tree. For this reason, [SuperEditor] should access
/// the [SuperEditorIosControlsScope] through [rootOf].
class SuperEditorIosControlsScope extends InheritedWidget {
  /// Finds the highest [SuperEditorIosControlsScope] in the widget tree, above the given
  /// [context], and returns its associated [SuperEditorIosControlsController].
  static SuperEditorIosControlsController rootOf(BuildContext context) {
    final data = maybeRootOf(context);

    if (data == null) {
      throw Exception("Tried to depend upon the root SuperEditorIosControlsScope but no such ancestor widget exists.");
    }

    return data;
  }

  static SuperEditorIosControlsController? maybeRootOf(BuildContext context) {
    InheritedElement? root;

    context.visitAncestorElements((element) {
      if (element is! InheritedElement || element.widget is! SuperEditorIosControlsScope) {
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

    // Create build dependency on the iOS controls context.
    context.dependOnInheritedElement(root!);

    // Return the current iOS controls data.
    return (root!.widget as SuperEditorIosControlsScope).controller;
  }

  /// Finds the nearest [SuperEditorIosControlsScope] in the widget tree, above the given
  /// [context], and returns its associated [SuperEditorIosControlsController].
  static SuperEditorIosControlsController nearestOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SuperEditorIosControlsScope>()!.controller;

  static SuperEditorIosControlsController? maybeNearestOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SuperEditorIosControlsScope>()?.controller;

  const SuperEditorIosControlsScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final SuperEditorIosControlsController controller;

  @override
  bool updateShouldNotify(SuperEditorIosControlsScope oldWidget) {
    return controller != oldWidget.controller;
  }
}

/// A controller, which coordinates the state of various iOS editor controls, including
/// the caret, handles, floating cursor, magnifier, and toolbar.
class SuperEditorIosControlsController {
  SuperEditorIosControlsController({
    this.useIosSelectionHeuristics = true,
    this.handleColor,
    FloatingCursorController? floatingCursorController,
    this.magnifierBuilder,
    this.toolbarBuilder,
    this.createOverlayControlsClipper,
  }) : floatingCursorController = floatingCursorController ?? FloatingCursorController();

  void dispose() {
    floatingCursorController.dispose();
    _shouldCaretBlink.dispose();
    _shouldShowMagnifier.dispose();
    _shouldShowToolbar.dispose();
  }

  /// {@template ios_use_selection_heuristics}
  /// Whether to adjust the user's selection similar to the way iOS does.
  ///
  /// For example: iOS doesn't let users tap directly on a text offset. Instead,
  /// iOS places the caret at the end of the word, or beginning of the word,
  /// based on how close the user is to those locations when he taps.
  ///
  /// When this property is `true`, iOS-style heuristics should be used. When
  /// this value is `false`, the user's gestures should directly impact the
  /// area they touched.
  /// {@endtemplate}
  final bool useIosSelectionHeuristics;

  /// Color of the text selection drag handles on iOS.
  final Color? handleColor;

  /// Whether the caret (collapsed handle) should blink right now.
  ValueListenable<bool> get shouldCaretBlink => _shouldCaretBlink;
  final _shouldCaretBlink = ValueNotifier<bool>(true);

  /// Tells the caret to blink by setting [shouldCaretBlink] to `true`.
  void blinkCaret() => _shouldCaretBlink.value = true;

  /// Tells the caret to stop blinking by setting [shouldCaretBlink] to `false`.
  void doNotBlinkCaret() => _shouldCaretBlink.value = false;

  /// {@macro are_selection_handles_allowed}
  ValueListenable<bool> get areSelectionHandlesAllowed => _areSelectionHandlesAllowed;
  final _areSelectionHandlesAllowed = ValueNotifier<bool>(true);

  /// Temporarily prevents any selection handles from being displayed.
  ///
  /// Call this when you want to select some content, but don't want to show the drag handles.
  /// [allowSelectionHandles] must be called to allow the drag handles to be displayed again.
  void allowSelectionHandles() => _areSelectionHandlesAllowed.value = true;

  /// Allows the selection handles to be displayed after they have been temporarily
  /// prevented by [preventSelectionHandles].
  void preventSelectionHandles() => _areSelectionHandlesAllowed.value = false;

  /// Reports the [HandleType] of the handle being dragged by the user.
  ///
  /// If no drag handle is being dragged, this value is `null`.
  final ValueNotifier<HandleType?> handleBeingDragged = ValueNotifier<HandleType?>(null);

  /// Controls the iOS floating cursor.
  late final FloatingCursorController floatingCursorController;

  /// Whether the iOS magnifier should be displayed right now.
  ValueListenable<bool> get shouldShowMagnifier => _shouldShowMagnifier;
  final _shouldShowMagnifier = ValueNotifier<bool>(false);

  /// Shows the magnifier by setting [shouldShowMagnifier] to `true`.
  void showMagnifier() => _shouldShowMagnifier.value = true;

  /// Hides the magnifier by setting [shouldShowMagnifier] to `false`.
  void hideMagnifier() => _shouldShowMagnifier.value = false;

  /// Toggles [shouldShowMagnifier].
  void toggleMagnifier() => _shouldShowMagnifier.value = !_shouldShowMagnifier.value;

  /// Link to a location where a magnifier should be focused.
  final magnifierFocalPoint = LeaderLink();

  /// (Optional) Builder to create the visual representation of the magnifier.
  ///
  /// If [magnifierBuilder] is `null`, a default iOS magnifier is displayed.
  final DocumentMagnifierBuilder? magnifierBuilder;

  /// Whether the iOS floating toolbar should be displayed right now.
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
  /// If [toolbarBuilder] is `null`, a default iOS toolbar is displayed.
  final DocumentFloatingToolbarBuilder? toolbarBuilder;

  /// Creates a clipper that restricts where the toolbar and magnifier can
  /// appear in the overlay.
  ///
  /// If no clipper factory method is provided, then the overlay controls
  /// will be allowed to appear anywhere in the overlay in which they sit
  /// (probably the entire screen).
  final CustomClipper<Rect> Function(BuildContext overlayContext)? createOverlayControlsClipper;
}

/// Document gesture interactor that's designed for iOS touch input, e.g.,
/// drag to scroll, tap to place the caret, double tap to select a word,
/// triple tap to select a paragraph.
///
/// Depends upon an ancestor [SuperEditorIosControlsScope], which coordinates the
/// state of visual iOS controls, e.g., caret, handles, magnifier, toolbar.
///
/// [IosDocumentTouchInteractor] coordinates half of the iOS floating cursor behavior.
/// This widget handles the following:
///  * Listens for the user to start moving the floating cursor, notifies the ancestor
///    [SuperEditorIosControlsScope] that the floating cursor is active, and starts
///    managing auto-scrolling based on the floating cursor offset in the viewport.
///  * Listens for all user movements of the floating cursor, maps the floating
///    cursor offset to a document position, chooses an appropriate size for the
///    floating cursor based on the content beneath it, and then notifies the ancestor
///    [SuperEditorIosControlsScope] of the new floating cursor position and size.
///  * Listens for the user to stop using the floating cursor, notifies the ancestor
///    [SuperEditorIosControlsScope] that the floating cursor is inactive, and stops
///    managing auto-scrolling based on the floating cursor offset in the viewport.
///
/// This widget does NOT paint a floating cursor. That responsibility is left to
/// other widgets.
class IosDocumentTouchInteractor extends StatefulWidget {
  const IosDocumentTouchInteractor({
    Key? key,
    required this.focusNode,
    required this.editor,
    required this.document,
    required this.getDocumentLayout,
    required this.selection,
    this.openKeyboardWhenTappingExistingSelection = true,
    required this.openSoftwareKeyboard,
    required this.isImeConnected,
    required this.scrollController,
    required this.dragHandleAutoScroller,
    required this.fillViewport,
    this.contentTapHandlers,
    this.dragAutoScrollBoundary = const AxisOffset.symmetric(54),
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

  /// A [ValueListenable] that should notify this widget when the IME connects
  /// and disconnects.
  final ValueListenable<bool> isImeConnected;

  /// Optional list of handlers that respond to taps on content, e.g., opening
  /// a link when the user taps on text with a link attribution.
  ///
  /// If a handler returns [TapHandlingInstruction.halt], no subsequent handlers
  /// nor the default tap behavior will be executed.
  final List<ContentTapDelegate>? contentTapHandlers;

  final ScrollController scrollController;

  final ValueNotifier<DragHandleAutoScroller?> dragHandleAutoScroller;

  /// The closest that the user's selection drag gesture can get to the
  /// document boundary before auto-scrolling.
  ///
  /// The default value is `54.0` pixels for both the leading and trailing
  /// edges.
  final AxisOffset dragAutoScrollBoundary;

  /// Whether the document gesture detector should fill the entire viewport
  /// even if the actual content is smaller.
  final bool fillViewport;

  final bool showDebugPaint;

  final Widget child;

  @override
  State createState() => _IosDocumentTouchInteractorState();
}

class _IosDocumentTouchInteractorState extends State<IosDocumentTouchInteractor>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // The ScrollPosition attached to the _ancestorScrollable.
  ScrollPosition? _ancestorScrollPosition;

  SuperEditorIosControlsController? _controlsController;
  late FloatingCursorListener _floatingCursorListener;

  Offset? _globalStartDragOffset;
  Offset? _dragStartInDoc;
  Offset? _startDragPositionOffset;
  double? _dragStartScrollOffset;
  Offset? _globalDragOffset;

  /// The [Offset] of the magnifier's focal point in the [DocumentLayout] coordinate space.
  final _magnifierFocalPointInDocumentSpace = ValueNotifier<Offset?>(null);
  Offset? _dragEndInInteractor;
  DragMode? _dragMode;

  // TODO: HandleType is the wrong type here, we need collapsed/base/extent,
  //       not collapsed/upstream/downstream. Change the type once it's working.
  HandleType? _dragHandleType;

  Timer? _tapDownLongPressTimer;
  Offset? _globalTapDownOffset;
  bool get _isLongPressInProgress => _longPressStrategy != null;
  IosLongPressSelectionStrategy? _longPressStrategy;

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

    _floatingCursorListener = FloatingCursorListener(
      onStart: _onFloatingCursorStart,
      onStop: _onFloatingCursorStop,
    );

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final view = View.of(context);
    _lastSize = view.physicalSize;
    _lastInsets = view.viewInsets;

    if (_controlsController != null) {
      _controlsController!.floatingCursorController.removeListener(_floatingCursorListener);
      _controlsController!.floatingCursorController.cursorGeometryInViewport
          .removeListener(_onFloatingCursorGeometryChange);
    }
    _controlsController = SuperEditorIosControlsScope.rootOf(context);
    _controlsController!.floatingCursorController.addListener(_floatingCursorListener);
    _controlsController!.floatingCursorController.cursorGeometryInViewport.addListener(_onFloatingCursorGeometryChange);

    _ancestorScrollPosition = context.findAncestorScrollableWithVerticalScroll?.position;
  }

  @override
  void didUpdateWidget(IosDocumentTouchInteractor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.document != oldWidget.document) {
      oldWidget.document.removeListener(_onDocumentChange);
      widget.document.addListener(_onDocumentChange);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _controlsController!.floatingCursorController.removeListener(_floatingCursorListener);
    _controlsController!.floatingCursorController.cursorGeometryInViewport
        .removeListener(_onFloatingCursorGeometryChange);

    widget.document.removeListener(_onDocumentChange);

    widget.dragHandleAutoScroller.value?.dispose();

    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // DidChangeMetrics is sometimes called even when metrics doesn't change
    // (i.e. on iOS with keyboard visible)
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
    // appearance/disappearance. Ensure the extent is still visible. Use a
    // post-frame callback to give the rest of the UI a chance to reflow, first.
    onNextFrame((_) {
      _ensureSelectionExtentIsVisible();
    });
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

    widget.dragHandleAutoScroller.value?.ensureOffsetIsVisible(extentOffsetInViewport);
  }

  void _onDocumentChange(_) {
    _controlsController!.hideToolbar();

    onNextFrame((_) {
      // The user may have changed the type of node, e.g., paragraph to
      // blockquote, which impacts the caret size and position. Ensure
      // the extent is still visible.
      _ensureSelectionExtentIsVisible();
    });
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

  Offset _documentOffsetToViewportOffset(Offset documentOffset) {
    final globalOffset = _docLayout.getGlobalOffsetFromDocumentOffset(documentOffset);
    return viewportBox.globalToLocal(globalOffset);
  }

  /// Returns the render box for the interactor gesture detector.
  RenderBox get interactorBox => _interactor.currentContext!.findRenderObject() as RenderBox;

  /// Converts the given [interactorOffset] from the [DocumentInteractor]'s coordinate
  /// space to the [DocumentLayout]'s coordinate space.
  Offset _interactorOffsetToDocumentOffset(Offset interactorOffset) {
    final globalOffset = interactorBox.localToGlobal(interactorOffset);
    return _docLayout.getDocumentOffsetFromAncestorOffset(globalOffset);
  }

  /// Maps the given [interactorOffset] within the interactor's coordinate space
  /// to the same screen position in the viewport's coordinate space.
  ///
  /// When this interactor includes it's own `ScrollView`, the [interactorOffset]
  /// is the same as the viewport offset.
  ///
  /// When this interactor defers to an ancestor `Scrollable`, then the
  /// [interactorOffset] is transformed into the ancestor coordinate space.
  Offset _interactorOffsetToViewportOffset(Offset interactorOffset) {
    // Viewport might be our box, or an ancestor box if we're inside someone
    // else's Scrollable.
    return viewportBox.globalToLocal(
      interactorBox.localToGlobal(interactorOffset),
    );
  }

  void _onTapDown(TapDownDetails details) {
    _globalTapDownOffset = details.globalPosition;
    _tapDownLongPressTimer?.cancel();
    if (!disableLongPressSelectionForSuperlist) {
      _tapDownLongPressTimer = Timer(kLongPressTimeout, _onLongPressDown);
    }

    // Stop the caret from blinking, in case this tap down turns into a long-press drag,
    // or a caret drag.
    _controlsController!.doNotBlinkCaret();
  }

  // Runs when a tap down has lasted long enough to signify a long-press.
  void _onLongPressDown() {
    final interactorOffset = interactorBox.globalToLocal(_globalTapDownOffset!);
    final tapDownDocumentOffset = _interactorOffsetToDocumentOffset(interactorOffset);
    final tapDownDocumentPosition = _docLayout.getDocumentPositionNearestToOffset(tapDownDocumentOffset);
    if (tapDownDocumentPosition == null) {
      return;
    }

    if (_isOverBaseHandle(interactorOffset) ||
        _isOverExtentHandle(interactorOffset) ||
        _isOverCollapsedHandle(interactorOffset)) {
      // Don't do anything for long presses over the handles, because we want the user
      // to be able to drag them without worrying about how long they've pressed.
      return;
    }

    _globalDragOffset = _globalTapDownOffset;
    _longPressStrategy = IosLongPressSelectionStrategy(
      document: widget.document,
      documentLayout: _docLayout,
      select: _select,
    );
    final didLongPressSelectionStart = _longPressStrategy!.onLongPressStart(
      tapDownDocumentOffset: tapDownDocumentOffset,
    );
    if (!didLongPressSelectionStart) {
      _longPressStrategy = null;
      return;
    }

    _placeFocalPointNearTouchOffset();
    _controlsController!
      ..hideToolbar()
      ..showMagnifier();

    widget.focusNode.requestFocus();
  }

  void _onTapCancel() {
    _tapDownLongPressTimer?.cancel();
    _tapDownLongPressTimer = null;
  }

  void _onTapUp(TapUpDetails details) {
    // Stop waiting for a long-press to start.
    _globalTapDownOffset = null;
    _tapDownLongPressTimer?.cancel();
    _controlsController!
      ..hideMagnifier()
      ..blinkCaret();

    editorGesturesLog.info("Tap down on document");
    final docOffset = _interactorOffsetToDocumentOffset(details.localPosition);
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

    final selection = widget.selection.value;
    if (selection != null &&
        !selection.isCollapsed &&
        (_isOverBaseHandle(details.localPosition) || _isOverExtentHandle(details.localPosition))) {
      _controlsController!.toggleToolbar();
      return;
    }

    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    editorGesturesLog.fine(" - tapped document position: $docPosition");
    if (docPosition != null &&
        selection != null &&
        !selection.isCollapsed &&
        widget.document.doesSelectionContainPosition(selection, docPosition)) {
      // The user tapped on an expanded selection. Toggle the toolbar and show
      // the software keyboard.
      _controlsController!.toggleToolbar();

      if (widget.openKeyboardWhenTappingExistingSelection) {
        widget.openSoftwareKeyboard();
      }

      return;
    }

    if (docPosition != null) {
      late final DocumentPosition adjustedSelectionPosition;
      if (docPosition.nodePosition is TextNodePosition) {
        // The user tapped a text position. Adjust the position to the start
        // or end of the word, as per iOS behavior.
        adjustedSelectionPosition = _moveTapPositionToWordBoundary(docPosition);
      } else {
        // Selection isn't text. Don't adjust the position.
        adjustedSelectionPosition = docPosition;
      }

      final didTapOnExistingSelection = selection != null &&
          selection.isCollapsed &&
          selection.extent.nodeId == docPosition.nodeId &&
          selection.extent.nodePosition.isEquivalentTo(docPosition.nodePosition);

      if (didTapOnExistingSelection && widget.isImeConnected.value) {
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

      if (didTapOnExistingSelection) {
        if (widget.openKeyboardWhenTappingExistingSelection) {
          // The user tapped on the existing selection. Show the software keyboard.
          //
          // If the user didn't tap on an existing selection, the software keyboard will
          // already be visible.
          widget.openSoftwareKeyboard();
        }
      } else {
        final tappedComponent = _docLayout.getComponentByNodeId(adjustedSelectionPosition.nodeId)!;
        if (!tappedComponent.isVisualSelectionSupported()) {
          // The user tapped a non-selectable component.
          // Place the document selection at the nearest selectable node
          // to the tapped component.
          moveSelectionToNearestSelectableNode(
            editor: widget.editor,
            document: widget.document,
            documentLayoutResolver: widget.getDocumentLayout,
            currentSelection: widget.selection.value,
            startingNode: widget.document.getNodeById(adjustedSelectionPosition.nodeId)!,
          );
          return;
        } else {
          // Place the document selection at the location where the
          // user tapped.
          _selectPosition(adjustedSelectionPosition);
        }
      }
    } else {
      widget.editor.execute([
        const ClearSelectionRequest(),
      ]);
      _controlsController!.hideToolbar();
    }

    widget.focusNode.requestFocus();
  }

  DocumentPosition _moveTapPositionToWordBoundary(DocumentPosition docPosition) {
    if (!SuperEditorIosControlsScope.rootOf(context).useIosSelectionHeuristics) {
      // iOS-style adjustments aren't desired. Don't adjust th given position.
      return docPosition;
    }

    final text = (widget.document.getNodeById(docPosition.nodeId) as TextNode).text;
    final tapOffset = (docPosition.nodePosition as TextNodePosition).offset;
    if (tapOffset == text.length) {
      return docPosition;
    }
    final adjustedSelectionOffset = IosHeuristics.adjustTapOffset(text.toPlainText(), tapOffset);

    return DocumentPosition(
      documentPath: docPosition.documentPath,
      nodePosition: TextNodePosition(offset: adjustedSelectionOffset),
    );
  }

  void _onDoubleTapUp(TapUpDetails details) {
    editorGesturesLog.info("Double tap down on document");
    final docOffset = _interactorOffsetToDocumentOffset(details.localPosition);
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

    final selection = widget.selection.value;
    if (selection != null &&
        !selection.isCollapsed &&
        (_isOverBaseHandle(details.localPosition) || _isOverExtentHandle(details.localPosition))) {
      return;
    }

    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    editorGesturesLog.fine(" - tapped document position: $docPosition");
    if (docPosition != null) {
      final tappedComponent = _docLayout.getComponentByNodeId(docPosition.nodeId)!;
      if (!tappedComponent.isVisualSelectionSupported()) {
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
      widget.editor.execute([
        const ClearSelectionRequest(),
      ]);
    }

    final newSelection = widget.selection.value;
    if (newSelection == null || newSelection.isCollapsed) {
      _controlsController!.hideToolbar();
    } else {
      _controlsController!.showToolbar();
    }

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

  void _onTripleTapUp(TapUpDetails details) {
    editorGesturesLog.info("Triple down down on document");

    final docOffset = _interactorOffsetToDocumentOffset(details.localPosition);
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
      widget.editor.execute([
        const ClearSelectionRequest(),
      ]);
    }

    final selection = widget.selection.value;
    if (selection == null || selection.isCollapsed) {
      _controlsController!.hideToolbar();
    } else {
      _controlsController!.showToolbar();
    }

    widget.focusNode.requestFocus();
  }

  void _onPanDown(DragDownDetails details) {
    // No-op: this method is only here to beat out any ancestor
    // Scrollable that's also trying to drag.
  }

  void _onPanStart(DragStartDetails details) {
    // Stop waiting for a long-press to start, if a long press isn't already in-progress.
    _globalTapDownOffset = null;
    _tapDownLongPressTimer?.cancel();

    if (widget.contentTapHandlers != null) {
      final docOffset = _interactorOffsetToDocumentOffset(details.localPosition);
      for (final handler in widget.contentTapHandlers!) {
        final result = handler.onPanStart(
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

    // TODO: to help the user drag handles instead of scrolling, try checking touch
    //       placement during onTapDown, and then pick that up here. I think the little
    //       bit of slop might be the problem.
    final selection = widget.selection.value;
    if (selection == null) {
      return;
    }

    if (_isLongPressInProgress) {
      _dragMode = DragMode.longPress;
      _dragHandleType = null;
      _longPressStrategy!.onLongPressDragStart();
    } else if (selection.isCollapsed && _isOverCollapsedHandle(details.localPosition)) {
      _dragMode = DragMode.collapsed;
      _dragHandleType = HandleType.collapsed;
    } else if (_isOverBaseHandle(details.localPosition)) {
      _dragMode = DragMode.base;
      _dragHandleType = HandleType.upstream;
    } else if (_isOverExtentHandle(details.localPosition)) {
      _dragMode = DragMode.extent;
      _dragHandleType = HandleType.downstream;
    } else {
      return;
    }

    _controlsController!
      ..doNotBlinkCaret()
      ..hideToolbar()
      ..showMagnifier();

    _updateDragStartLocation(details.globalPosition);

    widget.dragHandleAutoScroller.value?.startAutoScrollHandleMonitoring();

    scrollPosition.addListener(_onAutoScrollChange);
  }

  bool _isOverCollapsedHandle(Offset interactorOffset) {
    final collapsedPosition = widget.selection.value?.extent;
    if (collapsedPosition == null) {
      return false;
    }

    final extentRect = _docLayout.getRectForPosition(collapsedPosition)!;
    final caretHitArea = Rect.fromLTRB(
      extentRect.left - 24,
      extentRect.top,
      extentRect.right + 24,
      extentRect.bottom,
    );

    final docOffset = _interactorOffsetToDocumentOffset(interactorOffset);
    return caretHitArea.contains(docOffset);
  }

  bool _isOverBaseHandle(Offset interactorOffset) {
    final basePosition = widget.selection.value?.base;
    if (basePosition == null) {
      return false;
    }

    final baseRect = _docLayout.getRectForPosition(basePosition)!;
    // The following caretRect offset and size were chosen empirically, based
    // on trying to drag the handle from various locations near the handle.
    final caretRect = Rect.fromLTWH(baseRect.left - 24, baseRect.top - 24, 48, baseRect.height + 48);

    final docOffset = _interactorOffsetToDocumentOffset(interactorOffset);
    return caretRect.contains(docOffset);
  }

  bool _isOverExtentHandle(Offset interactorOffset) {
    final extentPosition = widget.selection.value?.extent;
    if (extentPosition == null) {
      return false;
    }

    final extentRect = _docLayout.getRectForPosition(extentPosition)!;
    // The following caretRect offset and size were chosen empirically, based
    // on trying to drag the handle from various locations near the handle.
    final caretRect = Rect.fromLTWH(extentRect.left - 24, extentRect.top, 48, extentRect.height + 32);

    final docOffset = _interactorOffsetToDocumentOffset(interactorOffset);
    return caretRect.contains(docOffset);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (widget.contentTapHandlers != null) {
      final docOffset = _interactorOffsetToDocumentOffset(details.localPosition);
      for (final handler in widget.contentTapHandlers!) {
        final result = handler.onPanUpdate(
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

    _globalDragOffset = details.globalPosition;

    _dragEndInInteractor = interactorBox.globalToLocal(details.globalPosition);
    final dragEndInViewport = _interactorOffsetToViewportOffset(_dragEndInInteractor!);

    if (_isLongPressInProgress) {
      final fingerDragDelta = _globalDragOffset! - _globalStartDragOffset!;
      final scrollDelta = _dragStartScrollOffset! - scrollPosition.pixels;
      final fingerDocumentOffset = _docLayout.getDocumentOffsetFromAncestorOffset(details.globalPosition);
      final fingerDocumentPosition = _docLayout.getDocumentPositionNearestToOffset(
        _startDragPositionOffset! + fingerDragDelta - Offset(0, scrollDelta),
      );
      _longPressStrategy!.onLongPressDragUpdate(fingerDocumentOffset, fingerDocumentPosition);
    } else {
      _updateSelectionForNewDragHandleLocation();
    }

    // Auto-scroll, if needed, for either handle dragging or long press dragging.
    widget.dragHandleAutoScroller.value?.updateAutoScrollHandleMonitoring(
      dragEndInViewport: dragEndInViewport,
    );

    _placeFocalPointNearTouchOffset();
  }

  void _updateSelectionForNewDragHandleLocation() {
    final docDragDelta = _globalDragOffset! - _globalStartDragOffset!;
    final dragScrollDelta = _dragStartScrollOffset! - scrollPosition.pixels;
    final docDragPosition = _docLayout
        .getDocumentPositionNearestToOffset(_startDragPositionOffset! + docDragDelta - Offset(0, dragScrollDelta));
    if (docDragPosition == null) {
      return;
    }

    if (_dragHandleType == HandleType.collapsed) {
      widget.editor.execute([
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: docDragPosition,
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
        const ClearComposingRegionRequest(),
      ]);
    } else if (_dragHandleType == HandleType.upstream) {
      _controlsController!.handleBeingDragged.value = HandleType.upstream;
      widget.editor.execute([
        ChangeSelectionRequest(
          widget.selection.value!.copyWith(
            base: docDragPosition,
          ),
          SelectionChangeType.expandSelection,
          SelectionReason.userInteraction,
        ),
        const ClearComposingRegionRequest(),
      ]);
    } else if (_dragHandleType == HandleType.downstream) {
      _controlsController!.handleBeingDragged.value = HandleType.downstream;
      widget.editor.execute([
        ChangeSelectionRequest(
          widget.selection.value!.copyWith(
            extent: docDragPosition,
          ),
          SelectionChangeType.expandSelection,
          SelectionReason.userInteraction,
        ),
        const ClearComposingRegionRequest(),
      ]);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (widget.contentTapHandlers != null) {
      final docOffset = _interactorOffsetToDocumentOffset(details.localPosition);
      for (final handler in widget.contentTapHandlers!) {
        final result = handler.onPanEnd(
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

    _controlsController!
      ..hideMagnifier()
      ..blinkCaret()
      ..handleBeingDragged.value = null;

    if (_dragMode != null) {
      // The user was dragging a selection change in some way, either with handles
      // or with a long-press. Finish that interaction.
      _onDragSelectionEnd();
    }
  }

  void _onPanCancel() {
    if (widget.contentTapHandlers != null) {
      for (final handler in widget.contentTapHandlers!) {
        final result = handler.onPanCancel();
        if (result == TapHandlingInstruction.halt) {
          // The custom tap handler doesn't want us to react at all
          // to the tap.
          return;
        }
      }
    }

    if (_dragMode != null) {
      _onDragSelectionEnd();
    }
    _controlsController!.handleBeingDragged.value = null;
  }

  void _onDragSelectionEnd() {
    if (_dragMode == DragMode.longPress) {
      _onLongPressEnd();
    } else {
      _onHandleDragEnd();
    }

    widget.dragHandleAutoScroller.value?.stopAutoScrollHandleMonitoring();
    scrollPosition.removeListener(_onAutoScrollChange);
  }

  void _onLongPressEnd() {
    _longPressStrategy!.onLongPressEnd();
    _longPressStrategy = null;
    _dragMode = null;

    _updateOverlayControlsAfterFinishingDragSelection();
  }

  void _onHandleDragEnd() {
    _dragMode = null;

    _updateOverlayControlsAfterFinishingDragSelection();
  }

  void _updateOverlayControlsAfterFinishingDragSelection() {
    _controlsController!.hideMagnifier();
    if (!widget.selection.value!.isCollapsed) {
      _controlsController!.showToolbar();
    }
  }

  void _onAutoScrollChange() {
    _updateDocumentSelectionOnAutoScrollFrame();
    _updateMagnifierFocalPointOnAutoScrollFrame();
  }

  void _updateMagnifierFocalPointOnAutoScrollFrame() {
    if (_magnifierFocalPointInDocumentSpace.value != null) {
      _placeFocalPointNearTouchOffset();
    }
  }

  void _updateDocumentSelectionOnAutoScrollFrame() {
    if (_dragStartInDoc == null) {
      return;
    }

    if (_dragHandleType == null) {
      // The user is probably doing a long-press drag. Nothing for us to do here.
      return;
    }

    final dragEndInDoc = _interactorOffsetToDocumentOffset(_dragEndInInteractor!);
    final dragPosition = _docLayout.getDocumentPositionNearestToOffset(dragEndInDoc);
    editorGesturesLog.info("Selecting new position during drag: $dragPosition");

    if (dragPosition == null) {
      return;
    }

    late DocumentPosition basePosition;
    late DocumentPosition extentPosition;
    late SelectionChangeType changeType;
    switch (_dragHandleType!) {
      case HandleType.collapsed:
        basePosition = dragPosition;
        extentPosition = dragPosition;
        changeType = SelectionChangeType.placeCaret;
        break;
      case HandleType.upstream:
        basePosition = dragPosition;
        extentPosition = widget.selection.value!.extent;
        changeType = SelectionChangeType.expandSelection;
        break;
      case HandleType.downstream:
        basePosition = widget.selection.value!.base;
        extentPosition = dragPosition;
        changeType = SelectionChangeType.expandSelection;
        break;
    }

    widget.editor.execute([
      ChangeSelectionRequest(
        DocumentSelection(
          base: basePosition,
          extent: extentPosition,
        ),
        changeType,
        SelectionReason.userInteraction,
      ),
      const ClearComposingRegionRequest(),
    ]);

    editorGesturesLog.fine("Selected region: ${widget.selection.value}");
  }

  bool _selectWordAt({
    required DocumentPosition docPosition,
    required DocumentLayout docLayout,
  }) {
    final newSelection = getWordSelection(docPosition: docPosition, docLayout: docLayout);
    if (newSelection != null) {
      _select(newSelection);
      return true;
    } else {
      return false;
    }
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

  void _onFloatingCursorStart() {
    if (widget.selection.value == null) {
      // The floating cursor doesn't mean anything when nothing is selected.
      return;
    }

    widget.dragHandleAutoScroller.value?.startAutoScrollHandleMonitoring();
  }

  void _onFloatingCursorGeometryChange() {
    final cursorGeometry = _controlsController!.floatingCursorController.cursorGeometryInViewport.value;
    if (cursorGeometry == null) {
      return;
    }

    widget.dragHandleAutoScroller.value?.updateAutoScrollHandleMonitoring(
      dragEndInViewport: cursorGeometry.center,
    );
  }

  void _onFloatingCursorStop() {
    widget.dragHandleAutoScroller.value?.stopAutoScrollHandleMonitoring();
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

  /// Updates the magnifier focal point in relation to the current drag position.
  void _placeFocalPointNearTouchOffset() {
    late DocumentPosition? docPositionToMagnify;

    if (_globalTapDownOffset != null) {
      // A drag isn't happening. Magnify the position that the user tapped.
      final interactorOffset = interactorBox.globalToLocal(_globalTapDownOffset!);
      final tapDownDocumentOffset = _interactorOffsetToDocumentOffset(interactorOffset);
      docPositionToMagnify = _docLayout.getDocumentPositionNearestToOffset(tapDownDocumentOffset);
    } else {
      final docDragDelta = _globalDragOffset! - _globalStartDragOffset!;
      final dragScrollDelta = _dragStartScrollOffset! - scrollPosition.pixels;
      docPositionToMagnify = _docLayout
          .getDocumentPositionNearestToOffset(_startDragPositionOffset! + docDragDelta - Offset(0, dragScrollDelta));
    }

    final centerOfContentAtOffset = _interactorOffsetToDocumentOffset(
      _docLayout.getRectForPosition(docPositionToMagnify!)!.center,
    );

    _magnifierFocalPointInDocumentSpace.value = centerOfContentAtOffset;
  }

  void _updateDragStartLocation(Offset globalOffset) {
    _globalStartDragOffset = globalOffset;
    final handleOffsetInInteractor = interactorBox.globalToLocal(globalOffset);
    _dragStartInDoc = _interactorOffsetToDocumentOffset(handleOffsetInInteractor);

    final selection = widget.selection.value;
    if (_dragHandleType != null && selection != null) {
      _startDragPositionOffset = _docLayout
          .getRectForPosition(
            _dragHandleType == HandleType.upstream ? selection.base : selection.extent,
          )!
          .center;
    } else {
      // User is long-press dragging, which is why there's no drag handle type.
      // In this case, the start drag offset is wherever the user touched.
      _startDragPositionOffset = _dragStartInDoc!;
    }

    // We need to record the scroll offset at the beginning of
    // a drag for the case that this interactor is embedded
    // within an ancestor Scrollable. We need to use this value
    // to calculate a scroll delta on every scroll frame to
    // account for the fact that this interactor is moving within
    // the ancestor scrollable, despite the fact that the user's
    // finger/mouse position hasn't changed.
    _dragStartScrollOffset = scrollPosition.pixels;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.scrollController.hasClients) {
      if (widget.scrollController.positions.length > 1) {
        // During Hot Reload, if the gesture mode was changed,
        // the widget might be built while the old gesture interactor
        // scroller is still attached to the _scrollController.
        //
        // Defer adding the listener to the next frame.
        scheduleBuildAfterBuild();
      }
    }

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
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            TapSequenceGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapSequenceGestureRecognizer>(
              () => TapSequenceGestureRecognizer(),
              (TapSequenceGestureRecognizer recognizer) {
                recognizer
                  ..onTapDown = _onTapDown
                  ..onTapCancel = _onTapCancel
                  ..onTapUp = _onTapUp
                  ..onDoubleTapUp = _onDoubleTapUp
                  ..onTripleTapUp = _onTripleTapUp
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
                    final panDown = interactorBox.globalToLocal(_globalTapDownOffset!);
                    final isOverHandle =
                        _isOverBaseHandle(panDown) || _isOverExtentHandle(panDown) || _isOverCollapsedHandle(panDown);
                    final res = isOverHandle || _isLongPressInProgress;
                    return res;
                  }
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onDown = _onPanDown
                  ..onStart = _onPanStart
                  ..onUpdate = _onPanUpdate
                  ..onEnd = _onPanEnd
                  ..onCancel = _onPanCancel
                  ..gestureSettings = gestureSettings;
              },
            ),
          },
          child: Stack(
            children: [
              _buildMagnifierFocalPoint(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMagnifierFocalPoint() {
    return ValueListenableBuilder(
      valueListenable: _magnifierFocalPointInDocumentSpace,
      builder: (context, magnifierFocalPoint, child) {
        if (magnifierFocalPoint == null) {
          return const SizedBox();
        }

        // When the user is dragging a handle in this overlay, we
        // are responsible for positioning the focal point for the
        // magnifier to follow. We do that here.
        return Positioned(
          left: magnifierFocalPoint.dx,
          top: magnifierFocalPoint.dy,
          child: Leader(
            link: _controlsController!.magnifierFocalPoint,
            child: const SizedBox(width: 1, height: 1),
          ),
        );
      },
    );
  }
}

enum DragMode {
  // Dragging the collapsed handle
  collapsed,
  // Dragging the base handle
  base,
  // Dragging the extent handle
  extent,
  // Dragging after a long-press, which selects by the word
  // around the selected word.
  longPress,
}

/// Adds and removes an iOS-style editor toolbar, as dictated by an ancestor
/// [SuperEditorIosControlsScope].
class SuperEditorIosToolbarOverlayManager extends StatefulWidget {
  const SuperEditorIosToolbarOverlayManager({
    super.key,
    this.tapRegionGroupId,
    this.defaultToolbarBuilder,
    required this.child,
  });

  /// {@macro super_editor_tap_region_group_id}
  final String? tapRegionGroupId;

  final DocumentFloatingToolbarBuilder? defaultToolbarBuilder;

  final Widget child;

  @override
  State<SuperEditorIosToolbarOverlayManager> createState() => SuperEditorIosToolbarOverlayManagerState();
}

@visibleForTesting
class SuperEditorIosToolbarOverlayManagerState extends State<SuperEditorIosToolbarOverlayManager> {
  final OverlayPortalController _overlayPortalController = OverlayPortalController();
  SuperEditorIosControlsController? _controlsController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _controlsController = SuperEditorIosControlsScope.rootOf(context);
    _overlayPortalController.show();
  }

  @visibleForTesting
  bool get wantsToDisplayToolbar => _controlsController!.shouldShowToolbar.value;

  @override
  Widget build(BuildContext context) {
    return SliverHybridStack(
      children: [
        widget.child,
        OverlayPortal(
          controller: _overlayPortalController,
          overlayChildBuilder: _buildToolbar,
          child: const SizedBox(),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return TapRegion(
      groupId: widget.tapRegionGroupId,
      child: IosFloatingToolbarOverlay(
        shouldShowToolbar: _controlsController!.shouldShowToolbar,
        toolbarFocalPoint: _controlsController!.toolbarFocalPoint,
        floatingToolbarBuilder:
            _controlsController!.toolbarBuilder ?? widget.defaultToolbarBuilder ?? (_, __, ___) => const SizedBox(),
        createOverlayControlsClipper: _controlsController!.createOverlayControlsClipper,
        showDebugPaint: false,
      ),
    );
  }
}

/// Adds and removes an iOS-style editor magnifier, as dictated by an ancestor
/// [SuperEditorIosControlsScope].
class SuperEditorIosMagnifierOverlayManager extends StatefulWidget {
  const SuperEditorIosMagnifierOverlayManager({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<SuperEditorIosMagnifierOverlayManager> createState() => SuperEditorIosMagnifierOverlayManagerState();
}

@visibleForTesting
class SuperEditorIosMagnifierOverlayManagerState extends State<SuperEditorIosMagnifierOverlayManager>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _overlayPortalController = OverlayPortalController();
  SuperEditorIosControlsController? _controlsController;

  @visibleForTesting
  bool get wantsToDisplayMagnifier => _controlsController!.shouldShowMagnifier.value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controlsController = SuperEditorIosControlsScope.rootOf(context);
    _overlayPortalController.show();
  }

  @override
  Widget build(BuildContext context) {
    return SliverHybridStack(
      children: [
        widget.child,
        OverlayPortal(
          controller: _overlayPortalController,
          overlayChildBuilder: _buildMagnifier,
          child: const SizedBox(),
        ),
      ],
    );
  }

  Widget _buildMagnifier(BuildContext context) {
    // Display a magnifier that tracks a focal point.
    //
    // When the user is dragging an overlay handle, SuperEditor
    // position a Leader with a LeaderLink. This magnifier follows that Leader
    // via the LeaderLink.
    return IgnorePointer(
      child: ValueListenableBuilder(
        valueListenable: _controlsController!.shouldShowMagnifier,
        builder: (context, shouldShowMagnifier, child) {
          return _controlsController!.magnifierBuilder != null //
              ? _controlsController!.magnifierBuilder!(
                  context,
                  DocumentKeys.magnifier,
                  _controlsController!.magnifierFocalPoint,
                  shouldShowMagnifier,
                )
              : _buildDefaultMagnifier(
                  context,
                  DocumentKeys.magnifier,
                  _controlsController!.magnifierFocalPoint,
                  shouldShowMagnifier,
                );
        },
      ),
    );
  }

  Widget _buildDefaultMagnifier(
      BuildContext context, Key magnifierKey, LeaderLink magnifierFocalPoint, bool isVisible) {
    if (CurrentPlatform.isWeb) {
      // Defer to the browser to display overlay controls on mobile.
      return const SizedBox();
    }

    return IOSFollowingMagnifier.roundedRectangle(
      magnifierKey: magnifierKey,
      leaderLink: magnifierFocalPoint,
      show: isVisible,
      // The magnifier is centered with the focal point. Translate it so that it sits
      // above the focal point and leave a few pixels between the bottom of the magnifier
      // and the focal point. This value was chosen empirically.
      offsetFromFocalPoint: Offset(0, (-defaultIosMagnifierSize.height / 2) - 20),
      handleColor: _controlsController!.handleColor,
    );
  }
}

/// Displays an iOS floating cursor for a document editor experience.
///
/// An [EditorFloatingCursor] also tracks the floating cursor focal point, sets the
/// floating cursor geometry on an ancestor [SuperEditorIosControlsController], as well as
/// toggling the magnifier and toolbar, and updates the [Editor]s [DocumentSelection]
/// as the user moves the floating cursor, or scrolls the document.
///
/// [EditorFloatingCursor] should wrap the editor's viewport (not the full document layout),
/// because the floating cursor moves around the visible area of the UI, it's position
/// is not tied directly to the document layout.
///
/// [EditorFloatingCursor] must be a descendant of an ancestor [SuperEditorIosControlsScope].
class EditorFloatingCursor extends StatefulWidget {
  const EditorFloatingCursor({
    super.key,
    required this.editor,
    required this.document,
    required this.getDocumentLayout,
    required this.selection,
    required this.scrollChangeSignal,
    required this.child,
  });

  final Editor editor;
  final Document document;
  final DocumentLayoutResolver getDocumentLayout;
  final ValueListenable<DocumentSelection?> selection;
  final SignalNotifier scrollChangeSignal;
  final Widget child;

  @override
  State<EditorFloatingCursor> createState() => _EditorFloatingCursorState();
}

class _EditorFloatingCursorState extends State<EditorFloatingCursor> {
  SuperEditorIosControlsController? _controlsContext;
  late FloatingCursorListener _floatingCursorListener;

  Offset? _initialFloatingCursorOffsetInViewport;
  Offset? _floatingCursorFocalPointInViewport;
  Offset? _floatingCursorFocalPointInDocument;
  double _floatingCursorHeight = FloatingCursorPolicies.defaultFloatingCursorHeight;

  @override
  void initState() {
    super.initState();

    _floatingCursorListener = FloatingCursorListener(
      onStart: _onFloatingCursorStart,
      onMove: _onFloatingCursorMove,
      onStop: _onFloatingCursorStop,
    );

    widget.scrollChangeSignal.addListener(_onScrollChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_controlsContext != null) {
      _controlsContext!.floatingCursorController.removeListener(_floatingCursorListener);
    }
    _controlsContext = SuperEditorIosControlsScope.rootOf(context);
    _controlsContext!.floatingCursorController.addListener(_floatingCursorListener);
  }

  @override
  void didUpdateWidget(EditorFloatingCursor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.scrollChangeSignal != oldWidget.scrollChangeSignal) {
      oldWidget.scrollChangeSignal.removeListener(_onScrollChange);
      widget.scrollChangeSignal.addListener(_onScrollChange);
    }
  }

  @override
  void dispose() {
    widget.scrollChangeSignal.removeListener(_onScrollChange);

    super.dispose();
  }

  /// Returns the layout for the current document, which answers questions
  /// about the locations and sizes of visual components within the layout.
  DocumentLayout get _docLayout => widget.getDocumentLayout();

  /// Returns the `RenderBox` for the scrolling viewport.
  ///
  /// This widget expects to wrap the viewport, so this widget's box is the same
  /// place and size as the actual viewport.
  RenderBox get viewportBox => context.findViewportBox();

  Offset _documentOffsetToViewportOffset(Offset documentOffset) {
    final globalOffset = _docLayout.getGlobalOffsetFromDocumentOffset(documentOffset);
    return viewportBox.globalToLocal(globalOffset);
  }

  Offset _viewportOffsetToDocumentOffset(Offset viewportOffset) {
    final globalOffset = viewportBox.localToGlobal(viewportOffset);
    return _docLayout.getDocumentOffsetFromAncestorOffset(globalOffset);
  }

  void _onFloatingCursorStart() {
    editorIosFloatingCursorLog.fine("Floating cursor started.");
    if (widget.selection.value == null) {
      // The floating cursor doesn't mean anything when nothing is selected.
      return;
    }

    final initialSelectionExtent = widget.selection.value!.extent;
    final nearestPositionRect = _docLayout.getRectForPosition(initialSelectionExtent)!;
    final verticalCenterOfCaret = nearestPositionRect.center;
    final initialFloatingCursorOffsetInDocument = verticalCenterOfCaret + const Offset(-1, 0);
    _initialFloatingCursorOffsetInViewport = _documentOffsetToViewportOffset(initialFloatingCursorOffsetInDocument);
    _floatingCursorFocalPointInViewport = _initialFloatingCursorOffsetInViewport!;
    _floatingCursorFocalPointInDocument = _viewportOffsetToDocumentOffset(_floatingCursorFocalPointInViewport!);

    _controlsContext!.hideToolbar();
    _controlsContext!.hideMagnifier();

    _updateFloatingCursorGeometryForCurrentFloatingCursorFocalPoint();
  }

  void _onFloatingCursorMove(Offset? offset) {
    editorIosFloatingCursorLog.finer("Floating cursor moved: $offset");
    if (offset == null) {
      return;
    }

    if (widget.selection.value == null) {
      // The floating cursor doesn't mean anything when nothing is selected.
      return;
    }
    if (!widget.selection.value!.isCollapsed) {
      // This shouldn't happen. An expanded selection should be collapsed for
      // we get to movement methods.
      editorIosFloatingCursorLog
          .shout("Floating cursor move reported with an expanded selection. The selection should be collapsed!");
    }

    // Update our floating cursor focal point trackers.
    final cursorViewportFocalPointUnbounded = _initialFloatingCursorOffsetInViewport! + offset;
    editorIosFloatingCursorLog.finer(" - unbounded cursor focal point: $cursorViewportFocalPointUnbounded");

    final viewportHeight = viewportBox.size.height;
    _floatingCursorFocalPointInViewport =
        Offset(cursorViewportFocalPointUnbounded.dx, cursorViewportFocalPointUnbounded.dy.clamp(0, viewportHeight));
    editorIosFloatingCursorLog.finer(" - bounded cursor focal point: $_floatingCursorFocalPointInViewport");

    _floatingCursorFocalPointInDocument = _viewportOffsetToDocumentOffset(_floatingCursorFocalPointInViewport!);
    editorIosFloatingCursorLog.finer(" - floating cursor offset in document: $_floatingCursorFocalPointInDocument");

    // Calculate an updated floating cursor rectangle and document selection.
    _updateFloatingCursorGeometryForCurrentFloatingCursorFocalPoint();
    _selectPositionUnderFloatingCursor();
  }

  void _onScrollChange() {
    if (!_controlsContext!.floatingCursorController.isActive.value) {
      return;
    }

    _updateFloatingCursorGeometryForCurrentFloatingCursorFocalPoint();
    _selectPositionUnderFloatingCursor();
  }

  /// Updates the offset and height of the floating cursor, based on the current
  /// floating cursor focal point.
  ///
  /// If anything impacted the focal point, such as user movement, or scroll changes,
  /// those changes must be made to the focal point before calling this method. This
  /// method doesn't update or alter the focal point.
  void _updateFloatingCursorGeometryForCurrentFloatingCursorFocalPoint() {
    final focalPointInDocument = _viewportOffsetToDocumentOffset(_floatingCursorFocalPointInViewport!);
    final nearestDocumentPosition = _docLayout.getDocumentPositionNearestToOffset(focalPointInDocument)!;
    editorIosFloatingCursorLog.finer(" - nearest position to floating cursor: $nearestDocumentPosition");

    if (nearestDocumentPosition.nodePosition is TextNodePosition) {
      final nearestPositionRect = _docLayout.getRectForPosition(nearestDocumentPosition)!;
      _floatingCursorHeight = nearestPositionRect.height;

      final distance = _floatingCursorFocalPointInDocument! - nearestPositionRect.topLeft + const Offset(1.0, 0.0);
      _controlsContext!.floatingCursorController.isNearText.value =
          distance.dx.abs() <= FloatingCursorPolicies.maximumDistanceToBeNearText;
    } else {
      final nearestComponent = _docLayout.getComponentByNodeId(nearestDocumentPosition.nodeId)!;
      _floatingCursorHeight = (nearestComponent.context.findRenderObject() as RenderBox).size.height;
      _controlsContext!.floatingCursorController.isNearText.value = false;
    }

    _controlsContext!.floatingCursorController.cursorGeometryInViewport.value = Rect.fromLTWH(
      _floatingCursorFocalPointInViewport!.dx,
      _floatingCursorFocalPointInViewport!.dy - (_floatingCursorHeight / 2),
      FloatingCursorPolicies.defaultFloatingCursorWidth,
      _floatingCursorHeight,
    );

    _controlsContext!.floatingCursorController.cursorGeometryInDocument.value = Rect.fromLTWH(
      _floatingCursorFocalPointInDocument!.dx,
      _floatingCursorFocalPointInDocument!.dy - (_floatingCursorHeight / 2),
      FloatingCursorPolicies.defaultFloatingCursorWidth,
      _floatingCursorHeight,
    );

    editorIosFloatingCursorLog.finer(
        "Set floating cursor geometry to: ${_controlsContext!.floatingCursorController.cursorGeometryInViewport.value}");
  }

  /// Inspects the viewport focal point offset of the floating cursor, finds the nearest position
  /// in the document, and moves the selection to that position.
  void _selectPositionUnderFloatingCursor() {
    editorIosFloatingCursorLog.finer("Updating document selection based on floating cursor focal point.");
    final floatingCursorRectInViewport = _controlsContext!.floatingCursorController.cursorGeometryInViewport.value;
    if (floatingCursorRectInViewport == null) {
      editorIosFloatingCursorLog.finer(" - the floating cursor rect is null. Not selecting anything.");
      return;
    }

    final nearestDocumentPosition = _docLayout
        .getDocumentPositionNearestToOffset(_viewportOffsetToDocumentOffset(floatingCursorRectInViewport.center))!;

    editorIosFloatingCursorLog.finer(" - selecting nearest position: $nearestDocumentPosition");
    _selectPosition(nearestDocumentPosition);
  }

  void _selectPosition(DocumentPosition position) {
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

  void _onFloatingCursorStop() {
    editorIosFloatingCursorLog.fine("Floating cursor stopped.");
    _controlsContext!.floatingCursorController.isNearText.value = false;
    _controlsContext!.floatingCursorController.cursorGeometryInViewport.value = null;
    _controlsContext!.floatingCursorController.cursorGeometryInDocument.value = null;

    _floatingCursorFocalPointInDocument = null;
    _floatingCursorFocalPointInViewport = null;
    _floatingCursorHeight = FloatingCursorPolicies.defaultFloatingCursorHeight;
  }

  @override
  Widget build(BuildContext context) {
    return SliverHybridStack(
      children: [
        widget.child,
        Stack(
          clipBehavior: Clip.none,
          children: [
            _buildFloatingCursor(),
          ],
        )
      ],
    );
  }

  Widget _buildFloatingCursor() {
    return ValueListenableBuilder<Rect?>(
      valueListenable: _controlsContext!.floatingCursorController.cursorGeometryInDocument,
      builder: (context, floatingCursorRect, child) {
        if (floatingCursorRect == null) {
          return const SizedBox();
        }

        return Positioned.fromRect(
          rect: floatingCursorRect,
          child: IgnorePointer(
            child: ColoredBox(
              color: Colors.red.withValues(alpha: 0.75),
            ),
          ),
        );
      },
    );
  }
}

/// A [SuperEditorDocumentLayerBuilder] that builds a [IosToolbarFocalPointDocumentLayer], which
/// positions a `Leader` widget around the document selection, as a focal point for an
/// iOS floating toolbar.
class SuperEditorIosToolbarFocalPointDocumentLayerBuilder implements SuperEditorLayerBuilder {
  const SuperEditorIosToolbarFocalPointDocumentLayerBuilder({
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
    if (defaultTargetPlatform != TargetPlatform.iOS || SuperEditorIosControlsScope.maybeNearestOf(context) == null) {
      // There's no controls scope. This probably means SuperEditor is configured with
      // a non-iOS gesture mode. Build nothing.
      return const ContentLayerProxyWidget(child: SizedBox());
    }

    return IosToolbarFocalPointDocumentLayer(
      document: editorContext.document,
      selection: editorContext.composer.selectionNotifier,
      toolbarFocalPointLink: SuperEditorIosControlsScope.rootOf(context).toolbarFocalPoint,
      showDebugLeaderBounds: showDebugLeaderBounds,
    );
  }
}

/// A [SuperEditorLayerBuilder], which builds a [IosHandlesDocumentLayer],
/// which displays iOS-style caret and handles.
class SuperEditorIosHandlesDocumentLayerBuilder implements SuperEditorLayerBuilder {
  const SuperEditorIosHandlesDocumentLayerBuilder({
    this.handleColor,
    this.caretWidth,
    this.handleBallDiameter,
  });

  final Color? handleColor;
  final double? caretWidth;

  /// The diameter of the small circle that appears on the top and bottom of
  /// expanded iOS text handles.
  final double? handleBallDiameter;

  @override
  ContentLayerWidget build(BuildContext context, SuperEditorContext editContext) {
    if (defaultTargetPlatform != TargetPlatform.iOS || SuperEditorIosControlsScope.maybeNearestOf(context) == null) {
      // There's no controls scope. This probably means SuperEditor is configured with
      // a non-iOS gesture mode. Build nothing.
      return const ContentLayerProxyWidget(child: SizedBox());
    }

    final controlsController = SuperEditorIosControlsScope.rootOf(context);

    return IosHandlesDocumentLayer(
      document: editContext.document,
      documentLayout: editContext.documentLayout,
      selection: editContext.composer.selectionNotifier,
      changeSelection: (newSelection, changeType, reason) {
        editContext.editor.execute([
          ChangeSelectionRequest(newSelection, changeType, reason),
          const ClearComposingRegionRequest(),
        ]);
      },
      areSelectionHandlesAllowed: controlsController.areSelectionHandlesAllowed,
      handleBeingDragged: controlsController.handleBeingDragged,
      handleColor: handleColor ?? controlsController.handleColor ?? Theme.of(context).primaryColor,
      caretWidth: caretWidth ?? 2,
      handleBallDiameter: handleBallDiameter ?? defaultIosHandleBallDiameter,
      shouldCaretBlink: controlsController.shouldCaretBlink,
      floatingCursorController: controlsController.floatingCursorController,
    );
  }
}

const defaultIosMagnifierEnterAnimationDuration = Duration(milliseconds: 180);
const defaultIosMagnifierExitAnimationDuration = Duration(milliseconds: 150);
const defaultIosMagnifierAnimationCurve = Curves.easeInOut;
const defaultIosMagnifierSize = Size(133, 96);

/// The diameter of the small circle that appears on the top and bottom of
/// expanded iOS text handles in dip.
const defaultIosHandleBallDiameter = 16.0;
