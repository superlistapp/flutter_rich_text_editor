import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';
import 'package:super_text_layout/super_text_layout.dart';

import '../../test_runners.dart';
import '../../test_tools.dart';
import '../supereditor_test_tools.dart';

void main() {
  group("SuperEditor > iOS > overlay controls >", () {
    testWidgetsOnIos("hides all controls when placing the caret", (tester) async {
      await _pumpSingleParagraphApp(tester);

      // Place the caret.
      await tester.tapInParagraph("1", 200);

      // Ensure all controls are hidden.
      expect(SuperEditorInspector.isMobileMagnifierVisible(), isFalse);
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);
    });

    testWidgetsOnIos("shows toolbar when tapping on caret", (tester) async {
      await _pumpSingleParagraphApp(tester);

      // Place the caret at the end of a word, because iOS snaps the caret
      // to word boundaries by default.
      await tester.tapInParagraph("1", 207);

      // Ensure all controls are hidden.
      expect(SuperEditorInspector.isMobileMagnifierVisible(), isFalse);
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);

      // Tap again on the caret.
      await tester.tapInParagraph("1", 207);

      // Ensure that the toolbar is visible.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isTrue);
      expect(SuperEditorInspector.isMobileMagnifierVisible(), isFalse);
    });

    testWidgetsOnIos("shows magnifier when dragging the caret", (tester) async {
      await _pumpSingleParagraphApp(tester);

      // Place the caret.
      await tester.tapInParagraph("1", 200);

      // Press and drag the caret somewhere else in the paragraph.
      final gesture = await tester.tapDownInParagraph("1", 200);
      for (int i = 0; i < 5; i += 1) {
        await gesture.moveBy(const Offset(24, 0));
        await tester.pump();
      }

      // Ensure magnifier is visible and toolbar is hidden.
      expect(SuperEditorInspector.isMobileMagnifierVisible(), isTrue);
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);

      // Resolve the gesture so that we don't have pending gesture timers.
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgetsOnIos("does not blink caret while dragging it", (tester) async {
      BlinkController.indeterminateAnimationsEnabled = true;
      addTearDown(() => BlinkController.indeterminateAnimationsEnabled = false);

      await _pumpSingleParagraphApp(tester);

      // Place the caret.
      await tester.tapInParagraph("1", 200);

      // Press and drag the caret somewhere else in the paragraph.
      final gesture = await tester.tapDownInParagraph("1", 200);
      for (int i = 0; i < 5; i += 1) {
        await gesture.moveBy(const Offset(24, 0));
        await tester.pump();
      }

      // Duration for the caret to switch between visible and invisible.
      final flashPeriod = SuperEditorInspector.caretFlashPeriod();

      // Ensure caret is visible.
      expect(SuperEditorInspector.isCaretVisible(), isTrue);

      // Trigger a frame with an ellapsed time equal to the flashPeriod,
      // so if the caret is blinking it will change from visible to invisible.
      await tester.pump(flashPeriod);

      // Ensure caret is still visible after the flash period, which means it isn't blinking.
      expect(SuperEditorInspector.isCaretVisible(), isTrue);

      // Trigger another frame.
      await tester.pump(flashPeriod);

      // Ensure caret is still visible.
      expect(SuperEditorInspector.isCaretVisible(), isTrue);

      // Resolve the gesture so that we don't have pending gesture timers.
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgetsOnIos("shows toolbar when selection is expanded", (tester) async {
      await _pumpSingleParagraphApp(tester);

      // Select a word.
      await tester.doubleTapInParagraph("1", 200);

      // Ensure toolbar is visible and magnifier is hidden.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isTrue);
      expect(SuperEditorInspector.isMobileMagnifierVisible(), isFalse);
    });

    testWidgetsOnIos("hides toolbar when tapping on expanded selection", (tester) async {
      await _pumpSingleParagraphApp(tester);

      // Select a word.
      await tester.doubleTapInParagraph("1", 200);

      // Ensure toolbar is visible and magnifier is hidden.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isTrue);
      expect(SuperEditorInspector.isMobileMagnifierVisible(), isFalse);

      // Tap on the selected text.
      await tester.tapInParagraph("1", 200);

      // Ensure that all controls are now hidden.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);
      expect(SuperEditorInspector.isMobileMagnifierVisible(), isFalse);
    });

    testWidgetsOnIos("does not show toolbar upon first tap", (tester) async {
      await tester //
          .createDocument()
          .withTwoEmptyParagraphs()
          .pump();

      // Place the caret at the beginning of the document.
      await tester.placeCaretInParagraph("1", 0);

      // Ensure the toolbar isn't visible.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);

      // Place the caret at the beginning of the second paragraph, at the same offset.
      await tester.placeCaretInParagraph("2", 0);

      // Ensure the toolbar isn't visible.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);
    });

    testWidgetsOnIos("shows magnifier when dragging expanded handle", (tester) async {
      await _pumpSingleParagraphApp(tester);

      // Select a word.
      await tester.doubleTapInParagraph("1", 250);

      // Press and drag upstream handle
      final gesture = await tester.pressDownOnUpstreamMobileHandle();
      for (int i = 0; i < 5; i += 1) {
        await gesture.moveBy(const Offset(-24, 0));
        await tester.pump();
      }

      // Ensure that the magnifier is visible.
      expect(SuperEditorInspector.isMobileMagnifierVisible(), isTrue);
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);

      // Resolve the gesture so that we don't have pending gesture timers.
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgetsOnIos("hides expanded handles and toolbar when deleting an expanded selection", (tester) async {
      // Configure BlinkController to animate, otherwise it won't blink. We want to make sure
      // the caret blinks after deleting the content.
      BlinkController.indeterminateAnimationsEnabled = true;
      addTearDown(() => BlinkController.indeterminateAnimationsEnabled = false);

      await _pumpSingleParagraphApp(tester);

      // Double tap to select "Lorem".
      await tester.doubleTapInParagraph("1", 1);
      await tester.pump();

      // Ensure the toolbar and the drag handles are visible.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isTrue);
      expect(SuperEditorInspector.findMobileExpandedDragHandles(), findsNWidgets(2));

      // Press backspace to delete the word "Lorem" while the expanded handles are visible.
      await tester.ime.backspace(getter: imeClientGetter);

      // Ensure the toolbar and the drag handles were hidden.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);
      expect(SuperEditorInspector.findMobileExpandedDragHandles(), findsNothing);

      // Ensure caret is blinking.

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

    testWidgetsOnIos("keeps current selection when tapping on caret", (tester) async {
      await _pumpSingleParagraphApp(tester);

      // Tap at "consectetur|" to place the caret.
      await tester.tapInParagraph("1", 39);

      // Ensure that the selection was placed at the end of the word.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        selectionEquivalentTo(const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "1",
            nodePosition: TextNodePosition(offset: 39),
          ),
        )),
      );

      // Press and drag the caret to "con|sectetur" because dragging is the only way
      // we can place the caret at the middle of a word when caret snapping is enabled.
      final gesture = await tester.tapDownInParagraph("1", 39);
      for (int i = 0; i < 7; i += 1) {
        await gesture.moveBy(const Offset(-19, 0));
        await tester.pump();
      }

      // Resolve the gesture so that we don't have pending gesture timers.
      await gesture.up();
      await tester.pump(kDoubleTapTimeout);

      // Ensure that the selection moved to "con|sectetur".
      expect(
        SuperEditorInspector.findDocumentSelection(),
        selectionEquivalentTo(const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "1",
            nodePosition: TextNodePosition(offset: 32),
          ),
        )),
      );

      // Ensure the toolbar is not visible.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);

      // Tap on the caret.
      await tester.tapInParagraph("1", 32);

      // Ensure the selection was kept at "con|sectetur".
      expect(
        SuperEditorInspector.findDocumentSelection(),
        selectionEquivalentTo(const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "1",
            nodePosition: TextNodePosition(offset: 32),
          ),
        )),
      );

      // Ensure the toolbar is visible.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isTrue);
    });

    group("on device and web > shows ", () {
      testWidgetsOnIosDeviceAndWeb("caret", (tester) async {
        await _pumpSingleParagraphApp(tester);

        // Create a collapsed selection.
        await tester.tapInParagraph("1", 1);

        // Ensure we have a collapsed selection.
        expect(SuperEditorInspector.findDocumentSelection(), isNotNull);
        expect(SuperEditorInspector.findDocumentSelection()!.isCollapsed, isTrue);

        // Ensure caret (and only caret) is visible.
        expect(SuperEditorInspector.findMobileCaret(), findsOneWidget);
        expect(SuperEditorInspector.findMobileExpandedDragHandles(), findsNothing);
      });

      testWidgetsOnIosDeviceAndWeb("upstream and downstream handles", (tester) async {
        await _pumpSingleParagraphApp(tester);

        // Create an expanded selection.
        await tester.doubleTapInParagraph("1", 1);

        // Ensure we have an expanded selection.
        expect(SuperEditorInspector.findDocumentSelection(), isNotNull);
        expect(SuperEditorInspector.findDocumentSelection()!.isCollapsed, isFalse);

        // Ensure expanded handles are visible, but caret isn't.
        expect(SuperEditorInspector.findMobileCaret(), findsNothing);
        expect(SuperEditorInspector.findMobileUpstreamDragHandle(), findsOneWidget);
        expect(SuperEditorInspector.findMobileDownstreamDragHandle(), findsOneWidget);
      });
    });

    group("on device >", () {
      group("shows", () {
        testWidgetsOnIos("the magnifier", (tester) async {
          await _pumpSingleParagraphApp(tester);

          // Long press, and hold, so that the magnifier appears.
          await tester.longPressDownInParagraph("1", 1);

          // Ensure the magnifier is wanted AND visible.
          expect(SuperEditorInspector.wantsMobileMagnifierToBeVisible(), isTrue);
          expect(SuperEditorInspector.isMobileMagnifierVisible(), isTrue);
        });

        testWidgetsOnIos("the floating toolbar", (tester) async {
          await _pumpSingleParagraphApp(tester);

          // Create an expanded selection.
          await tester.doubleTapInParagraph("1", 1);

          // Ensure we have an expanded selection.
          expect(SuperEditorInspector.findDocumentSelection(), isNotNull);
          expect(SuperEditorInspector.findDocumentSelection()!.isCollapsed, isFalse);

          // Ensure that the toolbar is desired AND displayed.
          expect(SuperEditorInspector.wantsMobileToolbarToBeVisible(), isTrue);
          expect(SuperEditorInspector.isMobileToolbarVisible(), isTrue);
        });
      });
    });

    group("on web >", () {
      group("defers to browser to show", () {
        testWidgetsOnWebIos("the magnifier", (tester) async {
          await _pumpSingleParagraphApp(tester);

          // Long press, and hold, so that the magnifier appears.
          await tester.longPressDownInParagraph("1", 1);

          // Ensure the magnifier is desired, but not displayed.
          expect(SuperEditorInspector.wantsMobileMagnifierToBeVisible(), isTrue);
          expect(SuperEditorInspector.isMobileMagnifierVisible(), isFalse);
        });

        testWidgetsOnWebIos("the floating toolbar", (tester) async {
          await _pumpSingleParagraphApp(tester);

          // Create an expanded selection.
          await tester.doubleTapInParagraph("1", 1);

          // Ensure we have an expanded selection.
          expect(SuperEditorInspector.findDocumentSelection(), isNotNull);
          expect(SuperEditorInspector.findDocumentSelection()!.isCollapsed, isFalse);

          // Ensure that the toolbar is desired, but not displayed.
          expect(SuperEditorInspector.wantsMobileToolbarToBeVisible(), isTrue);
          expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);
        });
      });
    });
  });
}

Future<void> _pumpSingleParagraphApp(WidgetTester tester) async {
  await tester
      .createDocument()
      // Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor...
      .withSingleParagraph()
      .simulateSoftwareKeyboardInsets(true)
      .useIosSelectionHeuristics(true)
      .pump();
}
