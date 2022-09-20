import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_layout.dart';

import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/default_editor/document_scrollable.dart';
import 'package:super_editor/src/default_editor/selection_upstream_downstream.dart';
import 'package:super_editor/src/default_editor/text_tools.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/multi_tap_gesture.dart';

import 'super_document.dart';

/// Governs mouse gesture interaction with a read-only document, such as scrolling
/// a document with a scroll wheel and tap-and-dragging to create an expanded selection.

/// Document gesture interactor that's designed for mouse input, e.g.,
/// drag to select, and mouse wheel to scroll.
///
///  - selects content on double, and triple taps
///  - selects content on drag, after single, double, or triple tap
///  - scrolls with the mouse wheel
///  - automatically scrolls up or down when the user drags near
///    a boundary
class ReadOnlyDocumentMouseInteractor extends StatefulWidget {
  const ReadOnlyDocumentMouseInteractor({
    Key? key,
    this.focusNode,
    required this.documentContext,
    required this.autoScroller,
    this.showDebugPaint = false,
    required this.child,
  }) : super(key: key);

  final FocusNode? focusNode;

  /// Service locator for document dependencies.
  final DocumentContext documentContext;

  /// Auto-scrolling delegate.
  final AutoScrollController autoScroller;

  /// Paints some extra visual ornamentation to help with
  /// debugging, when `true`.
  final bool showDebugPaint;

  /// The document to display within this [ReadOnlyDocumentMouseInteractor].
  final Widget child;

  @override
  State createState() => _ReadOnlyDocumentMouseInteractorState();
}

class _ReadOnlyDocumentMouseInteractorState extends State<ReadOnlyDocumentMouseInteractor>
    with SingleTickerProviderStateMixin {
  final _documentWrapperKey = GlobalKey();

  late FocusNode _focusNode;

  // Tracks user drag gestures for selection purposes.
  SelectionType _selectionType = SelectionType.position;
  Offset? _dragStartGlobal;
  Offset? _dragEndGlobal;
  bool _expandSelectionDuringDrag = false;

  /// Holds which kind of device started a pan gesture, e.g., a mouse or a trackpad.
  PointerDeviceKind? _panGestureDevice;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    widget.documentContext.selection.addListener(_onSelectionChange);
    widget.autoScroller.addListener(_updateDragSelection);
  }

  @override
  void didUpdateWidget(ReadOnlyDocumentMouseInteractor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _focusNode = widget.focusNode ?? FocusNode();
    }
    if (widget.documentContext.selection != oldWidget.documentContext.selection) {
      oldWidget.documentContext.selection.removeListener(_onSelectionChange);
      widget.documentContext.selection.addListener(_onSelectionChange);
    }
    if (widget.autoScroller != oldWidget.autoScroller) {
      oldWidget.autoScroller.removeListener(_updateDragSelection);
      widget.autoScroller.addListener(_updateDragSelection);
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    widget.documentContext.selection.removeListener(_onSelectionChange);
    widget.autoScroller.removeListener(_updateDragSelection);
    super.dispose();
  }

  /// Returns the layout for the current document, which answers questions
  /// about the locations and sizes of visual components within the layout.
  DocumentLayout get _docLayout => widget.documentContext.documentLayout;

  Offset _getDocOffsetFromGlobalOffset(Offset globalOffset) {
    return _docLayout.getDocumentOffsetFromAncestorOffset(globalOffset);
  }

  bool get _isShiftPressed =>
      (RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
          RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.shiftRight) ||
          RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.shift)) &&
      // TODO: this condition doesn't belong here. Move it to where it applies
      widget.documentContext.selection.value != null;

  void _onSelectionChange() {
    if (mounted) {
      // Use a post-frame callback to "ensure selection extent is visible"
      // so that any pending visual document changes can happen before
      // attempting to calculate the visual position of the selection extent.
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        editorGesturesLog.finer("Ensuring selection extent is visible because the doc selection changed");

        final globalExtentRect = _getSelectionExtentAsGlobalRect();
        if (globalExtentRect != null) {
          widget.autoScroller.ensureGlobalRectIsVisible(globalExtentRect);
        }
      });
    }
  }

  Rect? _getSelectionExtentAsGlobalRect() {
    final selection = widget.documentContext.selection.value;
    if (selection == null) {
      return null;
    }

    // The reason that a Rect is used instead of an Offset is
    // because things like Images and Horizontal Rules don't have
    // a clear selection offset. They are either entirely selected,
    // or not selected at all.
    final selectionExtentRectInDoc = _docLayout.getRectForPosition(
      selection.extent,
    );
    if (selectionExtentRectInDoc == null) {
      editorGesturesLog.warning(
          "Tried to ensure that position ${selection.extent} is visible on screen but no bounding box was returned for that position.");
      return null;
    }

    final globalTopLeft = _docLayout.getGlobalOffsetFromDocumentOffset(selectionExtentRectInDoc.topLeft);
    return Rect.fromLTWH(
        globalTopLeft.dx, globalTopLeft.dy, selectionExtentRectInDoc.width, selectionExtentRectInDoc.height);
  }

  void _onTapUp(TapUpDetails details) {
    editorGesturesLog.info("Tap up on document");
    final docOffset = _getDocOffsetFromGlobalOffset(details.globalPosition);
    editorGesturesLog.fine(" - document offset: $docOffset");
    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    editorGesturesLog.fine(" - tapped document position: $docPosition");

    _focusNode.requestFocus();

    if (docPosition == null) {
      editorGesturesLog.fine("No document content at ${details.globalPosition}.");
      _clearSelection();
      return;
    }

    final expandSelection = _isShiftPressed && widget.documentContext.selection.value != null;
    if (!expandSelection) {
      // Read-only documents don't show carets. Therefore, we only care about
      // a tap when we're expanding an existing selection.
      _clearSelection();
      _selectionType = SelectionType.position;
      return;
    }

    final tappedComponent = _docLayout.getComponentByNodeId(docPosition.nodeId)!;
    if (!tappedComponent.isVisualSelectionSupported()) {
      _moveToNearestSelectableComponent(
        docPosition.nodeId,
        tappedComponent,
      );
      return;
    }

    // The user tapped while pressing shift and there's an existing
    // selection. Move the extent of the selection to where the user tapped.
    widget.documentContext.selection.value = widget.documentContext.selection.value!.copyWith(
      extent: docPosition,
    );
  }

  void _onDoubleTapDown(TapDownDetails details) {
    editorGesturesLog.info("Double tap down on document");
    final docOffset = _getDocOffsetFromGlobalOffset(details.globalPosition);
    editorGesturesLog.fine(" - document offset: $docOffset");
    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    editorGesturesLog.fine(" - tapped document position: $docPosition");

    final tappedComponent = docPosition != null ? _docLayout.getComponentByNodeId(docPosition.nodeId)! : null;
    if (tappedComponent != null && !tappedComponent.isVisualSelectionSupported()) {
      // The user double tapped on a component that should never display itself
      // as selected. Therefore, we ignore this double-tap.
      return;
    }

    _selectionType = SelectionType.word;
    _clearSelection();

    if (docPosition != null) {
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
    }

    _focusNode.requestFocus();
  }

  bool _selectWordAt({
    required DocumentPosition docPosition,
    required DocumentLayout docLayout,
  }) {
    final newSelection = getWordSelection(docPosition: docPosition, docLayout: docLayout);
    if (newSelection != null) {
      widget.documentContext.selection.value = newSelection;
      return true;
    } else {
      return false;
    }
  }

  bool _selectBlockAt(DocumentPosition position) {
    if (position.nodePosition is! UpstreamDownstreamNodePosition) {
      return false;
    }

    widget.documentContext.selection.value = DocumentSelection(
      base: DocumentPosition(
        nodeId: position.nodeId,
        nodePosition: const UpstreamDownstreamNodePosition.upstream(),
      ),
      extent: DocumentPosition(
        nodeId: position.nodeId,
        nodePosition: const UpstreamDownstreamNodePosition.downstream(),
      ),
    );

    return true;
  }

  void _onDoubleTap() {
    editorGesturesLog.info("Double tap up on document");
    _selectionType = SelectionType.position;
  }

  void _onTripleTapDown(TapDownDetails details) {
    editorGesturesLog.info("Triple down down on document");
    final docOffset = _getDocOffsetFromGlobalOffset(details.globalPosition);
    editorGesturesLog.fine(" - document offset: $docOffset");
    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    editorGesturesLog.fine(" - tapped document position: $docPosition");

    if (docPosition != null) {
      final tappedComponent = _docLayout.getComponentByNodeId(docPosition.nodeId)!;
      if (!tappedComponent.isVisualSelectionSupported()) {
        return;
      }
    }

    _selectionType = SelectionType.paragraph;
    _clearSelection();

    if (docPosition != null) {
      final didSelectParagraph = _selectParagraphAt(
        docPosition: docPosition,
        docLayout: _docLayout,
      );
      if (!didSelectParagraph) {
        // Place the document selection at the location where the
        // user tapped.
        _selectPosition(docPosition);
      }
    }

    _focusNode.requestFocus();
  }

  bool _selectParagraphAt({
    required DocumentPosition docPosition,
    required DocumentLayout docLayout,
  }) {
    final newSelection = getParagraphSelection(docPosition: docPosition, docLayout: docLayout);
    if (newSelection != null) {
      widget.documentContext.selection.value = newSelection;
      return true;
    } else {
      return false;
    }
  }

  void _onTripleTap() {
    editorGesturesLog.info("Triple tap up on document");
    _selectionType = SelectionType.position;
  }

  void _selectPosition(DocumentPosition position) {
    editorGesturesLog.fine("Setting document selection to $position");
    widget.documentContext.selection.value = DocumentSelection.collapsed(
      position: position,
    );
  }

  void _onPanStart(DragStartDetails details) {
    editorGesturesLog.info("Pan start on document, global offset: ${details.globalPosition}, device: ${details.kind}");

    _panGestureDevice = details.kind;

    if (_panGestureDevice == PointerDeviceKind.trackpad) {
      // After flutter 3.3, dragging with two fingers on a trackpad triggers a pan gesture.
      // This gesture should scroll the document and keep the selection unchanged.
      return;
    }

    _dragStartGlobal = details.globalPosition;

    widget.autoScroller.enableAutoScrolling();

    if (_isShiftPressed) {
      _expandSelectionDuringDrag = true;
    }

    if (!_isShiftPressed) {
      // Only clear the selection if the user isn't pressing shift. Shift is
      // used to expand the current selection, not replace it.
      editorGesturesLog.fine("Shift isn't pressed. Clearing any existing selection before panning.");
      _clearSelection();
    }

    _focusNode.requestFocus();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    editorGesturesLog
        .info("Pan update on document, global offset: ${details.globalPosition}, device: $_panGestureDevice");

    if (_panGestureDevice == PointerDeviceKind.trackpad) {
      // The user dragged using two fingers on a trackpad.
      // Scroll the document and keep the selection unchanged.
      // We multiply by -1 because the scroll should be in the opposite
      // direction of the drag, e.g., dragging up on a trackpad scrolls
      // the document to downstream direction.
      _scrollVertically(details.delta.dy * -1);
      return;
    }

    setState(() {
      _dragEndGlobal = details.globalPosition;

      _updateDragSelection();

      widget.autoScroller.setGlobalAutoScrollRegion(
        Rect.fromLTWH(_dragEndGlobal!.dx, _dragEndGlobal!.dy, 1, 1),
      );
    });
  }

  void _onPanEnd(DragEndDetails details) {
    editorGesturesLog.info("Pan end on document, device: $_panGestureDevice");

    if (_panGestureDevice == PointerDeviceKind.trackpad) {
      // The user ended a pan gesture with two fingers on a trackpad.
      // We already scrolled the document.
      return;
    }
    _onDragEnd();
  }

  void _onPanCancel() {
    editorGesturesLog.info("Pan cancel on document");
    _onDragEnd();
  }

  void _onDragEnd() {
    setState(() {
      _dragStartGlobal = null;
      _dragEndGlobal = null;
      _expandSelectionDuringDrag = false;
    });

    widget.autoScroller.disableAutoScrolling();
  }

  /// Scrolls the document vertically by [delta] pixels.
  void _scrollVertically(double delta) {
    widget.autoScroller.jumpBy(delta);
    _updateDragSelection();
  }

  /// We prevent SingleChildScrollView from processing mouse events because
  /// it scrolls by drag by default, which we don't want. However, we do
  /// still want mouse scrolling. This method re-implements a primitive
  /// form of mouse scrolling.
  void _scrollOnMouseWheel(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _scrollVertically(event.scrollDelta.dy);
    }
  }

  void _updateDragSelection() {
    if (_dragEndGlobal == null) {
      // User isn't dragging. No need to update drag selection.
      return;
    }

    final dragStartInDoc =
        _getDocOffsetFromGlobalOffset(_dragStartGlobal!) + Offset(0, widget.autoScroller.deltaWhileAutoScrolling);
    final dragEndInDoc = _getDocOffsetFromGlobalOffset(_dragEndGlobal!);
    editorGesturesLog.finest(
      '''
Updating drag selection:
 - drag start in doc: $dragStartInDoc
 - drag end in doc: $dragEndInDoc''',
    );

    _selectRegion(
      documentLayout: _docLayout,
      baseOffsetInDocument: dragStartInDoc,
      extentOffsetInDocument: dragEndInDoc,
      selectionType: _selectionType,
      expandSelection: _expandSelectionDuringDrag,
    );

    if (widget.showDebugPaint) {
      setState(() {
        // Repaint the debug UI.
      });
    }
  }

  void _selectRegion({
    required DocumentLayout documentLayout,
    required Offset baseOffsetInDocument,
    required Offset extentOffsetInDocument,
    required SelectionType selectionType,
    bool expandSelection = false,
  }) {
    editorGesturesLog.info("Selecting region with selection mode: $selectionType");
    DocumentSelection? selection = documentLayout.getDocumentSelectionInRegion(
      baseOffsetInDocument,
      extentOffsetInDocument,
    );
    DocumentPosition? basePosition = selection?.base;
    DocumentPosition? extentPosition = selection?.extent;
    editorGesturesLog.fine(" - base: $basePosition, extent: $extentPosition");

    if (basePosition == null || extentPosition == null) {
      widget.documentContext.selection.value = null;
      return;
    }

    if (selectionType == SelectionType.paragraph) {
      final baseParagraphSelection = getParagraphSelection(
        docPosition: basePosition,
        docLayout: documentLayout,
      );
      if (baseParagraphSelection == null) {
        widget.documentContext.selection.value = null;
        return;
      }
      basePosition = baseOffsetInDocument.dy < extentOffsetInDocument.dy
          ? baseParagraphSelection.base
          : baseParagraphSelection.extent;

      final extentParagraphSelection = getParagraphSelection(
        docPosition: extentPosition,
        docLayout: documentLayout,
      );
      if (extentParagraphSelection == null) {
        widget.documentContext.selection.value = null;
        return;
      }
      extentPosition = baseOffsetInDocument.dy < extentOffsetInDocument.dy
          ? extentParagraphSelection.extent
          : extentParagraphSelection.base;
    } else if (selectionType == SelectionType.word) {
      final baseWordSelection = getWordSelection(
        docPosition: basePosition,
        docLayout: documentLayout,
      );
      if (baseWordSelection == null) {
        widget.documentContext.selection.value = null;
        return;
      }
      basePosition = baseWordSelection.base;

      final extentWordSelection = getWordSelection(
        docPosition: extentPosition,
        docLayout: documentLayout,
      );
      if (extentWordSelection == null) {
        widget.documentContext.selection.value = null;
        return;
      }
      extentPosition = extentWordSelection.extent;
    }

    widget.documentContext.selection.value = (DocumentSelection(
      // If desired, expand the selection instead of replacing it.
      base: expandSelection ? widget.documentContext.selection.value?.base ?? basePosition : basePosition,
      extent: extentPosition,
    ));
    editorGesturesLog.fine("Selected region: ${widget.documentContext.selection.value}");
  }

  void _clearSelection() {
    editorGesturesLog.fine("Clearing document selection");
    widget.documentContext.selection.value = null;
  }

  void _moveToNearestSelectableComponent(
    String nodeId,
    DocumentComponent component,
  ) {
    // TODO: this was taken from CommonOps. We don't have CommonOps in this
    // interactor, because it's for read-only documents. Selection operations
    // should probably be moved to something outside of CommonOps
    DocumentNode startingNode = widget.documentContext.document.getNodeById(nodeId)!;
    String? newNodeId;
    NodePosition? newPosition;

    // Try to find a new selection downstream.
    final downstreamNode = _getDownstreamSelectableNodeAfter(startingNode);
    if (downstreamNode != null) {
      newNodeId = downstreamNode.id;
      final nextComponent = widget.documentContext.documentLayout.getComponentByNodeId(newNodeId);
      newPosition = nextComponent?.getBeginningPosition();
    }

    // Try to find a new selection upstream.
    if (newPosition == null) {
      final upstreamNode = _getUpstreamSelectableNodeBefore(startingNode);
      if (upstreamNode != null) {
        newNodeId = upstreamNode.id;
        final previousComponent = widget.documentContext.documentLayout.getComponentByNodeId(newNodeId);
        newPosition = previousComponent?.getBeginningPosition();
      }
    }

    if (newNodeId == null || newPosition == null) {
      return;
    }

    widget.documentContext.selection.value = widget.documentContext.selection.value!.expandTo(
      DocumentPosition(
        nodeId: newNodeId,
        nodePosition: newPosition,
      ),
    );
  }

  /// Returns the first [DocumentNode] before [startingNode] whose
  /// [DocumentComponent] is visually selectable.
  DocumentNode? _getUpstreamSelectableNodeBefore(DocumentNode startingNode) {
    bool foundSelectableNode = false;
    DocumentNode prevNode = startingNode;
    DocumentNode? selectableNode;
    do {
      selectableNode = widget.documentContext.document.getNodeBefore(prevNode);

      if (selectableNode != null) {
        final nextComponent = widget.documentContext.documentLayout.getComponentByNodeId(selectableNode.id);
        if (nextComponent != null) {
          foundSelectableNode = nextComponent.isVisualSelectionSupported();
        }
        prevNode = selectableNode;
      }
    } while (!foundSelectableNode && selectableNode != null);

    return selectableNode;
  }

  /// Returns the first [DocumentNode] after [startingNode] whose
  /// [DocumentComponent] is visually selectable.
  DocumentNode? _getDownstreamSelectableNodeAfter(DocumentNode startingNode) {
    bool foundSelectableNode = false;
    DocumentNode prevNode = startingNode;
    DocumentNode? selectableNode;
    do {
      selectableNode = widget.documentContext.document.getNodeAfter(prevNode);

      if (selectableNode != null) {
        final nextComponent = widget.documentContext.documentLayout.getComponentByNodeId(selectableNode.id);
        if (nextComponent != null) {
          foundSelectableNode = nextComponent.isVisualSelectionSupported();
        }
        prevNode = selectableNode;
      }
    } while (!foundSelectableNode && selectableNode != null);

    return selectableNode;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _scrollOnMouseWheel,
      child: _buildCursorStyle(
        child: _buildGestureInput(
          child: _buildDocumentContainer(
            document: widget.child,
          ),
        ),
      ),
    );
  }

  Widget _buildCursorStyle({
    required Widget child,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: child,
    );
  }

  Widget _buildGestureInput({
    required Widget child,
  }) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        TapSequenceGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapSequenceGestureRecognizer>(
          () => TapSequenceGestureRecognizer(),
          (TapSequenceGestureRecognizer recognizer) {
            recognizer
              ..onTapUp = _onTapUp
              ..onDoubleTapDown = _onDoubleTapDown
              ..onDoubleTap = _onDoubleTap
              ..onTripleTapDown = _onTripleTapDown
              ..onTripleTap = _onTripleTap;
          },
        ),
        PanGestureRecognizer: GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
          () => PanGestureRecognizer(),
          (PanGestureRecognizer recognizer) {
            recognizer
              ..onStart = _onPanStart
              ..onUpdate = _onPanUpdate
              ..onEnd = _onPanEnd
              ..onCancel = _onPanCancel;
          },
        ),
      },
      child: child,
    );
  }

  Widget _buildDocumentContainer({
    required Widget document,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: Stack(
        children: [
          SizedBox(
            key: _documentWrapperKey,
            child: document,
          ),
          if (widget.showDebugPaint) //
            ..._buildDebugPaintInDocSpace(),
        ],
      ),
    );
  }

  List<Widget> _buildDebugPaintInDocSpace() {
    final dragStartInDoc = _dragStartGlobal != null
        ? _getDocOffsetFromGlobalOffset(_dragStartGlobal!) + Offset(0, widget.autoScroller.deltaWhileAutoScrolling)
        : null;
    final dragEndInDoc = _dragEndGlobal != null ? _getDocOffsetFromGlobalOffset(_dragEndGlobal!) : null;

    return [
      if (dragStartInDoc != null)
        Positioned(
          left: dragStartInDoc.dx,
          top: dragStartInDoc.dy,
          child: FractionalTranslation(
            translation: const Offset(-0.5, -0.5),
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0088FF),
              ),
            ),
          ),
        ),
      if (dragEndInDoc != null)
        Positioned(
          left: dragEndInDoc.dx,
          top: dragEndInDoc.dy,
          child: FractionalTranslation(
            translation: const Offset(-0.5, -0.5),
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0088FF),
              ),
            ),
          ),
        ),
      if (dragStartInDoc != null && dragEndInDoc != null)
        Positioned(
          left: min(dragStartInDoc.dx, dragEndInDoc.dx),
          top: min(dragStartInDoc.dy, dragEndInDoc.dy),
          width: (dragEndInDoc.dx - dragStartInDoc.dx).abs(),
          height: (dragEndInDoc.dy - dragStartInDoc.dy).abs(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF0088FF), width: 3),
            ),
          ),
        ),
    ];
  }
}

enum SelectionType {
  position,
  word,
  paragraph,
}

/// Paints a rectangle border around the given `selectionRect`.
class DragRectanglePainter extends CustomPainter {
  DragRectanglePainter({
    this.selectionRect,
    Listenable? repaint,
  }) : super(repaint: repaint);

  final Rect? selectionRect;
  final Paint _selectionPaint = Paint()
    ..color = const Color(0xFFFF0000)
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    if (selectionRect != null) {
      canvas.drawRect(selectionRect!, _selectionPaint);
    }
  }

  @override
  bool shouldRepaint(DragRectanglePainter oldDelegate) {
    return oldDelegate.selectionRect != selectionRect;
  }
}
