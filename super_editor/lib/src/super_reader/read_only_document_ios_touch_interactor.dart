import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/default_editor/document_gestures_touch_ios.dart';
import 'package:super_editor/src/document_operations/selection_operations.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/content_layers.dart';
import 'package:super_editor/src/infrastructure/document_gestures.dart';
import 'package:super_editor/src/infrastructure/document_gestures_interaction_overrides.dart';
import 'package:super_editor/src/infrastructure/flutter/flutter_pipeline.dart';
import 'package:super_editor/src/infrastructure/multi_tap_gesture.dart';
import 'package:super_editor/src/infrastructure/platforms/ios/ios_document_controls.dart';
import 'package:super_editor/src/infrastructure/platforms/ios/long_press_selection.dart';
import 'package:super_editor/src/infrastructure/platforms/mobile_documents.dart';
import 'package:super_editor/src/infrastructure/touch_controls.dart';
import 'package:super_editor/src/super_reader/reader_context.dart';
import 'package:super_editor/src/super_reader/super_reader.dart';

/// An [InheritedWidget] that provides shared access to a [SuperReaderIosControlsController],
/// which coordinates the state of iOS controls like drag handles, magnifier, and toolbar.
///
/// This widget and its associated controller exist so that [SuperReader] has maximum freedom
/// in terms of where to implement iOS gestures vs handles vs the magnifier vs the toolbar.
/// Each of these responsibilities have some unique differences, which make them difficult
/// or impossible to implement within a single widget. By sharing a controller, a group of
/// independent widgets can work together to cover those various responsibilities.
///
/// Centralizing a controller in an [InheritedWidget] also allows [SuperReader] to share that
/// control with application code outside of [SuperReader], by placing an [SuperReaderIosControlsScope]
/// above the [SuperReader] in the widget tree. For this reason, [SuperReader] should access
/// the [SuperReaderIosControlsScope] through [rootOf].
class SuperReaderIosControlsScope extends InheritedWidget {
  /// Finds the highest [SuperReaderIosControlsScope] in the widget tree, above the given
  /// [context], and returns its associated [SuperReaderIosControlsController].
  static SuperReaderIosControlsController rootOf(BuildContext context) {
    final data = maybeRootOf(context);

    if (data == null) {
      throw Exception("Tried to depend upon the root IosReaderControlsScope but no such ancestor widget exists.");
    }

    return data;
  }

  static SuperReaderIosControlsController? maybeRootOf(BuildContext context) {
    InheritedElement? root;

    context.visitAncestorElements((element) {
      if (element is! InheritedElement || element.widget is! SuperReaderIosControlsScope) {
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
    return (root!.widget as SuperReaderIosControlsScope).controller;
  }

  /// Finds the nearest [SuperReaderIosControlsScope] in the widget tree, above the given
  /// [context], and returns its associated [SuperReaderIosControlsController].
  static SuperReaderIosControlsController nearestOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SuperReaderIosControlsScope>()!.controller;

  static SuperReaderIosControlsController? maybeNearestOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SuperReaderIosControlsScope>()?.controller;

  const SuperReaderIosControlsScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final SuperReaderIosControlsController controller;

  @override
  bool updateShouldNotify(SuperReaderIosControlsScope oldWidget) {
    return controller != oldWidget.controller;
  }
}

/// A controller, which coordinates the state of various iOS reader controls, including
/// drag handles, magnifier, and toolbar.
class SuperReaderIosControlsController {
  SuperReaderIosControlsController({
    this.handleColor,
    this.magnifierBuilder,
    this.toolbarBuilder,
    this.createOverlayControlsClipper,
  });

  void dispose() {
    shouldShowMagnifier.dispose();
    shouldShowToolbar.dispose();
  }

  /// Color of the text selection drag handles on iOS.
  final Color? handleColor;

  /// Whether the iOS magnifier should be displayed right now.
  final shouldShowMagnifier = ValueNotifier<bool>(false);

  /// Link to a location where a magnifier should be focused.
  final magnifierFocalPoint = LeaderLink();

  /// (Optional) Builder to create the visual representation of the magnifier.
  ///
  /// If [magnifierBuilder] is `null`, a default iOS magnifier is displayed.
  final Widget Function(BuildContext, LeaderLink focalPoint)? magnifierBuilder;

  /// Whether the iOS floating toolbar should be displayed right now.
  final shouldShowToolbar = ValueNotifier<bool>(false);

  /// Toggles [shouldShowToolbar].
  void toggleToolbar() => shouldShowToolbar.value = !shouldShowToolbar.value;

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
  final Widget Function(BuildContext, LeaderLink focalPoint)? toolbarBuilder;

  /// Creates a clipper that restricts where the toolbar and magnifier can
  /// appear in the overlay.
  ///
  /// If no clipper factory method is provided, then the overlay controls
  /// will be allowed to appear anywhere in the overlay in which they sit
  /// (probably the entire screen).
  final CustomClipper<Rect> Function(BuildContext overlayContext)? createOverlayControlsClipper;
}

/// Document gesture interactor that's designed for iOS touch input, e.g.,
/// drag to scroll, double and triple tap to select content, and drag
/// selection ends to expand selection.
///
/// The primary difference between a read-only touch interactor, and an
/// editing touch interactor, is that read-only documents don't support
/// collapsed selections, i.e., caret display. When the user taps on
/// a read-only document, nothing happens. The user must drag an expanded
/// selection, or double/triple tap to select content.
class SuperReaderIosDocumentTouchInteractor extends StatefulWidget {
  const SuperReaderIosDocumentTouchInteractor({
    Key? key,
    required this.focusNode,
    required this.document,
    required this.documentKey,
    required this.getDocumentLayout,
    required this.selection,
    required this.scrollController,
    this.contentTapHandler,
    this.dragAutoScrollBoundary = const AxisOffset.symmetric(54),
    this.showDebugPaint = false,
    this.child,
  }) : super(key: key);

  final FocusNode focusNode;

  final Document document;
  final GlobalKey documentKey;
  final DocumentLayout Function() getDocumentLayout;
  final ValueNotifier<DocumentSelection?> selection;

  final ScrollController scrollController;

  /// Optional handler that responds to taps on content, e.g., opening
  /// a link when the user taps on text with a link attribution.
  final ContentTapDelegate? contentTapHandler;

  /// The closest that the user's selection drag gesture can get to the
  /// document boundary before auto-scrolling.
  ///
  /// The default value is `54.0` pixels for both the leading and trailing
  /// edges.
  final AxisOffset dragAutoScrollBoundary;

  final bool showDebugPaint;

  final Widget? child;

  @override
  State createState() => _SuperReaderIosDocumentTouchInteractorState();
}

class _SuperReaderIosDocumentTouchInteractorState extends State<SuperReaderIosDocumentTouchInteractor>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // The ScrollPosition attached to the _ancestorScrollable.
  ScrollPosition? _ancestorScrollPosition;
  // The actual ScrollPosition that's used for the document layout, either
  // the Scrollable installed by this interactor, or an ancestor Scrollable.
  ScrollPosition? _activeScrollPosition;

  SuperReaderIosControlsController? _controlsContext;

  late DragHandleAutoScroller _handleAutoScrolling;
  Offset? _globalStartDragOffset;
  Offset? _dragStartInDoc;
  Offset? _startDragPositionOffset;
  double? _dragStartScrollOffset;
  Offset? _globalDragOffset;
  Offset? _dragEndInInteractor;
  DragMode? _dragMode;
  // TODO: HandleType is the wrong type here, we need collapsed/base/extent,
  //       not collapsed/upstream/downstream. Change the type once it's working.
  HandleType? _dragHandleType;

  final _magnifierOffset = ValueNotifier<Offset?>(null);

  Timer? _tapDownLongPressTimer;
  Offset? _globalTapDownOffset;
  bool get _isLongPressInProgress => _longPressStrategy != null;
  IosLongPressSelectionStrategy? _longPressStrategy;

  @override
  void initState() {
    super.initState();

    _handleAutoScrolling = DragHandleAutoScroller(
      vsync: this,
      dragAutoScrollBoundary: widget.dragAutoScrollBoundary,
      getScrollPosition: () => scrollPosition,
      getViewportBox: () => viewportBox,
    );

    widget.document.addListener(_onDocumentChange);

    widget.selection.addListener(_onSelectionChange);
    // If we already have a selection, we may need to display drag handles.
    if (widget.selection.value != null) {
      _onSelectionChange();
    }

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _controlsContext = SuperReaderIosControlsScope.rootOf(context);

    _ancestorScrollPosition = _findAncestorScrollable(context)?.position;

    // On the next frame, check if our active scroll position changed to a
    // different instance. If it did, move our listener to the new one.
    //
    // This is posted to the next frame because the first time this method
    // runs, we haven't attached to our own ScrollController yet, so
    // this.scrollPosition might be null.
    onNextFrame((_) {
      final newScrollPosition = scrollPosition;
      if (newScrollPosition == _activeScrollPosition) {
        return;
      }

      setState(() {
        _activeScrollPosition = newScrollPosition;
      });
    });
  }

  @override
  void didUpdateWidget(SuperReaderIosDocumentTouchInteractor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.document != oldWidget.document) {
      oldWidget.document.removeListener(_onDocumentChange);
      widget.document.addListener(_onDocumentChange);
    }

    if (widget.selection != oldWidget.selection) {
      oldWidget.selection.removeListener(_onSelectionChange);
      widget.selection.addListener(_onSelectionChange);

      // Selection has changed, we need to update the caret.
      if (widget.selection.value != oldWidget.selection.value) {
        _onSelectionChange();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    widget.document.removeListener(_onDocumentChange);
    widget.selection.removeListener(_onSelectionChange);

    _handleAutoScrolling.dispose();

    super.dispose();
  }

  void _ensureSelectionExtentIsVisible() {
    readerGesturesLog.fine("Ensuring selection extent is visible");
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

    _handleAutoScrolling.ensureOffsetIsVisible(extentOffsetInViewport);
  }

  Offset _documentOffsetToViewportOffset(Offset documentOffset) {
    final globalOffset = _docLayout.getGlobalOffsetFromDocumentOffset(documentOffset);
    return viewportBox.globalToLocal(globalOffset);
  }

  void _onDocumentChange(_) {
    _controlsContext!.shouldShowToolbar.value = false;

    onNextFrame((_) {
      // The user may have changed the type of node, e.g., paragraph to
      // blockquote, which impacts the caret size and position. Reposition
      // the caret on the next frame.
      // TODO: find a way to only do this when something relevant changes
      _updateHandlesAfterSelectionOrLayoutChange();

      _ensureSelectionExtentIsVisible();
    });
  }

  void _onSelectionChange() {
    // The selection change might correspond to new content that's not
    // laid out yet. Wait until the next frame to update visuals.
    onNextFrame((_) => _updateHandlesAfterSelectionOrLayoutChange());
  }

  void _updateHandlesAfterSelectionOrLayoutChange() {
    final newSelection = widget.selection.value;

    if (newSelection == null) {
      _controlsContext!.shouldShowToolbar.value = false;
    }
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
  RenderBox get viewportBox =>
      (_findAncestorScrollable(context)?.context.findRenderObject() ?? context.findRenderObject()) as RenderBox;

  RenderBox get interactorBox => context.findRenderObject() as RenderBox;

  /// Converts the given [interactorOffset] from the [DocumentInteractor]'s coordinate
  /// space to the [DocumentLayout]'s coordinate space.
  Offset _interactorOffsetToDocumentOffset(Offset interactorOffset) {
    final globalOffset = (context.findRenderObject() as RenderBox).localToGlobal(interactorOffset);
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
  Offset _interactorOffsetInViewport(Offset interactorOffset) {
    // Viewport might be our box, or an ancestor box if we're inside someone
    // else's Scrollable.
    return viewportBox.globalToLocal(
      interactorBox.localToGlobal(interactorOffset),
    );
  }

  void _onTapDown(TapDownDetails details) {
    _globalTapDownOffset = details.globalPosition;
    _tapDownLongPressTimer?.cancel();
    _tapDownLongPressTimer = Timer(kLongPressTimeout, _onLongPressDown);
  }

  // Runs when a tap down has lasted long enough to signify a long-press.
  void _onLongPressDown() {
    final interactorOffset = interactorBox.globalToLocal(_globalTapDownOffset!);
    final tapDownDocumentOffset = _interactorOffsetToDocumentOffset(interactorOffset);
    final tapDownDocumentPosition = _docLayout.getDocumentPositionNearestToOffset(tapDownDocumentOffset);
    if (tapDownDocumentPosition == null) {
      return;
    }

    if (_isOverBaseHandle(interactorOffset) || _isOverExtentHandle(interactorOffset)) {
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

    _magnifierOffset.value = _interactorOffsetToDocumentOffset(interactorBox.globalToLocal(_globalTapDownOffset!));
    _controlsContext!
      ..shouldShowToolbar.value = false
      ..shouldShowMagnifier.value = true;

    widget.focusNode.requestFocus();
  }

  void _onTapUp(TapUpDetails details) {
    // Stop waiting for a long-press to start.
    _globalTapDownOffset = null;
    _tapDownLongPressTimer?.cancel();
    _controlsContext!.shouldShowMagnifier.value = false;

    final selection = widget.selection.value;
    if (selection != null &&
        !selection.isCollapsed &&
        (_isOverBaseHandle(details.localPosition) || _isOverExtentHandle(details.localPosition))) {
      _controlsContext!.toggleToolbar();
      return;
    }

    readerGesturesLog.info("Tap down on document");
    final docOffset = _interactorOffsetToDocumentOffset(details.localPosition);
    readerGesturesLog.fine(" - document offset: $docOffset");
    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    readerGesturesLog.fine(" - tapped document position: $docPosition");

    if (widget.contentTapHandler != null && docPosition != null) {
      final result = widget.contentTapHandler!.onTap(docPosition);
      if (result == TapHandlingInstruction.halt) {
        // The custom tap handler doesn't want us to react at all
        // to the tap.
        return;
      }
    }

    if (docPosition != null &&
        selection != null &&
        !selection.isCollapsed &&
        widget.document.doesSelectionContainPosition(selection, docPosition)) {
      // The user tapped on an expanded selection. Toggle the toolbar.
      _controlsContext!.toggleToolbar();
      return;
    }

    widget.selection.value = null;
    _controlsContext!.shouldShowToolbar.value = false;

    widget.focusNode.requestFocus();
  }

  void _onDoubleTapUp(TapUpDetails details) {
    final selection = widget.selection.value;
    if (selection != null &&
        !selection.isCollapsed &&
        (_isOverBaseHandle(details.localPosition) || _isOverExtentHandle(details.localPosition))) {
      return;
    }

    readerGesturesLog.info("Double tap down on document");
    final docOffset = _interactorOffsetToDocumentOffset(details.localPosition);
    readerGesturesLog.fine(" - document offset: $docOffset");
    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    readerGesturesLog.fine(" - tapped document position: $docPosition");

    if (docPosition != null && widget.contentTapHandler != null) {
      final result = widget.contentTapHandler!.onDoubleTap(docPosition);
      if (result == TapHandlingInstruction.halt) {
        // The custom tap handler doesn't want us to react at all
        // to the tap.
        return;
      }
    }

    widget.selection.value = null;

    if (docPosition != null) {
      final tappedComponent = _docLayout.getComponentByNodeId(docPosition.nodeId)!;
      if (!tappedComponent.isVisualSelectionSupported()) {
        return;
      }

      widget.selection.value = null;

      bool didSelectContent = selectWordAt(
        docPosition: docPosition,
        docLayout: _docLayout,
        selection: widget.selection,
      );

      if (!didSelectContent) {
        selectBlockAt(docPosition, widget.selection);
      }
    }

    final newSelection = widget.selection.value;
    if (newSelection == null || newSelection.isCollapsed) {
      _controlsContext!.shouldShowToolbar.value = false;
    } else {
      _controlsContext!.shouldShowToolbar.value = true;
    }

    widget.focusNode.requestFocus();
  }

  void _onTripleTapUp(TapUpDetails details) {
    readerGesturesLog.info("Triple down down on document");

    final docOffset = _interactorOffsetToDocumentOffset(details.localPosition);
    readerGesturesLog.fine(" - document offset: $docOffset");
    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    readerGesturesLog.fine(" - tapped document position: $docPosition");

    if (docPosition != null && widget.contentTapHandler != null) {
      final result = widget.contentTapHandler!.onTripleTap(docPosition);
      if (result == TapHandlingInstruction.halt) {
        // The custom tap handler doesn't want us to react at all
        // to the tap.
        return;
      }
    }

    widget.selection.value = null;

    if (docPosition != null) {
      final tappedComponent = _docLayout.getComponentByNodeId(docPosition.nodeId)!;
      if (!tappedComponent.isVisualSelectionSupported()) {
        return;
      }

      selectParagraphAt(
        docPosition: docPosition,
        docLayout: _docLayout,
        selection: widget.selection,
      );
    }

    final selection = widget.selection.value;
    if (selection == null || selection.isCollapsed) {
      _controlsContext!.shouldShowToolbar.value = false;
    } else {
      _controlsContext!.shouldShowToolbar.value = true;
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
    } else if (_isOverBaseHandle(details.localPosition)) {
      _dragMode = DragMode.base;
      _dragHandleType = HandleType.upstream;
    } else if (_isOverExtentHandle(details.localPosition)) {
      _dragMode = DragMode.extent;
      _dragHandleType = HandleType.downstream;
    } else {
      return;
    }

    _controlsContext!.shouldShowToolbar.value = false;

    _globalStartDragOffset = details.globalPosition;
    final interactorBox = context.findRenderObject() as RenderBox;
    final handleOffsetInInteractor = interactorBox.globalToLocal(details.globalPosition);
    _dragStartInDoc = _interactorOffsetToDocumentOffset(handleOffsetInInteractor);

    if (_dragHandleType != null) {
      _startDragPositionOffset = _docLayout
          .getRectForPosition(
            _dragHandleType! == HandleType.upstream ? selection.base : selection.extent,
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

    _handleAutoScrolling.startAutoScrollHandleMonitoring();

    scrollPosition.addListener(_onAutoScrollChange);
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
    // If the user isn't dragging a handle, then the user is trying to
    // scroll the document. Scroll it, accordingly.
    if (_dragMode == null) {
      scrollPosition.jumpTo(scrollPosition.pixels - details.delta.dy);
      return;
    }

    // The user is dragging a handle. Update the document selection, and
    // auto-scroll, if needed.
    _globalDragOffset = details.globalPosition;
    final interactorBox = context.findRenderObject() as RenderBox;
    _dragEndInInteractor = interactorBox.globalToLocal(details.globalPosition);
    final dragEndInViewport = _interactorOffsetInViewport(_dragEndInInteractor!);

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

    _handleAutoScrolling.updateAutoScrollHandleMonitoring(
      dragEndInViewport: dragEndInViewport,
    );

    _controlsContext!.shouldShowMagnifier.value = true;

    _magnifierOffset.value = _interactorOffsetToDocumentOffset(interactorBox.globalToLocal(details.globalPosition));
  }

  void _updateSelectionForNewDragHandleLocation() {
    final docDragDelta = _globalDragOffset! - _globalStartDragOffset!;
    final dragScrollDelta = _dragStartScrollOffset! - scrollPosition.pixels;
    final docDragPosition = _docLayout
        .getDocumentPositionNearestToOffset(_startDragPositionOffset! + docDragDelta - Offset(0, dragScrollDelta));

    if (docDragPosition == null) {
      return;
    }

    if (_dragHandleType == HandleType.upstream) {
      widget.selection.value = widget.selection.value!.copyWith(
        base: docDragPosition,
      );
    } else if (_dragHandleType == HandleType.downstream) {
      widget.selection.value = widget.selection.value!.copyWith(
        extent: docDragPosition,
      );
    }
  }

  void _onPanEnd(DragEndDetails details) {
    _magnifierOffset.value = null;

    if (_dragMode == null) {
      // User was dragging the scroll area. Go ballistic.
      if (scrollPosition is ScrollPositionWithSingleContext) {
        (scrollPosition as ScrollPositionWithSingleContext).goBallistic(-details.velocity.pixelsPerSecond.dy);

        if (_activeScrollPosition != scrollPosition) {
          // We add the scroll change listener again, because going ballistic
          // seems to switch out the scroll position.
          _activeScrollPosition = scrollPosition;
        }
      }
    } else {
      // The user was dragging a selection change in some way, either with handles
      // or with a long-press. Finish that interaction.
      _onDragSelectionEnd();
    }
  }

  void _onPanCancel() {
    _magnifierOffset.value = null;

    if (_dragMode != null) {
      _onDragSelectionEnd();
    }
  }

  void _onDragSelectionEnd() {
    if (_dragMode == DragMode.longPress) {
      _onLongPressEnd();
    } else {
      _onHandleDragEnd();
    }

    _handleAutoScrolling.stopAutoScrollHandleMonitoring();
    scrollPosition.removeListener(_onAutoScrollChange);
  }

  void _onLongPressEnd() {
    _longPressStrategy!.onLongPressEnd();
    _longPressStrategy = null;
    _dragMode = null;

    _updateOverlayControlsAfterFinishingDragSelection();
  }

  void _onHandleDragEnd() {
    _handleAutoScrolling.stopAutoScrollHandleMonitoring();
    _dragMode = null;

    _updateOverlayControlsAfterFinishingDragSelection();
  }

  void _updateOverlayControlsAfterFinishingDragSelection() {
    _controlsContext!.shouldShowMagnifier.value = false;
    if (!widget.selection.value!.isCollapsed) {
      _controlsContext!.shouldShowToolbar.value = true;
    } else {
      // Read-only documents don't support collapsed selections.
      widget.selection.value = null;
    }
  }

  void _select(DocumentSelection newSelection) {
    widget.selection.value = newSelection;
  }

  ScrollableState? _findAncestorScrollable(BuildContext context) {
    final ancestorScrollable = Scrollable.maybeOf(context);
    if (ancestorScrollable == null) {
      return null;
    }

    final direction = ancestorScrollable.axisDirection;
    // If the direction is horizontal, then we are inside a widget like a TabBar
    // or a horizontal ListView, so we can't use the ancestor scrollable
    if (direction == AxisDirection.left || direction == AxisDirection.right) {
      return null;
    }

    return ancestorScrollable;
  }

  void _onAutoScrollChange() {
    _updateDragSelection();
    _updateMagnifierFocalPointOnAutoScrollFrame();
  }

  void _updateDragSelection() {
    if (_dragStartInDoc == null) {
      return;
    }

    final dragEndInDoc = _interactorOffsetToDocumentOffset(_dragEndInInteractor!);
    final dragPosition = _docLayout.getDocumentPositionNearestToOffset(dragEndInDoc);
    readerGesturesLog.info("Selecting new position during drag: $dragPosition");

    if (dragPosition == null) {
      return;
    }

    late DocumentPosition basePosition;
    late DocumentPosition extentPosition;
    switch (_dragHandleType!) {
      case HandleType.collapsed:
        // no-op for read-only documents
        return;
      case HandleType.upstream:
        basePosition = dragPosition;
        extentPosition = widget.selection.value!.extent;
        break;
      case HandleType.downstream:
        basePosition = widget.selection.value!.base;
        extentPosition = dragPosition;
        break;
    }

    widget.selection.value = DocumentSelection(
      base: basePosition,
      extent: extentPosition,
    );
    readerGesturesLog.fine("Selected region: ${widget.selection.value}");
  }

  void _updateMagnifierFocalPointOnAutoScrollFrame() {
    if (_magnifierOffset.value != null) {
      final interactorBox = context.findRenderObject() as RenderBox;
      _magnifierOffset.value = _interactorOffsetToDocumentOffset(interactorBox.globalToLocal(_globalDragOffset!));
    }
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
      } else {
        if (scrollPosition != _activeScrollPosition) {
          _activeScrollPosition = scrollPosition;
        }
      }
    }

    final gestureSettings = MediaQuery.maybeOf(context)?.gestureSettings;
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        TapSequenceGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapSequenceGestureRecognizer>(
          () => TapSequenceGestureRecognizer(),
          (TapSequenceGestureRecognizer recognizer) {
            recognizer
              ..onTapDown = _onTapDown
              ..onTapUp = _onTapUp
              ..onDoubleTapUp = _onDoubleTapUp
              ..onTripleTapUp = _onTripleTapUp
              ..gestureSettings = gestureSettings;
          },
        ),
        // We use a VerticalDragGestureRecognizer instead of a PanGestureRecognizer
        // because `Scrollable` also uses a VerticalDragGestureRecognizer and we
        // need to beat out any ancestor `Scrollable` in the gesture arena.
        VerticalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
          () => VerticalDragGestureRecognizer(),
          (VerticalDragGestureRecognizer instance) {
            instance
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
          widget.child ?? const SizedBox(),
          _buildMagnifierFocalPoint(),
        ],
      ),
    );
  }

  Widget _buildMagnifierFocalPoint() {
    return ValueListenableBuilder(
      valueListenable: _magnifierOffset,
      builder: (context, magnifierOffset, child) {
        if (magnifierOffset == null) {
          return const SizedBox();
        }

        // When the user is dragging a handle in this overlay, we
        // are responsible for positioning the focal point for the
        // magnifier to follow. We do that here.
        return Positioned(
          left: magnifierOffset.dx,
          top: magnifierOffset.dy,
          child: Leader(
            link: _controlsContext!.magnifierFocalPoint,
            child: const SizedBox(width: 1, height: 1),
          ),
        );
      },
    );
  }
}

/// Adds and removes an iOS-style editor toolbar, as dictated by an ancestor
/// [SuperReaderIosControlsScope].
class SuperReaderIosToolbarOverlayManager extends StatefulWidget {
  const SuperReaderIosToolbarOverlayManager({
    super.key,
    this.defaultToolbarBuilder,
    this.child,
  });

  final Widget Function(BuildContext, LeaderLink)? defaultToolbarBuilder;

  final Widget? child;

  @override
  State<SuperReaderIosToolbarOverlayManager> createState() => _SuperReaderIosToolbarOverlayManagerState();
}

class _SuperReaderIosToolbarOverlayManagerState extends State<SuperReaderIosToolbarOverlayManager> {
  SuperReaderIosControlsController? _controlsContext;
  OverlayEntry? _toolbarOverlayEntry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _controlsContext = SuperReaderIosControlsScope.rootOf(context);

    // Add our overlay on the next frame. If we did it immediately, it would
    // cause a setState() to be called during didChangeDependencies, which is
    // a framework violation.
    onNextFrame((timeStamp) {
      _addToolbarOverlay();
    });
  }

  @override
  void dispose() {
    _removeToolbarOverlay();
    super.dispose();
  }

  void _addToolbarOverlay() {
    if (_toolbarOverlayEntry != null) {
      return;
    }

    _toolbarOverlayEntry = OverlayEntry(builder: (overlayContext) {
      return IosFloatingToolbarOverlay(
        shouldShowToolbar: _controlsContext!.shouldShowToolbar,
        toolbarFocalPoint: _controlsContext!.toolbarFocalPoint,
        popoverToolbarBuilder:
            _controlsContext!.toolbarBuilder ?? widget.defaultToolbarBuilder ?? (_, __) => const SizedBox(),
        createOverlayControlsClipper: _controlsContext!.createOverlayControlsClipper,
        showDebugPaint: false,
      );
    });

    Overlay.of(context).insert(_toolbarOverlayEntry!);
  }

  void _removeToolbarOverlay() {
    if (_toolbarOverlayEntry == null) {
      return;
    }

    _toolbarOverlayEntry!.remove();
    _toolbarOverlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child ?? const SizedBox();
  }
}

/// A [SuperReaderLayerBuilder], which builds a [IosMagnifierDocumentLayer],
/// which displays iOS-style magnifier.
class SuperReaderIosMagnifierDocumentLayerBuilder implements SuperReaderDocumentLayerBuilder {
  const SuperReaderIosMagnifierDocumentLayerBuilder();

  @override
  ContentLayerWidget build(BuildContext context, SuperReaderContext editContext) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const ContentLayerProxyWidget(child: SizedBox());
    }

    return IosMagnifierDocumentLayer(
      focalPoint: SuperReaderIosControlsScope.rootOf(context).magnifierFocalPoint,
      shouldShowMagnifier: SuperReaderIosControlsScope.rootOf(context).shouldShowMagnifier,
      magnifierBuilder: SuperReaderIosControlsScope.rootOf(context).magnifierBuilder,
    );
  }
}

/// A [SuperReaderLayerBuilder], which builds a [IosControlsDocumentLayer],
/// which displays iOS-style handles.
class SuperReaderIosControlsDocumentLayerBuilder implements SuperReaderDocumentLayerBuilder {
  const SuperReaderIosControlsDocumentLayerBuilder({
    this.handleColor,
  });

  final Color? handleColor;

  @override
  ContentLayerWidget build(BuildContext context, SuperReaderContext readerContext) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const ContentLayerProxyWidget(child: SizedBox());
    }

    return IosControlsDocumentLayer(
      document: readerContext.document,
      documentLayout: readerContext.documentLayout,
      selection: readerContext.selection,
      changeSelection: (newSelection, changeType, reason) {
        readerContext.selection.value = newSelection;
      },
      handleColor: handleColor ?? Theme.of(context).primaryColor,
      shouldCaretBlink: ValueNotifier<bool>(false),
    );
  }
}
