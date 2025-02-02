import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/src/infrastructure/links.dart';
import 'package:super_editor/src/infrastructure/platforms/android/selection_handles.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';

import '../test_tools.dart';
import 'supereditor_test_tools.dart';

void main() {
  group('SuperEditor gestures', () {
    testWidgetsOnAllPlatforms('places the caret when tapping an empty document (top left)', (tester) async {
      final testContext = await tester
          .createDocument() //
          .withSingleEmptyParagraph()
          .withEditorSize(const Size(300, 300))
          .pump();

      // Ensure editor is not focused
      expect(SuperEditorInspector.hasFocus(), isFalse);

      // Tap inside SuperEditor
      await tester.tapAt(tester.getTopLeft(find.byType(SuperEditor)) + const Offset(1, 1));
      await tester.pump(kTapMinTime);

      // Ensure editor is focused
      expect(SuperEditorInspector.hasFocus(), isTrue);

      // Ensure selection is at the beginning of the document
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: testContext.findEditContext().document.first.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
      );
    });

    testWidgetsOnAllPlatforms('places the caret when tapping an empty document (top right)', (tester) async {
      final testContext = await tester
          .createDocument() //
          .withSingleEmptyParagraph()
          .withEditorSize(const Size(300, 300))
          .pump();

      // Ensure editor is not focused
      expect(SuperEditorInspector.hasFocus(), isFalse);

      // Tap inside SuperEditor
      await tester.tapAt(tester.getTopRight(find.byType(SuperEditor)) + const Offset(-1, 1));
      await tester.pump(kTapMinTime);

      // Ensure editor is focused
      expect(SuperEditorInspector.hasFocus(), isTrue);

      // Ensure selection is at the beginning of the document
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: testContext.findEditContext().document.first.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
      );
    });

    testWidgetsOnAllPlatforms('places the caret when tapping an empty document (bottom left)', (tester) async {
      final testContext = await tester
          .createDocument() //
          .withSingleEmptyParagraph()
          .withEditorSize(const Size(300, 300))
          .pump();

      // Ensure editor is not focused
      expect(SuperEditorInspector.hasFocus(), isFalse);

      // Tap inside SuperEditor
      await tester.tapAt(tester.getBottomLeft(find.byType(SuperEditor)) + const Offset(1, -1));
      await tester.pump(kTapMinTime);

      // Ensure editor is focused
      expect(SuperEditorInspector.hasFocus(), isTrue);

      // Ensure selection is at the beginning of the document
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: testContext.findEditContext().document.first.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
      );
    });

    testWidgetsOnAllPlatforms('places the caret when tapping an empty document (bottom right)', (tester) async {
      final testContext = await tester
          .createDocument() //
          .withSingleEmptyParagraph()
          .withEditorSize(const Size(300, 300))
          .pump();

      // Ensure editor is not focused
      expect(SuperEditorInspector.hasFocus(), isFalse);

      // Tap inside SuperEditor
      await tester.tapAt(tester.getBottomRight(find.byType(SuperEditor)) - const Offset(1, 1));
      await tester.pump(kTapMinTime);

      // Ensure editor is focused
      expect(SuperEditorInspector.hasFocus(), isTrue);

      // Ensure selection is at the beginning of the document
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: testContext.findEditContext().document.first.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
      );
    });

    testWidgetsOnAllPlatforms('places the caret when tapping an empty document (center)', (tester) async {
      final testContext = await tester
          .createDocument() //
          .withSingleEmptyParagraph()
          .withEditorSize(const Size(300, 300))
          .pump();

      // Ensure editor is not focused
      expect(SuperEditorInspector.hasFocus(), isFalse);

      // Tap inside SuperEditor
      await tester.tapAt(tester.getCenter(find.byType(SuperEditor)));
      await tester.pump(kTapMinTime);

      // Ensure editor is focused
      expect(SuperEditorInspector.hasFocus(), isTrue);

      // Ensure selection is at the beginning of the document
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: testContext.findEditContext().document.first.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
      );
    });

    testWidgetsOnAllPlatforms('places the caret at the end when tapping beyond the end of the document',
        (tester) async {
      final testContext = await tester
          .createDocument() //
          .fromMarkdown("This is a text")
          .withEditorSize(const Size(300, 300))
          .pump();

      // Tap beyond the end of document with a small margin.
      // As the document has only one line, this offset is after all the content.
      await tester.tapAt(tester.getBottomLeft(find.byType(SuperEditor)) - const Offset(0, 10));
      await tester.pump(kTapMinTime);

      // Ensure selection is at the end of the document.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: testContext.findEditContext().document.last.id,
            nodePosition: const TextNodePosition(offset: 14),
          ),
        ),
      );
    });

    testWidgetsOnAllPlatforms('places the caret at the beginning when tapping above the start of the content',
        (tester) async {
      final testContext = await tester
          .createDocument() //
          .withSingleParagraph()
          .withEditorSize(const Size(300, 300))
          .pump();

      // Tap above the start of the content a small margin.
      await tester.tapAt(tester.getTopRight(find.byType(SuperEditor)) - const Offset(10, 0));
      await tester.pump(kTapMinTime);

      // Ensure selection is at the beginning of the document.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: testContext.findEditContext().document.first.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
      );
    });

    testWidgetsOnDesktop(
        "dragging a single component selection above a component selects to the beginning of the component",
        (tester) async {
      // For example, a user drags to select text in a paragraph. The user
      // is dragging the cursor up the center of the paragraph. When the cursor
      // moves above the paragraph, the selection extent should move to the
      // beginning of the paragraph, rather than get stuck in the middle of the
      // top line of text.

      await tester
          .createDocument()
          .fromMarkdown(
            '''
This is a paragraph of text that
spans multiple lines.''',
          )
          .forDesktop()
          .pump();

      final document = SuperEditorInspector.findDocument()!;
      final paragraphNode = document.first as ParagraphNode;

      await tester.dragSelectDocumentFromPositionByOffset(
        from: DocumentPosition(
          nodeId: paragraphNode.id,
          nodePosition: paragraphNode.endPosition,
        ),
        delta: const Offset(0, -300),
      );

      // Ensure that the entire paragraph is selected, after dragging
      // above it.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection(
          base: DocumentPosition(
            nodeId: paragraphNode.id,
            nodePosition: paragraphNode.endPosition,
          ),
          extent: DocumentPosition(
            nodeId: paragraphNode.id,
            nodePosition: paragraphNode.beginningPosition,
          ),
        ),
      );
    });

    testWidgetsOnDesktop("dragging a single component selection below a component selects to the end of the component",
        (tester) async {
      // For example, a user drags to select text in a paragraph. The user
      // is dragging the cursor down the center of the paragraph. When the cursor
      // moves below the paragraph, the selection extent should move to the
      // end of the paragraph, rather than get stuck in the middle of the
      // bottom line of text.

      await tester
          .createDocument()
          .fromMarkdown(
            '''
This is a paragraph of text that
spans multiple lines.''',
          )
          .forDesktop()
          .pump();

      final document = SuperEditorInspector.findDocument()!;
      final paragraphNode = document.first as ParagraphNode;

      await tester.dragSelectDocumentFromPositionByOffset(
        from: DocumentPosition(
          nodeId: paragraphNode.id,
          nodePosition: paragraphNode.beginningPosition,
        ),
        delta: const Offset(0, 300),
      );

      // Ensure that the entire paragraph is selected, after dragging
      // below it.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection(
          base: DocumentPosition(
            nodeId: paragraphNode.id,
            nodePosition: paragraphNode.beginningPosition,
          ),
          extent: DocumentPosition(
            nodeId: paragraphNode.id,
            nodePosition: paragraphNode.endPosition,
          ),
        ),
      );
    });

    testWidgetsOnDesktop(
        "dragging a multi-component selection above a component selects to the beginning of the top component",
        (tester) async {
      // For example, a user drags to select text in a paragraph. The user
      // is dragging the cursor up the center of the paragraph. When the cursor
      // moves above the paragraph, the selection extent should move to the
      // beginning of the paragraph, rather than get stuck in the middle of the
      // top line of text.

      await tester
          .createDocument()
          .fromMarkdown(
            '''
# This is a test
This is a paragraph of text that
spans multiple lines.''',
          )
          .forDesktop()
          .pump();

      final document = SuperEditorInspector.findDocument()!;
      final titleNode = document.first as ParagraphNode;
      final paragraphNode = document.getNodeAt(1)! as ParagraphNode;

      await tester.dragSelectDocumentFromPositionByOffset(
        from: DocumentPosition(
          nodeId: paragraphNode.id,
          nodePosition: paragraphNode.endPosition,
        ),
        delta: const Offset(0, -300),
      );

      // Ensure that the entire paragraph is selected, after dragging
      // above it.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection(
          base: DocumentPosition(
            nodeId: paragraphNode.id,
            nodePosition: paragraphNode.endPosition,
          ),
          extent: DocumentPosition(
            nodeId: titleNode.id,
            nodePosition: titleNode.beginningPosition,
          ),
        ),
      );
    });

    testWidgetsOnDesktop(
        "dragging a multi-component selection below a component selects to the end of the bottom component",
        (tester) async {
      // For example, a user drags to select text in a paragraph. The user
      // is dragging the cursor up the center of the paragraph. When the cursor
      // moves above the paragraph, the selection extent should move to the
      // beginning of the paragraph, rather than get stuck in the middle of the
      // top line of text.

      await tester
          .createDocument()
          .fromMarkdown(
            '''
# This is a test
This is a paragraph of text that
spans multiple lines.''',
          )
          .forDesktop()
          .pump();

      final document = SuperEditorInspector.findDocument()!;
      final titleNode = document.first as ParagraphNode;
      final paragraphNode = document.getNodeAt(1)! as ParagraphNode;

      await tester.dragSelectDocumentFromPositionByOffset(
        from: DocumentPosition(
          nodeId: titleNode.id,
          nodePosition: titleNode.beginningPosition,
        ),
        delta: const Offset(0, 300),
      );

      // Ensure that the entire paragraph is selected, after dragging
      // above it.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection(
          base: DocumentPosition(
            nodeId: titleNode.id,
            nodePosition: titleNode.beginningPosition,
          ),
          extent: DocumentPosition(
            nodeId: paragraphNode.id,
            nodePosition: paragraphNode.endPosition,
          ),
        ),
      );
    });

    testWidgetsOnAllPlatforms("places the caret at the end of a wrapped line when tapping there", (tester) async {
      // Configure and render a document.
      await tester
          .createDocument()
          .withSingleParagraph()
          .autoFocus(true)
          .withEditorSize(const Size(300, 700))
          .withSelection(
            const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 0))),
          )
          .pump();
      final offset = SuperEditorInspector.findOffsetOfLineBreak('1');

      // Tap to place the at the end of the first line
      await tester.placeCaretInParagraph("1", offset, affinity: TextAffinity.upstream);

      // Ensure that the document has the expected text caret selection.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "1",
            nodePosition: TextNodePosition(offset: offset, affinity: TextAffinity.upstream),
          ),
        ),
      );
    });

    testWidgetsOnAllPlatforms("places the caret at the beginning of a wrapped line when tapping there", (tester) async {
      // Configure and render a document.
      await tester
          .createDocument()
          .withSingleParagraph()
          .withEditorSize(const Size(300, 700))
          .withSelection(
            const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 0))),
          )
          .pump();

      final offsetOfLineBreak = SuperEditorInspector.findOffsetOfLineBreak('1');

      // Tap to place the at the end of the first line
      await tester.placeCaretInParagraph("1", offsetOfLineBreak, affinity: TextAffinity.downstream);

      // Ensure that the document has the expected text caret selection.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "1",
            nodePosition: TextNodePosition(offset: offsetOfLineBreak, affinity: TextAffinity.downstream),
          ),
        ),
      );
    });

    testWidgetsOnAndroid('configures default gesture mode', (tester) async {
      await tester //
          .createDocument()
          .withSingleParagraph()
          .pump();

      // Tap to place caret.
      await tester.placeCaretInParagraph(SuperEditorInspector.findDocument()!.first.id, 0);

      // Ensure the drag handle is displayed.
      expect(find.byType(AndroidSelectionHandle), findsOneWidget);
    });

    testWidgetsOnIos('configures default gesture mode', (tester) async {
      await tester //
          .createDocument()
          .withSingleParagraph()
          .pump();

      // Tap to place caret.
      await tester.placeCaretInParagraph(SuperEditorInspector.findDocument()!.first.id, 0);

      // Ensure the drag handle is displayed.
      expect(find.byType(IosFloatingToolbarOverlay), findsOneWidget);
    });

    testWidgetsOnDesktop('configures default gesture mode', (tester) async {
      await tester //
          .createDocument()
          .withSingleParagraph()
          .pump();

      await tester.placeCaretInParagraph(SuperEditorInspector.findDocument()!.first.id, 0);

      // Ensure no drag handle is displayed.
      expect(find.byType(AndroidSelectionHandle), findsNothing);
      expect(find.byType(IosFloatingToolbarOverlay), findsNothing);
    });

    testWidgetsOnDesktop('scrolls the content when dragging the scrollbar down', (tester) async {
      final scrollController = ScrollController();
      await tester //
          .createDocument()
          .withSingleParagraph()
          .withEditorSize(const Size(300, 300))
          .withScrollController(scrollController)
          .pump();

      // Ensure the editor didn't start scrolled.
      expect(scrollController.position.pixels, 0.0);

      // Double tap to select "Lorem" to ensure the selection don't change
      // when dragging the scrollbar.
      await tester.doubleTapInParagraph('1', 0);
      expect(
        SuperEditorInspector.findDocumentSelection(),
        selectionEquivalentTo(const DocumentSelection(
          base: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 0)),
          extent: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 5)),
        )),
      );

      // Drag the scrollbar down.
      await tester.dragScrollbar(300);

      // Ensure the content scrolled to the end of the document.
      expect(scrollController.position.pixels, moreOrLessEquals(770.0));

      // Ensure the selection didn't change.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        selectionEquivalentTo(const DocumentSelection(
          base: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 0)),
          extent: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 5)),
        )),
      );
    });

    testWidgetsOnDesktop('scrolls the content when dragging the scrollbar up', (tester) async {
      final scrollController = ScrollController();
      await tester //
          .createDocument()
          .withSingleParagraph()
          .withEditorSize(const Size(300, 300))
          .withScrollController(scrollController)
          .pump();

      // Double tap to select "Lorem" to ensure the selection don't change
      // when dragging the scrollbar.
      await tester.doubleTapInParagraph('1', 0);
      expect(
        SuperEditorInspector.findDocumentSelection(),
        selectionEquivalentTo(const DocumentSelection(
          base: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 0)),
          extent: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 5)),
        )),
      );

      // Jump to the end of the document.
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();

      // Drag the scrollbar up.
      await tester.dragScrollbar(-300);

      // Ensure the content scrolled to the beginning of the document.
      expect(scrollController.position.pixels, 0);

      // Ensure the selection didn't change.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        selectionEquivalentTo(
          const DocumentSelection(
            base: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 0)),
            extent: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 5)),
          ),
        ),
      );
    });

    group("interaction mode", () {
      group("when active", () {
        testWidgetsOnAllPlatforms("launches URL on tap", (tester) async {
          // Setup test version of UrlLauncher to log URL launches.
          final testUrlLauncher = TestUrlLauncher();
          UrlLauncher.instance = testUrlLauncher;
          addTearDown(() => UrlLauncher.instance = null);

          // Pump the UI.
          final context = await tester //
              .createDocument()
              .withSingleParagraphAndLink()
              .autoFocus(true)
              .pump();

          // Activate interaction mode.
          if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
            // On mobile, there's no hardware keyboard to easily activate
            // interaction mode. In practice, app developers will decide
            // when/how to activate interaction mode on mobile. Rather than
            // add buttons in our test just for this purpose, we'll explicitly
            // activate interaction mode.
            context.findEditContext().editor.execute([
              const ChangeInteractionModeRequest(isInteractionModeDesired: true),
            ]);
          } else if (defaultTargetPlatform == TargetPlatform.macOS) {
            // Press CMD to activate interaction mode on Mac.
            await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
          } else {
            // Press CTRL to activate interaction mode on Windows and Linux.
            await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
          }

          // Ensure that interaction mode is "on".
          expect(context.findEditContext().composer.isInInteractionMode.value, isTrue);

          // Tap on the link.
          await tester.tapInParagraph("1", 27);

          // Ensure that we tried to launch the URL.
          expect(testUrlLauncher.urlLaunchLog.length, 1);
          expect(testUrlLauncher.urlLaunchLog.first.toString(), "https://fake.url");
        });

        testWidgetsOnAllPlatforms("launches different URLs on tap", (tester) async {
          // Setup test version of UrlLauncher to log URL launches.
          final testUrlLauncher = TestUrlLauncher();
          UrlLauncher.instance = testUrlLauncher;
          addTearDown(() => UrlLauncher.instance = null);

          // Pump the UI.
          final context = await tester //
              .createDocument()
              .fromMarkdown("[Google](https://google.com) and [Flutter](https://flutter.dev)")
              .autoFocus(true)
              .pump();

          // Activate interaction mode.
          if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
            // On mobile, there's no hardware keyboard to easily activate
            // interaction mode. In practice, app developers will decide
            // when/how to activate interaction mode on mobile. Rather than
            // add buttons in our test just for this purpose, we'll explicitly
            // activate interaction mode.
            context.findEditContext().editor.execute([
              const ChangeInteractionModeRequest(isInteractionModeDesired: true),
            ]);
          } else if (defaultTargetPlatform == TargetPlatform.macOS) {
            // Press CMD to activate interaction mode on Mac.
            await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
          } else {
            // Press CTRL to activate interaction mode on Windows and Linux.
            await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
          }

          // Ensure that interaction mode is "on".
          expect(context.findEditContext().composer.isInInteractionMode.value, isTrue);

          // Tap on the first link.
          final textNode = context.document.first;
          await tester.tapInParagraph(textNode.id, 3);

          // Ensure that we tried to launch the first URL.
          expect(testUrlLauncher.urlLaunchLog.length, 1);
          expect(testUrlLauncher.urlLaunchLog.first.toString(), "https://google.com");

          // Tap on the second link.
          await tester.tapInParagraph(textNode.id, 14);

          // Ensure that we tried to launch the second URL.
          expect(testUrlLauncher.urlLaunchLog.length, 2);
          expect(testUrlLauncher.urlLaunchLog.last.toString(), "https://flutter.dev");
        });
      });

      group("when inactive", () {
        testWidgetsOnAllPlatforms("doesn't launch URL on tap", (tester) async {
          // Setup test version of UrlLauncher to log URL launches.
          final testUrlLauncher = TestUrlLauncher();
          UrlLauncher.instance = testUrlLauncher;
          addTearDown(() => UrlLauncher.instance = null);

          // Pump the UI.
          final context = await tester //
              .createDocument()
              .withSingleParagraphAndLink()
              .autoFocus(true)
              .pump();

          // Ensure that interaction mode is "off".
          expect(context.findEditContext().composer.isInInteractionMode.value, isFalse);

          // Tap on the link.
          await tester.tapInParagraph("1", 27);

          // Ensure that we DIDN'T try to launch the URL.
          expect(testUrlLauncher.urlLaunchLog.length, 0);
        });
      });
    });
  });
}
