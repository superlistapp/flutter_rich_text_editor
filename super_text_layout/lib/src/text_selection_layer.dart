import 'package:flutter/widgets.dart';

import 'text_layout.dart';

// The default width of a selection highlight box when a given
// text area is empty.
const _defaultEmptySelectionHighlightWidth = 20.0;

class TextLayoutSelectionHighlight extends StatelessWidget {
  const TextLayoutSelectionHighlight({
    Key? key,
    required this.textLayout,
    required this.style,
    required this.selection,
  }) : super(key: key);

  final TextLayout? textLayout;
  final SelectionHighlightStyle style;
  final TextSelection? selection;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: TextSelectionPainter(
        textLayout: textLayout,
        selectionColor: style.color,
        borderRadius: style.borderRadius,
        textSelection: selection,
      ),
    );
  }
}

class TextLayoutEmptyHighlight extends StatelessWidget {
  const TextLayoutEmptyHighlight({
    Key? key,
    required this.textLayout,
    required this.style,
    this.highlightWidth = _defaultEmptySelectionHighlightWidth,
  }) : super(key: key);

  final TextLayout? textLayout;
  final SelectionHighlightStyle style;
  final double highlightWidth;

  @override
  Widget build(BuildContext context) {
    if (textLayout == null) {
      return const SizedBox();
    }

    // We render an empty selection with a CustomPainter because from the widget
    // tree's perspective, the text box has zero width. Therefore, we use a CustomPainter
    // to ignore the layout bounds and paint our desired width.
    final highlightHeight = textLayout!.getLineHeightAtPosition(const TextPosition(offset: -1));
    return CustomPaint(
      painter: _EmptyHighlightPainter(
        width: highlightWidth,
        height: highlightHeight,
        style: style,
      ),
    );
  }
}

class _EmptyHighlightPainter extends CustomPainter {
  _EmptyHighlightPainter({
    required this.width,
    required this.height,
    required this.style,
  });

  final double width;
  final double height;
  final SelectionHighlightStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, width, height),
        topLeft: style.borderRadius.topLeft,
        topRight: style.borderRadius.topRight,
        bottomLeft: style.borderRadius.bottomLeft,
        bottomRight: style.borderRadius.bottomRight,
      ),
      Paint()..color = style.color,
    );
  }

  @override
  bool shouldRepaint(_EmptyHighlightPainter oldDelegate) {
    return false;
  }
}

/// The source of a given text selection, e.g., a user, like "John", or a
/// type of selection, like "textSearchMatch".
///
/// The meaning of a [SelectionSource] is determined by the object that
/// paints the given selection.
class SelectionSource {
  const SelectionSource({
    required this.id,
    required this.selectionStyle,
  });

  final String id;
  final SelectionHighlightStyle selectionStyle;
}

/// Visual styles for a selection highlight.
class SelectionHighlightStyle {
  const SelectionHighlightStyle({
    this.color = const Color(0xFFACCEF7),
    this.borderRadius = BorderRadius.zero,
  });

  final Color color;
  final BorderRadius borderRadius;

  SelectionHighlightStyle copyWith({
    Color? color,
    BorderRadius? borderRadius,
  }) {
    return SelectionHighlightStyle(
      color: color ?? this.color,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }
}

/// Paints selection highlight rectangles around a [textSelection] in a given [textLayout]
/// using the desired [selectionColor].
///
/// [TextSelectionPainter] doesn't handle painting a selection highlight rectangle when
/// the text is empty.
class TextSelectionPainter extends CustomPainter {
  TextSelectionPainter({
    required this.textLayout,
    required this.textSelection,
    this.borderRadius = BorderRadius.zero,
    required this.selectionColor,
  }) : _selectionPaint = Paint()..color = selectionColor;

  final TextLayout? textLayout;
  final TextSelection? textSelection;
  final Color selectionColor;
  final BorderRadius borderRadius;
  final Paint _selectionPaint;

  @override
  void paint(Canvas canvas, Size size) {
    if (textLayout == null) {
      // No layout is available yet. Nothing to paint.
      return;
    }
    if (textSelection == null || textSelection == const TextSelection.collapsed(offset: -1)) {
      // No selection to paint. Return.
      return;
    }

    final selectionBoxes = textLayout!.getBoxesForSelection(textSelection!);

    for (final box in selectionBoxes) {
      final rawRect = box.toRect();
      final rect = Rect.fromLTWH(
        rawRect.left,
        rawRect.top - selectionHighlightBoxTopPixelsDecrement,
        rawRect.width,
        rawRect.height + selectionHighlightBoxBottomPixelsIncrement,
      );
      final rrect = RRect.fromRectAndCorners(rect,
          topLeft: borderRadius.topLeft,
          topRight: borderRadius.topRight,
          bottomLeft: borderRadius.bottomLeft,
          bottomRight: borderRadius.bottomRight);

      canvas.drawRRect(
        // Note: If the rect has no width then we've selected an empty line. Give
        //       that line a slight width for visibility.
        rect.width > 0
            ? rrect
            : RRect.fromRectAndRadius(Rect.fromLTWH(rect.left, rect.top, 5, rect.height), Radius.zero),
        _selectionPaint,
      );
    }
  }

  @override
  bool shouldRepaint(TextSelectionPainter oldDelegate) {
    return textLayout != oldDelegate.textLayout ||
        textSelection != oldDelegate.textSelection ||
        selectionColor != oldDelegate.selectionColor;
  }
}

/// The number of pixels to decrement from the top of selection box to display
/// the selection highlight.
///
/// The final selection highlight top is the top of the box returned by
/// `TextLayout.getBoxesForSelection` minus [selectionHighlightBoxTopPixelsDecrement] pixels.
const selectionHighlightBoxTopPixelsDecrement = 2.0;

/// The number of pixels to increment from the bottom of selection box to display
/// the selection highlight.
///
/// The final selection highlight top bottom the bottom of the box returned by
/// `TextLayout.getBoxesForSelection` plus [selectionHighlightBoxBottomPixelsIncrement] pixels.
const selectionHighlightBoxBottomPixelsIncrement = 4.0;
