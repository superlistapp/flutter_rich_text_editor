import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_composer.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/default_editor/document_scrollable.dart';
import 'package:super_editor/src/document_operations/selection_operations.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/multi_tap_gesture.dart';

import 'reader_context.dart';

/// Governs mouse gesture interaction with a read-only document, such as scrolling
/// a document with a scroll wheel and tap-and-dragging to create an expanded selection.

/// Document gesture interactor that's designed for read-only mouse input,
/// e.g., drag to select, and mouse wheel to scroll.
///
///  - selects content on double, and triple taps
///  - selects content on drag, after single, double, or triple tap
///  - scrolls with the mouse wheel
///  - automatically scrolls up or down when the user drags near
///    a boundary
///
/// The primary difference between a read-only mouse interactor, and an
/// editing mouse interactor, is that read-only documents don't support
/// collapsed selections, i.e., caret display. When the user taps on
/// a read-only document, nothing happens. The user must drag an expanded
/// selection, or double/triple tap to select content.
class ReadOnlyDocumentMouseInteractor extends StatefulWidget {
  const ReadOnlyDocumentMouseInteractor({
    Key? key,
    this.focusNode,
    required this.readerContext,
    required this.autoScroller,
    this.showDebugPaint = false,
    required this.child,
  }) : super(key: key);

  final FocusNode? focusNode;

  /// Service locator for document dependencies.
  final ReaderContext readerContext;

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

  late StreamSubscription<DocumentSelectionChange> _selectionSubscription;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _selectionSubscription = widget.readerContext.composer.selectionChanges.listen(_onSelectionChange);
    widget.autoScroller.addListener(_updateDragSelection);
  }

  @override
  void didUpdateWidget(ReadOnlyDocumentMouseInteractor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _focusNode = widget.focusNode ?? FocusNode();
    }
    if (widget.readerContext.composer != oldWidget.readerContext.composer) {
      _selectionSubscription.cancel();
      _selectionSubscription = widget.readerContext.composer.selectionChanges.listen(_onSelectionChange);
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
    _selectionSubscription.cancel();
    widget.autoScroller.removeListener(_updateDragSelection);
    super.dispose();
  }

  /// Returns the layout for the current document, which answers questions
  /// about the locations and sizes of visual components within the layout.
  DocumentLayout get _docLayout => widget.readerContext.documentLayout;

  Offset _getDocOffsetFromGlobalOffset(Offset globalOffset) {
    return _docLayout.getDocumentOffsetFromAncestorOffset(globalOffset);
  }

  bool get _isShiftPressed => (RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
      RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.shiftRight) ||
      RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.shift));

  void _onSelectionChange(DocumentSelectionChange selectionChange) {
    if (mounted) {
      // Use a post-frame callback to "ensure selection extent is visible"
      // so that any pending visual document changes can happen before
      // attempting to calculate the visual position of the selection extent.
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        readerGesturesLog.finer("Ensuring selection extent is visible because the doc selection changed");

        final globalExtentRect = _getSelectionExtentAsGlobalRect();
        if (globalExtentRect != null) {
          widget.autoScroller.ensureGlobalRectIsVisible(globalExtentRect);
        }
      });
    }
  }

  Rect? _getSelectionExtentAsGlobalRect() {
    final selection = widget.readerContext.composer.selection;
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
      readerGesturesLog.warning(
          "Tried to ensure that position ${selection.extent} is visible on screen but no bounding box was returned for that position.");
      return null;
    }

    final globalTopLeft = _docLayout.getGlobalOffsetFromDocumentOffset(selectionExtentRectInDoc.topLeft);
    return Rect.fromLTWH(
        globalTopLeft.dx, globalTopLeft.dy, selectionExtentRectInDoc.width, selectionExtentRectInDoc.height);
  }

  void _onTapUp(TapUpDetails details) {
    readerGesturesLog.info("Tap up on document");
    final docOffset = _getDocOffsetFromGlobalOffset(details.globalPosition);
    readerGesturesLog.fine(" - document offset: $docOffset");
    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    readerGesturesLog.fine(" - tapped document position: $docPosition");

    _focusNode.requestFocus();

    if (docPosition == null) {
      readerGesturesLog.fine("No document content at ${details.globalPosition}.");
      widget.readerContext.composer.clearSelection();
      return;
    }

    final expandSelection = _isShiftPressed && widget.readerContext.composer.selection != null;
    if (!expandSelection) {
      // Read-only documents don't show carets. Therefore, we only care about
      // a tap when we're expanding an existing selection.
      widget.readerContext.composer.clearSelection();
      _selectionType = SelectionType.position;
      return;
    }

    final tappedComponent = _docLayout.getComponentByNodeId(docPosition.nodeId)!;
    if (!tappedComponent.isVisualSelectionSupported()) {
      moveToNearestSelectableComponent(
        widget.readerContext.document,
        widget.readerContext.documentLayout,
        widget.readerContext.composer,
        docPosition.nodeId,
        tappedComponent,
      );
      return;
    }

    // The user tapped while pressing shift and there's an existing
    // selection. Move the extent of the selection to where the user tapped.
    widget.readerContext.composer.setSelection(widget.readerContext.composer.selection!.copyWith(
      extent: docPosition,
    ));
  }

  void _onDoubleTapDown(TapDownDetails details) {
    readerGesturesLog.info("Double tap down on document");
    final docOffset = _getDocOffsetFromGlobalOffset(details.globalPosition);
    readerGesturesLog.fine(" - document offset: $docOffset");
    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    readerGesturesLog.fine(" - tapped document position: $docPosition");

    final tappedComponent = docPosition != null ? _docLayout.getComponentByNodeId(docPosition.nodeId)! : null;
    if (tappedComponent != null && !tappedComponent.isVisualSelectionSupported()) {
      // The user double tapped on a component that should never display itself
      // as selected. Therefore, we ignore this double-tap.
      return;
    }

    _selectionType = SelectionType.word;
    widget.readerContext.composer.clearSelection();

    if (docPosition != null) {
      bool didSelectContent = selectWordAt(
        docPosition: docPosition,
        docLayout: _docLayout,
        composer: widget.readerContext.composer,
      );

      if (!didSelectContent) {
        didSelectContent = selectBlockAt(docPosition, widget.readerContext.composer);
      }

      if (!didSelectContent) {
        // Place the document selection at the location where the
        // user tapped.
        _selectPosition(docPosition);
      }
    }

    _focusNode.requestFocus();
  }

  void _onDoubleTap() {
    readerGesturesLog.info("Double tap up on document");
    _selectionType = SelectionType.position;
  }

  void _onTripleTapDown(TapDownDetails details) {
    readerGesturesLog.info("Triple down down on document");
    final docOffset = _getDocOffsetFromGlobalOffset(details.globalPosition);
    readerGesturesLog.fine(" - document offset: $docOffset");
    final docPosition = _docLayout.getDocumentPositionNearestToOffset(docOffset);
    readerGesturesLog.fine(" - tapped document position: $docPosition");

    if (docPosition != null) {
      final tappedComponent = _docLayout.getComponentByNodeId(docPosition.nodeId)!;
      if (!tappedComponent.isVisualSelectionSupported()) {
        return;
      }
    }

    _selectionType = SelectionType.paragraph;
    widget.readerContext.composer.clearSelection();

    if (docPosition != null) {
      final didSelectParagraph = selectParagraphAt(
        docPosition: docPosition,
        docLayout: _docLayout,
        composer: widget.readerContext.composer,
      );
      if (!didSelectParagraph) {
        // Place the document selection at the location where the
        // user tapped.
        _selectPosition(docPosition);
      }
    }

    _focusNode.requestFocus();
  }

  void _onTripleTap() {
    readerGesturesLog.info("Triple tap up on document");
    _selectionType = SelectionType.position;
  }

  void _selectPosition(DocumentPosition position) {
    readerGesturesLog.fine("Setting document selection to $position");
    widget.readerContext.composer.setSelection(DocumentSelection.collapsed(
      position: position,
    ));
  }

  void _onPanStart(DragStartDetails details) {
    readerGesturesLog.info("Pan start on document, global offset: ${details.globalPosition}, device: ${details.kind}");

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
      readerGesturesLog.fine("Shift isn't pressed. Clearing any existing selection before panning.");
      widget.readerContext.composer.clearSelection();
    }

    _focusNode.requestFocus();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    readerGesturesLog
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
    readerGesturesLog.info("Pan end on document, device: $_panGestureDevice");

    if (_panGestureDevice == PointerDeviceKind.trackpad) {
      // The user ended a pan gesture with two fingers on a trackpad.
      // We already scrolled the document.
      return;
    }
    _onDragEnd();
  }

  void _onPanCancel() {
    readerGesturesLog.info("Pan cancel on document");
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

  /// We prevent SingleChildScrollView from processing mouse events because
  /// it scrolls by drag by default, which we don't want. However, we do
  /// still want mouse scrolling. This method re-implements a primitive
  /// form of mouse scrolling.
  void _scrollOnMouseWheel(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _scrollVertically(event.scrollDelta.dy);
    }
  }

  /// Scrolls the document vertically by [delta] pixels.
  void _scrollVertically(double delta) {
    widget.autoScroller.jumpBy(delta);
    _updateDragSelection();
  }

  void _updateDragSelection() {
    if (_dragEndGlobal == null) {
      // User isn't dragging. No need to update drag selection.
      return;
    }

    final dragStartInDoc =
        _getDocOffsetFromGlobalOffset(_dragStartGlobal!) + Offset(0, widget.autoScroller.deltaWhileAutoScrolling);
    final dragEndInDoc = _getDocOffsetFromGlobalOffset(_dragEndGlobal!);
    readerGesturesLog.finest(
      '''
Updating drag selection:
 - drag start in doc: $dragStartInDoc
 - drag end in doc: $dragEndInDoc''',
    );

    selectRegion(
      documentLayout: _docLayout,
      baseOffsetInDocument: dragStartInDoc,
      extentOffsetInDocument: dragEndInDoc,
      selectionType: _selectionType,
      expandSelection: _expandSelectionDuringDrag,
      composer: widget.readerContext.composer,
    );

    if (widget.showDebugPaint) {
      setState(() {
        // Repaint the debug UI.
      });
    }
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
