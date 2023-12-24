import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';
import 'package:super_text_layout/super_text_layout.dart';

import 'supereditor_test_tools.dart';

void main() {
  group("SuperEditor", () {
    // We're testing the automatic movement of the caret when the available space changes. This
    // text position sits at a location that should move to a different line when the available space
    // is reduced.
    const textPosition = TextPosition(offset: 46);
    final tapPosition = DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: textPosition.offset));

    group('text affinity', () {
      // Use a relatively small size to make sure we have a line break.
      const editorSize = Size(400, 400);
      // Add some minimum buffer to the greater than x and y offset expectations to reduce the chance of false
      // positives. The x buffer is chosen to be most of the width of the editor, the y to be slightly less than the
      // height of the rendered caret. If these tests start to fail check the actual offsets reported in the output
      // and adjust these numbers if necessary.
      const xExpectBuffer = 300;
      const yExpectBuffer = 24;

      testWidgetsOnAllPlatforms('upstream and downstream positions render differently at a line break',
          (WidgetTester tester) async {
        await tester //
            .createDocument()
            .withSingleParagraph()
            .withEditorSize(editorSize)
            .pump();

        // Find the coordinates of the caret at the start of the first line.
        await tester.placeCaretInParagraph('1', 0);
        final startOfFirstLineCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();

        // Find the offset of the first line break.
        final lineBreakOffset = SuperEditorInspector.findOffsetOfLineBreak('1');

        // Find the coordinates of the caret at the end of the first line (line break offset w/ upstream affinity).
        await tester.pump(kTapTimeout * 2); // Simulate a pause to avoid a double tap.
        await tester.placeCaretInParagraph('1', lineBreakOffset, affinity: TextAffinity.upstream);
        final upstreamCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();

        // The upstream caret should be at the same y and greater x than the caret at the start of the paragraph.
        expect(upstreamCaretOffset.dx, greaterThan(startOfFirstLineCaretOffset.dx + xExpectBuffer));
        expect(upstreamCaretOffset.dy, startOfFirstLineCaretOffset.dy);

        // Find the coordinates of the caret at the start of the second line (line break offset w/ downstream affinity).
        await tester.pump(kTapTimeout * 2); // Simulate a pause to avoid a double tap.
        await tester.placeCaretInParagraph('1', lineBreakOffset, affinity: TextAffinity.downstream);
        final downstreamCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();

        // The downstream caret should be at the same x and greater y than the caret at the start of the paragraph.
        expect(downstreamCaretOffset.dx, startOfFirstLineCaretOffset.dx);
        expect(downstreamCaretOffset.dy, greaterThan(startOfFirstLineCaretOffset.dy + yExpectBuffer));
      });

      testWidgetsOnAllPlatforms('upstream and downstream positions render the same if not at a line break',
          (WidgetTester tester) async {
        await tester //
            .createDocument()
            .withSingleParagraph()
            .withEditorSize(editorSize)
            .pump();

        // Find an offset that is not at a line break, so that the caret should render the same with upstream or
        // downstream affinity.
        final textOffset = SuperEditorInspector.findOffsetOfLineBreak('1') - 1;

        // Place the caret at that offset with a downstream affinity.
        await tester.placeCaretInParagraph('1', textOffset, affinity: TextAffinity.downstream);
        final downstreamCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();
        final downstreamSelection = SuperEditorInspector.findDocumentSelection();

        // Place the caret at the same offset but with an upstream affinity.
        await tester.pump(kTapTimeout * 2); // Simulate a pause to avoid a double tap.
        await tester.placeCaretInParagraph('1', textOffset, affinity: TextAffinity.upstream);
        final upstreamCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();
        final upstreamSelection = SuperEditorInspector.findDocumentSelection();

        // Make sure the selection actually changed.
        expect(downstreamSelection, isNot(upstreamSelection));

        // Make sure that the caret renders at the same location for both upstream and downstream affinities.
        expect(upstreamCaretOffset, downstreamCaretOffset);
      });
    });

    group('window resizing', () {
      const screenSizeBigger = Size(1000.0, 400.0);
      const screenSizeSmaller = Size(250.0, 400.0);

      testWidgetsOnDesktop('moves caret to next line when available width contracts', (WidgetTester tester) async {
        tester.view
          ..devicePixelRatio = 1.0
          ..platformDispatcher.textScaleFactorTestValue = 1.0
          ..physicalSize = screenSizeBigger;

        final docKey = GlobalKey();
        await tester.pumpWidget(
          _createTestApp(
            gestureMode: DocumentGestureMode.mouse,
            docKey: docKey,
          ),
        );
        await tester.pumpAndSettle();

        // Place caret at a position that will move to the next line when the width contracts
        await tester.tapAtDocumentPosition(tapPosition);
        await tester.pump();

        // Ensure that the caret is displayed at the correct (x,y) in the document before resizing the window
        final initialCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();
        final expectedInitialCaretOffset = _computeExpectedDesktopCaretOffset(tester, textPosition);
        expect(initialCaretOffset, expectedInitialCaretOffset);

        // Make the window more narrow, pushing the caret text position down a line.
        await _resizeWindow(
            tester: tester, frameCount: 60, initialScreenSize: screenSizeBigger, finalScreenSize: screenSizeSmaller);

        // Ensure that after resizing the window, the caret updated its (x,y) to match the text
        // position that was pushed down to the next line.
        final finalCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();
        final expectedFinalCaretOffset = _computeExpectedDesktopCaretOffset(tester, textPosition);
        expect(finalCaretOffset, expectedFinalCaretOffset);
      });

      testWidgetsOnDesktop('moves caret to preceding line when available width expands', (WidgetTester tester) async {
        tester.view
          ..devicePixelRatio = 1.0
          ..platformDispatcher.textScaleFactorTestValue = 1.0
          ..physicalSize = screenSizeSmaller;

        final docKey = GlobalKey();
        await tester.pumpWidget(
          _createTestApp(
            gestureMode: DocumentGestureMode.mouse,
            docKey: docKey,
          ),
        );
        await tester.pumpAndSettle();

        // Place caret at a position that will move to the preceding line when the width expands
        await tester.tapAtDocumentPosition(tapPosition);
        await tester.pump();

        // Ensure that the caret is displayed at the correct (x,y) in the document before resizing the window
        final initialCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();
        final expectedInitialCaretOffset = _computeExpectedDesktopCaretOffset(tester, textPosition);
        expect(initialCaretOffset, expectedInitialCaretOffset);

        // Make the window wider, pushing the caret text position up a line.
        await _resizeWindow(
            tester: tester, frameCount: 60, initialScreenSize: screenSizeSmaller, finalScreenSize: screenSizeBigger);

        // Ensure that after resizing the window, the caret updated its (x,y) to match the text
        // position that was pushed up to the preceding line.
        final finalCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();
        final expectedFinalCaretOffset = _computeExpectedDesktopCaretOffset(tester, textPosition);
        expect(finalCaretOffset, expectedFinalCaretOffset);
      });
    });

    group('phone rotation', () {
      const screenSizePortrait = Size(400.0, 1000.0);
      const screenSizeLandscape = Size(1000.0, 400);

      group('on Android', () {
        testWidgets('from portrait to landscape updates caret position', (WidgetTester tester) async {
          tester.view
            ..devicePixelRatio = 1.0
            ..platformDispatcher.textScaleFactorTestValue = 1.0
            ..physicalSize = screenSizePortrait;

          final docKey = GlobalKey();
          await tester.pumpWidget(
            _createTestApp(
              gestureMode: DocumentGestureMode.android,
              docKey: docKey,
            ),
          );
          await tester.pumpAndSettle();

          // Place caret at a position that will move to the preceding line when the width expands
          await tester.tapAtDocumentPosition(tapPosition);
          await tester.pump();

          // Ensure that the caret is displayed at the correct (x,y) in the document before phone rotation
          final initialCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();
          final expectedInitialCaretOffset =
              _computeExpectedMobileCaretOffsetInDocumentLayout(tester, docKey, tapPosition);
          expect(initialCaretOffset, expectedInitialCaretOffset);

          // Make the window wider, pushing the caret text position up a line.
          tester.view.physicalSize = screenSizeLandscape;
          await tester.pumpAndSettle();

          // Ensure that after rotating the phone, the caret updated its (x,y) to match the text
          // position that was pushed up to the preceding line.
          final finalCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();
          final expectedFinalCaretOffset =
              _computeExpectedMobileCaretOffsetInDocumentLayout(tester, docKey, tapPosition);
          expect(finalCaretOffset, expectedFinalCaretOffset);
        });

        testWidgets('from landscape to portrait updates caret position', (WidgetTester tester) async {
          tester.view
            ..devicePixelRatio = 1.0
            ..platformDispatcher.textScaleFactorTestValue = 1.0
            ..physicalSize = screenSizeLandscape;

          final docKey = GlobalKey();
          await tester.pumpWidget(
            _createTestApp(
              gestureMode: DocumentGestureMode.android,
              docKey: docKey,
            ),
          );
          await tester.pumpAndSettle();

          // Place caret at a position that will move to the next line when the width contracts
          await tester.tapAtDocumentPosition(tapPosition);
          await tester.pump();

          // Ensure that the caret is displayed at the correct (x,y) in the document before phone rotation
          final initialCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();
          final expectedInitialCaretOffset =
              _computeExpectedMobileCaretOffsetInDocumentLayout(tester, docKey, tapPosition);
          expect(initialCaretOffset, expectedInitialCaretOffset);

          // Make the window more narrow, pushing the caret text position up a line.
          tester.view.physicalSize = screenSizePortrait;
          await tester.pumpAndSettle();

          // Ensure that after rotating the phone, the caret updated its (x,y) to match the text
          // position that was pushed down to the next line.
          final finalCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();
          final expectedFinalCaretOffset =
              _computeExpectedMobileCaretOffsetInDocumentLayout(tester, docKey, tapPosition);
          expect(finalCaretOffset, expectedFinalCaretOffset);
        });
      });

      group('on iOS', () {
        testWidgetsOnIos('from portrait to landscape updates caret position', (WidgetTester tester) async {
          tester.view
            ..devicePixelRatio = 1.0
            ..platformDispatcher.textScaleFactorTestValue = 1.0
            ..physicalSize = screenSizePortrait;

          final docKey = GlobalKey();
          await tester.pumpWidget(
            _createTestApp(
              gestureMode: DocumentGestureMode.iOS,
              docKey: docKey,
            ),
          );
          await tester.pumpAndSettle();

          // Place caret at a position that will move to the preceding line when the width expands
          await tester.tapAtDocumentPosition(tapPosition);
          await tester.pump();

          // Ensure that the caret is displayed at the correct (x,y) in the document before phone rotation
          final initialOffset = SuperEditorInspector.findCaretOffsetInDocument();
          final expectedInitialCaretOffset =
              _computeExpectedMobileCaretOffsetInDocumentLayout(tester, docKey, tapPosition);
          expect(initialOffset, expectedInitialCaretOffset);

          // Make the window wider, pushing the caret text position up a line.
          tester.view.physicalSize = screenSizeLandscape;
          await tester.pumpAndSettle();

          // Ensure that after rotating the phone, the caret updated its (x,y) to match the text
          // position that was pushed up to the preceding line.
          final finalCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();
          final expectedFinalCaretOffset =
              _computeExpectedMobileCaretOffsetInDocumentLayout(tester, docKey, tapPosition);
          expect(finalCaretOffset, expectedFinalCaretOffset);
        });

        testWidgetsOnIos('from landscape to portrait updates caret position', (WidgetTester tester) async {
          tester.view
            ..devicePixelRatio = 1.0
            ..platformDispatcher.textScaleFactorTestValue = 1.0
            ..physicalSize = screenSizeLandscape;

          final docKey = GlobalKey();
          await tester.pumpWidget(
            _createTestApp(
              gestureMode: DocumentGestureMode.iOS,
              docKey: docKey,
            ),
          );
          await tester.pumpAndSettle();

          // Place caret at a position that will move to the next line when the width contracts
          await tester.tapAtDocumentPosition(tapPosition);
          await tester.pump();

          // Ensure that the caret is displayed at the correct (x,y) in the document before phone rotation
          final initialOffset = SuperEditorInspector.findCaretOffsetInDocument();
          final expectedInitialCaretOffset =
              _computeExpectedMobileCaretOffsetInDocumentLayout(tester, docKey, tapPosition);
          expect(initialOffset, expectedInitialCaretOffset);

          // Make the window more narrow, pushing the caret text position down a line.
          tester.view.physicalSize = screenSizePortrait;
          await tester.pumpAndSettle();

          // Ensure that after rotating the phone, the caret updated its (x,y) to match the text
          // position that was pushed down to the next line.
          final finalCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();
          final expectedFinalCaretOffset =
              _computeExpectedMobileCaretOffsetInDocumentLayout(tester, docKey, tapPosition);
          expect(finalCaretOffset, expectedFinalCaretOffset);
        });
      });
    });

    testWidgetsOnAllPlatforms('blinks the caret when the user places the caret with a single tap', (tester) async {
      // Configure BlinkController to animate, otherwise it won't blink.
      BlinkController.indeterminateAnimationsEnabled = true;
      addTearDown(() => BlinkController.indeterminateAnimationsEnabled = false);

      await tester //
          .createDocument()
          .withSingleEmptyParagraph()
          .pump();

      // Tap to place the caret at the beginning of the document.
      // We don't use the robot method here because it calls pumpAndSettle,
      // which causes a pumpAndSettle timeout, because we are constantly
      // scheduling frames.
      await tester.tap(find.byType(SuperEditor));
      await tester.pump();

      // Ensure caret is visible.
      expect(SuperEditorInspector.isCaretVisible(), true);

      // Duration to switch between visible and invisible.
      final flashPeriod = SuperEditorInspector.caretFlashPeriod();

      // Trigger a frame with an ellapsed time equal to the flashPeriod,
      // so the caret should change from visible to invisible.
      await tester.pump(flashPeriod);

      // Ensure caret is invisible after the flash period.
      expect(SuperEditorInspector.isCaretVisible(), false);

      // Trigger another frame to make caret visible again.
      await tester.pump(flashPeriod);

      // Ensure caret is visible.
      expect(SuperEditorInspector.isCaretVisible(), true);
    });
  });
}

Widget _createTestApp({required DocumentGestureMode gestureMode, required GlobalKey docKey}) {
  final doc = _createTestDocument();
  final composer = MutableDocumentComposer();
  final editor = createDefaultDocumentEditor(document: doc, composer: composer);

  return MaterialApp(
    home: Scaffold(
      body: SuperEditor(
        documentLayoutKey: docKey,
        editor: editor,
        document: doc,
        composer: composer,
        gestureMode: gestureMode,
      ),
    ),
  );
}

/// Given a [textPosition], compute the expected (x,y) for the caret
///
/// Should be used only when the document gesture mode is equal to [DocumentGestureMode.mouse]
Offset _computeExpectedDesktopCaretOffset(WidgetTester tester, TextPosition textPosition) {
  return SuperEditorInspector.calculateOffsetForCaret(DocumentPosition(
    nodeId: "1",
    nodePosition: TextNodePosition.fromTextPosition(textPosition),
  ));
}

/// Given a [textPosition], compute the expected (x,y) for the caret within the document layout.
///
/// Should be used only when the document gesture mode is equal to [DocumentGestureMode.android]
/// or [DocumentGestureMode.iOS]
Offset _computeExpectedMobileCaretOffsetInDocumentLayout(
    WidgetTester tester, GlobalKey docKey, DocumentPosition documentPosition) {
  final docLayout = docKey.currentState as DocumentLayout;
  final extentRect = docLayout.getRectForSelection(documentPosition, documentPosition)!;
  return Offset(extentRect.left, extentRect.top);
}

MutableDocument _createTestDocument() {
  return MutableDocument(
    nodes: [
      ParagraphNode(
        id: '1',
        text: AttributedText(
          "Super Editor is a toolkit to help you build document editors, document layouts, text fields, and more.",
        ),
      )
    ],
  );
}

Future<void> _resizeWindow({
  required WidgetTester tester,
  required Size initialScreenSize,
  required Size finalScreenSize,
  required int frameCount,
}) async {
  double resizedWidth = 0.0;
  double resizedHeight = 0.0;
  double totalWidthResize = initialScreenSize.width - finalScreenSize.width;
  double totalHeightResize = initialScreenSize.height - finalScreenSize.height;
  double widthShrinkPerFrame = totalWidthResize / frameCount;
  double heightShrinkPerFrame = totalHeightResize / frameCount;
  for (var i = 0; i < frameCount; i++) {
    resizedWidth += widthShrinkPerFrame;
    resizedHeight += heightShrinkPerFrame;
    final currentScreenSize = (initialScreenSize - Offset(resizedWidth, resizedHeight)) as Size;
    tester.view.physicalSize = currentScreenSize;
    await tester.pumpAndSettle();
  }
}
