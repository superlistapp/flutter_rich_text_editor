import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/src/infrastructure/blinking_caret.dart';
import 'package:super_editor/src/infrastructure/flutter/material_scrollbar.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';

import '../test_tools.dart';
import 'supereditor_test_tools.dart';
import 'test_documents.dart';

void main() {
  group("SuperEditor scrolling", () {
    testWidgetsOnArbitraryDesktop('scrolls document when dragging using the trackpad (downstream)', (tester) async {
      final scrollController = ScrollController();
      await tester
          .createDocument() //
          .withLongTextContent()
          .withEditorSize(const Size(300, 300))
          .withScrollController(scrollController)
          .pump();

      final document = SuperEditorInspector.findDocument()!;
      final firstParagraph = document.first as ParagraphNode;

      final dragGesture = await tester.startDocumentDragFromPosition(
        from: DocumentPosition(
          nodeId: firstParagraph.id,
          nodePosition: firstParagraph.beginningPosition,
        ),
        startAlignmentWithinPosition: Alignment.topLeft,
        deviceKind: PointerDeviceKind.trackpad,
      );

      // Move a distance big enough to ensure a pan gesture.
      await dragGesture.moveBy(const Offset(0, kPanSlop));
      await tester.pump();

      // Drag up.
      await dragGesture.moveBy(const Offset(0, -300));
      await tester.pump();

      await tester.endDocumentDragGesture(dragGesture);

      // Ensure the document scrolled down.
      expect(scrollController.offset, greaterThan(0));
    });

    testWidgetsOnArbitraryDesktop('scrolls document when dragging using the trackpad (upstream)', (tester) async {
      final scrollController = ScrollController();
      await tester
          .createDocument() //
          .withLongTextContent()
          .withEditorSize(const Size(300, 300))
          .withScrollController(scrollController)
          .pump();

      final document = SuperEditorInspector.findDocument()!;
      final lastParagraph = document.last as ParagraphNode;

      // Jump to the end of the document
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();

      final dragGesture = await tester.startDocumentDragFromPosition(
        from: DocumentPosition(
          nodeId: lastParagraph.id,
          nodePosition: lastParagraph.endPosition,
        ),
        startAlignmentWithinPosition: Alignment.bottomRight,
        deviceKind: PointerDeviceKind.trackpad,
      );

      // Move a distance big enough to ensure a pan gesture.
      await dragGesture.moveBy(const Offset(0, kPanSlop));
      await tester.pump();

      // Drag down.
      await dragGesture.moveBy(const Offset(0, 300));
      await tester.pump();

      await tester.endDocumentDragGesture(dragGesture);

      // Ensure the document scrolled up.
      expect(scrollController.offset, lessThan(scrollController.position.maxScrollExtent));
    });

    testWidgetsOnDesktop("auto-scrolls down", (tester) async {
      const windowSize = Size(800, 600);
      tester.view.physicalSize = windowSize;

      await tester //
          .createDocument() //
          .withLongTextContent() //
          .forDesktop() //
          .pump();

      final document = SuperEditorInspector.findDocument()!;
      final firstParagraph = document.first as ParagraphNode;
      final lastParagraph = document.last as ParagraphNode;

      final dragGesture = await tester.startDocumentDragFromPosition(
        from: DocumentPosition(
          nodeId: firstParagraph.id,
          nodePosition: firstParagraph.beginningPosition,
        ),
        startAlignmentWithinPosition: Alignment.topLeft,
      );
      await dragGesture.moveBy(Offset(windowSize.width - 20, windowSize.height - 20));
      // Pump enough times to scroll all the way to the top.
      // TODO: find a way to scroll as much as possible without pumping an arbitrary number of times
      for (int i = 0; i < 60; i += 1) {
        await tester.pump();
      }
      await tester.endDocumentDragGesture(dragGesture);

      // Ensure that the entire document is selected.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection(
          base: DocumentPosition(
            nodeId: firstParagraph.id,
            nodePosition: firstParagraph.beginningPosition,
          ),
          extent: DocumentPosition(
            nodeId: lastParagraph.id,
            nodePosition: lastParagraph.endPosition,
          ),
        ),
      );
    });

    testWidgetsOnDesktop("auto-scrolls up", (tester) async {
      const windowSize = Size(800, 600);
      tester.view.physicalSize = windowSize;

      final docContext = await tester //
          .createDocument() //
          .withLongTextContent() //
          .forDesktop() //
          .pump();

      final document = SuperEditorInspector.findDocument()!;
      final firstParagraph = document.first as ParagraphNode;
      final lastParagraph = document.last as ParagraphNode;

      // Place the caret at the end of the document, which causes the editor to
      // scroll to the bottom.
      docContext.findEditContext().editor.execute([
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: lastParagraph.id,
              nodePosition: lastParagraph.endPosition,
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);

      docContext.focusNode.requestFocus();
      await tester.pumpAndSettle();

      final dragGesture = await tester.startDocumentDragFromPosition(
        from: DocumentPosition(
          nodeId: lastParagraph.id,
          nodePosition: lastParagraph.endPosition,
        ),
        startAlignmentWithinPosition: Alignment.bottomRight,
      );
      await dragGesture.moveBy(-Offset(windowSize.width - 20, windowSize.height - 20));
      // Pump enough times to scroll all the way to the top.
      // TODO: find a way to scroll as much as possible without pumping an arbitrary number of times
      for (int i = 0; i < 60; i += 1) {
        await tester.pump();
      }
      await tester.endDocumentDragGesture(dragGesture);

      // Ensure that the entire document is selected.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        selectionEquivalentTo(
          DocumentSelection(
            base: DocumentPosition(
              nodeId: lastParagraph.id,
              nodePosition: TextNodePosition(
                offset: lastParagraph.endPosition.offset,
                affinity: TextAffinity.upstream,
              ),
            ),
            extent: DocumentPosition(
              nodeId: firstParagraph.id,
              nodePosition: firstParagraph.beginningPosition,
            ),
          ),
        ),
      );
    });

    testWidgetsOnMobile('starts auto-scrolling when dragging near the top', (tester) async {
      final scrollController = ScrollController();

      // Pump an editor with an appbar above the editor so we make sure that
      // auto-scroll starts when the user dragged near the top of the editor,
      // not at the top of the screen.
      await tester
          .createDocument()
          .withLongTextContent()
          .withScrollController(scrollController)
          .withEditorSize(const Size(300, 300))
          .autoFocus(true)
          .withAppBar(100.0)
          .pump();

      // Scroll all the way to the bottom.
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pumpAndSettle();

      // Place the caret at approximately at the middle of the first visible line.
      await tester.tapAt(tester.getTopLeft(find.byType(SuperEditor)) + const Offset(150, 20));
      await tester.pump(kDoubleTapTimeout);

      final scrollOffsetBeforeDrag = scrollController.offset;

      // Drag the handle a bit to the top.
      final dragGesture = await tester.startGesture(tester.getCenter(
        SuperEditorInspector.findMobileCaretDragHandle(),
      ));
      await dragGesture.moveBy(const Offset(0, -20));
      await tester.pump();

      // Pump some frames to let the auto-scroll kick in.
      for (int i = 0; i < 60; i += 1) {
        await tester.pump();
      }

      // Release the gesture.
      await dragGesture.up();
      await tester.pump();

      // Ensure the editor scrolled up.
      expect(scrollController.offset, lessThan(scrollOffsetBeforeDrag));

      // Let the long-press timer resolve.
      await tester.pump(kLongPressTimeout);
    });

    testWidgetsOnDesktop("auto-scrolls to caret position", (tester) async {
      const windowSize = Size(800, 600);
      tester.view.physicalSize = windowSize;

      final docContext = await tester //
          .createDocument() //
          .withLongTextContent() //
          .forDesktop() //
          .pump();
      final document = SuperEditorInspector.findDocument()!;
      final lastParagraph = document.last as ParagraphNode;

      // Place the caret at the end of the document, which should cause the
      // editor to scroll to the bottom.
      docContext.findEditContext().editor.execute([
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: lastParagraph.id,
              nodePosition: lastParagraph.endPosition,
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);
      docContext.focusNode.requestFocus();
      await tester.pumpAndSettle();

      // Ensure that the last character in the document is visible.
      expect(
        SuperEditorInspector.isPositionVisibleGlobally(
          DocumentPosition(
            nodeId: lastParagraph.id,
            nodePosition: lastParagraph.endPosition,
          ),
          windowSize,
        ),
        isTrue,
      );
    });

    testWidgetsOnAndroid("auto-scrolls to caret position when dragging the spacebar", (tester) async {
      // Pump an editor with a size that will cause it to be scrollable.
      const windowSize = Size(800, 400);
      tester.view.physicalSize = windowSize;
      addTearDown(() => tester.platformDispatcher.clearAllTestValues());

      await tester //
          .createDocument() //
          .withLongTextContent() //
          .pump();

      // Place the caret at the beginning of the document.
      await tester.placeCaretInParagraph('1', 0);

      final paragraphImeText = '. ${SuperEditorInspector.findTextInComponent('1').toPlainText()}';

      // Simulate the user dragging the spacebar to move the caret to
      // "In aliquet convallis efficitur|.". This position was chosen arbitrarily, we
      // just need a position that is outside of the viewport.
      const destinationOffset = 226;
      int currentOffset = 0;
      while (currentOffset < destinationOffset) {
        await tester.ime.sendDeltas(
          [
            TextEditingDeltaNonTextUpdate(
              oldText: paragraphImeText,
              selection: TextSelection.collapsed(offset: currentOffset),
              composing: TextRange.empty,
            ),
          ],
          getter: imeClientGetter,
        );

        await tester.pump();
        currentOffset += 1;
      }

      // Ensure that the selection is visible.
      expect(
        SuperEditorInspector.isPositionVisibleGlobally(
          const DocumentPosition(
            nodeId: '1',
            nodePosition: TextNodePosition(offset: destinationOffset),
          ),
          windowSize,
        ),
        isTrue,
      );
    });

    testWidgetsOnAllPlatforms("doesn't jump the content when typing at the first line", (tester) async {
      final scrollController = ScrollController();

      // We use a custom stylesheet to avoid any padding, ensuring that the text
      // will be close to the edge.
      await tester //
          .createDocument()
          .withSingleParagraph()
          .withScrollController(scrollController)
          .withInputSource(TextInputSource.keyboard)
          .useStylesheet(
            Stylesheet(
              inlineTextStyler: (Set<Attribution> attributions, TextStyle base) {
                return base;
              },
              rules: [
                StyleRule(BlockSelector.all, (document, node) {
                  return {
                    Styles.textStyle: const TextStyle(
                      color: Colors.black,
                    ),
                  };
                }),
              ],
            ),
          )
          .pump();

      // Ensure the editor starts without any scrolling.
      expect(scrollController.position.pixels, 0);

      // Place caret at the beginning of the document.
      await tester.placeCaretInParagraph('1', 0);

      // Simulate the user typing.
      await tester.typeKeyboardText("A");

      // Ensure typing doesn't cause the content to jump.
      expect(scrollController.position.pixels, 0);
    });

    testWidgetsOnAllPlatforms("doesn't jump the content when typing at the last line", (tester) async {
      final scrollController = ScrollController();

      // Pump an editor with a size that will know will cause it to be scrollable.
      // We use a custom stylesheet to avoid any padding, ensuring that the text
      // will be close to the edge.
      await tester //
          .createDocument()
          .withSingleParagraph()
          .withScrollController(scrollController)
          .withInputSource(TextInputSource.keyboard)
          .withEditorSize(const Size(600, 100))
          .useStylesheet(
            Stylesheet(
              inlineTextStyler: (Set<Attribution> attributions, TextStyle base) {
                return base;
              },
              rules: [
                StyleRule(BlockSelector.all, (document, node) {
                  return {
                    Styles.textStyle: const TextStyle(
                      color: Colors.black,
                    ),
                  };
                }),
              ],
            ),
          )
          .pump();

      // Ensure the editor starts without any scrolling.
      expect(scrollController.position.pixels, 0);

      // Ensure the editor is scrollable.
      expect(scrollController.position.maxScrollExtent, greaterThan(0));

      // On mobile, changing the selection isn't causing the editor
      // to reveal the selection, so we manually jump to the end of the scrollable
      // and then change the selection.
      scrollController.position.jumpTo(scrollController.position.maxScrollExtent);
      // Place caret at last line of the editor.
      await tester.placeCaretInParagraph('1', 444);

      // Simulate the user typing.
      await tester.typeKeyboardText("A");

      // Ensure typing doesn't cause the content to jump.
      expect(scrollController.position.pixels, scrollController.position.maxScrollExtent);
    });

    testWidgetsOnDesktop("doesn't auto-scroll for selection changes that aren't user interactions", (tester) async {
      final scrollController = ScrollController();

      // Pump a editor with a size we know will cause the editor to be scrollable.
      final docContext = await tester //
          .createDocument()
          .withLongTextContent()
          .withEditorSize(const Size(300, 100))
          .withScrollController(scrollController)
          .pump();

      // Select the first paragraph.
      await tester.placeCaretInParagraph('1', 0);

      // Place the caret at the last paragraph, simulating an event that wasn't initiated by the user.
      // This paragraph is outside the viewport.
      docContext.findEditContext().editor.execute([
        const ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: '4',
              nodePosition: TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.contentChange,
        ),
      ]);
      await tester.pumpAndSettle();

      // Ensure the editor didn't scroll.
      expect(scrollController.position.pixels, 0.0);
    });

    testWidgetsOnAllPlatforms("doesn't auto-scroll for key presses that don't insert any content", (tester) async {
      final scrollController = ScrollController();

      // Pump an editor with a size we know will cause the editor to be scrollable.
      final docContext = await tester //
          .createDocument()
          .withLongTextContent()
          .withEditorSize(const Size(300, 100))
          .withScrollController(scrollController)
          .pump();

      // Select the first paragraph.
      await tester.placeCaretInParagraph('1', 0);

      // Place the caret at the last paragraph, simulating an event that was initiated by the user.
      // We pretend it was initiated by the user because that's what causes an auto-scroll.
      // But the auto-scroll should be smart enough to see that the selection hasn't changed
      // and therefore it shouldn't auto-scroll.
      docContext.findEditContext().editor.execute([
        const ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: '1',
              nodePosition: TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);
      await tester.pumpAndSettle();

      // Ensure the editor didn't scroll.
      expect(scrollController.position.pixels, 0.0);

      // Press non-content keys.
      await tester.sendKeyEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.shift);
      await tester.pump();

      // We don't expect anything to happen, but in case something unexpected happens,
      // give the editor whatever time it needs to run the unexpected behavior.
      await tester.pumpAndSettle();

      // Ensure the editor didn't scroll.
      expect(scrollController.position.pixels, 0.0);
    });

    testWidgetsOnArbitraryDesktop("doesn't scroll when dragging over an image", (tester) async {
      const editorSize = Size(300, 300);

      await tester
          .createDocument()
          .withCustomContent(
            MutableDocument(
              nodes: [
                ParagraphNode(
                  id: "1",
                  text: AttributedText("First Paragraph"),
                ),
                ParagraphNode(
                  id: "2",
                  text: AttributedText("Second Paragraph"),
                ),
                ImageNode(
                  id: "img-node",
                  imageUrl: 'https://this.is.a.fake.image',
                  metadata: const SingleColumnLayoutComponentStyles(
                    width: double.infinity,
                  ).toMetadata(),
                ),
              ],
            ),
          )
          .withAddedComponents([const FakeImageComponentBuilder(size: editorSize)])
          .withEditorSize(editorSize)
          .pump();

      // Drag from the second paragraph to the image.
      await tester.dragSelectDocumentFromPositionByOffset(
        from: const DocumentPosition(
          nodeId: '2',
          nodePosition: TextNodePosition(offset: 1),
        ),
        delta: const Offset(0, 50),
      );

      // Ensure the bottom of the image isn't visible.
      expect(
        SuperEditorInspector.isPositionVisibleGlobally(
          const DocumentPosition(
            nodeId: 'img-node',
            nodePosition: UpstreamDownstreamNodePosition.downstream(),
          ),
          editorSize,
        ),
        false,
      );
    });

    testWidgetsOnMobile("stops momentum on tap down and doesn't place the caret", (tester) async {
      final scrollController = ScrollController();

      await tester //
          .createDocument() //
          .withLongDoc() //
          .withScrollController(scrollController) //
          .pump();

      // Ensure the editor initially has no selection.
      expect(SuperEditorInspector.findDocumentSelection(), isNull);

      // Fling scroll the editor.
      await tester.fling(find.byType(SuperEditor), const Offset(0.0, -1000), 1000);

      // Pump a few frames of momentum.
      for (int i = 0; i < 25; i += 1) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final scrollOffsetInMiddleOfMomentum = scrollController.offset;

      // Tap down to stop the momentum.
      final gesture = await tester.startGesture(tester.getCenter(find.byType(SuperEditor)));

      // Let any remaining momentum run (there shouldn't be any).
      await tester.pumpAndSettle();

      // Ensure that the momentum stopped exactly where we tapped.
      expect(scrollOffsetInMiddleOfMomentum, scrollController.offset);

      // Release the pointer.
      await gesture.up();
      await tester.pump();

      // Ensure that tapping on the editor didn't place the caret.
      expect(SuperEditorInspector.findDocumentSelection(), isNull);
    });

    testWidgetsOnDesktop("stops momentum on tap down with trackpad and doesn't place the caret", (tester) async {
      final scrollController = ScrollController();

      await tester //
          .createDocument() //
          .withLongDoc() //
          .withScrollController(scrollController) //
          .pump();

      // Ensure the editor initially has no selection.
      expect(SuperEditorInspector.findDocumentSelection(), isNull);

      // Fling scroll the editor with the trackpad.
      final scrollGesture = await tester.startGesture(
        tester.getCenter(find.byType(SuperEditor)),
        kind: PointerDeviceKind.trackpad,
      );
      await scrollGesture.moveBy(const Offset(0, -1000));
      await scrollGesture.up();

      // Pump a few frames of momentum.
      for (int i = 0; i < 25; i += 1) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final scrollOffsetInMiddleOfMomentum = scrollController.offset;

      // Ensure the editor scrolled.
      expect(scrollOffsetInMiddleOfMomentum, greaterThan(0.0));

      // Tap down to stop the momentum.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SuperEditor)),
        kind: PointerDeviceKind.trackpad,
      );

      // Let any remaining momentum run (there shouldn't be any).
      await tester.pumpAndSettle();

      // Ensure that the momentum stopped exactly where we tapped.
      expect(scrollController.offset, scrollOffsetInMiddleOfMomentum);

      // Release the pointer.
      await gesture.up();
      await tester.pump();

      // Ensure that tapping on the editor didn't change the selection.
      expect(SuperEditorInspector.findDocumentSelection(), isNull);
    });

    testWidgetsOnArbitraryDesktop("does not stop momentum on mouse move", (tester) async {
      final scrollController = ScrollController();

      // Pump an editor with a small size to make it scrollable.
      await tester //
          .createDocument() //
          .withLongDoc() //
          .withScrollController(scrollController) //
          .withEditorSize(const Size(300, 300))
          .pump();

      // Fling scroll with the trackpad to generate momentum.
      await tester.trackpadFling(
        find.byType(SuperEditor),
        const Offset(0.0, -300),
        300.0,
      );

      final scrollOffsetInMiddleOfMomentum = scrollController.offset;

      // Move the mouse around.
      final gesture = await tester.createGesture();
      await gesture.moveTo(tester.getTopLeft(find.byType(SuperEditor)));

      // Let any momentum run.
      await tester.pumpAndSettle();

      // Ensure that the momentum didn't stop due to mouse movement.
      expect(scrollOffsetInMiddleOfMomentum, lessThan(scrollController.offset));
    });

    testWidgetsOnAndroid("doesn't overscroll when dragging down", (tester) async {
      final scrollController = ScrollController();

      await tester //
          .createDocument()
          .withSingleParagraph()
          .withScrollController(scrollController)
          .pump();

      // Ensure the editor didn't start scrolled.
      expect(scrollController.offset, 0);

      // Drag an arbitrary amount of pixels from the top of the editor with a small margin.
      final dragGesture = await tester.dragByFrameCount(
        startLocation: tester.getRect(find.byType(SuperEditor)).topCenter + const Offset(0, 5),
        totalDragOffset: const Offset(0, 200.0),
      );

      // Ensure the drag gesture didn't scroll the editor.
      expect(scrollController.offset, 0);

      // End the gesture.
      await dragGesture.up();

      // Wait for the long-press timer to resolve.
      await tester.pumpAndSettle();
    });

    testWidgetsOnAndroid("doesn't overscroll when dragging up", (tester) async {
      final scrollController = ScrollController();

      await tester //
          .createDocument()
          .withSingleParagraph()
          .withScrollController(scrollController)
          .pump();

      // Jump to the bottom.
      scrollController.jumpTo(scrollController.position.maxScrollExtent);

      // Drag an arbitrary amount of pixels from the bottom of the editor.
      // The gesture starts with an arbitrary small margin from the bottom.
      final dragGesture = await tester.dragByFrameCount(
        startLocation: tester.getRect(find.byType(SuperEditor)).bottomCenter - const Offset(0, 10),
        totalDragOffset: const Offset(0, -200.0),
      );

      // Ensure we don't scroll.
      expect(scrollController.offset, scrollController.position.maxScrollExtent);

      // End the gesture.
      await dragGesture.up();

      // Wait for the long-press timer to resolve.
      await tester.pumpAndSettle();
    });

    testWidgetsOnIos('overscrolls when dragging down', (tester) async {
      final scrollController = ScrollController();

      await tester //
          .createDocument()
          .withLongDoc()
          .withScrollController(scrollController)
          .pump();

      // Ensure the scrollview didn't start scrolled.
      expect(scrollController.offset, 0);

      // Drag an arbitrary amount of pixels a few pixels below the top of the editor.
      final dragGesture = await tester.dragByFrameCount(
        startLocation: tester.getRect(find.byType(SuperEditor)).topCenter + const Offset(0, 5),
        totalDragOffset: const Offset(0, 80.0),
      );

      // Ensure we are overscrolling while holding the pointer down.
      await tester.pumpAndSettle();
      expect(scrollController.offset, lessThan(0.0));

      // Release the pointer to end the gesture.
      await dragGesture.up();

      // Wait for the long-press timer to resolve.
      await tester.pumpAndSettle();

      // Ensure the we scrolled back to the top.
      expect(scrollController.offset, 0.0);
    });

    testWidgetsOnIos('overscrolls when dragging up', (tester) async {
      final scrollController = ScrollController();

      await tester //
          .createDocument()
          .withLongDoc()
          .withScrollController(scrollController)
          .pump();

      // Jump to the bottom.
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pumpAndSettle();

      // Drag an arbitrary amount of pixels from the bottom of the editor.
      // The gesture starts with an arbitrary margin from the bottom.
      final dragGesture = await tester.dragByFrameCount(
        startLocation: tester.getRect(find.byType(SuperEditor)).bottomCenter - const Offset(0, 5),
        totalDragOffset: const Offset(0, -200.0),
      );

      // Ensure we are overscrolling while holding the pointer down.
      await tester.pumpAndSettle();
      expect(scrollController.offset, greaterThan(scrollController.position.maxScrollExtent));

      // Release the pointer to end the gesture.
      await dragGesture.up();

      // Wait for the long-press timer to resolve.
      await tester.pumpAndSettle();

      // Ensure the we scrolled back to the end.
      expect(scrollController.offset, scrollController.position.maxScrollExtent);
    });

    group('scrolls when dragging at empty space', () {
      testWidgetsOnMobile("with collapsed selection", (tester) async {
        final scrollController = ScrollController();

        // Pump an editor with horizontal padding, so we can drag from an offset where there is no text.
        await tester //
            .createDocument()
            .withLongDoc()
            .withEditorSize(const Size(300, 300))
            .withScrollController(scrollController)
            .useStylesheet(
              defaultStylesheet.copyWith(
                documentPadding: const EdgeInsets.symmetric(horizontal: 100),
              ),
            )
            .pump();

        // Place the caret at the beginning of the document.
        await tester.placeCaretInParagraph('1', 0);

        final scrollOffsetBeforeDrag = scrollController.offset;

        // Drag from approximately the bottom of the editor until the top.
        await tester.dragFrom(
          tester.getBottomLeft(find.byType(SuperEditor)) + const Offset(10, -10),
          const Offset(0, -300),
        );
        await tester.pump();

        // Ensure the editor scrolled up and the selection didn't change.
        expect(scrollController.offset, greaterThan(scrollOffsetBeforeDrag));
        expect(
          SuperEditorInspector.findDocumentSelection(),
          selectionEquivalentTo(const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: '1',
              nodePosition: TextNodePosition(offset: 0),
            ),
          )),
        );

        // Let the long-press timer resolve.
        await tester.pump(kLongPressTimeout);
      });

      testWidgetsOnMobile("with expanded selection", (tester) async {
        final scrollController = ScrollController();

        // Pump an editor with horizontal padding, so we can drag from an offset where there is no text.
        await tester //
            .createDocument()
            .withLongDoc()
            .withEditorSize(const Size(300, 300))
            .withScrollController(scrollController)
            .useStylesheet(
              defaultStylesheet.copyWith(
                documentPadding: const EdgeInsets.symmetric(horizontal: 100),
              ),
            )
            .pump();

        // Double tap the word "Lorem".
        await tester.doubleTapInParagraph('1', 1);

        final scrollOffsetBeforeDrag = scrollController.offset;

        // Drag from approximately the bottom of the editor until the top.
        await tester.dragFrom(
          tester.getBottomLeft(find.byType(SuperEditor)) + const Offset(10, -10),
          const Offset(0, -300),
        );
        await tester.pump();

        // Ensure the editor scrolled up and the selection didn't change.
        expect(scrollController.offset, greaterThan(scrollOffsetBeforeDrag));
        expect(
          SuperEditorInspector.findDocumentSelection(),
          selectionEquivalentTo(const DocumentSelection(
            base: DocumentPosition(
              nodeId: '1',
              nodePosition: TextNodePosition(offset: 0),
            ),
            extent: DocumentPosition(
              nodeId: '1',
              nodePosition: TextNodePosition(offset: 5),
            ),
          )),
        );

        // Let the long-press timer resolve.
        await tester.pump(kLongPressTimeout);
      });

      testWidgetsOnMobile("with no selection", (tester) async {
        final scrollController = ScrollController();

        // Pump an editor with horizontal padding, so we can drag from an offset where there is no text.
        await tester //
            .createDocument()
            .withLongDoc()
            .withEditorSize(const Size(300, 300))
            .withScrollController(scrollController)
            .useStylesheet(
              defaultStylesheet.copyWith(
                documentPadding: const EdgeInsets.symmetric(horizontal: 100),
              ),
            )
            .pump();

        final scrollOffsetBeforeDrag = scrollController.offset;

        // Drag from approximately the bottom of the editor until the top.
        await tester.dragFrom(
          tester.getBottomLeft(find.byType(SuperEditor)) + const Offset(10, -10),
          const Offset(0, -300),
        );
        await tester.pump();

        // Ensure the editor scrolled up and the selection didn't change.
        expect(scrollController.offset, greaterThan(scrollOffsetBeforeDrag));
        expect(SuperEditorInspector.findDocumentSelection(), isNull);

        // Let the long-press timer resolve.
        await tester.pump(kLongPressTimeout);
      });
    });

    group("within an ancestor Scrollable", () {
      const screenSizeWithoutKeyboard = Size(390.0, 844.0);
      const screenSizeWithKeyboard = Size(390.0, 544.0);
      const keyboardExpansionFrameCount = 60;
      final shrinkPerFrame =
          (screenSizeWithoutKeyboard.height - screenSizeWithKeyboard.height) / keyboardExpansionFrameCount;

      testWidgetsOnAndroid('on Android, keeps caret visible when keyboard appears', (WidgetTester tester) async {
        tester.view
          ..physicalSize = screenSizeWithoutKeyboard
          ..platformDispatcher.textScaleFactorTestValue = 1.0
          ..devicePixelRatio = 1.0;

        await tester.pumpWidget(
          const _SliverTestEditor(
            gestureMode: DocumentGestureMode.android,
          ),
        );

        // Select text near the bottom of the screen, where the keyboard will appear
        final tapPosition = Offset(screenSizeWithoutKeyboard.width / 2, screenSizeWithoutKeyboard.height - 1);
        await tester.tapAt(tapPosition);
        await tester.pump();

        // TODO: add caret finder to inspector
        final caretFinder = find.byKey(DocumentKeys.caret);
        expect(caretFinder, findsOneWidget);

        // Shrink the screen height, as if the keyboard appeared.
        await _simulateKeyboardAppearance(
          tester: tester,
          initialScreenSize: screenSizeWithoutKeyboard,
          shrinkPerFrame: shrinkPerFrame,
          frameCount: keyboardExpansionFrameCount,
        );

        // Ensure that the editor auto-scrolled to keep the caret visible.
        expect(caretFinder, findsOneWidget);
        final caretOffset = tester.getBottomLeft(caretFinder);

        // The default trailing boundary of the default `SuperEditor`
        const trailingBoundary = 54.0;

        // The caret should be at the trailing boundary, within a small margin of error
        expect(caretOffset.dy, lessThanOrEqualTo(screenSizeWithKeyboard.height - trailingBoundary));
        expect(caretOffset.dy, greaterThanOrEqualTo(screenSizeWithKeyboard.height - trailingBoundary));
      });

      testWidgetsOnIos('on iOS, keeps caret visible when keyboard appears', (WidgetTester tester) async {
        tester.view
          ..physicalSize = screenSizeWithoutKeyboard
          ..platformDispatcher.textScaleFactorTestValue = 1.0
          ..devicePixelRatio = 1.0;

        await tester.pumpWidget(
          const _SliverTestEditor(
            gestureMode: DocumentGestureMode.iOS,
          ),
        );

        // Select text near the bottom of the screen, where the keyboard will appear
        final tapPosition = Offset(screenSizeWithoutKeyboard.width / 2, screenSizeWithoutKeyboard.height - 1);
        await tester.tapAt(tapPosition);
        await tester.pump();

        // Shrink the screen height, as if the keyboard appeared.
        await _simulateKeyboardAppearance(
          tester: tester,
          initialScreenSize: screenSizeWithoutKeyboard,
          shrinkPerFrame: shrinkPerFrame,
          frameCount: keyboardExpansionFrameCount,
        );

        // Ensure that the editor auto-scrolled to keep the caret visible.
        final caretFinder = find.byType(BlinkingCaret);
        final caretOffset = tester.getBottomLeft(caretFinder);

        // The default trailing boundary of the default `SuperEditor`
        const trailingBoundary = 54.0;

        // The caret should be at the trailing boundary, within a small margin of error
        expect(caretOffset.dy, lessThanOrEqualTo(screenSizeWithKeyboard.height - trailingBoundary + 2));
        expect(caretOffset.dy, greaterThanOrEqualTo(screenSizeWithKeyboard.height - trailingBoundary - 2));
      });

      testWidgetsOnMobile('scrolling and holding the pointer doesn\'t cause the keyboard to open', (tester) async {
        final scrollController = ScrollController();

        // Pump an editor inside a CustomScrollView without enough room to display
        // the whole content.
        await tester
            .createDocument() //
            .withLongTextContent()
            .withEditorSize(const Size(200, 200))
            .insideCustomScrollView()
            .withScrollController(scrollController)
            .pump();

        // Ensure the scrollview didn't start scrolled.
        expect(scrollController.offset, 0);

        final scrollableRect = tester.getRect(find.byType(CustomScrollView));

        const dragFrameCount = 10;
        final dragAmountPerFrame = scrollableRect.height / dragFrameCount;

        // Drag from the bottom all the way up to the top of the scrollable.
        final dragGesture = await tester.startGesture(scrollableRect.bottomCenter - const Offset(0, 1));
        for (int i = 0; i < dragFrameCount; i += 1) {
          await dragGesture.moveBy(Offset(0, -dragAmountPerFrame));
          await tester.pump();
        }

        // The editor supports long press to select.
        // Wait long enough to make sure  this gesture wasn't confused with a long press.
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));

        // Ensure we scrolled, didn't changed the selection and didn't attach to the IME.
        expect(scrollController.offset, greaterThan(0));
        expect(SuperEditorInspector.findDocumentSelection(), isNull);
        expect(tester.testTextInput.hasAnyClients, isFalse);

        // Release the pointer.
        await dragGesture.up();
        await dragGesture.removePointer();
      });

      testWidgetsOnMobile('scrolling and releasing the pointer doesn\'t cause the keyboard to open', (tester) async {
        final scrollController = ScrollController();

        // Pump an editor inside a CustomScrollView without enough room to display
        // the whole content.
        await tester
            .createDocument() //
            .withLongTextContent()
            .withEditorSize(const Size(200, 200))
            .insideCustomScrollView()
            .withScrollController(scrollController)
            .pump();

        // Ensure the scrollview didn't start scrolled.
        expect(scrollController.offset, 0);

        final scrollableRect = tester.getRect(find.byType(CustomScrollView));

        const dragFrameCount = 10;
        final dragAmountPerFrame = scrollableRect.height / dragFrameCount;

        // Drag from the bottom all the way up to the top of the scrollable.
        final dragGesture = await tester.startGesture(scrollableRect.bottomCenter - const Offset(0, 1));
        for (int i = 0; i < dragFrameCount; i += 1) {
          await dragGesture.moveBy(Offset(0, -dragAmountPerFrame));
          await tester.pump();
        }

        // Stop the scrolling gesture.
        await dragGesture.up();
        await dragGesture.removePointer();
        await tester.pump();

        // The editor supports long press to select.
        // Wait long enough to make sure  this gesture wasn't confused with a long press.
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));

        // Ensure we scrolled, didn't changed the selection and didn't attach to the IME.
        expect(scrollController.offset, greaterThan(0));
        expect(SuperEditorInspector.findDocumentSelection(), isNull);
        expect(tester.testTextInput.hasAnyClients, isFalse);
      });

      testWidgetsOnAndroid("doesn't overscroll when dragging down", (tester) async {
        final scrollController = ScrollController();

        await tester
            .createDocument() //
            .withSingleParagraph()
            .insideCustomScrollView()
            .withScrollController(scrollController)
            .pump();

        // Ensure the scrollview didn't start scrolled.
        expect(scrollController.offset, 0);

        // Drag an arbitrary amount of pixels from the top of the editor.
        final dragGesture = await tester.dragByFrameCount(
          startLocation: tester.getRect(find.byType(CustomScrollView)).topCenter + const Offset(0, 5),
          totalDragOffset: const Offset(0, 400.0),
        );

        // Ensure we don't scroll.
        expect(scrollController.offset, 0);

        // End the gesture.
        await dragGesture.up();

        // Wait for the long-press timer to resolve.
        await tester.pumpAndSettle();
      });

      testWidgetsOnAndroid("doesn't overscroll when dragging up", (tester) async {
        final scrollController = ScrollController();

        // Pump an editor inside a CustomScrollView without enough room to display
        // the whole content.
        await tester
            .createDocument()
            .withSingleParagraph()
            .withEditorSize(const Size(200, 200))
            .insideCustomScrollView()
            .withScrollController(scrollController)
            .pump();

        // Jump to the bottom.
        scrollController.jumpTo(scrollController.position.maxScrollExtent);

        // Drag an arbitrary amount of pixels from the bottom of the editor.
        final dragGesture = await tester.dragByFrameCount(
          startLocation: tester.getRect(find.byType(CustomScrollView)).bottomCenter - const Offset(0, 10),
          totalDragOffset: const Offset(0, -400.0),
        );

        // Ensure we don't scroll.
        expect(scrollController.offset, scrollController.position.maxScrollExtent);

        // End the gesture.
        await dragGesture.up();

        // Wait for the long-press timer to resolve.
        await tester.pumpAndSettle();
      });

      testWidgetsOnIos('overscrolls when dragging down', (tester) async {
        final scrollController = ScrollController();

        // Pump an editor inside a CustomScrollView without enough room to display
        // the whole content.
        await tester
            .createDocument() //
            .withLongTextContent()
            .insideCustomScrollView()
            .withScrollController(scrollController)
            .pump();

        // Ensure the scrollview didn't start scrolled.
        expect(scrollController.offset, 0);

        // Drag an arbitrary amount, smaller than the editor size.
        final dragGesture = await tester.dragByFrameCount(
          startLocation: tester.getRect(find.byType(CustomScrollView)).topCenter + const Offset(0, 5),
          totalDragOffset: const Offset(0, 80.0),
        );

        // Ensure we are overscrolling while holding the pointer down.
        await tester.pumpAndSettle();
        expect(scrollController.offset, lessThan(0.0));

        // Release the pointer to end the gesture.
        await dragGesture.up();

        // Wait for the long-press timer to resolve.
        await tester.pumpAndSettle();

        // Ensure the we scrolled back to the top.
        expect(scrollController.offset, 0.0);
      });

      testWidgetsOnIos('overscrolls when dragging up', (tester) async {
        final scrollController = ScrollController();

        // Pump an editor inside a CustomScrollView without enough room to display
        // the whole content.
        await tester
            .createDocument() //
            .withLongTextContent()
            .withEditorSize(const Size(200, 200))
            .insideCustomScrollView()
            .withScrollController(scrollController)
            .pump();

        // Jump to the bottom.
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        await tester.pumpAndSettle();

        // Drag up an arbitrary amount, smaller than the editor size.
        final dragGesture = await tester.dragByFrameCount(
          startLocation: tester.getRect(find.byType(CustomScrollView)).bottomCenter - const Offset(0, 5),
          totalDragOffset: const Offset(0, -100.0),
        );

        // Ensure we are overscrolling while holding the pointer down.
        await tester.pumpAndSettle();
        expect(scrollController.offset, greaterThan(scrollController.position.maxScrollExtent));

        // Release the pointer to end the gesture.
        await dragGesture.up();

        // Wait for the long-press timer to resolve.
        await tester.pumpAndSettle();

        // Ensure the we scrolled back to the end.
        expect(scrollController.offset, scrollController.position.maxScrollExtent);
      });

      group('respects horizontal scrolling', () {
        testWidgetsOnAllPlatforms('inside a TabBar', (tester) async {
          final tabController = TabController(length: 2, vsync: tester);
          final scrollController = ScrollController();

          // Pump a SuperEditor with a small maxHeight, so adding lines
          // will cause the editor to scroll.
          await tester
              .createDocument()
              .withSingleEmptyParagraph()
              .withInputSource(TextInputSource.ime)
              .withScrollController(scrollController)
              .withCustomWidgetTreeBuilder(
                (superEditor) => MaterialApp(
                  home: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 300,
                      maxHeight: 100,
                    ),
                    child: Scaffold(
                      appBar: AppBar(
                        bottom: TabBar(
                          controller: tabController,
                          tabs: const [
                            Tab(text: 'Tab 1'),
                            Tab(text: 'Tab 2'),
                          ],
                        ),
                      ),
                      body: TabBarView(
                        controller: tabController,
                        children: [
                          superEditor,
                          const SizedBox(),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .pump();

          // Select the editor.
          await tester.placeCaretInParagraph('1', 0);

          // Add new lines so the content will cause editor to scroll
          await _addNewLines(tester, count: 40);
          await tester.pumpAndSettle();

          // Ensure SuperEditor has scrolled
          expect(scrollController.offset, greaterThan(0));

          // Ensure that scrolling didn't cause a tab change
          expect(tabController.index, equals(0));
        });

        testWidgetsOnAllPlatforms('inside a horizontal ListView', (tester) async {
          final listScrollController = ScrollController();
          final editorScrollController = ScrollController();

          // Pump a SuperEditor with a small maxHeight, so adding lines
          // will cause the editor to scroll.
          await tester
              .createDocument()
              .withSingleEmptyParagraph()
              .withInputSource(TextInputSource.ime)
              .withScrollController(editorScrollController)
              .withCustomWidgetTreeBuilder(
                (superEditor) => MaterialApp(
                  home: Scaffold(
                    body: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 300,
                        maxHeight: 100,
                        maxWidth: 300,
                      ),
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        controller: listScrollController,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 100),
                            child: superEditor,
                          ),
                          ...List.generate(20, (index) => Text('Text $index')),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .pump();

          // Select the editor.
          await tester.placeCaretInParagraph('1', 0);

          // Add new lines so the content will cause editor to scroll
          await _addNewLines(tester, count: 40);
          await tester.pumpAndSettle();

          // Ensure SuperEditor has scrolled
          expect(editorScrollController.offset, greaterThan(0));
        });
      });

      group("when all content fits in the viewport", () {
        testWidgetsOnDesktop(
          "trackpad doesn't scroll content",
          (tester) async {
            tester.view.physicalSize = const Size(800, 600);

            final isScrollingUp = _scrollDirectionVariant.currentValue == _ScrollDirection.up;

            await tester //
                .createDocument()
                .withCustomContent(
                  paragraphThenHrThenParagraphDoc()
                    ..insertNodeAt(
                      0,
                      ParagraphNode(
                        id: Editor.createNodeId(),
                        text: AttributedText('Document #1'),
                        metadata: {
                          'blockType': header1Attribution,
                        },
                      ),
                    ),
                )
                .pump();

            final scrollState = tester.state<ScrollableState>(find.byType(Scrollable));

            // Perform a fling on the editor to attemp scrolling.
            await tester.trackpadFling(
              find.byType(SuperEditor),
              Offset(0.0, isScrollingUp ? 100 : -100),
              300,
            );

            await tester.pump();

            // Ensure SuperEditor is not scrolling.
            expect(scrollState.position.activity?.isScrolling, false);
          },
          variant: _scrollDirectionVariant,
        );

        testWidgetsOnDesktop(
          "mouse scroll wheel doesn't scroll content",
          (tester) async {
            tester.view.physicalSize = const Size(800, 600);

            final isScrollUp = _scrollDirectionVariant.currentValue == _ScrollDirection.up;

            await tester //
                .createDocument()
                .withCustomContent(
                  paragraphThenHrThenParagraphDoc()
                    ..insertNodeAt(
                      0,
                      ParagraphNode(
                        id: Editor.createNodeId(),
                        text: AttributedText('Document #1'),
                        metadata: {
                          'blockType': header1Attribution,
                        },
                      ),
                    ),
                )
                .pump();

            final scrollState = tester.state<ScrollableState>(find.byType(Scrollable));

            final Offset scrollEventLocation = tester.getCenter(find.byType(SuperEditor));
            final TestPointer testPointer = TestPointer(1, PointerDeviceKind.mouse);

            // Send initial pointer event to set the location for subsequent pointer scroll events.
            await tester.sendEventToBinding(testPointer.hover(scrollEventLocation));

            // Send pointer scroll event to start scrolling.
            await tester.sendEventToBinding(
              testPointer.scroll(
                Offset(
                  0.0,
                  isScrollUp ? 100 : -100.0,
                ),
              ),
            );

            await tester.pump();

            // Ensure SuperReader is not scrolling.
            expect(scrollState.position.activity!.isScrolling, false);
          },
          variant: _scrollDirectionVariant,
        );
      });
    });

    testWidgetsOnDesktop('shows scrollbar by default', (tester) async {
      final scrollController = ScrollController();
      await tester //
          .createDocument()
          .withSingleParagraph()
          .withEditorSize(const Size(300, 300))
          .withScrollController(scrollController)
          .pump();

      // Ensure the editor is scrollable.
      expect(scrollController.position.maxScrollExtent, greaterThan(0.0));

      // Ensure the scrollbar is displayed.
      expect(
        find.descendant(
          of: find.byType(SuperEditor),
          matching: find.byType(Scrollbar),
        ),
        findsOneWidget,
      );
    });

    testWidgetsOnDesktop('does not show scrollbar when ancestor ScrollConfiguration does not want one', (tester) async {
      final scrollController = ScrollController();
      await tester //
          .createDocument()
          .withSingleParagraph()
          .withEditorSize(const Size(300, 300))
          .withScrollController(scrollController)
          .withCustomWidgetTreeBuilder(
            (superEditor) => MaterialApp(
              home: Scaffold(
                body: ScrollConfiguration(
                  behavior: const ScrollBehavior().copyWith(scrollbars: false),
                  child: superEditor,
                ),
              ),
            ),
          )
          .pump();

      // Ensure the editor is scrollable.
      expect(scrollController.position.maxScrollExtent, greaterThan(0.0));

      // Ensure no scrollbar is displayed.
      expect(
        find.descendant(
          of: find.byType(SuperEditor),
          matching: find.byType(Scrollbar),
        ),
        findsNothing,
      );
    });

    testWidgetsOnMobile('spurious metrics change is ignored', (tester) async {
      final scrollController = ScrollController();
      await tester //
          .createDocument()
          .withLongDoc()
          .withEditorSize(const Size(300, 300))
          .withScrollController(scrollController)
          .pump();
      await tester.tapInParagraph('1', 0);
      final gesture = await tester.startGesture(const Offset(100, 100), kind: PointerDeviceKind.touch);
      await gesture.moveBy(const Offset(0, -100));
      await tester.pumpAndSettle();
      final pixels = scrollController.position.pixels;
      // This should not change scroll position.
      WidgetsBinding.instance.handleMetricsChanged();
      await Future.microtask(() {});
      await tester.pump();
      expect(scrollController.position.pixels, pixels);
    });
  });
}

/// Displays a [SuperEditor] within a parent [Scrollable], including additional
/// content above the [SuperEditor] and additional content on top of [Scrollable].
///
/// By including content above the [SuperEditor], it doesn't have the same origin as the parent [Scrollable].
///
/// By including content on top of [Scrollable], it doesn't have the origin at [Offset.zero].
class _SliverTestEditor extends StatefulWidget {
  const _SliverTestEditor({
    Key? key,
    required this.gestureMode,
  }) : super(key: key);

  final DocumentGestureMode gestureMode;

  @override
  State<_SliverTestEditor> createState() => _SliverTestEditorState();
}

class _SliverTestEditorState extends State<_SliverTestEditor> {
  late MutableDocument _doc;
  late MutableDocumentComposer _composer;
  late Editor _docEditor;

  @override
  void initState() {
    super.initState();

    _doc = _createExampleDocumentForScrolling();
    _composer = MutableDocumentComposer();
    _docEditor = createDefaultDocumentEditor(document: _doc, composer: _composer);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.only(top: 300),
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                title: const Text(
                  'Rich Text Editor Sliver Example',
                ),
                expandedHeight: 200.0,
                leading: const SizedBox(),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(color: Colors.blue),
                ),
              ),
              const SliverToBoxAdapter(
                child: Text(
                  'Lorem Ipsum Dolor',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SuperEditor(
                editor: _docEditor,
                stylesheet: defaultStylesheet.copyWith(
                  documentPadding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
                ),
                gestureMode: widget.gestureMode,
                inputSource: TextInputSource.ime,
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                    return ListTile(title: Text('$index'));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Slowly reduces window size to imitate the appearance of a keyboard.
Future<void> _simulateKeyboardAppearance({
  required WidgetTester tester,
  required Size initialScreenSize,
  required double shrinkPerFrame,
  required int frameCount,
}) async {
  // Shrink the height of the screen, one frame at a time.
  double keyboardHeight = 0.0;
  for (var i = 0; i < frameCount; i++) {
    // Shrink the height of the screen by a small amount.
    keyboardHeight += shrinkPerFrame;
    final currentScreenSize = (initialScreenSize - Offset(0, keyboardHeight)) as Size;
    tester.view.physicalSize = currentScreenSize;

    // Let the scrolling system auto-scroll, as desired.
    await tester.pumpAndSettle();
  }
}

/// Adds [count] new lines using IME actions
Future<void> _addNewLines(
  WidgetTester tester, {
  required int count,
}) async {
  for (int i = 0; i < count; i++) {
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pump();
  }
}

MutableDocument _createExampleDocumentForScrolling() {
  return MutableDocument(
    nodes: [
      ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText(
          'Example Document',
        ),
        metadata: {
          'blockType': header1Attribution,
        },
      ),
      HorizontalRuleNode(id: Editor.createNodeId()),
      ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText(
          'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus sed sagittis urna. Aenean mattis ante justo, quis sollicitudin metus interdum id. Aenean ornare urna ac enim consequat mollis. In aliquet convallis efficitur. Phasellus convallis purus in fringilla scelerisque. Ut ac orci a turpis egestas lobortis. Morbi aliquam dapibus sem, vitae sodales arcu ultrices eu. Duis vulputate mauris quam, eleifend pulvinar quam blandit eget.',
        ),
      ),
      ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText(
          'Cras vitae sodales nisi. Vivamus dignissim vel purus vel aliquet. Sed viverra diam vel nisi rhoncus pharetra. Donec gravida ut ligula euismod pharetra. Etiam sed urna scelerisque, efficitur mauris vel, semper arcu. Nullam sed vehicula sapien. Donec id tellus volutpat, eleifend nulla eget, rutrum mauris.',
        ),
      ),
      ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText(
          'Nam hendrerit vitae elit ut placerat. Maecenas nec congue neque. Fusce eget tortor pulvinar, cursus neque vitae, sagittis lectus. Duis mollis libero eu scelerisque ullamcorper. Pellentesque eleifend arcu nec augue molestie, at iaculis dui rutrum. Etiam lobortis magna at magna pellentesque ornare. Sed accumsan, libero vel porta molestie, tortor lorem eleifend ante, at egestas leo felis sed nunc. Quisque mi neque, molestie vel dolor a, eleifend tempor odio.',
        ),
      ),
      ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText(
          'Etiam id lacus interdum, efficitur ex convallis, accumsan ipsum. Integer faucibus mollis mauris, a suscipit ante mollis vitae. Fusce justo metus, congue non lectus ac, luctus rhoncus tellus. Phasellus vitae fermentum orci, sit amet sodales orci. Fusce at ante iaculis nunc aliquet pharetra. Nam placerat, nisl in gravida lacinia, nisl nibh feugiat nunc, in sagittis nisl sapien nec arcu. Nunc gravida faucibus massa, sit amet accumsan dolor feugiat in. Mauris ut elementum leo.',
        ),
      ),
    ],
  );
}

final _scrollDirectionVariant = ValueVariant<_ScrollDirection>({
  _ScrollDirection.up,
  _ScrollDirection.down,
});

enum _ScrollDirection {
  up,
  down;
}
