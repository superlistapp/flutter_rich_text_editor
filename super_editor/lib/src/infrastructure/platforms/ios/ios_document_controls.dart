import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:overlord/follow_the_leader.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/default_editor/document_gestures_touch_ios.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/content_layers.dart';
import 'package:super_editor/src/infrastructure/documents/document_layers.dart';
import 'package:super_editor/src/infrastructure/documents/selection_leader_document_layer.dart';
import 'package:super_editor/src/infrastructure/flutter/flutter_scheduler.dart';
import 'package:super_editor/src/infrastructure/multi_listenable_builder.dart';
import 'package:super_editor/src/infrastructure/platforms/ios/selection_handles.dart';
import 'package:super_editor/src/infrastructure/platforms/mobile_documents.dart';
import 'package:super_editor/src/infrastructure/render_sliver_ext.dart';
import 'package:super_editor/src/infrastructure/touch_controls.dart';
import 'package:super_text_layout/super_text_layout.dart';

/// An application overlay that displays an iOS-style toolbar.
class IosFloatingToolbarOverlay extends StatefulWidget {
  const IosFloatingToolbarOverlay({
    Key? key,
    required this.shouldShowToolbar,
    required this.toolbarFocalPoint,
    required this.floatingToolbarBuilder,
    this.createOverlayControlsClipper,
    this.showDebugPaint = false,
  }) : super(key: key);

  final ValueListenable<bool> shouldShowToolbar;

  /// The focal point, which determines where the toolbar is positioned, and
  /// where the toolbar points.
  ///
  /// In the case that the associated [Leader] has meaningful width and height,
  /// the toolbar focuses on the center of the [Leader]'s bounding box.
  final LeaderLink toolbarFocalPoint;

  /// Creates a clipper that applies to overlay controls, preventing
  /// the overlay controls from appearing outside the given clipping
  /// region.
  ///
  /// If no clipper factory method is provided, then the overlay controls
  /// will be allowed to appear anywhere in the overlay in which they sit
  /// (probably the entire screen).
  final CustomClipper<Rect> Function(BuildContext overlayContext)? createOverlayControlsClipper;

  /// Builder that constructs the floating toolbar that's displayed above
  /// selected text.
  ///
  /// Typically, this bar includes actions like "copy", "cut", "paste", etc.
  final DocumentFloatingToolbarBuilder floatingToolbarBuilder;

  final bool showDebugPaint;

  @override
  State createState() => _IosFloatingToolbarOverlayState();
}

class _IosFloatingToolbarOverlayState extends State<IosFloatingToolbarOverlay> with SingleTickerProviderStateMixin {
  final _boundsKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.shouldShowToolbar,
      builder: (context, _) {
        return Padding(
          // Remove the keyboard from the space that we occupy so that
          // clipping calculations apply to the expected visual borders,
          // instead of applying underneath the keyboard.
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: ClipRect(
            clipper: widget.createOverlayControlsClipper?.call(context),
            child: SizedBox(
              // ^ SizedBox tries to be as large as possible, because
              // a Stack will collapse into nothing unless something
              // expands it.
              key: _boundsKey,
              width: double.infinity,
              height: double.infinity,
              child: Stack(
                children: [
                  // Build the editing toolbar
                  if (widget.shouldShowToolbar.value) //
                    _buildToolbar(),
                  if (widget.showDebugPaint) //
                    _buildDebugPaint(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolbar() {
    return FollowerFadeOutBeyondBoundary(
      link: widget.toolbarFocalPoint,
      boundary: WidgetFollowerBoundary(
        boundaryKey: _boundsKey,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      ),
      child: Follower.withAligner(
        link: widget.toolbarFocalPoint,
        aligner: CupertinoPopoverToolbarAligner(_boundsKey),
        boundary: WidgetFollowerBoundary(
          boundaryKey: _boundsKey,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
        child: widget.floatingToolbarBuilder(context, DocumentKeys.mobileToolbar, widget.toolbarFocalPoint),
      ),
    );
  }

  Widget _buildDebugPaint() {
    return IgnorePointer(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.yellow.withValues(alpha: 0.2),
      ),
    );
  }
}

/// Controls the display of drag handles, a magnifier, and a
/// floating toolbar, assuming iOS-style behavior for the
/// handles.
class IosDocumentGestureEditingController extends GestureEditingController {
  IosDocumentGestureEditingController({
    required LayerLink documentLayoutLink,
    required super.selectionLinks,
    required super.magnifierFocalPointLink,
    required super.overlayController,
  });

  /// Whether or not a caret should be displayed.
  bool get hasCaret => caretTop != null;

  /// The offset of the top of the caret, or `null` if no caret should
  /// be displayed.
  ///
  /// When the caret is drawn, the caret will have a thickness. That width
  /// should be placed either on the left or right of this offset, based on
  /// whether the [caretAffinity] is upstream or downstream, respectively.
  Offset? get caretTop => _caretTop;
  Offset? _caretTop;

  /// The height of the caret, or `null` if no caret should be displayed.
  double? get caretHeight => _caretHeight;
  double? _caretHeight;

  /// Updates the caret's size and position.
  ///
  /// The [top] offset is in the document layout's coordinate space.
  void updateCaret({
    Offset? top,
    double? height,
  }) {
    bool changed = false;
    if (top != null) {
      _caretTop = top;
      changed = true;
    }
    if (height != null) {
      _caretHeight = height;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// Removes the caret from the display.
  void removeCaret() {
    if (!hasCaret) {
      return;
    }

    _caretTop = null;
    _caretHeight = null;
    notifyListeners();
  }

  /// Whether a collapsed handle should be displayed.
  bool get shouldDisplayCollapsedHandle => _collapsedHandleOffset != null;

  /// The offset of the collapsed handle focal point, within the coordinate space
  /// of the document layout, or `null` if no collapsed handle should be displayed.
  Offset? get collapsedHandleOffset => _collapsedHandleOffset;
  Offset? _collapsedHandleOffset;
  set collapsedHandleOffset(Offset? offset) {
    if (offset != _collapsedHandleOffset) {
      _collapsedHandleOffset = offset;
      notifyListeners();
    }
  }

  /// Whether the expanded handles (base + extent) should be displayed.
  bool get shouldDisplayExpandedHandles => _upstreamHandleOffset != null && _downstreamHandleOffset != null;

  double? get upstreamCaretHeight => _upstreamCaretHeight;
  double? _upstreamCaretHeight;
  set upstreamCaretHeight(double? height) {
    if (height != _upstreamCaretHeight) {
      _upstreamCaretHeight = height;
      notifyListeners();
    }
  }

  /// The offset of the upstream handle focal point, within the coordinate space
  /// of the document layout, or `null` if no upstream handle should be displayed.
  Offset? get upstreamHandleOffset => _upstreamHandleOffset;
  Offset? _upstreamHandleOffset;
  set upstreamHandleOffset(Offset? offset) {
    if (offset != _upstreamHandleOffset) {
      _upstreamHandleOffset = offset;
      notifyListeners();
    }
  }

  double? get downstreamCaretHeight => _downstreamCaretHeight;
  double? _downstreamCaretHeight;
  set downstreamCaretHeight(double? height) {
    if (height != _downstreamCaretHeight) {
      _downstreamCaretHeight = height;
      notifyListeners();
    }
  }

  /// The offset of the downstream handle focal point, within the coordinate space
  /// of the document layout, or `null` if no downstream handle should be displayed.
  Offset? get downstreamHandleOffset => _downstreamHandleOffset;
  Offset? _downstreamHandleOffset;
  set downstreamHandleOffset(Offset? offset) {
    if (offset != _downstreamHandleOffset) {
      _downstreamHandleOffset = offset;
      notifyListeners();
    }
  }

  final _magnifierLink = LayerLink();

  @override
  void showMagnifier() {
    _newMagnifierLink = _magnifierLink;
    super.showMagnifier();
  }

  @override
  void hideMagnifier() {
    _newMagnifierLink = null;
    super.hideMagnifier();
  }

  LayerLink? get newMagnifierLink => _newMagnifierLink;
  LayerLink? _newMagnifierLink;
  set newMagnifierLink(LayerLink? link) {
    if (_newMagnifierLink == link) {
      return;
    }

    _newMagnifierLink = link;
    notifyListeners();
  }
}

class FloatingCursorController {
  void dispose() {
    isActive.dispose();
    isNearText.dispose();
    cursorGeometryInViewport.dispose();
    _listeners.clear();
  }

  /// Whether the user is currently interacting with the floating cursor via the
  /// software keyboard.
  final isActive = ValueNotifier<bool>(false);

  /// Whether the floating cursor is currently near text, which impacts whether
  /// or not a standard gray caret should be displayed.
  final isNearText = ValueNotifier<bool>(false);

  /// The offset, width, and height of the active floating cursor in viewport coordinates.
  final cursorGeometryInViewport = ValueNotifier<Rect?>(null);

  /// The offset, width, and height of the active floating cursor in document coordinates.
  final cursorGeometryInDocument = ValueNotifier<Rect?>(null);

  /// Report that the user has activated the floating cursor.
  void onStart() {
    isActive.value = true;
    for (final listener in _listeners) {
      listener.onStart();
    }
  }

  Offset? get offset => _offset;
  Offset? _offset;

  /// Report that the user has moved the floating cursor.
  void onMove(Offset? newOffset) {
    if (newOffset == _offset) {
      return;
    }
    _offset = newOffset;

    for (final listener in _listeners) {
      listener.onMove(newOffset);
    }
  }

  /// Report that the user has deactivated the floating cursor.
  void onStop() {
    isActive.value = false;
    for (final listener in _listeners) {
      listener.onStop();
    }
  }

  final _listeners = <FloatingCursorListener>{};

  void addListener(FloatingCursorListener listener) {
    _listeners.add(listener);
  }

  void removeListener(FloatingCursorListener listener) {
    _listeners.remove(listener);
  }
}

class FloatingCursorListener {
  FloatingCursorListener({
    VoidCallback? onStart,
    void Function(Offset?)? onMove,
    VoidCallback? onStop,
  })  : _onStart = onStart,
        _onMove = onMove,
        _onStop = onStop;

  final VoidCallback? _onStart;
  final void Function(Offset?)? _onMove;
  final VoidCallback? _onStop;

  void onStart() => _onStart?.call();

  void onMove(Offset? newOffset) => _onMove?.call(newOffset);

  void onStop() => _onStop?.call();
}

/// A document layer that positions a leader widget around the user's selection,
/// as a focal point for an iOS-style toolbar display.
///
/// By default, the toolbar focal point [LeaderLink] is obtained from an ancestor
/// [SuperEditorIosControlsScope].
class IosToolbarFocalPointDocumentLayer extends DocumentLayoutLayerStatefulWidget {
  const IosToolbarFocalPointDocumentLayer({
    Key? key,
    required this.document,
    required this.selection,
    required this.toolbarFocalPointLink,
    this.showDebugLeaderBounds = false,
  }) : super(key: key);

  /// The editor's [Document], which is used to find the start and end of
  /// the user's expanded selection.
  final Document document;

  /// The current user's selection within a document.
  final ValueListenable<DocumentSelection?> selection;

  /// The [LeaderLink], which is attached to the toolbar focal point bounds.
  ///
  /// By default, this [LeaderLink] is obtained from an ancestor [SuperEditorIosControlsScope].
  /// If [toolbarFocalPointLink] is non-null, it's used instead of the ancestor value.
  final LeaderLink toolbarFocalPointLink;

  /// Whether to paint colorful bounds around the leader widgets, for debugging purposes.
  final bool showDebugLeaderBounds;

  @override
  DocumentLayoutLayerState<ContentLayerStatefulWidget, Rect> createState() => _IosToolbarFocalPointDocumentLayerState();
}

class _IosToolbarFocalPointDocumentLayerState extends DocumentLayoutLayerState<IosToolbarFocalPointDocumentLayer, Rect>
    with SingleTickerProviderStateMixin {
  DocumentSelection? _selectionUsedForMostRecentLayout;

  @override
  void initState() {
    super.initState();

    widget.selection.addListener(_onSelectionChange);
  }

  @override
  void didUpdateWidget(IosToolbarFocalPointDocumentLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selection != oldWidget.selection) {
      oldWidget.selection.removeListener(_onSelectionChange);
      widget.selection.addListener(_onSelectionChange);
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChange);

    super.dispose();
  }

  void _onSelectionChange() {
    final selection = widget.selection.value;
    if (selection == _selectionUsedForMostRecentLayout) {
      // The selection didn't change from what it was the last time we calculated selection bounds.
      return;
    }
    _selectionUsedForMostRecentLayout = selection;

    // The selection changed, which means the selection bounds changed, we need to recalculate the
    // toolbar focal point bounds.
    setStateAsSoonAsPossible(() {
      // The selection bounds, and Leader build, will take place in methods that
      // run in response to setState().
    });
  }

  @override
  Rect? computeLayoutDataWithDocumentLayout(
      BuildContext contentLayersContext, BuildContext documentContext, DocumentLayout documentLayout) {
    final documentSelection = widget.selection.value;
    if (documentSelection == null) {
      return null;
    }

    final selectedComponent = documentLayout.getComponentByNodeId(widget.selection.value!.extent.nodeId);
    if (selectedComponent == null) {
      // Assume that we're in a momentary transitive state where the document layout
      // just gained or lost a component. We expect this method to run again in a moment
      // to correct for this.
      return null;
    }

    return documentLayout.getRectForSelection(
      documentSelection.base,
      documentSelection.extent,
    );
  }

  @override
  Widget doBuild(BuildContext context, Rect? selectionBounds) {
    if (selectionBounds == null) {
      return const SizedBox();
    }

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: selectionBounds,
            child: Leader(
              link: widget.toolbarFocalPointLink,
              child: widget.showDebugLeaderBounds
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          width: 4,
                          color: const Color(0xFFFF00FF),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// A document layer that displays an iOS-style caret and handles.
///
/// This layer positions the caret and handles directly, rather than using
/// `Leader`s and `Follower`s, because their position is based on the document
/// layout, rather than the user's gesture behavior.
class IosHandlesDocumentLayer extends DocumentLayoutLayerStatefulWidget {
  const IosHandlesDocumentLayer({
    super.key,
    required this.document,
    required this.documentLayout,
    required this.selection,
    required this.changeSelection,
    this.areSelectionHandlesAllowed,
    this.handleBeingDragged,
    required this.handleColor,
    this.caretWidth = 2,
    this.handleBallDiameter = defaultIosHandleBallDiameter,
    required this.shouldCaretBlink,
    this.floatingCursorController,
    this.showDebugPaint = false,
  });

  final Document document;

  final DocumentLayout documentLayout;

  final ValueListenable<DocumentSelection?> selection;

  final void Function(DocumentSelection?, SelectionChangeType, String selectionReason) changeSelection;

  /// {@macro are_selection_handles_allowed}
  final ValueListenable<bool>? areSelectionHandlesAllowed;

  /// Reports the [HandleType] of the handle being dragged by the user.
  ///
  /// If no drag handle is being dragged, this value is `null`.
  final ValueListenable<HandleType?>? handleBeingDragged;

  /// Color the iOS-style text selection drag handles.
  final Color handleColor;

  final double caretWidth;

  /// The diameter of the small circle that appears on the top and bottom of
  /// expanded iOS text handles.
  final double handleBallDiameter;

  /// Whether the caret should blink, whenever the caret is visible.
  final ValueListenable<bool> shouldCaretBlink;

  /// Floating cursor state, used to determine when the floating cursor is active,
  /// during which the regular caret is either hidden, or is displayed as a gray
  /// caret when the floating cursor is far away from its nearest text.
  final FloatingCursorController? floatingCursorController;

  final bool showDebugPaint;

  @override
  DocumentLayoutLayerState<IosHandlesDocumentLayer, DocumentSelectionLayout> createState() =>
      IosControlsDocumentLayerState();
}

@visibleForTesting
class IosControlsDocumentLayerState extends DocumentLayoutLayerState<IosHandlesDocumentLayer, DocumentSelectionLayout>
    with SingleTickerProviderStateMixin {
  // These global keys are assigned to each draggable handle to
  // prevent a strange dragging issue.
  //
  // Without these keys, if the user drags into the auto-scroll area
  // for a period of time, we never receive a
  // "pan end" or "pan cancel" callback. I have no idea why this is
  // the case. These handles sit in an Overlay, so it's not as if they
  // suffered some conflict within a ScrollView. I tried many adjustments
  // to recover the end/cancel callbacks. Finally, I tried adding these
  // global keys based on a hunch that perhaps the gesture detector was
  // somehow getting switched out, or assigned to a different widget, and
  // that was somehow disrupting the callback series. For now, these keys
  // seem to solve the problem.
  final _collapsedHandleKey = GlobalKey();
  final _upstreamHandleKey = GlobalKey();
  final _downstreamHandleKey = GlobalKey();

  late BlinkController _caretBlinkController;

  @override
  void initState() {
    super.initState();
    _caretBlinkController = BlinkController.withTimer();

    widget.selection.addListener(_onSelectionChange);
    widget.shouldCaretBlink.addListener(_onBlinkModeChange);
    widget.floatingCursorController?.isActive.addListener(_onFloatingCursorActivationChange);
    widget.handleBeingDragged?.addListener(_onDragChanged);

    _onBlinkModeChange();
  }

  @override
  void didUpdateWidget(IosHandlesDocumentLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selection != oldWidget.selection) {
      oldWidget.selection.removeListener(_onSelectionChange);
      widget.selection.addListener(_onSelectionChange);
    }

    if (widget.shouldCaretBlink != oldWidget.shouldCaretBlink) {
      oldWidget.shouldCaretBlink.removeListener(_onBlinkModeChange);
      widget.shouldCaretBlink.addListener(_onBlinkModeChange);
    }

    if (widget.floatingCursorController != oldWidget.floatingCursorController) {
      oldWidget.floatingCursorController?.isActive.removeListener(_onFloatingCursorActivationChange);
      widget.floatingCursorController?.isActive.addListener(_onFloatingCursorActivationChange);
    }

    if (widget.handleBeingDragged != oldWidget.handleBeingDragged) {
      oldWidget.handleBeingDragged?.removeListener(_onDragChanged);
      widget.handleBeingDragged?.addListener(_onDragChanged);
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChange);
    widget.shouldCaretBlink.removeListener(_onBlinkModeChange);
    widget.floatingCursorController?.isActive.removeListener(_onFloatingCursorActivationChange);
    widget.handleBeingDragged?.removeListener(_onDragChanged);

    _caretBlinkController.dispose();
    super.dispose();
  }

  @visibleForTesting
  Rect? get caret => layoutData?.caret;

  @visibleForTesting
  Color get caretColor => widget.handleColor;

  @visibleForTesting
  bool get isCaretDisplayed => layoutData?.caret != null;

  @visibleForTesting
  bool get isCaretVisible => _caretBlinkController.isVisible && isCaretDisplayed;

  @visibleForTesting
  Duration get caretFlashPeriod => _caretBlinkController.flashPeriod;

  @visibleForTesting
  bool get isUpstreamHandleDisplayed => layoutData?.upstream != null;

  @visibleForTesting
  bool get isDownstreamHandleDisplayed => layoutData?.downstream != null;

  void _onSelectionChange() {
    _updateCaretFlash();
    setState(() {
      // Schedule a new layout computation because the caret and/or handles need to move.
    });
  }

  void _onDragChanged() {
    setState(() {
      // Schedule a new layout computation because we might need to hide/show the handle ball.
    });
  }

  void _updateCaretFlash() {
    _caretBlinkController.jumpToOpaque();
    _startOrStopBlinking();
  }

  void _startOrStopBlinking() {
    // TODO: allow a configurable policy as to whether to show the caret at all when the selection is expanded: https://github.com/superlistapp/super_editor/issues/234
    final wantsToBlink = widget.selection.value != null && widget.shouldCaretBlink.value;
    if (wantsToBlink && _caretBlinkController.isBlinking) {
      return;
    }
    if (!wantsToBlink && !_caretBlinkController.isBlinking) {
      return;
    }

    wantsToBlink //
        ? _caretBlinkController.startBlinking()
        : _caretBlinkController.stopBlinking();
  }

  void _onBlinkModeChange() {
    if (widget.shouldCaretBlink.value) {
      _caretBlinkController.startBlinking();
    } else {
      _caretBlinkController.stopBlinking();
    }
  }

  void _onFloatingCursorActivationChange() {
    if (widget.floatingCursorController?.isActive.value == true) {
      _caretBlinkController.stopBlinking();
    } else {
      _caretBlinkController.startBlinking();
    }
  }

  /// Computes a zero width `Rect` that represents the x and y offsets and the height
  /// of the upstream or downstream handle in content space.
  ///
  /// The `Rect` returned by [DocumentLayout.getRectForPosition] doesn't match the
  /// top and bottom of the selection hightlight box. This method computes an
  /// expanded selection based on the given [position], computes the box for that
  /// selection, and returns the edge of the selection box.
  Rect _computeRectForExpandedHandle(DocumentPosition position) {
    final component = widget.documentLayout.getComponentByNodeId(position.nodeId);
    if (component == null) {
      return Rect.zero;
    }

    // Check if we have a position to the right of the current position within the same node.
    NodePosition? extentNodePosition = component.movePositionRight(position.nodePosition);
    bool isExtentDownstream = extentNodePosition != null;

    if (extentNodePosition == null) {
      // Couldn't find a valid position to the right. Look for a position to the left
      // of the current position within the same node.
      extentNodePosition = component.movePositionLeft(position.nodePosition);
    }

    if (extentNodePosition == null) {
      // We couldn't expand the selection neither to the left of the right. Fallback
      // to rect for the position, which relies on Flutter's computation for the
      // caret offset and height. Flutter's computation produces different offset
      // a height from what is returned by the selection highlight box.
      return widget.documentLayout.getRectForPosition(position)!;
    }

    final rectForSelection = widget.documentLayout.getRectForSelection(
      position,
      DocumentPosition(
        nodeId: position.nodeId,
        nodePosition: extentNodePosition,
      ),
    )!;

    return Rect.fromLTWH(
      isExtentDownstream ? rectForSelection.left : rectForSelection.right,
      rectForSelection.top,
      0,
      rectForSelection.bottom - rectForSelection.top,
    );
  }

  @override
  DocumentSelectionLayout? computeLayoutDataWithDocumentLayout(
      BuildContext contentLayersContext, BuildContext documentContext, DocumentLayout documentLayout) {
    final selection = widget.selection.value;
    if (selection == null) {
      return null;
    }

    if (widget.areSelectionHandlesAllowed?.value == false) {
      /// We don't want to show any selection handles.
      return null;
    }

    if (selection.isCollapsed) {
      Rect caretRect = documentLayout.getEdgeForPosition(selection.extent)!;

      // Default caret width used by IOSCollapsedHandle.
      const caretWidth = 2;

      // Use the content's RenderBox instead of the layer's RenderBox to get the layer's width.
      //
      // ContentLayers works in four steps:
      //
      // 1. The content is built.
      // 2. The content is laid out.
      // 3. The layers are built.
      // 4. The layers are laid out.
      //
      // The computeLayoutData method is called during the layer's build, which means that the
      // layer's RenderBox is outdated, because it wasn't laid out yet for the current frame.
      // Use the content's RenderBox, which was already laid out for the current frame.
      final contentBox = documentContext.findRenderObject() as RenderSliver?;
      if (contentBox != null && contentBox.hasSize && caretRect.left + caretWidth >= contentBox.size.width) {
        // Ajust the caret position to make it entirely visible because it's currently placed
        // partially or entirely outside of the layers' bounds. This can happen for downstream selections
        // of block components that take all the available width.
        caretRect = Rect.fromLTWH(
          contentBox.size.width - caretWidth,
          caretRect.top,
          caretRect.width,
          caretRect.height,
        );
      }

      return DocumentSelectionLayout(
        caret: caretRect,
      );
    } else {
      return DocumentSelectionLayout(
        upstream: _computeRectForExpandedHandle(
          widget.document.selectUpstreamPosition(selection.base, selection.extent),
        ),
        downstream: _computeRectForExpandedHandle(
          widget.document.selectDownstreamPosition(selection.base, selection.extent),
        ),
        expandedSelectionBounds: documentLayout.getRectForSelection(
          selection.base,
          selection.extent,
        ),
      );
    }
  }

  @override
  Widget doBuild(BuildContext context, DocumentSelectionLayout? layoutData) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: layoutData != null //
            ? _buildHandles(layoutData)
            : const SizedBox(),
      ),
    );
  }

  Widget _buildHandles(DocumentSelectionLayout layoutData) {
    if (widget.selection.value == null) {
      editorGesturesLog.finer("Not building overlay handles because there's no selection.");
      return const SizedBox.shrink();
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (layoutData.caret != null) //
          _buildCollapsedHandle(caret: layoutData.caret!),
        if (layoutData.upstream != null && layoutData.downstream != null) ...[
          _buildUpstreamHandle(
            upstream: layoutData.upstream!,
            debugColor: Colors.green,
          ),
          _buildDownstreamHandle(
            downstream: layoutData.downstream!,
            debugColor: Colors.red,
          ),
        ],
      ],
    );
  }

  Widget _buildCollapsedHandle({
    required Rect caret,
  }) {
    return Positioned(
      key: _collapsedHandleKey,
      left: caret.left,
      top: caret.top,
      child: MultiListenableBuilder(
        listenables: {
          if (widget.floatingCursorController != null) ...{
            widget.floatingCursorController!.isActive,
            widget.floatingCursorController!.isNearText,
          }
        },
        builder: (context) {
          final isShowingFloatingCursor = widget.floatingCursorController?.isActive.value == true;
          final isNearText = widget.floatingCursorController?.isNearText.value == true;
          if (isShowingFloatingCursor && isNearText) {
            // The floating cursor is active and it's near some text. We don't want to
            // paint a collapsed handle/caret.
            return const SizedBox();
          }

          return IOSCollapsedHandle(
            key: DocumentKeys.caret,
            controller: _caretBlinkController,
            color: isShowingFloatingCursor ? Colors.grey : widget.handleColor,
            caretHeight: caret.height,
            caretWidth: widget.caretWidth,
          );
        },
      ),
    );
  }

  Widget _buildUpstreamHandle({
    required Rect upstream,
    required Color debugColor,
  }) {
    final shouldShowBall = widget.handleBeingDragged?.value != HandleType.upstream;
    final ballRadius = shouldShowBall ? widget.handleBallDiameter / 2 : 0.0;
    return Positioned(
      key: _upstreamHandleKey,
      left: upstream.left,
      // Move the handle up so the ball is above the selected area and add half
      // of the radius to make the ball overlap the selected area.
      top: upstream.top -
          selectionHighlightBoxVerticalExpansion +
          (shouldShowBall ? (ballRadius / 2) - widget.handleBallDiameter : 0.0),
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: IOSSelectionHandle.upstream(
          key: DocumentKeys.upstreamHandle,
          color: widget.handleColor,
          handleType: HandleType.upstream,
          caretHeight: upstream.height + (selectionHighlightBoxVerticalExpansion * 2) - (ballRadius / 2),
          caretWidth: widget.caretWidth,
          ballRadius: ballRadius,
        ),
      ),
    );
  }

  Widget _buildDownstreamHandle({
    required Rect downstream,
    required Color debugColor,
  }) {
    final ballRadius = widget.handleBeingDragged?.value == HandleType.downstream //
        ? 0.0
        : widget.handleBallDiameter / 2;

    return Positioned(
      key: _downstreamHandleKey,
      left: downstream.left,
      top: downstream.top - selectionHighlightBoxVerticalExpansion,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: IOSSelectionHandle.downstream(
          key: DocumentKeys.downstreamHandle,
          color: widget.handleColor,
          handleType: HandleType.downstream,
          caretHeight: downstream.height + (selectionHighlightBoxVerticalExpansion * 2) - (ballRadius / 2),
          caretWidth: widget.caretWidth,
          ballRadius: ballRadius,
        ),
      ),
    );
  }
}
