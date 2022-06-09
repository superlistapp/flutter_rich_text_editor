import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:super_text_layout/super_text_layout_logging.dart';

import 'text_layout.dart';

/// Displays text with a visual layer above the text, and a visual layer
/// beneath the text, which can be used to add text decorations, like
/// selections and carets.
///
/// To display a widget that includes standard text selection display,
/// see [SuperTextWithSelection].
///
/// The layers in a [SuperText] are built by provided [SuperTextLayerBuilder]s.
/// These builders are similar to a typical `WidgetBuilder`, except that
/// [SuperTextLayerBuilder]s are also given a reference to the [TextLayout]
/// within this [SuperText]. The layer builders can then use the [TextLayout] to
/// position widgets and paint coordinates near lines and characters in the text.
///
/// If you discover performance issues with your [SuperText], consider wrapping
/// the [SuperTextLayerBuilder] content with [RepaintBoundary]s, which might prevent
/// unnecessary repaints between your layers and the text content.
class SuperText extends StatefulWidget {
  const SuperText({
    Key? key,
    required this.richText,
    this.textAlign = TextAlign.left,
    this.textDirection = TextDirection.ltr,
    this.layerBeneathBuilder,
    this.layerAboveBuilder,
    this.foregroundIntoTextBlendMode,
    this.textIntoBackgroundBlendMode,
    this.debugTrackTextBuilds = false,
  })  : assert(foregroundIntoTextBlendMode == null || textIntoBackgroundBlendMode == null),
        super(key: key);

  /// The text to display in this [SuperText] widget.
  final InlineSpan richText;

  /// The alignment to use for [richText] display.
  final TextAlign textAlign;

  /// The text direction to use for [richText] display.
  final TextDirection textDirection;

  /// Builds a widget that appears beneath the text, e.g., to render text
  /// selection boxes.
  final SuperTextLayerBuilder? layerBeneathBuilder;

  /// Builds a widget that appears above the text, e.g., to render a caret.
  final SuperTextLayerBuilder? layerAboveBuilder;

  /// The blending mode used when painting the foreground layer on top of text.
  ///
  /// When using a blending mode, the foreground is blended only with the text.
  /// The background is moved to a separate layer. As such, if you provide a
  /// [foregroundIntoTextBlendMode], you shouldn't provide a [textIntoBackgroundBlendMode].
  final BlendMode? foregroundIntoTextBlendMode;

  /// The blending mode used when painting the text layer on top of the background.
  ///
  /// When using a blending mode, the text is blended only with the background.
  /// The foreground is moved to a separate layer. As such, if you provide a
  /// [textIntoBackgroundBlendMode], you shouldn't provide a [foregroundIntoTextBlendMode].
  final BlendMode? textIntoBackgroundBlendMode;

  /// Whether this [SuperText] widget should track the number of times it
  /// builds its inner rich text, so that tests can ensure the inner text
  /// is not rebuilt unnecessarily, due to text decorations.
  final bool debugTrackTextBuilds;

  @override
  State<SuperText> createState() => SuperTextState();
}

@visibleForTesting
class SuperTextState extends State<SuperText> with ProseTextBlock {
  final _textLayoutKey = GlobalKey();
  @override
  ProseTextLayout get textLayout => RenderSuperTextLayout.textLayoutFrom(_textLayoutKey)!;

  int _textBuildCount = 0;
  @visibleForTesting
  int get textBuildCount => _textBuildCount;

  RenderLayoutAwareParagraph? _paragraph;
  void _invalidateParagraph() => _paragraph = null;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      if (widget.debugTrackTextBuilds || SuperTextAnalytics.of(context)?.trackBuilds == true) {
        _textBuildCount += 1;
      }
    }

    return _SuperTextLayout(
      key: _textLayoutKey,
      state: this,
      text: LayoutAwareRichText(
        text: widget.richText,
        onMarkNeedsLayout: _invalidateParagraph,
      ),
      background: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final background = widget.layerBeneathBuilder;
          if (background != null && _paragraph != null) {
            return background(
              context,
              RenderParagraphProseTextLayout(
                richText: widget.richText,
                renderParagraph: _paragraph!,
              ),
            );
          } else {
            return const SizedBox();
          }
        },
      ),
      foreground: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final foreground = widget.layerAboveBuilder;
          if (foreground != null && _paragraph != null) {
            return foreground(
              context,
              RenderParagraphProseTextLayout(
                richText: widget.richText,
                renderParagraph: _paragraph!,
              ),
            );
          } else {
            return const SizedBox();
          }
        },
      ),
    );
  }
}

enum SuperTextCompositeGrouping {
  /// The background, text, and foreground are all composited in
  /// the same layer.
  ///
  /// This is the typical Flutter painting configuration.
  allTogether,

  /// The background and text are painted in a shared layer, and the
  /// foreground is painted in a separate layer.
  ///
  /// This mode makes it possible to blend the text with the background,
  /// without worrying about what's in the foreground.
  backgroundWithText,

  /// The foreground and text are painted in a shared layer, and the
  /// background is painted in a separate layer.
  ///
  /// This mode makes it possible to blend the text with the foreground,
  /// without worrying about what's in the background.
  foregroundWithText,

  /// The background, text, and foreground are all composited in different
  /// layers.
  ///
  /// This mode prevents any cross-blending between the background, text, and
  /// foreground. This mode should only be chosen when there is a specific
  /// reason to do so, because separating compositor layers might prevent
  /// internal optimizations.
  allSeparate,
}

@visibleForTesting
class SuperTextAnalytics extends InheritedWidget {
  static SuperTextAnalytics? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SuperTextAnalytics>();
  }

  const SuperTextAnalytics({
    Key? key,
    this.trackBuilds = false,
    required Widget child,
  }) : super(
          key: key,
          child: child,
        );

  final bool trackBuilds;

  @override
  bool updateShouldNotify(SuperTextAnalytics oldWidget) {
    return trackBuilds != oldWidget.trackBuilds;
  }
}

class _SuperTextLayout extends MultiChildRenderObjectWidget {
  _SuperTextLayout({
    Key? key,
    required this.state,
    required LayoutAwareRichText text,
    required Widget foreground,
    required Widget background,
  }) : super(key: key, children: [background, text, foreground]);

  final SuperTextState state;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderSuperTextLayout(state: state);
  }

  @override
  void updateRenderObject(BuildContext context, RenderSuperTextLayout renderObject) {
    renderObject.state = state;
  }
}

class _SuperTextLayoutParentData extends ContainerBoxParentData<RenderBox> {}

class RenderSuperTextLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SuperTextLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SuperTextLayoutParentData> {
  /// Returns the [ProseTextLayout] within a [SuperText] that's connected
  /// to the given [key].
  static ProseTextLayout? textLayoutFrom(GlobalKey key) {
    final renderTextLayout = key.currentContext?.findRenderObject() as RenderSuperTextLayout;
    if (renderTextLayout.state._paragraph == null) {
      return null;
    }

    return RenderParagraphProseTextLayout(
      richText: renderTextLayout.state.widget.richText,
      renderParagraph: renderTextLayout.state._paragraph!,
    );
  }

  RenderSuperTextLayout({
    required SuperTextState state,
  }) : _state = state;

  SuperTextState? _state;

  SuperTextState get state => _state!;

  set state(SuperTextState value) {
    if (_state != value) {
      _state = value;
      markNeedsLayout();
      markNeedsPaint();
    }
  }

  @override
  bool get alwaysNeedsCompositing {
    return true;
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SuperTextLayoutParentData) {
      child.parentData = _SuperTextLayoutParentData();
    }
  }

  @override
  void performLayout() {
    layoutLog.info("Running SuperText layout. Incoming constraints: $constraints");
    final children = getChildrenAsList();
    final background = children[0];
    final text = children[1];
    final foreground = children[2];

    text.layout(constraints, parentUsesSize: true);
    state._paragraph = text as RenderLayoutAwareParagraph;
    layoutLog.info("SuperText text layout size: ${text.size}");

    final layerConstraints = BoxConstraints.tight(text.size);

    layoutLog.finer("Laying out SuperText background layer. Constraints: $layerConstraints");
    background.layout(layerConstraints);

    layoutLog.finer("Laying out SuperText foreground layer. Constraints: $layerConstraints");
    foreground.layout(layerConstraints);

    size = text.size;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final backgroundLayerParentData = firstChild!.parentData as _SuperTextLayoutParentData;
    context.paintChild(firstChild!, backgroundLayerParentData.offset + offset);

    if (state.widget.foregroundIntoTextBlendMode != null) {
      // Separate background layer from the text and foreground.
      context.canvas.saveLayer(offset & size, Paint());
    } else if (state.widget.textIntoBackgroundBlendMode != null) {
      // Push the desired blending mode so that the text is blended with the background.
      context.canvas.saveLayer(offset & size, Paint()..blendMode = state.widget.textIntoBackgroundBlendMode!);
    }

    final textChild = backgroundLayerParentData.nextSibling;
    final textParentData = textChild!.parentData as _SuperTextLayoutParentData;
    context.paintChild(textChild, textParentData.offset + offset);

    if (state.widget.foregroundIntoTextBlendMode != null) {
      // Blend the foreground with the text.
      context.canvas.saveLayer(offset & size, Paint()..blendMode = state.widget.foregroundIntoTextBlendMode!);
    }

    final foregroundLayerChild = textParentData.nextSibling;
    final foregroundLayerParentData = foregroundLayerChild!.parentData! as _SuperTextLayoutParentData;
    context.paintChild(foregroundLayerChild, foregroundLayerParentData.offset + offset);

    if (state.widget.textIntoBackgroundBlendMode != null) {
      // Pop the one layer that was added for background blending.
      context.canvas.restore();
    } else if (state.widget.foregroundIntoTextBlendMode != null) {
      // Pop both of the layers that were added for foreground blending.
      context.canvas
        ..restore()
        ..restore();
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

/// A version of [RichText] that notifies clients when the underlying
/// [RenderParagraph] invalidates its layout, so that clients can avoid
/// accessing properties when the layout is invalid.
@visibleForTesting
class LayoutAwareRichText extends RichText {
  LayoutAwareRichText({
    Key? key,
    required InlineSpan text,
    required this.onMarkNeedsLayout,
  }) : super(key: key, text: text);

  /// Callback invoked when the underlying [RenderParagraph] invalidates
  /// its layout.
  final VoidCallback onMarkNeedsLayout;

  @override
  RenderLayoutAwareParagraph createRenderObject(BuildContext context) {
    assert(textDirection != null || debugCheckHasDirectionality(context));
    return RenderLayoutAwareParagraph(
      text,
      textAlign: textAlign,
      textDirection: textDirection ?? Directionality.of(context),
      softWrap: softWrap,
      overflow: overflow,
      textScaleFactor: textScaleFactor,
      maxLines: maxLines,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      locale: locale ?? Localizations.maybeLocaleOf(context),
      onMarkNeedsLayout: onMarkNeedsLayout,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderLayoutAwareParagraph renderObject) {
    assert(textDirection != null || debugCheckHasDirectionality(context));
    renderObject
      ..text = text
      ..textAlign = textAlign
      ..textDirection = textDirection ?? Directionality.of(context)
      ..softWrap = softWrap
      ..overflow = overflow
      ..textScaleFactor = textScaleFactor
      ..maxLines = maxLines
      ..strutStyle = strutStyle
      ..textWidthBasis = textWidthBasis
      ..textHeightBehavior = textHeightBehavior
      ..locale = locale ?? Localizations.maybeLocaleOf(context)
      ..onMarkNeedsLayout = onMarkNeedsLayout;
  }
}

/// A [RenderParagraph] that publicly reports whether or not its
/// layout is valid, and also accepts a callback to notify a listener
/// when the layout is marked invalid.
class RenderLayoutAwareParagraph extends RenderParagraph {
  RenderLayoutAwareParagraph(
    InlineSpan text, {
    TextAlign textAlign = TextAlign.start,
    required TextDirection textDirection,
    bool softWrap = true,
    TextOverflow overflow = TextOverflow.clip,
    double textScaleFactor = 1.0,
    int? maxLines,
    Locale? locale,
    StrutStyle? strutStyle,
    TextWidthBasis textWidthBasis = TextWidthBasis.parent,
    TextHeightBehavior? textHeightBehavior,
    List<RenderBox>? children,
    VoidCallback? onMarkNeedsLayout,
  })  : _onMarkNeedsLayout = onMarkNeedsLayout,
        super(
          text,
          textAlign: textAlign,
          textDirection: textDirection,
          softWrap: softWrap,
          overflow: overflow,
          textScaleFactor: textScaleFactor,
          maxLines: maxLines,
          locale: locale,
          strutStyle: strutStyle,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
          children: children,
        );

  VoidCallback? get onMarkNeedsLayout => _onMarkNeedsLayout;
  VoidCallback? _onMarkNeedsLayout;
  set onMarkNeedsLayout(VoidCallback? value) {
    if (_onMarkNeedsLayout != value) {
      _onMarkNeedsLayout = value;
    }
  }

  bool get needsLayout => _needsLayout;
  bool _needsLayout = true;

  @override
  void markNeedsLayout() {
    super.markNeedsLayout();
    _needsLayout = true;
    _onMarkNeedsLayout?.call();
  }

  @override
  void performLayout() {
    super.performLayout();
    _needsLayout = false;
  }
}

typedef SuperTextLayerBuilder = Widget Function(BuildContext, TextLayout textLayout);

/// A [SuperTextLayerBuilder] that combines multiple other layers into a single
/// layer, to be displayed above or beneath [SuperText].
///
/// The layers are drawn bottom-to-top, with the bottom layer being the first
/// layer in the list of layers.
class MultiLayerBuilder {
  const MultiLayerBuilder(this._layers);

  final List<SuperTextLayerBuilder> _layers;

  Widget build(BuildContext context, TextLayout textLayout) {
    return Stack(
      children: [
        for (final layer in _layers) //
          layer(context, textLayout),
      ],
    );
  }
}
