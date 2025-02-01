import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:super_editor/src/infrastructure/platforms/android/selection_handles.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';
import 'package:super_text_layout/super_text_layout.dart';

import '../../test_runners.dart';
import '../../test_tools.dart';
import '../supereditor_test_tools.dart';

void main() {
  group("SuperEditor > Android > overlay controls >", () {
    testWidgetsOnAndroid("hides all controls when placing the caret", (tester) async {
      await _pumpSingleParagraphApp(tester);

      // Place the caret.
      await tester.tapInParagraph("1", 200);

      // Ensure all controls are hidden.
      expect(SuperEditorInspector.isMobileMagnifierVisible(), isFalse);
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);
    });

    testWidgetsOnAndroid("shows magnifier when dragging the caret", (tester) async {
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
      await tester.pump(kTapMinTime);
    });

    testWidgetsOnAndroid("shows magnifier when dragging the collapsed handle", (tester) async {
      await _pumpSingleParagraphApp(tester);

      // Place the caret.
      await tester.tapInParagraph("1", 200);

      // Press and drag the caret somewhere else in the paragraph.
      final gesture = await tester.pressDownOnCollapsedMobileHandle();
      for (int i = 0; i < 5; i += 1) {
        await gesture.moveBy(const Offset(24, 0));
        await tester.pump();
      }

      // Ensure magnifier is visible and toolbar is hidden.
      expect(SuperEditorInspector.isMobileMagnifierVisible(), isTrue);
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);

      // Resolve the gesture so that we don't have pending gesture timers.
      await gesture.up();
      await tester.pump(kTapMinTime);
    });

    testWidgetsOnAndroid("shows and hides toolbar upon tap on collapsed handle", (tester) async {
      await _pumpSingleParagraphApp(tester);

      // Place the caret at the beginning of the document.
      await tester.placeCaretInParagraph("1", 0);

      // Ensure the toolbar isn't visible.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);

      // Tap the drag handle to show the toolbar.
      await tester.tapOnCollapsedMobileHandle();
      await tester.pump();

      // Ensure the toolbar is visible.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isTrue);

      // Tap the drag handle to hide the toolbar.
      await tester.tapOnCollapsedMobileHandle();
      await tester.pump();

      // Ensure the toolbar isn't visible.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);
    });

    testWidgetsOnAndroid("hides toolbar when the user taps to move the caret", (tester) async {
      await _pumpSingleParagraphApp(tester);

      // Place the caret at the beginning of the document.
      await tester.placeCaretInParagraph("1", 0);

      // Ensure the toolbar isn't visible.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);

      // Tap the drag handle to show the toolbar.
      await tester.tapOnCollapsedMobileHandle();
      await tester.pump();

      // Ensure the toolbar is visible.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isTrue);

      // Place the caret at "Lorem |ipsum".
      await tester.placeCaretInParagraph("1", 6);

      // Ensure the toolbar isn't visible.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);
    });

    testWidgetsOnAndroid("does not show toolbar upon first tap", (tester) async {
      await tester //
          .createDocument()
          .withTwoEmptyParagraphs()
          .pump();

      // Place the caret at the beginning of the document.
      await tester.placeCaretInParagraph("1", 0);

      // Ensure the toolbar isn't visible.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);

      // Wait for the collapsed handle to disappear so that it doesn't cover the
      // line below.
      await tester.pump(const Duration(seconds: 5));

      // Place the caret at the beginning of the second paragraph, at the same offset.
      await tester.placeCaretInParagraph("2", 0);

      // Ensure the toolbar isn't visible.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isFalse);
    });

    testWidgetsOnAndroid("shows toolbar when selection is expanded", (tester) async {
      await _pumpSingleParagraphApp(tester);

      // Select a word.
      await tester.doubleTapInParagraph("1", 200);

      // Ensure toolbar is visible and magnifier is hidden.
      expect(SuperEditorInspector.isMobileToolbarVisible(), isTrue);
      expect(SuperEditorInspector.isMobileMagnifierVisible(), isFalse);
    });

    testWidgetsOnAndroid("hides toolbar when tapping on expanded selection", (tester) async {
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

    testWidgetsOnAndroid("shows magnifier when dragging expanded handle", (tester) async {
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
      await tester.pump(kTapMinTime);
    });

    testWidgetsOnAndroid("shows expanded handles when dragging to a collapsed selection", (tester) async {
      await _pumpSingleParagraphApp(tester);

      // Select the word "Lorem".
      await tester.doubleTapInParagraph('1', 1);

      // Press the upstream drag handle and drag it downstream until "Lorem|" to collapse the selection.
      final gesture = await tester.pressDownOnUpstreamMobileHandle();
      await gesture.moveBy(SuperEditorInspector.findDeltaBetweenCharactersInTextNode(NodePath.forNode('1'), 0, 5));
      await tester.pump();

      // Ensure that the selection collapsed.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        selectionEquivalentTo(
          DocumentSelection.collapsed(
            position:
                DocumentPosition(documentPath: NodePath.forNode('1'), nodePosition: const TextNodePosition(offset: 5)),
          ),
        ),
      );

      // Find the rectangle for the selected character.
      final documentLayout = SuperEditorInspector.findDocumentLayout();
      final selectedPositionRect = documentLayout.getRectForPosition(
        DocumentPosition(documentPath: NodePath.forNode('1'), nodePosition: const TextNodePosition(offset: 5)),
      )!;

      // Ensure that the drag handles are visible and in the correct location.
      expect(SuperEditorInspector.findAllMobileDragHandles(), findsExactly(2));
      expect(
        tester.getTopLeft(SuperEditorInspector.findMobileDownstreamDragHandle()),
        offsetMoreOrLessEquals(documentLayout.getGlobalOffsetFromDocumentOffset(selectedPositionRect.bottomRight) -
            Offset(AndroidSelectionHandle.defaultTouchRegionExpansion.left, 0)),
      );
      expect(
        tester.getTopRight(SuperEditorInspector.findMobileUpstreamDragHandle()),
        offsetMoreOrLessEquals(documentLayout.getGlobalOffsetFromDocumentOffset(selectedPositionRect.bottomRight) +
            Offset(AndroidSelectionHandle.defaultTouchRegionExpansion.right, 0)),
      );

      // Release the drag handle.
      await gesture.up();
      await tester.pumpAndSettle();

      // Ensure the expanded handles were hidden and the collapsed handle
      // and the caret were displayed.
      expect(SuperEditorInspector.findAllMobileDragHandles(), findsOneWidget);
      expect(SuperEditorInspector.findMobileCaretDragHandle(), findsOneWidget);
      expect(SuperEditorInspector.isCaretVisible(), isTrue);
    });

    testWidgetsOnAndroid("shows expanded handles when expanding the selection", (tester) async {
      final context = await _pumpSingleParagraphApp(tester);

      // Place the caret at the beginning of the paragraph.
      await tester.placeCaretInParagraph("1", 0);
      await tester.pump();

      // Ensure the collapsed handle is visible and the expanded handles aren't visible.
      expect(SuperEditorInspector.findMobileCaretDragHandle(), findsOneWidget);
      expect(SuperEditorInspector.findMobileExpandedDragHandles(), findsNothing);

      // Select all of the text.
      context.findEditContext().commonOps.selectAll();
      await tester.pump();

      // Ensure the handles are visible and the collapsed handle isn't visible.
      expect(SuperEditorInspector.findMobileExpandedDragHandles(), findsNWidgets(2));
      expect(SuperEditorInspector.findMobileCaretDragHandle(), findsNothing);
    });

    testWidgetsOnAndroid("hides expanded handles and toolbar when deleting an expanded selection", (tester) async {
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

    testWidgetsOnAndroid("allows customizing the collapsed handle", (tester) async {
      // Use a key different from the provided by the builder to make sure our handle
      // is used instead of the default one.
      final collapsedFinderKey = GlobalKey();

      await tester //
          .createDocument()
          .withSingleParagraph()
          .withAndroidCollapsedHandleBuilder(
        (
          BuildContext context, {
          required Key handleKey,
          required LeaderLink focalPoint,
          required DocumentHandleGestureDelegate gestureDelegate,
          required bool shouldShow,
        }) {
          return SizedBox(
            key: collapsedFinderKey,
            width: 20,
            height: 20,
            child: Container(
              key: handleKey,
            ),
          );
        },
      ).pump();

      // Place the caret at the beginning of the document to show the collapsed handle.
      await tester.placeCaretInParagraph('1', 0);

      // Ensure the custom handle is used.
      expect(find.byKey(collapsedFinderKey), findsOneWidget);
    });

    testWidgetsOnAndroid("allows customizing the expanded handles", (tester) async {
      // Use keys different from the provided by the builder to make sure our handles
      // are used instead of the default ones.
      final upstreamFinderKey = GlobalKey();
      final downstreamFinderKey = GlobalKey();

      await tester //
          .createDocument()
          .withSingleParagraph()
          .withAndroidExpandedHandlesBuilder(
        (
          BuildContext context, {
          required Key upstreamHandleKey,
          required LeaderLink upstreamFocalPoint,
          required DocumentHandleGestureDelegate upstreamGestureDelegate,
          required Key downstreamHandleKey,
          required LeaderLink downstreamFocalPoint,
          required DocumentHandleGestureDelegate downstreamGestureDelegate,
          required bool shouldShow,
        }) {
          return Stack(
            children: [
              SizedBox(
                key: upstreamFinderKey,
                width: 20,
                height: 20,
                child: Container(
                  key: upstreamHandleKey,
                ),
              ),
              SizedBox(
                key: downstreamFinderKey,
                width: 20,
                height: 20,
                child: Container(
                  key: downstreamHandleKey,
                ),
              ),
            ],
          );
        },
      ).pump();

      // Double tap to select the first word and show the expanded handles.
      await tester.doubleTapInParagraph('1', 0);

      // Ensure the custom handles are used.
      expect(find.byKey(upstreamFinderKey), findsOneWidget);
      expect(find.byKey(downstreamFinderKey), findsOneWidget);
    });

    group('shows magnifier above the caret when dragging the collapsed handle', () {
      testWidgetsOnAndroid('with an ancestor scrollable', (tester) async {
        final scrollController = ScrollController();

        // Pump the editor inside a CustomScrollView with a number of widgets
        // above the editor, so we can check if the magnifier is positioned at the correct
        // position, even if the editor isn't aligned with the top-left of the screen.
        await tester
            .createDocument()
            .withSingleParagraph()
            .withCustomWidgetTreeBuilder(
              (superEditor) => MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 300,
                    height: 300,
                    child: CustomScrollView(
                      controller: scrollController,
                      slivers: [
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (BuildContext context, int index) => Text('$index'),
                            childCount: 50,
                          ),
                        ),
                        superEditor,
                      ],
                    ),
                  ),
                ),
              ),
            )
            .pump();

        // Ensure the scrollview is scrollable.
        expect(scrollController.position.maxScrollExtent, greaterThan(0.0));

        // Jump to the end of the content.
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        await tester.pump();

        // Place the caret near the end of the document.
        await tester.tapInParagraph("1", 440);

        // Press and drag the caret somewhere else in the paragraph.
        final gesture = await tester.pressDownOnCollapsedMobileHandle();
        for (int i = 0; i < 5; i += 1) {
          await gesture.moveBy(const Offset(24, 0));
          await tester.pump();
        }

        // Ensure that the magnifier appears above the caret. To check this, we make
        // sure the bottom of the magnifier is above the top of the caret, and we make
        // sure that the bottom of the magnifier is not unreasonable far above the caret.
        expect(SuperEditorInspector.isMobileMagnifierVisible(), isTrue);
        expect(
          tester.getBottomLeft(SuperEditorInspector.findMobileMagnifier()).dy,
          lessThan(tester.getTopLeft(SuperEditorInspector.findMobileCaret()).dy),
        );
        expect(
          tester.getTopLeft(SuperEditorInspector.findMobileCaret()).dy -
              tester.getBottomLeft(SuperEditorInspector.findMobileMagnifier()).dy,
          lessThan(20.0),
        );

        // Resolve the gesture so that we don't have pending gesture timers.
        await gesture.up();
        await tester.pump(kTapMinTime);
      });

      testWidgetsOnAndroid('without an ancestor scrollable', (tester) async {
        final scrollController = ScrollController();

        await tester //
            .createDocument()
            .withSingleParagraph()
            .withScrollController(scrollController)
            .withEditorSize(const Size(300, 300))
            .pump();

        // Ensure the editor is scrollable.
        expect(scrollController.position.maxScrollExtent, greaterThan(0.0));

        // Jump to the end of the content.
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        await tester.pump();

        // Place the caret near the end of the document.
        await tester.tapInParagraph("1", 440);
        await tester.pumpAndSettle();

        // Press and drag the caret somewhere else in the paragraph.
        final gesture = await tester.pressDownOnCollapsedMobileHandle();
        for (int i = 0; i < 5; i += 1) {
          await gesture.moveBy(const Offset(24, 0));
          await tester.pump();
        }

        // Ensure that the magnifier appears above the caret. To check this, we make
        // sure the bottom of the magnifier is above the top of the caret, and we make
        // sure that the bottom of the magnifier is not unreasonable far above the caret.
        expect(SuperEditorInspector.isMobileMagnifierVisible(), isTrue);
        expect(
          tester.getBottomLeft(SuperEditorInspector.findMobileMagnifier()).dy,
          lessThan(tester.getTopLeft(SuperEditorInspector.findMobileCaret()).dy),
        );
        expect(
          tester.getTopLeft(SuperEditorInspector.findMobileCaret()).dy -
              tester.getBottomLeft(SuperEditorInspector.findMobileMagnifier()).dy,
          lessThan(20.0),
        );

        // Resolve the gesture so that we don't have pending gesture timers.
        await gesture.up();
        await tester.pump(kTapMinTime);
      });

      testWidgetsOnAndroid('without an ancestor scrollable having widgets above the editor', (tester) async {
        final scrollController = ScrollController();

        // Pump a tree with another widget above the editor,
        // so we can check if the magnifier is positioned at the correct
        // position, even if the editor isn't aligned with the top-left of the screen.
        await tester //
            .createDocument()
            .withSingleParagraph()
            .withScrollController(scrollController)
            .withCustomWidgetTreeBuilder(
              (superEditor) => MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 300,
                    height: 300,
                    child: Column(
                      children: [
                        const SizedBox(height: 100),
                        Expanded(child: superEditor),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .pump();

        // Ensure the editor is scrollable.
        expect(scrollController.position.maxScrollExtent, greaterThan(0.0));

        // Jump to the end of the content.
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        await tester.pump();

        // Place the caret near the end of the document.
        await tester.tapInParagraph("1", 440);
        await tester.pumpAndSettle();

        // Press and drag the caret somewhere else in the paragraph.
        final gesture = await tester.pressDownOnCollapsedMobileHandle();
        for (int i = 0; i < 5; i += 1) {
          await gesture.moveBy(const Offset(24, 0));
          await tester.pump();
        }

        // Ensure that the magnifier appears above the caret. To check this, we make
        // sure the bottom of the magnifier is above the top of the caret, and we make
        // sure that the bottom of the magnifier is not unreasonable far above the caret.
        expect(SuperEditorInspector.isMobileMagnifierVisible(), isTrue);
        expect(
          tester.getBottomLeft(SuperEditorInspector.findMobileMagnifier()).dy,
          lessThan(tester.getTopLeft(SuperEditorInspector.findMobileCaret()).dy),
        );
        expect(
          tester.getTopLeft(SuperEditorInspector.findMobileCaret()).dy -
              tester.getBottomLeft(SuperEditorInspector.findMobileMagnifier()).dy,
          lessThan(20.0),
        );

        // Resolve the gesture so that we don't have pending gesture timers.
        await gesture.up();
        await tester.pump(kTapMinTime);
      });
    });

    group("on device and web > shows", () {
      testWidgetsOnAndroidDeviceAndWeb("caret", (tester) async {
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

      testWidgetsOnAndroidDeviceAndWeb("upstream and downstream handles", (tester) async {
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

    group("on device > shows", () {
      testWidgetsOnAndroid("the magnifier", (tester) async {
        await _pumpSingleParagraphApp(tester);

        final gesture = await tester.longPressDownInParagraph("1", 1);
        for (int i = 0; i < 5; i += 1) {
          await gesture.moveBy(const Offset(-24, 0));
          await tester.pump();
        }

        // Ensure the magnifier is wanted AND visible.
        expect(SuperEditorInspector.wantsMobileMagnifierToBeVisible(), isTrue);
        expect(SuperEditorInspector.isMobileMagnifierVisible(), isTrue);
      });

      testWidgetsOnAndroid("the floating toolbar", (tester) async {
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

    group("on web > shows", () {
      testWidgetsOnWebAndroid("the magnifier", (tester) async {
        // Explanation: On iOS, we defer some overlay controls to the mobile browser.
        // This test is here to explicitly show that we don't defer those things to
        // the mobile browser on Android.
        await _pumpSingleParagraphApp(tester);

        // Long press and drag so that the magnifier appears.
        final gesture = await tester.longPressDownInParagraph("1", 1);
        for (int i = 0; i < 5; i += 1) {
          await gesture.moveBy(const Offset(-24, 0));
          await tester.pump();
        }

        // Ensure the magnifier is desired AND displayed.
        expect(SuperEditorInspector.wantsMobileMagnifierToBeVisible(), isTrue);
        expect(SuperEditorInspector.isMobileMagnifierVisible(), isTrue);
      });

      testWidgetsOnWebAndroid("the floating toolbar", (tester) async {
        // Explanation: On iOS, we defer some overlay controls to the mobile browser.
        // This test is here to explicitly show that we don't defer those things to
        // the mobile browser on Android.
        await _pumpSingleParagraphApp(tester);

        // Create an expanded selection.
        await tester.doubleTapInParagraph("1", 1);

        // Ensure we have an expanded selection.
        expect(SuperEditorInspector.findDocumentSelection(), isNotNull);
        expect(SuperEditorInspector.findDocumentSelection()!.isCollapsed, isFalse);

        // Ensure that the toolbar is desired AND displayed
        expect(SuperEditorInspector.wantsMobileToolbarToBeVisible(), isTrue);
        expect(SuperEditorInspector.isMobileToolbarVisible(), isTrue);
      });
    });
  });
}

Future<TestDocumentContext> _pumpSingleParagraphApp(WidgetTester tester) async {
  return await tester
      .createDocument()
      // Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor...
      .withSingleParagraph()
      .pump();
}
