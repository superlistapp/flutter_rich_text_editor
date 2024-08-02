import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';

import 'text_layout.dart';

/// A [SuperText] layer that displays an underline beneath the text within a given
/// selection.
class TextUnderlineLayer extends StatefulWidget {
  const TextUnderlineLayer({
    Key? key,
    required this.textLayout,
    required this.style,
    required this.underlines,
  }) : super(key: key);

  final TextLayout textLayout;
  final UnderlineStyle style;
  final List<TextLayoutUnderline> underlines;

  @override
  State<TextUnderlineLayer> createState() => TextUnderlineLayerState();
}

@visibleForTesting
class TextUnderlineLayerState extends State<TextUnderlineLayer> with TickerProviderStateMixin {
  List<LineSegment> _computeUnderlineLineSegments() {
    final lineSegments = <LineSegment>[];
    for (final underline in widget.underlines) {
      // Convert selection bounding boxes into underline line segments.
      final boxes = widget.textLayout.getBoxesForSelection(
        TextSelection(baseOffset: underline.range.start, extentOffset: underline.range.end),
        boxHeightStyle: BoxHeightStyle.max,
      );
      final lineSegmentsForRange = <LineSegment>[];
      for (final box in boxes) {
        lineSegmentsForRange.add(
          LineSegment(
            Offset(box.left, box.bottom + underline.gap),
            Offset(box.right, box.bottom + underline.gap),
          ),
        );
      }

      lineSegments.addAll(lineSegmentsForRange);
    }

    return lineSegments;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.underlines.isEmpty) {
      return const SizedBox();
    }

    return CustomPaint(
      size: Size.infinite,
      // painter: _UnderlinePainter(underlines: _computeUnderlineLineSegments()),
      // painter: _DottedPainter(underlines: _computeUnderlineLineSegments()),
      // painter: SquiggleUnderlinePainter(underlines: _computeUnderlineLineSegments()),
      painter: widget.style.createPainter(_computeUnderlineLineSegments()),
    );
  }
}

class TextLayoutUnderline {
  const TextLayoutUnderline({
    required this.range,
    this.gap = 1,
  });

  final TextRange range;
  final double gap;
}

abstract interface class UnderlineStyle {
  CustomPainter createPainter(List<LineSegment> underlines);
}

class StraightUnderlineStyle implements UnderlineStyle {
  const StraightUnderlineStyle({
    this.color = const Color(0xFF000000),
    this.thickness = 2,
    this.capType = StrokeCap.square,
  });

  final Color color;
  final double thickness;
  final StrokeCap capType;

  @override
  CustomPainter createPainter(List<LineSegment> underlines) {
    return StraightUnderlinePainter(underlines: underlines, color: color, thickness: thickness, capType: capType);
  }
}

class StraightUnderlinePainter extends CustomPainter {
  const StraightUnderlinePainter({
    required List<LineSegment> underlines,
    this.color = const Color(0xFF000000),
    this.thickness = 2,
    this.capType = StrokeCap.square,
  }) : _underlines = underlines;

  final List<LineSegment> _underlines;

  final Color color;
  final double thickness;
  final StrokeCap capType;

  @override
  void paint(Canvas canvas, Size size) {
    if (_underlines.isEmpty) {
      return;
    }

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = capType;
    for (final underline in _underlines) {
      canvas.drawLine(underline.start, underline.end, linePaint);
    }
  }

  @override
  bool shouldRepaint(StraightUnderlinePainter oldDelegate) {
    return color != oldDelegate.color ||
        thickness != oldDelegate.thickness ||
        capType != oldDelegate.capType ||
        !const DeepCollectionEquality().equals(_underlines, oldDelegate._underlines);
  }
}

class DottedUnderlineStyle implements UnderlineStyle {
  const DottedUnderlineStyle({
    this.color = const Color(0xFFFF0000),
    this.dotDiameter = 2,
    this.dotSpace = 1,
  });

  final Color color;
  final double dotDiameter;
  final double dotSpace;

  @override
  CustomPainter createPainter(List<LineSegment> underlines) {
    return DottedUnderlinePainter(underlines: underlines, color: color, dotDiameter: dotDiameter, dotSpace: dotSpace);
  }
}

class DottedUnderlinePainter extends CustomPainter {
  const DottedUnderlinePainter({
    required List<LineSegment> underlines,
    this.color = const Color(0xFFFF0000),
    this.dotDiameter = 2,
    this.dotSpace = 1,
  }) : _underlines = underlines;

  final List<LineSegment> _underlines;

  final Color color;
  final double dotDiameter;
  final double dotSpace;

  @override
  void paint(Canvas canvas, Size size) {
    if (_underlines.isEmpty) {
      return;
    }

    final dotPaint = Paint()..color = color;
    for (final underline in _underlines) {
      final dotCount = ((underline.end.dx - underline.start.dx) / (dotDiameter + dotSpace)).floor();

      // Draw the dots.
      final delta = Offset(dotDiameter + dotSpace, (underline.end.dy - underline.start.dy) / dotCount);
      Offset offset = underline.start + Offset(dotDiameter / 2, 0);
      for (int i = 0; i < dotCount; i += 1) {
        canvas.drawCircle(offset, dotDiameter / 2, dotPaint);
        offset = offset + delta;
      }
    }
  }

  @override
  bool shouldRepaint(DottedUnderlinePainter oldDelegate) {
    return !const DeepCollectionEquality().equals(_underlines, oldDelegate._underlines);
  }
}

class SquiggleUnderlineStyle implements UnderlineStyle {
  const SquiggleUnderlineStyle({
    this.color = const Color(0xFFFF0000),
    this.thickness = 1,
    this.jaggedDeltaX = 2,
    this.jaggedDeltaY = 2,
  })  : assert(jaggedDeltaX > 0, "The squiggle jaggedDeltaX must be > 0"),
        assert(jaggedDeltaY > 0, "The squiggle jaggedDeltaY must be > 0");

  final Color color;
  final double thickness;
  final double jaggedDeltaX;
  final double jaggedDeltaY;

  @override
  CustomPainter createPainter(List<LineSegment> underlines) {
    return SquiggleUnderlinePainter(
      underlines: underlines,
      color: color,
      thickness: thickness,
      jaggedDeltaX: jaggedDeltaX,
      jaggedDeltaY: jaggedDeltaY,
    );
  }
}

class SquiggleUnderlinePainter extends CustomPainter {
  const SquiggleUnderlinePainter({
    required List<LineSegment> underlines,
    this.color = const Color(0xFFFF0000),
    this.thickness = 1,
    this.jaggedDeltaX = 2,
    this.jaggedDeltaY = 2,
  })  : assert(jaggedDeltaX > 0, "The squiggle jaggedDeltaX must be > 0"),
        assert(jaggedDeltaY > 0, "The squiggle jaggedDeltaY must be > 0"),
        _underlines = underlines;

  final List<LineSegment> _underlines;

  final Color color;
  final double thickness;
  final double jaggedDeltaX;
  final double jaggedDeltaY;

  @override
  void paint(Canvas canvas, Size size) {
    if (_underlines.isEmpty) {
      return;
    }

    final delta = Offset(jaggedDeltaX, jaggedDeltaY);
    final squigglePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;

    for (final underline in _underlines) {
      // Draw the squiggle.
      Offset offset = underline.start + Offset(delta.dy / 2, 0);
      int nextDirection = -1;
      while (offset.dx <= underline.end.dx) {
        // Calculate the endpoint of this jagged squiggle segment.
        final endPoint = offset + Offset(delta.dx, delta.dy * nextDirection);

        // Paint this tiny segment.
        canvas.drawLine(offset, endPoint, squigglePaint);

        // Move the next start offset to the previous end offset, and flip direction.
        offset = endPoint;
        nextDirection = nextDirection * -1;
      }
    }
  }

  @override
  bool shouldRepaint(SquiggleUnderlinePainter oldDelegate) {
    return !const DeepCollectionEquality().equals(_underlines, oldDelegate._underlines);
  }
}

class LineSegment {
  const LineSegment(this.start, this.end);

  final Offset start;
  final Offset end;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineSegment && runtimeType == other.runtimeType && start == other.start && end == other.end;

  @override
  int get hashCode => start.hashCode ^ end.hashCode;
}
