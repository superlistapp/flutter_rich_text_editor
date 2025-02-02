import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/documents/document_scroller.dart';
import 'package:super_editor/src/infrastructure/flutter/build_context.dart';
import 'package:super_editor/src/infrastructure/flutter/flutter_scheduler.dart';
import 'package:super_editor/src/infrastructure/scrolling_diagnostics/_scrolling_minimap.dart';

import '../infrastructure/document_gestures.dart';

/// Scroller for a document.
///
/// If there's an ancestor [Scrollable] in the widget tree, then this
/// [DocumentScrollable] controls the ancestor [Scrollable]. Otherwise,
/// this [DocumentScrollable] builds a [Scrollable] into its sub-tree
/// and controls that [Scrollable].
///
/// Aside from possibly adding a [Scrollable] to the widget tree, a
/// [DocumentScrollable] primarily exists to implement auto-scrolling.
/// A [DocumentScrollable] attaches itself to a given [autoScroller].
/// The given [autoScroller] should also be given to some associated
/// gesture input system, which would tell the [autoScroller] when to
/// scroll.
class DocumentScrollable extends StatefulWidget {
  const DocumentScrollable({
    Key? key,
    required this.autoScroller,
    this.scrollController,
    this.scroller,
    this.scrollingMinimapId,
    this.showDebugPaint = false,
    required this.shrinkWrap,
    required this.child,
  }) : super(key: key);

  /// Controller that adjusts the scroll offset of this [DocumentScrollable].
  final AutoScrollController autoScroller;

  /// The [ScrollController] that governs this [DocumentScrollable]'s scroll
  /// offset.
  ///
  /// `scrollController` is not used if this `SuperEditor` has an ancestor
  /// `Scrollable`.
  final ScrollController? scrollController;

  /// A [DocumentScroller], to which this scrollable attaches itself, so
  /// that external actors, such as keyboard handlers, can query and change
  /// the scroll offset.
  final DocumentScroller? scroller;

  /// ID that this widget's scrolling system registers with an ancestor
  /// [ScrollingMinimaps] to report scrolling diagnostics for debugging.
  final String? scrollingMinimapId;

  /// Paints some extra visual ornamentation to help with
  /// debugging, when `true`.
  final bool showDebugPaint;

  /// This widget's child, which should include a document.
  final Widget child;

  /// Whether to shrink wrap the [CustomScrollView] that's used to host
  /// the editor content. Only used when there's no ancestor [Scrollable].
  final bool shrinkWrap;

  @override
  State<DocumentScrollable> createState() => _DocumentScrollableState();
}

class _DocumentScrollableState extends State<DocumentScrollable> with SingleTickerProviderStateMixin {
  // The ScrollController that's used when we install our own Scrollable.
  late ScrollController _scrollController;
  // The ScrollPosition used when there's an ancestor Scrollable.
  ScrollPosition? _ancestorScrollPosition;

  ScrollableInstrumentation? _debugInstrumentation;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();

    onNextFrame((_) {
      // Wait until the next frame to attach to auto-scroller because
      // our ScrollController isn't attached to the Scrollable, yet.
      widget.autoScroller.attachScrollable(
        this,
        () => _viewport,
        () => _scrollPosition,
      );

      widget.scroller?.attach(_scrollPosition);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // If we were given a scrollingMinimapId, it means our client wants us
    // to report our scrolling behavior for debugging. Register with an
    // ancestor ScrollingMinimaps.
    if (widget.scrollingMinimapId != null) {
      _debugInstrumentation = ScrollableInstrumentation()
        ..viewport.value = Scrollable.of(context).context
        ..scrollPosition.value = Scrollable.of(context).position;
      ScrollingMinimaps.of(context)?.put(widget.scrollingMinimapId!, _debugInstrumentation);
    }
  }

  @override
  void didUpdateWidget(DocumentScrollable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollController != oldWidget.scrollController) {
      if (oldWidget.scrollController == null) {
        _scrollController.dispose();
      }
      _scrollController = widget.scrollController ?? ScrollController();
    }

    if (widget.autoScroller != oldWidget.autoScroller) {
      oldWidget.autoScroller.detachScrollable();
      widget.autoScroller.attachScrollable(
        this,
        () => _viewport,
        () => _scrollPosition,
      );
    }

    if (widget.scroller != oldWidget.scroller) {
      oldWidget.scroller?.detach();
      widget.scroller?.attach(_scrollPosition);
    }
  }

  @override
  void dispose() {
    // TODO: Flutter says the following de-registration is unsafe. Where are we
    //       supposed to de-register from an ancestor?
    //       I'm commenting this out until we can find the right approach.
    // if (widget.scrollingMinimapId == null) {
    //   ScrollingMinimaps.of(context)?.put(widget.scrollingMinimapId!, null);
    // }

    if (widget.scrollController == null) {
      _scrollController.dispose();
    }

    widget.autoScroller.detachScrollable();

    widget.scroller?.detach();

    super.dispose();
  }

  /// Returns the `RenderBox` for the scrolling viewport.
  ///
  /// If this widget has an ancestor `Scrollable`, then the returned
  /// `RenderBox` belongs to that ancestor `Scrollable`.
  ///
  /// If this widget doesn't have an ancestor `Scrollable`, then this
  /// widget includes a `ScrollView` and this `State`'s render object
  /// is the viewport `RenderBox`.
  RenderBox get _viewport =>
      (context.findAncestorScrollableWithVerticalScroll?.context.findRenderObject() ?? context.findRenderObject())
          as RenderBox;

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
  ScrollPosition get _scrollPosition => _ancestorScrollPosition ?? _scrollController.position;

  @override
  Widget build(BuildContext context) {
    final ancestorScrollable = context.findAncestorScrollableWithVerticalScroll;
    _ancestorScrollPosition = ancestorScrollable?.position;
    if (ancestorScrollable != null) {
      return widget.child;
    }
    return Stack(
      children: [
        _buildScroller(
          child: widget.child,
        ),
        if (widget.showDebugPaint)
          ..._buildScrollingDebugPaint(
            includesScrollView: ancestorScrollable == null,
          ),
      ],
    );
  }

  Widget _buildScroller({
    required Widget child,
  }) {
    final scrollBehavior = ScrollConfiguration.of(context);
    return _maybeBuildScrollbar(
      behavior: scrollBehavior,
      child: ScrollConfiguration(
        behavior: scrollBehavior.copyWith(scrollbars: false),
        child: CustomScrollView(
          controller: _scrollController,
          shrinkWrap: widget.shrinkWrap,
          slivers: [child],
        ),
      ),
    );
  }

  Widget _maybeBuildScrollbar({
    required ScrollBehavior behavior,
    required Widget child,
  }) {
    // We allow apps to prevent the custom scrollbar from being added by
    // wrapping the editor with a `ScrollConfiguration` configured to not
    // display scrollbars. However, at this moment we can't query this
    // information from the BuildContext. As a workaround, we check whether
    // or not the buildScrollbar method returns a ScrollBar. If it doesn't,
    // this means the app doesn't want us to add our own ScrollBar.
    //
    // Change this after https://github.com/flutter/flutter/issues/141508 is solved.
    final maybeScrollBar = behavior.buildScrollbar(
      context,
      child,
      ScrollableDetails.vertical(controller: _scrollController),
    );
    if (maybeScrollBar == child) {
      // The scroll behavior is configured to NOT show scrollbars.
      return child;
    }

    return Scrollbar(
      controller: _scrollController,
      child: child,
    );
  }

  List<Widget> _buildScrollingDebugPaint({
    required bool includesScrollView,
  }) {
    return [
      if (includesScrollView) ...[
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: widget.autoScroller._gutter.leading.toDouble(),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0x440088FF),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: widget.autoScroller._gutter.trailing.toDouble(),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0x440088FF),
            ),
          ),
        ),
      ],
    ];
  }
}

/// Controller that governs a scroll offset, and auto-scrolls that offset
/// based on client requests.
class AutoScrollController with ChangeNotifier {
  AutoScrollController({
    double maxScrollSpeed = 20.0,
    this.selectionExtentAutoScrollBoundary = AxisOffset.zero,
    AxisOffset gutter = const AxisOffset(leading: 100, trailing: 100),
  })  : _maxScrollSpeed = maxScrollSpeed,
        _gutter = gutter;

  @override
  void dispose() {
    detachScrollable();
    super.dispose();
  }

  final double _maxScrollSpeed;

  /// The closest distance between the user's selection extent (caret)
  /// and the boundary of a document before the document auto-scrolls
  /// to make room for the caret.
  ///
  /// The default value is zero for the leading and trailing boundaries.
  /// This means that the top of the caret is permitted to touch the top
  /// of the scrolling region, but if the caret goes above the viewport
  /// boundary then the document scrolls up. If the caret goes below the
  /// bottom of the viewport boundary then the document scrolls down.
  ///
  /// A positive value for each boundary creates a buffer zone at each
  /// edge of the viewport. For example, a value of `100.0` would cause
  /// the document to auto-scroll whenever the caret sits within 100
  /// pixels of the edge of a document.
  ///
  /// A negative value allows the caret to move outside the viewport
  /// before auto-scrolling.
  ///
  /// See also:
  ///
  ///  * [dragAutoScrollBoundary], which defines how close the user's
  ///    drag gesture can get to the document boundary before auto-scrolling.
  final AxisOffset selectionExtentAutoScrollBoundary;

  /// The closest that the user's selection drag gesture can get to the
  /// document boundary before auto-scrolling.
  ///
  /// The default value is `100.0` pixels for both the leading and trailing
  /// edges.
  ///
  /// See also:
  ///
  ///  * [selectionExtentAutoScrollBoundary], which defines how close the
  ///    selection extent can get to the document boundary before
  ///    auto-scrolling. For example, when the user taps into some text, or
  ///    when the user presses up/down arrows to move the selection extent.
  final AxisOffset _gutter;

  Ticker? _ticker;
  ViewportResolver? _getViewport;
  ScrollPositionResolver? _getScrollPosition;

  bool _isAutoScrollingEnabled = false;
  double? _autoScrollingStartOffset;
  Rect? _autoScrollGlobalRegion;

  /// Returns `true` if this controller is attached a [Scrollable].
  bool get hasScrollable => _getScrollPosition != null;

  /// Returns the change to the scroll offset that's accumulated during
  /// the current auto-scroll behavior, or `0.0` if no auto-scroll
  /// is taking place.
  double get deltaWhileAutoScrolling => _deltaWhileAutoScrolling;
  double _deltaWhileAutoScrolling = 0;

  /// Starts controlling the scroll offset for a [Scrollable].
  ///
  /// A [viewportResolver] is needed so that auto-scroll regions can be
  /// compared to the boundary of the viewport.
  ///
  /// A [scrollPositionResolver] is needed so that this controller can adjust
  /// the scroll position.
  ///
  /// A [vsync] is needed to create a [Ticker], which is used to animate
  /// auto-scrolling.
  void attachScrollable(
      TickerProvider vsync, ViewportResolver viewportResolver, ScrollPositionResolver scrollPositionResolver) {
    detachScrollable();
    _ticker = vsync.createTicker(_onTick);
    _getViewport = viewportResolver;
    _getScrollPosition = scrollPositionResolver;

    // TODO: what if the scroll position changes? We'll be listening the old one...
    scrollPositionResolver().addListener(_onScrollPositionChange);
  }

  void _onScrollPositionChange() {
    // The scroll position changed. Probably because the position scrolled
    // up or down. Notify our listeners so that they can adjust the document
    // selection bounds or other related properties.
    //
    // The scroll position may trigger layout changes, notify the listeners
    // after the layout settles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasScrollable) {
        notifyListeners();
      }
    });
  }

  /// Stops controlling a [Scrollable] that was attached with [attachScrollable].
  void detachScrollable() {
    if (!hasScrollable) {
      return;
    }

    if (_ticker!.isActive) {
      _ticker!.stop();
    }
    _ticker!.dispose();
    _getViewport = null;
    _getScrollPosition = null;
  }

  /// Immediately changes the attached [Scrollable]'s scroll offset by [delta].
  void jumpBy(double delta) {
    if (_getScrollPosition == null) {
      editorScrollingLog.warning(
          "Tried to jump a document scrollable by $delta pixels, but no scrollable is attached to this controller.");
      return;
    }

    final scrollPosition = _getScrollPosition!();

    if (scrollPosition.maxScrollExtent == 0) {
      return;
    }

    scrollPosition.jumpTo(
      (scrollPosition.pixels + delta).clamp(0.0, scrollPosition.maxScrollExtent),
    );
  }

  /// Animates the scroll position like a ballistic particle with friction, beginning
  /// with the given [pixelsPerSecond] velocity.
  void goBallistic(double pixelsPerSecond) {
    final pos = _getScrollPosition?.call();
    if (pos == null) {
      // We're not attached to a scroll position. We can't go ballistic.
      return;
    }

    if (pos is ScrollPositionWithSingleContext) {
      if (pos.maxScrollExtent > 0) {
        pos.goBallistic(pixelsPerSecond);
      }
      pos.context.setIgnorePointer(false);
    }
  }

  /// Immediately stops scrolling animation/momentum.
  void goIdle() {
    final pos = _getScrollPosition?.call();
    if (pos == null) {
      // We're not attached to a scroll position. There's nothing to idle.
      return;
    }

    if (pos is ScrollPositionWithSingleContext) {
      if (pos.pixels > pos.minScrollExtent && pos.pixels < pos.maxScrollExtent) {
        pos.goIdle();
      }
    }
  }

  /// Immediately changes the attached [Scrollable]'s scroll offset so that all
  /// of the given [globalRegion] is visible.
  void ensureGlobalRectIsVisible(Rect globalRegion) {
    if (!hasScrollable) {
      return;
    }

    final scrollPosition = _getScrollPosition!();

    // Viewport might be our box, or an ancestor box if we're inside someone
    // else's Scrollable.
    final viewportBox = _getViewport!();
    final viewportTopLeft = viewportBox.globalToLocal(globalRegion.topLeft);
    final selectionExtentRectInViewport = Rect.fromLTWH(
      viewportTopLeft.dx,
      viewportTopLeft.dy,
      globalRegion.width,
      globalRegion.height,
    );

    final beyondTopExtent = min(selectionExtentRectInViewport.top, 0).abs();

    final beyondBottomExtent = max(selectionExtentRectInViewport.bottom - viewportBox.size.height, 0);

    editorScrollingLog.finest('Ensuring extent is visible.');
    editorScrollingLog.finest(' - viewport size: ${viewportBox.size}');
    editorScrollingLog.finest(' - scroll controller offset: ${scrollPosition.pixels}');
    editorScrollingLog.finest(' - selection extent rect in viewport: $selectionExtentRectInViewport');
    editorScrollingLog.finest(' - beyond top: $beyondTopExtent');
    editorScrollingLog.finest(' - beyond bottom: $beyondBottomExtent');

    late double newScrollPosition;
    if (beyondTopExtent > 0) {
      newScrollPosition = (scrollPosition.pixels - beyondTopExtent).clamp(0.0, scrollPosition.maxScrollExtent);
    } else if (beyondBottomExtent > 0) {
      newScrollPosition = (beyondBottomExtent + scrollPosition.pixels).clamp(0.0, scrollPosition.maxScrollExtent);
    } else {
      return;
    }

    editorScrollingLog.finest('Animating scroll offset to: $newScrollPosition');
    scrollPosition.animateTo(
      newScrollPosition,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  /// Starts auto-scrolling, when necessary.
  ///
  /// Auto-scrolling occurs when a given region gets close enough to the
  /// boundary of the viewport. That region of interest is set with
  /// [setGlobalAutoScrollRegion]. For example, when a user is dragging
  /// a selection, the dragging system should call [setGlobalAutoScrollRegion]
  /// every time the mouse moves.
  void enableAutoScrolling() {
    if (!hasScrollable) {
      // We don't have a scrollable to scroll.
      return;
    }

    if (_isAutoScrollingEnabled) {
      // Auto-scrolling is already enabled.
      return;
    }
    _isAutoScrollingEnabled = true;

    // We need to record the scroll offset at the beginning of
    // a drag for the case that this interactor is embedded
    // within an ancestor Scrollable. We need to use this value
    // to calculate a scroll delta on every scroll frame to
    // account for the fact that this interactor is moving within
    // the ancestor scrollable, despite the fact that the user's
    // finger/mouse position hasn't changed.
    _autoScrollingStartOffset = _getScrollPosition!().pixels;
    _deltaWhileAutoScrolling = 0;

    _ticker!.start();
  }

  /// Sets the [globalRegion] that should be considered for auto-scrolling.
  ///
  /// If the [globalRegion] is close enough to a viewport boundary, then
  /// auto-scrolling begins. If it's not, then auto-scrolling ends.
  void setGlobalAutoScrollRegion(Rect globalRegion) {
    if (!_isAutoScrollingEnabled) {
      return;
    }

    _autoScrollGlobalRegion = globalRegion;
  }

  /// Stops auto-scrolling.
  void disableAutoScrolling() {
    _isAutoScrollingEnabled = false;
    _autoScrollGlobalRegion = null;
    if (_ticker != null && _ticker!.isActive) {
      _ticker!.stop();
    }
  }

  void _onTick(Duration elapsedTime) {
    if (_autoScrollGlobalRegion == null) {
      // No one has given us an auto-scroll focal point. Nothing to do.
      return;
    }

    assert(hasScrollable);
    if (!hasScrollable) {
      // This shouldn't happen. The Ticker should have been stopped whenever
      // the scrollable was detached.
      _ticker!
        ..stop()
        ..dispose();
      return;
    }

    final viewport = _getViewport!();
    final globalViewportTopLeft = viewport.localToGlobal(Offset.zero);
    final globalAutoScrollRect = Rect.fromLTWH(
      globalViewportTopLeft.dx,
      globalViewportTopLeft.dy + _gutter.leading,
      viewport.size.width,
      viewport.size.height - _gutter.leading - _gutter.trailing,
    );

    if (_autoScrollGlobalRegion!.top < globalAutoScrollRect.top) {
      _scrollUp(globalAutoScrollRect.top - _autoScrollGlobalRegion!.top);
    } else if (_autoScrollGlobalRegion!.bottom > globalAutoScrollRect.bottom) {
      _scrollDown(_autoScrollGlobalRegion!.bottom - globalAutoScrollRect.bottom);
    }

    // We have to re-calculate the drag end in the doc (instead of
    // caching the value during the pan update) because the position
    // in the document is impacted by auto-scrolling behavior.
    _deltaWhileAutoScrolling = _autoScrollingStartOffset! - _getScrollPosition!().pixels;
  }

  void _scrollUp(double distanceInGutter) {
    final scrollPosition = _getScrollPosition!();
    if (scrollPosition.pixels <= 0) {
      editorScrollingLog.finest("Tried to scroll up but the scroll position is already at the top");
      return;
    }

    editorScrollingLog.finest("Scrolling up on tick");

    final speedPercent = distanceInGutter / _gutter.leading;
    final scrollAmount = lerpDouble(0, _maxScrollSpeed, speedPercent)!;

    editorScrollingLog.finest("Speed percent: $speedPercent");
    editorScrollingLog.finest("Jumping from ${scrollPosition.pixels} to ${scrollPosition.pixels + scrollAmount}");

    scrollPosition.jumpTo(scrollPosition.pixels - scrollAmount);
  }

  void _scrollDown(double distanceInGutter) {
    final scrollPosition = _getScrollPosition!();
    if (scrollPosition.pixels >= scrollPosition.maxScrollExtent) {
      editorScrollingLog.finest("Tried to scroll down but the scroll position is already beyond the max");
      return;
    }

    editorScrollingLog.finest("Scrolling down on tick");

    final speedPercent = distanceInGutter / _gutter.trailing;
    final scrollAmount = lerpDouble(0, _maxScrollSpeed, speedPercent)!;

    editorScrollingLog.finest("Speed percent: $speedPercent");
    editorScrollingLog.finest("Jumping from ${scrollPosition.pixels} to ${scrollPosition.pixels + scrollAmount}");

    scrollPosition.jumpTo(scrollPosition.pixels + scrollAmount);
  }
}

typedef ViewportResolver = RenderBox Function();

typedef ScrollPositionResolver = ScrollPosition Function();
