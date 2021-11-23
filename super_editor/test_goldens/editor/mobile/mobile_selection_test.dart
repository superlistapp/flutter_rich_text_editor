import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_editor.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/default_editor/paragraph.dart';
import 'package:super_editor/src/default_editor/super_editor.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/attributed_text.dart';
import 'package:super_editor/src/infrastructure/platforms/android/selection_handles.dart';
import 'package:super_editor/src/infrastructure/platforms/ios/selection_handles.dart';

void main() {
  group('SuperEditor', () {
    group('mobile selection', () {
      group('Android', () {
        testParagraphSelection(
          'single tap text',
          DocumentGestureMode.android,
          "mobile-selection_android_single-tap-text",
          (tester, docKey, _) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBox = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 34)),
            );

            await tester.tapAt(
              docBox.localToGlobal(characterBox!.center),
            );
            await tester.pumpAndSettle();
          },
        );

        testParagraphSelection(
          'drag collapsed handle upstream',
          DocumentGestureMode.android,
          "mobile-selection_android_drag-collapsed-upstream",
          (tester, docKey, dragLine) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBoxStart = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 34)),
            );
            final characterBoxEnd = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 28)),
            );
            final dragDelta =
                characterBoxEnd!.center - characterBoxStart!.center;

            await tester.tapAt(
              docBox.localToGlobal(characterBoxStart.center),
            );
            await tester.pumpAndSettle();

            final handleFinder = find.byType(AndroidSelectionHandle);
            final handleBox =
                handleFinder.evaluate().first.renderObject as RenderBox;
            final handleRectGlobal = Rect.fromPoints(
              handleBox.localToGlobal(Offset.zero),
              handleBox.localToGlobal(
                Offset(handleBox.size.width, handleBox.size.height),
              ),
            );

            await tester.dragFrom(handleRectGlobal.center, dragDelta);

            // Update the drag line for debug purposes
            dragLine.value = _Line(
                handleRectGlobal.center, handleRectGlobal.center + dragDelta);
          },
        );

        testParagraphSelection(
          'drag collapsed handle downstream',
          DocumentGestureMode.android,
          "mobile-selection_android_drag-collapsed-downstream",
          (tester, docKey, dragLine) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBoxStart = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 34)),
            );
            final characterBoxEnd = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 39)),
            );
            final dragDelta =
                characterBoxEnd!.center - characterBoxStart!.center;

            await tester.tapAt(
              docBox.localToGlobal(characterBoxStart.center),
            );
            await tester.pumpAndSettle();

            final handleFinder = find.byType(AndroidSelectionHandle);
            final handleBox =
                handleFinder.evaluate().first.renderObject as RenderBox;
            final handleRectGlobal = Rect.fromPoints(
              handleBox.localToGlobal(Offset.zero),
              handleBox.localToGlobal(
                Offset(handleBox.size.width, handleBox.size.height),
              ),
            );

            await tester.dragFrom(handleRectGlobal.center, dragDelta);

            // Update the drag line for debug purposes
            dragLine.value = _Line(
                handleRectGlobal.center, handleRectGlobal.center + dragDelta);
          },
        );

        testParagraphSelection(
          'double tap text',
          DocumentGestureMode.android,
          "mobile-selection_android_double-tap-text",
          (tester, docKey, rootWidget) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBox = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 34)),
            );

            await tester.doubleTapAt(
              docBox.localToGlobal(characterBox!.center),
            );
            await tester.pumpAndSettle();
          },
        );

        testParagraphSelection(
          'triple tap text',
          DocumentGestureMode.android,
          "mobile-selection_android_trip-tap-text",
          (tester, docKey, _) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBox = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 34)),
            );

            await tester.tripleTapAt(
              docBox.localToGlobal(characterBox!.center),
            );
            await tester.pumpAndSettle();
          },
        );

        testParagraphSelection(
          'drag base handle upstream',
          DocumentGestureMode.android,
          "mobile-selection_android_drag-base-upstream",
          (tester, docKey, dragLine) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBoxStart = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 28)),
            );
            final characterBoxEnd = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 22)),
            );
            final dragDelta =
                characterBoxEnd!.center - characterBoxStart!.center;

            await tester.doubleTapAt(
              docBox.localToGlobal(characterBoxStart.center),
            );

            await tester.pumpAndSettle();

            final handleFinder = find.byType(AndroidSelectionHandle);
            final handleBox =
                handleFinder.evaluate().first.renderObject as RenderBox;
            final handleRectGlobal = Rect.fromPoints(
              handleBox.localToGlobal(Offset.zero),
              handleBox.localToGlobal(
                Offset(handleBox.size.width, handleBox.size.height),
              ),
            );

            await tester.dragFrom(handleRectGlobal.center, dragDelta);

            // Update the drag line for debug purposes
            dragLine.value = _Line(
                handleRectGlobal.center, handleRectGlobal.center + dragDelta);
          },
        );

        testParagraphSelection(
          'drag extent handle upstream',
          DocumentGestureMode.android,
          "mobile-selection_android_drag-extent-upstream",
          (tester, docKey, dragLine) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBoxStart = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 38)),
            );
            final characterBoxEnd = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 30)),
            );
            final dragDelta =
                characterBoxEnd!.center - characterBoxStart!.center;

            await tester.doubleTapAt(
              docBox.localToGlobal(characterBoxStart.center),
            );
            await tester.pumpAndSettle();

            final handleFinder = find.byType(AndroidSelectionHandle);
            final handleBox =
                handleFinder.evaluate().elementAt(1).renderObject as RenderBox;
            final handleRectGlobal = Rect.fromPoints(
              handleBox.localToGlobal(Offset.zero),
              handleBox.localToGlobal(
                Offset(handleBox.size.width, handleBox.size.height),
              ),
            );

            await tester.dragFrom(handleRectGlobal.center, dragDelta);

            // Update the drag line for debug purposes
            dragLine.value = _Line(
                handleRectGlobal.center, handleRectGlobal.center + dragDelta);
          },
        );

        testParagraphSelection(
          'drag extent handle downstream',
          DocumentGestureMode.android,
          "mobile-selection_android_drag-extent-downstream",
          (tester, docKey, dragLine) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBoxStart = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 38)),
            );
            final characterBoxEnd = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 44)),
            );
            final dragDelta =
                characterBoxEnd!.center - characterBoxStart!.center;

            await tester.doubleTapAt(
              docBox.localToGlobal(characterBoxStart.center),
            );
            await tester.pumpAndSettle();

            final handleFinder = find.byType(AndroidSelectionHandle);
            final handleBox =
                handleFinder.evaluate().elementAt(1).renderObject as RenderBox;
            final handleRectGlobal = Rect.fromPoints(
              handleBox.localToGlobal(Offset.zero),
              handleBox.localToGlobal(
                Offset(handleBox.size.width, handleBox.size.height),
              ),
            );

            await tester.dragFrom(handleRectGlobal.center, dragDelta);

            // Update the drag line for debug purposes
            dragLine.value = _Line(
                handleRectGlobal.center, handleRectGlobal.center + dragDelta);
          },
        );
      });

      group('iOS', () {
        testParagraphSelection(
          'single tap text',
          DocumentGestureMode.iOS,
          "mobile-selection_ios_single-tap-text",
          (tester, docKey, _) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBox = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 34)),
            );

            await tester.tapAt(
              docBox.localToGlobal(characterBox!.center),
            );
            await tester.pumpAndSettle();
          },
        );

        testParagraphSelection(
          'drag collapsed handle upstream',
          DocumentGestureMode.iOS,
          "mobile-selection_ios_drag-collapsed-upstream",
          (tester, docKey, dragLine) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBoxStart = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 34)),
            );
            final characterBoxEnd = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 28)),
            );
            final dragDelta =
                characterBoxEnd!.center - characterBoxStart!.center;

            await tester.tapAt(
              docBox.localToGlobal(characterBoxStart.center),
            );
            await tester.pumpAndSettle();

            final handleFinder = find.byType(IOSCollapsedHandle);
            final handleBox =
                handleFinder.evaluate().first.renderObject as RenderBox;
            final handleRectGlobal = Rect.fromPoints(
              handleBox.localToGlobal(Offset.zero),
              handleBox.localToGlobal(
                Offset(handleBox.size.width, handleBox.size.height),
              ),
            );

            await tester.dragFrom(handleRectGlobal.center, dragDelta);

            // Update the drag line for debug purposes
            dragLine.value = _Line(
                handleRectGlobal.center, handleRectGlobal.center + dragDelta);
          },
        );

        testParagraphSelection(
          'drag collapsed handle downstream',
          DocumentGestureMode.iOS,
          "mobile-selection_ios_drag-collapsed-downstream",
          (tester, docKey, dragLine) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBoxStart = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 34)),
            );
            final characterBoxEnd = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 39)),
            );
            final dragDelta =
                characterBoxEnd!.center - characterBoxStart!.center;

            await tester.tapAt(
              docBox.localToGlobal(characterBoxStart.center),
            );
            await tester.pumpAndSettle();

            final handleFinder = find.byType(IOSCollapsedHandle);
            final handleBox =
                handleFinder.evaluate().first.renderObject as RenderBox;
            final handleRectGlobal = Rect.fromPoints(
              handleBox.localToGlobal(Offset.zero),
              handleBox.localToGlobal(
                Offset(handleBox.size.width, handleBox.size.height),
              ),
            );

            await tester.dragFrom(handleRectGlobal.center, dragDelta);

            // Update the drag line for debug purposes
            dragLine.value = _Line(
                handleRectGlobal.center, handleRectGlobal.center + dragDelta);
          },
        );

        testParagraphSelection(
          'double tap text',
          DocumentGestureMode.iOS,
          "mobile-selection_ios_double-tap-text",
          (tester, docKey, rootWidget) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBox = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 34)),
            );

            await tester.doubleTapAt(
              docBox.localToGlobal(characterBox!.center),
            );
            await tester.pumpAndSettle();
          },
        );

        testParagraphSelection(
          'triple tap text',
          DocumentGestureMode.iOS,
          "mobile-selection_ios_trip-tap-text",
          (tester, docKey, _) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBox = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 34)),
            );

            await tester.tripleTapAt(
              docBox.localToGlobal(characterBox!.center),
            );
            await tester.pumpAndSettle();
          },
        );

        testParagraphSelection(
          'drag base handle upstream',
          DocumentGestureMode.iOS,
          "mobile-selection_ios_drag-base-upstream",
          (tester, docKey, dragLine) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBoxStart = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 28)),
            );
            final characterBoxEnd = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 22)),
            );
            final dragDelta =
                characterBoxEnd!.center - characterBoxStart!.center;

            await tester.doubleTapAt(
              docBox.localToGlobal(characterBoxStart.center),
            );

            await tester.pumpAndSettle();

            final handleFinder = find.byType(IOSSelectionHandle);
            final handleBox =
                handleFinder.evaluate().first.renderObject as RenderBox;
            final handleRectGlobal = Rect.fromPoints(
              handleBox.localToGlobal(Offset.zero),
              handleBox.localToGlobal(
                Offset(handleBox.size.width, handleBox.size.height),
              ),
            );

            await tester.dragFrom(handleRectGlobal.center, dragDelta);

            // Update the drag line for debug purposes
            dragLine.value = _Line(
                handleRectGlobal.center, handleRectGlobal.center + dragDelta);
          },
        );

        testParagraphSelection(
          'drag extent handle upstream',
          DocumentGestureMode.iOS,
          "mobile-selection_ios_drag-extent-upstream",
          (tester, docKey, dragLine) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBoxStart = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 38)),
            );
            final characterBoxEnd = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 30)),
            );
            final dragDelta =
                characterBoxEnd!.center - characterBoxStart!.center;

            await tester.doubleTapAt(
              docBox.localToGlobal(characterBoxStart.center),
            );
            await tester.pumpAndSettle();

            final handleFinder = find.byType(IOSSelectionHandle);
            final handleBox =
                handleFinder.evaluate().elementAt(1).renderObject as RenderBox;
            final handleRectGlobal = Rect.fromPoints(
              handleBox.localToGlobal(Offset.zero),
              handleBox.localToGlobal(
                Offset(handleBox.size.width, handleBox.size.height),
              ),
            );

            await tester.dragFrom(handleRectGlobal.center, dragDelta);

            // Update the drag line for debug purposes
            dragLine.value = _Line(
                handleRectGlobal.center, handleRectGlobal.center + dragDelta);
          },
        );

        testParagraphSelection(
          'drag extent handle downstream',
          DocumentGestureMode.iOS,
          "mobile-selection_ios_drag-extent-downstream",
          (tester, docKey, dragLine) async {
            final docBox =
                docKey.currentContext!.findRenderObject() as RenderBox;
            final docLayout = docKey.currentState as DocumentLayout;
            final characterBoxStart = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 38)),
            );
            final characterBoxEnd = docLayout.getRectForPosition(
              const DocumentPosition(
                  nodeId: "1", nodePosition: TextNodePosition(offset: 44)),
            );
            final dragDelta =
                characterBoxEnd!.center - characterBoxStart!.center;

            await tester.doubleTapAt(
              docBox.localToGlobal(characterBoxStart.center),
            );
            await tester.pumpAndSettle();

            final handleFinder = find.byType(IOSSelectionHandle);
            final handleBox =
                handleFinder.evaluate().elementAt(1).renderObject as RenderBox;
            final handleRectGlobal = Rect.fromPoints(
              handleBox.localToGlobal(Offset.zero),
              handleBox.localToGlobal(
                Offset(handleBox.size.width, handleBox.size.height),
              ),
            );

            await tester.dragFrom(handleRectGlobal.center, dragDelta);

            // Update the drag line for debug purposes
            dragLine.value = _Line(
                handleRectGlobal.center, handleRectGlobal.center + dragDelta);
          },
        );
      });
    });
  });
}

/// Pumps a single-paragraph document into the WidgetTester and then hands control
/// to the given [test] method.
void testParagraphSelection(
  String description,
  DocumentGestureMode platform,
  String goldenName,
  Future<void> Function(
          WidgetTester, GlobalKey docKey, ValueNotifier<_Line?> dragLine)
      test,
) {
  final docKey = GlobalKey();

  testGoldens(description, (tester) async {
    tester.binding.window
      ..physicalSizeTestValue = const Size(800, 200)
      ..textScaleFactorTestValue = 1.0
      ..devicePixelRatioTestValue = 1.0;

    final dragLine = ValueNotifier<_Line?>(null);

    final content = _buildScaffold(
      dragLine: dragLine,
      child: SuperEditor(
        documentLayoutKey: docKey,
        editor: _createSingleParagraphEditor(),
        gestureMode: platform,
        textStyleBuilder: _textStyleBuilder,
      ),
    );

    // Display the content
    await tester.pumpWidget(
      content,
    );

    // Run the test
    await test(tester, docKey, dragLine);

    // Compare the golden
    await screenMatchesGolden(tester, goldenName);

    tester.binding.window.clearPhysicalSizeTestValue();
  });
}

Widget _buildScaffold({
  required ValueNotifier<_Line?> dragLine,
  required Widget child,
}) {
  return DragLinePaint(
    line: dragLine,
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: IntrinsicHeight(
            child: child,
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
    ),
  );
}

TextStyle _textStyleBuilder(attributions) {
  return const TextStyle(
    color: Colors.black,
    fontFamily: 'Roboto',
    fontSize: 16,
    height: 1.4,
  );
}

DocumentEditor _createSingleParagraphEditor() {
  return DocumentEditor(document: _createSingleParagraphDoc());
}

MutableDocument _createSingleParagraphDoc() {
  return MutableDocument(
    nodes: [
      ParagraphNode(
        id: "1",
        text: AttributedText(
          text:
              "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
        ),
      ),
    ],
  );
}

class DragLinePaint extends StatelessWidget {
  const DragLinePaint({
    Key? key,
    required this.line,
    required this.child,
  }) : super(key: key);

  final ValueNotifier<_Line?> line;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_Line?>(
      valueListenable: line,
      builder: (context, line, child) {
        return CustomPaint(
          foregroundPainter: line != null ? DragLinePainter(line: line) : null,
          child: child,
        );
      },
      child: child,
    );
  }
}

class DragLinePainter extends CustomPainter {
  DragLinePainter({
    required _Line line,
  })  : _line = line,
        _paint = Paint();

  final _Line _line;
  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    _paint.color = Colors.red;
    canvas.drawCircle(_line.from, 5, _paint);

    _paint.shader = ui.Gradient.linear(
      _line.from,
      _line.to,
      [const Color(0x00FF0000), const Color(0xFFFF0000)],
    );

    canvas.drawRect(
        Rect.fromPoints(
          _line.from - const Offset(0, 2),
          _line.to + const Offset(0, 2),
        ),
        _paint);
  }

  @override
  bool shouldRepaint(DragLinePainter oldDelegate) {
    return _line != oldDelegate._line;
  }
}

class _Line {
  _Line(this.from, this.to);

  final Offset from;
  final Offset to;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Line &&
          runtimeType == other.runtimeType &&
          from == other.from &&
          to == other.to;

  @override
  int get hashCode => from.hashCode ^ to.hashCode;
}

extension on WidgetTester {
  Future<void> doubleTapAt(Offset offset) async {
    await tapAt(offset);
    await pump(kDoubleTapMinTime);
    await tapAt(offset);
  }

  Future<void> tripleTapAt(Offset offset) async {
    await tapAt(offset);
    await pump(kDoubleTapMinTime);
    await tapAt(offset);
    await pump(kDoubleTapMinTime);
    await tapAt(offset);
  }
}
