import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';

import '../super_textfield/super_textfield_robot.dart';
import '../test_tools.dart';
import 'supereditor_test_tools.dart';

void main() {
  group("SuperEditor selection", () {
    group("styles", () {
      testWidgetsOnAllPlatforms("changes color of selected text", (tester) async {
        final stylesheet = defaultStylesheet.copyWith(
          selectedTextColorStrategy: ({required Color originalTextColor, required Color selectionHighlightColor}) {
            return Colors.white;
          },
        );

        await tester //
            .createDocument()
            .withSingleParagraph()
            .useStylesheet(stylesheet)
            .pump();

        // Select the 2nd word in the paragraph.
        await tester.doubleTapInParagraph("1", 7);

        // Ensure that the first word is black and the second (selected) word is white.
        final richText = SuperEditorInspector.findRichTextInParagraph("1");

        expect(richText.getSpanForPosition(const TextPosition(offset: 0))!.style!.color, Colors.black);
        expect(richText.getSpanForPosition(const TextPosition(offset: 5))!.style!.color, Colors.black);

        expect(richText.getSpanForPosition(const TextPosition(offset: 6))!.style!.color, Colors.white);
        expect(richText.getSpanForPosition(const TextPosition(offset: 10))!.style!.color, Colors.white);
      });

      testWidgetsOnAllPlatforms("overrides existing color attributions", (tester) async {
        final stylesheet = defaultStylesheet.copyWith(
          selectedTextColorStrategy: ({required Color originalTextColor, required Color selectionHighlightColor}) {
            return Colors.white;
          },
        );

        // Pump an editor with green text throught the document.
        await tester //
            .createDocument()
            .withCustomContent(
              MutableDocument(
                nodes: [
                  ParagraphNode(
                    id: '1',
                    text: AttributedText(
                      'Lorem ipsum dolor',
                      AttributedSpans(
                        attributions: [
                          const SpanMarker(
                              attribution: ColorAttribution(Colors.green), offset: 0, markerType: SpanMarkerType.start),
                          const SpanMarker(
                              attribution: ColorAttribution(Colors.green), offset: 16, markerType: SpanMarkerType.end),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
            .useStylesheet(stylesheet)
            .pump();

        // Double tap to select the word "Lorem".
        await tester.doubleTapInParagraph('1', 2);

        // Ensure that the first word is white and the rest is green.
        final richText = SuperEditorInspector.findRichTextInParagraph('1');

        expect(richText.getSpanForPosition(const TextPosition(offset: 0))!.style!.color, Colors.white);
        expect(richText.getSpanForPosition(const TextPosition(offset: 4))!.style!.color, Colors.white);

        expect(richText.getSpanForPosition(const TextPosition(offset: 5))!.style!.color, Colors.green);
        expect(richText.getSpanForPosition(const TextPosition(offset: 16))!.style!.color, Colors.green);
      });

      testWidgetsOnAllPlatforms("does not crash when triple tapping on an empty paragraph", (tester) async {
        // This test is to ensure that the selection color strategy doesn't crash when the paragraph is empty.
        // See https://github.com/superlistapp/super_editor/issues/2253 for more context.
        final stylesheet = defaultStylesheet.copyWith(
          selectedTextColorStrategy: ({required Color originalTextColor, required Color selectionHighlightColor}) {
            return Colors.white;
          },
        );

        await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .useStylesheet(stylesheet)
            .pump();

        // Tripple tap on the empty paragraph.
        await tester.tripleTapInParagraph("1", 0);

        // Reaching this point means the editor didn't crash.
      });
    });

    testWidgetsOnArbitraryDesktop("calculates upstream document selection within a single node", (tester) async {
      await tester //
          .createDocument() //
          .fromMarkdown("This all fits on one line.") //
          .pump();

      // TODO: replace the following direct layout access with a simulated user
      // drag, once we've merged some new dragging tools in #645.
      final layoutState = (find.byType(SingleColumnDocumentLayout).evaluate().single as StatefulElement).state;
      final layout = layoutState as DocumentLayout;

      // Drag from upper-right to lower-left.
      //
      // By dragging in this exact direction, we're purposefully introducing contrary
      // directions: right-to-left is upstream for a single line, and up-to-down is
      // downstream for multi-node. This test ensures that the single-line direction is
      // honored by the document layout, rather than the more common multi-node calculation.
      final selection = layout.getDocumentSelectionInRegion(const Offset(1100, 35), const Offset(1050, 45));
      expect(selection, isNotNull);

      // Ensure that the document selection is upstream.
      final base = selection!.base.nodePosition as TextNodePosition;
      final extent = selection.extent.nodePosition as TextNodePosition;
      expect(base.offset > extent.offset, isTrue);
    });

    testWidgetsOnArbitraryDesktop("calculates downstream document selection within a single node", (tester) async {
      await tester //
          .createDocument() //
          .fromMarkdown("This all fits on one line.") //
          .pump();

      // TODO: replace the following direct layout access with a simulated user
      // drag, once we've merged some new dragging tools in #645.
      final layoutState = (find.byType(SingleColumnDocumentLayout).evaluate().single as StatefulElement).state;
      final layout = layoutState as DocumentLayout;

      // Drag from lower-left to upper-right.
      //
      // By dragging in this exact direction, we're purposefully introducing contrary
      // directions: left-to-right is downstream for a single line, and down-to-up is
      // upstream for multi-node. This test ensures that the single-line direction is
      // honored by the document layout, rather than the more common multi-node calculation.
      final selection = layout.getDocumentSelectionInRegion(const Offset(1050, 45), const Offset(1100, 35));
      expect(selection, isNotNull);

      // Ensure that the document selection is downstream.
      final base = selection!.base.nodePosition as TextNodePosition;
      final extent = selection.extent.nodePosition as TextNodePosition;
      expect(base.offset < extent.offset, isTrue);
    });

    testWidgetsOnArbitraryDesktop("calculates downstream document selection within a single node", (tester) async {
      final testContext = await tester //
          .createDocument() //
          .fromMarkdown("This is paragraph one.\nThis is paragraph two.") //
          .pump();
      final nodeId = testContext.findEditContext().document.first.id;

      /// Triple tap on the first line in the paragraph node.
      await tester.tripleTapInParagraph(nodeId, 10);

      /// Ensure that only the first line is selected.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection(
          base: DocumentPosition(nodeId: nodeId, nodePosition: const TextNodePosition(offset: 0)),
          extent: DocumentPosition(nodeId: nodeId, nodePosition: const TextNodePosition(offset: 22)),
        ),
      );

      /// Triple tap on the second line in the paragraph node.
      await tester.tripleTapInParagraph(nodeId, 25);

      /// Ensure that only the second line is selected.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection(
          base: DocumentPosition(nodeId: nodeId, nodePosition: const TextNodePosition(offset: 23)),
          extent: DocumentPosition(nodeId: nodeId, nodePosition: const TextNodePosition(offset: 45)),
        ),
      );
    });

    testWidgetsOnArbitraryDesktop("doesn't select an unselectable component at base (dragging upstream)",
        (tester) async {
      final testContext = await _pumpUnselectableComponentTestApp(tester);

      final firstParagraphId = testContext.findEditContext().document.first.id;

      // TODO: replace the following direct layout access with a simulated user
      // drag, once we've merged some new dragging tools in #645.
      final layoutState = (find.byType(SingleColumnDocumentLayout).evaluate().single as StatefulElement).state;
      final layout = layoutState as DocumentLayout;

      // Attempt to select from the horizontal rule to the beginning of the first paragraph
      final selection = layout.getDocumentSelectionInRegion(
        tester.getBottomRight(find.byType(Divider)),
        tester.getTopLeft(find.text('First Paragraph', findRichText: true)),
      );

      // Ensure we don't select the horizontal rule
      expect(
        selection,
        DocumentSelection(
          base: DocumentPosition(nodeId: firstParagraphId, nodePosition: const TextNodePosition(offset: 15)),
          extent: DocumentPosition(nodeId: firstParagraphId, nodePosition: const TextNodePosition(offset: 0)),
        ),
      );
    });

    testWidgetsOnArbitraryDesktop("doesn't select an unselectable component at extent (dragging upstream)",
        (tester) async {
      final testContext = await _pumpUnselectableComponentTestApp(tester);

      final secondParagraphId = testContext.findEditContext().document.last.id;

      // TODO: replace the following direct layout access with a simulated user
      // drag, once we've merged some new dragging tools in #645.
      final layoutState = (find.byType(SingleColumnDocumentLayout).evaluate().single as StatefulElement).state;
      final layout = layoutState as DocumentLayout;

      // Attempt to select from the end of the second paragraph to the horizontal rule
      final selection = layout.getDocumentSelectionInRegion(
        tester.getBottomRight(find.text('Second Paragraph', findRichText: true)),
        tester.getTopLeft(find.byType(Divider)),
      );

      // Ensure we don't select the horizontal rule
      expect(
        selection,
        DocumentSelection(
          base: DocumentPosition(
              nodeId: secondParagraphId,
              nodePosition: const TextNodePosition(
                offset: 16,
                affinity: TextAffinity.upstream,
              )),
          extent: DocumentPosition(nodeId: secondParagraphId, nodePosition: const TextNodePosition(offset: 0)),
        ),
      );
    });

    testWidgetsOnArbitraryDesktop("doesn't select an unselectable component at base (dragging downstream)",
        (tester) async {
      final testContext = await _pumpUnselectableComponentTestApp(tester);

      final secondParagraphId = testContext.findEditContext().document.last.id;

      // TODO: replace the following direct layout access with a simulated user
      // drag, once we've merged some new dragging tools in #645.
      final layoutState = (find.byType(SingleColumnDocumentLayout).evaluate().single as StatefulElement).state;
      final layout = layoutState as DocumentLayout;

      // Attempt to select from the horizontal rule to the end of the second paragraph
      final selection = layout.getDocumentSelectionInRegion(
        tester.getTopLeft(find.byType(Divider)),
        tester.getBottomRight(find.text('Second Paragraph', findRichText: true)),
      );

      // Ensure we don't select the horizontal rule
      expect(
        selection,
        DocumentSelection(
          base: DocumentPosition(nodeId: secondParagraphId, nodePosition: const TextNodePosition(offset: 0)),
          extent: DocumentPosition(
              nodeId: secondParagraphId,
              nodePosition: const TextNodePosition(
                offset: 16,
                affinity: TextAffinity.upstream,
              )),
        ),
      );
    });

    testWidgetsOnArbitraryDesktop("doesn't select an unselectable component at extent (dragging downstream)",
        (tester) async {
      final testContext = await _pumpUnselectableComponentTestApp(tester);

      final firstParagraphId = testContext.findEditContext().document.first.id;

      // TODO: replace the following direct layout access with a simulated user
      // drag, once we've merged some new dragging tools in #645.
      final layoutState = (find.byType(SingleColumnDocumentLayout).evaluate().single as StatefulElement).state;
      final layout = layoutState as DocumentLayout;

      // Attempt to select from first paragraph to the horizontal rule
      final selection = layout.getDocumentSelectionInRegion(
        tester.getTopLeft(find.text('First Paragraph', findRichText: true)),
        tester.getBottomRight(find.byType(Divider)),
      );

      // Ensure we don't select the horizontal rule
      expect(
        selection,
        DocumentSelection(
          base: DocumentPosition(nodeId: firstParagraphId, nodePosition: const TextNodePosition(offset: 0)),
          extent: DocumentPosition(nodeId: firstParagraphId, nodePosition: const TextNodePosition(offset: 15)),
        ),
      );
    });

    testWidgetsOnArbitraryDesktop("selects paragraphs surrounding an unselectable component (dragging upstream)",
        (tester) async {
      final testContext = await _pumpUnselectableComponentTestApp(tester);

      final firstParagraphId = testContext.findEditContext().document.first.id;
      final secondParagraphId = testContext.findEditContext().document.last.id;

      // TODO: replace the following direct layout access with a simulated user
      // drag, once we've merged some new dragging tools in #645.
      final layoutState = (find.byType(SingleColumnDocumentLayout).evaluate().single as StatefulElement).state;
      final layout = layoutState as DocumentLayout;

      // Attempt to select from the end of the second paragraph to the beginning of the first paragraph
      final selection = layout.getDocumentSelectionInRegion(
        tester.getBottomRight(find.text('Second Paragraph', findRichText: true)),
        tester.getTopLeft(find.text('First Paragraph', findRichText: true)),
      );

      // Ensure we select the whole document
      expect(
        selection,
        DocumentSelection(
          base: DocumentPosition(
            nodeId: secondParagraphId,
            nodePosition: const TextNodePosition(offset: 16, affinity: TextAffinity.upstream),
          ),
          extent: DocumentPosition(nodeId: firstParagraphId, nodePosition: const TextNodePosition(offset: 0)),
        ),
      );
    });

    testWidgetsOnArbitraryDesktop("selects paragraphs surrounding an unselectable component (dragging downstream)",
        (tester) async {
      final testContext = await _pumpUnselectableComponentTestApp(tester);

      final firstParagraphId = testContext.findEditContext().document.first.id;
      final secondParagraphId = testContext.findEditContext().document.last.id;

      // TODO: replace the following direct layout access with a simulated user
      // drag, once we've merged some new dragging tools in #645.
      final layoutState = (find.byType(SingleColumnDocumentLayout).evaluate().single as StatefulElement).state;
      final layout = layoutState as DocumentLayout;

      // Attempt to select from the beginning of the first paragraph to the end of the second paragraph
      final selection = layout.getDocumentSelectionInRegion(
        tester.getTopLeft(find.text('First Paragraph', findRichText: true)),
        tester.getBottomRight(find.text('Second Paragraph', findRichText: true)),
      );

      // Ensure we select the whole document
      expect(
        selection,
        DocumentSelection(
          base: DocumentPosition(nodeId: firstParagraphId, nodePosition: const TextNodePosition(offset: 0)),
          extent: DocumentPosition(
              nodeId: secondParagraphId,
              nodePosition: const TextNodePosition(
                offset: 16,
                affinity: TextAffinity.upstream,
              )),
        ),
      );
    });

    testWidgetsOnArbitraryDesktop("keeps selection base while dragging a selection across components that change size",
        (tester) async {
      final document = MutableDocument(
        nodes: [
          TaskNode(
            id: '1',
            text: AttributedText('Task 1'),
            isComplete: false,
          ),
          TaskNode(
            id: '2',
            text: AttributedText('Task 2'),
            isComplete: false,
          ),
          TaskNode(
            id: '3',
            text: AttributedText('Task 3'),
            isComplete: false,
          ),
        ],
      );

      await tester //
          .createDocument()
          .withCustomContent(document)
          .withAddedComponents([ExpandingTaskComponentBuilder()]) //
          .pump();

      // Place the caret at "Tas|k 3" to make it expand.
      await tester.placeCaretInParagraph('3', 3);
      expect(
        SuperEditorInspector.findDocumentSelection(),
        selectionEquivalentTo(
          const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: '3',
              nodePosition: TextNodePosition(offset: 3),
            ),
          ),
        ),
      );

      // Start dragging from "Tas|k 3" to the beginning of the document.
      final gesture = await tester.startDocumentDragFromPosition(
        from: const DocumentPosition(
          nodeId: '3',
          nodePosition: TextNodePosition(offset: 3),
        ),
      );
      addTearDown(() => gesture.removePointer());

      // Gradually move up until the beginning of the document.
      for (int i = 0; i <= 10; i++) {
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump();
      }

      // Ensure the selection expanded to the beginning of the document
      // and the selection base was retained.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        selectionEquivalentTo(
          const DocumentSelection(
            base: DocumentPosition(
              nodeId: '3',
              nodePosition: TextNodePosition(offset: 3),
            ),
            extent: DocumentPosition(
              nodeId: '1',
              nodePosition: TextNodePosition(offset: 0),
            ),
          ),
        ),
      );

      // Pump with enough time to expire the tap recognizer timer.
      await tester.pump(kTapTimeout);
    });

    testWidgetsOnAllPlatforms("removes caret when it loses focus", (tester) async {
      await tester
          .createDocument()
          .withLongTextContent()
          .withCustomWidgetTreeBuilder(
            (superEditor) => MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const TextField(),
                    Expanded(child: superEditor),
                  ],
                ),
              ),
            ),
          )
          .pump();

      // Place the caret in the document.
      await tester.placeCaretInParagraph("1", 0);

      // Focus the textfield.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // Ensure that the document doesn't have focus, and isn't displaying a caret.
      expect(SuperEditorInspector.hasFocus(), isFalse);
      expect(SuperEditorInspector.findDocumentSelection(), isNull);
      expect(_caretFinder(), findsNothing); // TODO: move caret finding into inspector
    });

    testWidgetsOnAllPlatforms("places caret at end of document upon first editor focus with tab", (tester) async {
      await tester
          .createDocument()
          .withLongTextContent()
          .withAddedComponents([const _UnselectableHrComponentBuilder()])
          .withCustomWidgetTreeBuilder(
            (superEditor) => MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const TextField(),
                    Expanded(child: superEditor),
                  ],
                ),
              ),
            ),
          )
          .pump();

      // Focus the textfield.
      await tester.tap(find.byType(TextField));

      // Press tab to focus the editor.
      await tester.pressTab();
      await tester.pumpAndSettle();

      final doc = SuperEditorInspector.findDocument();

      // Ensure selection is at the last character of the last paragraph.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: doc!.last.id,
            nodePosition: const TextNodePosition(offset: 477),
          ),
        ),
      );

      // Ensure caret is displayed.
      expect(_caretFinder(), findsOneWidget);
    });

    testWidgetsOnAllPlatforms("places caret at end of document upon first editor focus with next", (tester) async {
      await tester
          .createDocument()
          .withLongTextContent()
          .withInputSource(TextInputSource.ime)
          .withAddedComponents([const _UnselectableHrComponentBuilder()])
          .withCustomWidgetTreeBuilder(
            (superEditor) => MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const TextField(),
                    Expanded(child: superEditor),
                  ],
                ),
              ),
            ),
          )
          .pump();

      // Focus the textfield.
      await tester.tap(find.byType(TextField));

      // Simulate a tap at the action button on the text field.
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();

      final doc = SuperEditorInspector.findDocument();

      // Ensure selection is at the last character of the last paragraph.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: doc!.last.id,
            nodePosition: const TextNodePosition(offset: 477),
          ),
        ),
      );

      // Ensure caret is displayed.
      expect(_caretFinder(), findsOneWidget);
    });

    testWidgetsOnAllPlatforms("places caret at end of document upon first editor focus when requesting focus",
        (tester) async {
      final focusNode = FocusNode();

      await tester //
          .createDocument()
          .withLongTextContent()
          .withFocusNode(focusNode)
          .withAddedComponents([const _UnselectableHrComponentBuilder()]).pump();

      // Ensure the editor doesn't have a selection.
      expect(SuperEditorInspector.findDocumentSelection(), isNull);

      // Focus the editor.
      focusNode.requestFocus();
      await tester.pumpAndSettle();

      final doc = SuperEditorInspector.findDocument();

      // Ensure selection is at the last character of the second paragraph.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: doc!.last.id,
            nodePosition: const TextNodePosition(offset: 477),
          ),
        ),
      );

      // Ensure caret is displayed.
      expect(_caretFinder(), findsOneWidget);
    });

    testWidgetsOnAllPlatforms("places caret at end of document upon first editor focus on autofocus", (tester) async {
      await tester //
          .createDocument()
          .withLongTextContent()
          .autoFocus(true)
          .withAddedComponents([const _UnselectableHrComponentBuilder()]).pump();

      await tester.pumpAndSettle();

      final doc = SuperEditorInspector.findDocument();

      // Ensure selection is at the last character of the last paragraph.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: doc!.last.id,
            nodePosition: const TextNodePosition(offset: 477),
          ),
        ),
      );

      // Ensure caret is displayed.
      expect(_caretFinder(), findsOneWidget);
    });

    testWidgetsOnAllPlatforms("ignores unselectable components upon first editor focus", (tester) async {
      await tester
          .createDocument()
          .fromMarkdown("""
First Paragraph

Second Paragraph

---
""")
          .withAddedComponents([const _UnselectableHrComponentBuilder()])
          .withCustomWidgetTreeBuilder(
            (superEditor) => MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const TextField(),
                    Expanded(child: superEditor),
                  ],
                ),
              ),
            ),
          )
          .pump();

      // Focus the textfield.
      await tester.tap(find.byType(TextField));

      // Press tab to focus the editor.
      await tester.pressTab();
      await tester.pumpAndSettle();

      final doc = SuperEditorInspector.findDocument();
      final secondParagraphNodeId = doc!.getNodeAt(1)!.id;

      // Ensure selection is at the last character of the second paragraph.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: secondParagraphNodeId,
            nodePosition: const TextNodePosition(offset: 16),
          ),
        ),
      );

      // Ensure caret is displayed.
      expect(_caretFinder(), findsOneWidget);
    });

    testWidgetsOnDesktop("by default keeps IME connection open when it loses primary focus", (tester) async {
      // Note: we don't include mobile in this test because mobile text fields always use IME
      // which will steal the IME connection away from SuperEditor and interfere with the expected
      // result.

      final textFieldFocus = FocusNode();
      final subtreeFocus = FocusNode();
      final editorFocus = FocusNode();
      await tester
          .createDocument()
          .withSingleParagraph()
          .withInputSource(TextInputSource.ime)
          .withFocusNode(editorFocus)
          .withCustomWidgetTreeBuilder(
            (superEditor) => MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    Focus(
                      focusNode: subtreeFocus,
                      parentNode: editorFocus,
                      child: SuperTextField(
                        focusNode: textFieldFocus,
                        // We put the SuperTextField in keyboard mode so that the SuperTextField
                        // doesn't steal the IME connection. This way, we ensure that SuperEditor,
                        // left to its own devices, will proactively close the IME connection when
                        // it loses primary focus.
                        inputSource: TextInputSource.keyboard,
                      ),
                    ),
                    Expanded(
                      child: superEditor,
                    ),
                  ],
                ),
              ),
            ),
          )
          .autoFocus(true)
          .pump();

      // Ensure that SuperEditor begins with focus, a selection, and IME connection
      expect(editorFocus.hasPrimaryFocus, isTrue);
      expect(SuperEditorInspector.findDocumentSelection(), isNotNull);
      expect(SuperEditorInspector.isImeConnectionOpen(), isTrue);

      // Focus the textfield.
      await tester.placeCaretInSuperTextField(0);

      // Ensure that the textfield has primary focus, the editor doesn't, and the editor
      // still has an open IME connection.
      expect(textFieldFocus.hasPrimaryFocus, isTrue);
      expect(editorFocus.hasPrimaryFocus, isFalse);
      expect(editorFocus.hasFocus, isTrue);
      expect(SuperEditorInspector.findDocumentSelection(), isNotNull);
      expect(SuperEditorInspector.isImeConnectionOpen(), isTrue);

      // Give focus back to the editor.
      textFieldFocus.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
      await tester.pump();

      // Ensure that the textfield doesn't have any focus, and the editor has primary focus again.
      expect(textFieldFocus.hasFocus, isFalse);
      expect(editorFocus.hasPrimaryFocus, isTrue);
      expect(SuperEditorInspector.findDocumentSelection(), isNotNull);
      expect(SuperEditorInspector.isImeConnectionOpen(), isTrue);
    });

    testWidgetsOnDesktop("can optionally close IME connection when it loses primary focus", (tester) async {
      // Note: we don't include mobile in this test because mobile text fields always use IME
      // which will steal the IME connection away from SuperEditor and interfere with the expected
      // result.

      final textFieldFocus = FocusNode();
      final subtreeFocus = FocusNode();
      final editorFocus = FocusNode();
      await tester
          .createDocument()
          .withSingleParagraph()
          .withInputSource(TextInputSource.ime)
          .withFocusNode(editorFocus)
          .withImePolicies(
            const SuperEditorImePolicies(closeKeyboardOnLosePrimaryFocus: true),
          )
          .withCustomWidgetTreeBuilder(
            (superEditor) => MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    Focus(
                      focusNode: subtreeFocus,
                      parentNode: editorFocus,
                      child: SuperTextField(
                        focusNode: textFieldFocus,
                        // We put the SuperTextField in keyboard mode so that the SuperTextField
                        // doesn't steal the IME connection. This way, we ensure that SuperEditor,
                        // left to its own devices, will proactively close the IME connection when
                        // it loses primary focus.
                        inputSource: TextInputSource.keyboard,
                      ),
                    ),
                    Expanded(
                      child: superEditor,
                    ),
                  ],
                ),
              ),
            ),
          )
          .autoFocus(true)
          .pump();

      // Ensure that SuperEditor begins with focus, a selection, and IME connection
      expect(editorFocus.hasPrimaryFocus, isTrue);
      expect(SuperEditorInspector.findDocumentSelection(), isNotNull);
      expect(SuperEditorInspector.isImeConnectionOpen(), isTrue);

      // Focus the textfield.
      await tester.placeCaretInSuperTextField(0);

      // Ensure that the textfield has primary focus, the editor doesn't, and the editor
      // closed the IME connection.
      expect(textFieldFocus.hasPrimaryFocus, isTrue);
      expect(editorFocus.hasPrimaryFocus, isFalse);
      expect(editorFocus.hasFocus, isTrue);
      expect(SuperEditorInspector.findDocumentSelection(), isNotNull);
      expect(SuperEditorInspector.isImeConnectionOpen(), isFalse);

      // Give focus back to the editor.
      textFieldFocus.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
      await tester.pump();

      // Ensure that the textfield doesn't have any focus, and the editor has primary focus again.
      expect(textFieldFocus.hasFocus, isFalse);
      expect(editorFocus.hasPrimaryFocus, isTrue);
      expect(SuperEditorInspector.findDocumentSelection(), isNotNull);
      expect(SuperEditorInspector.isImeConnectionOpen(), isTrue);
    });

    testWidgetsOnAllPlatforms("retains selection when user types in sub-focus text field", (tester) async {
      final textFieldFocus = FocusNode();
      final subTreeFocusNode = FocusNode();
      final textFieldController = ImeAttributedTextEditingController();
      final editorFocus = FocusNode();
      const initialEditorSelection = DocumentSelection(
        base: DocumentPosition(nodeId: "1", nodePosition: TextNodePosition(offset: 6)),
        extent: DocumentPosition(nodeId: "1", nodePosition: TextNodePosition(offset: 11)),
      );
      await tester
          .createDocument()
          .withSingleParagraph()
          .withInputSource(TextInputSource.ime)
          .withFocusNode(editorFocus)
          .withSelection(initialEditorSelection)
          .withSelectionPolicies(const SuperEditorSelectionPolicies(
            clearSelectionWhenEditorLosesFocus: true,
          ))
          .withCustomWidgetTreeBuilder(
            (superEditor) => MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    Focus(
                      focusNode: subTreeFocusNode,
                      parentNode: editorFocus,
                      child: SuperTextField(
                        focusNode: textFieldFocus,
                        textController: textFieldController,
                        inputSource: TextInputSource.ime,
                      ),
                    ),
                    Expanded(
                      child: superEditor,
                    ),
                  ],
                ),
              ),
            ),
          )
          .autoFocus(true)
          .pump();

      // Ensure that SuperEditor has focus, a selection, and IME connection
      expect(editorFocus.hasPrimaryFocus, isTrue);
      expect(SuperEditorInspector.findDocumentSelection(), initialEditorSelection);

      // Type into the text field.
      await tester.placeCaretInSuperTextField(0);
      await tester.typeImeText("Hello, world", find.byType(SuperTextField));

      // Ensure the text field received the text.
      expect(textFieldController.text.toPlainText(), "Hello, world");

      // Ensure that SuperEditor has the same selection as before.
      expect(SuperEditorInspector.findDocumentSelection(), initialEditorSelection);
    });

    // TODO: make sure caret disappears when editor has focus, but not primary focus

    testWidgetsOnAllPlatforms("places caret at the previous selection when re-focusing by tab", (tester) async {
      await tester
          .createDocument()
          .withSingleParagraph()
          .withInputSource(TextInputSource.ime)
          .withCustomWidgetTreeBuilder(
            (superEditor) => MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const TextField(),
                    Expanded(child: superEditor),
                  ],
                ),
              ),
            ),
          )
          .pump();

      // Place caret in the middle of a word.
      await tester.placeCaretInParagraph('1', 8);
      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: '1',
            nodePosition: TextNodePosition(offset: 8),
          ),
        ),
      );

      // Focus the textfield.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // Ensure selection was cleared.
      expect(SuperEditorInspector.findDocumentSelection(), isNull);

      // Press tab to focus the editor.
      await tester.pressTab();
      await tester.pumpAndSettle();

      // Ensure selection is restored.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: '1',
            nodePosition: TextNodePosition(offset: 8),
          ),
        ),
      );

      // Ensure caret is displayed.
      expect(_caretFinder(), findsOneWidget);
    });

    testWidgetsOnAllPlatforms("places caret at the previous selection when re-focusing by next", (tester) async {
      await tester
          .createDocument()
          .withSingleParagraph()
          .withInputSource(TextInputSource.ime)
          .withCustomWidgetTreeBuilder(
            (superEditor) => MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const TextField(),
                    Expanded(child: superEditor),
                  ],
                ),
              ),
            ),
          )
          .pump();

      // Place caret in the middle of a word.
      await tester.placeCaretInParagraph('1', 8);
      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: '1',
            nodePosition: TextNodePosition(offset: 8),
          ),
        ),
      );

      // Focus the textfield.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // Ensure selection was cleared.
      expect(SuperEditorInspector.findDocumentSelection(), isNull);

      // Simulate a tap at the action button.
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();

      // Ensure selection is restored.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: '1',
            nodePosition: TextNodePosition(offset: 8),
          ),
        ),
      );

      // Ensure caret is displayed.
      expect(_caretFinder(), findsOneWidget);
    });

    testWidgetsOnAllPlatforms("places caret at the previous selection when re-focusing by requesting focus",
        (tester) async {
      final focusNode = FocusNode();

      await tester
          .createDocument()
          .withSingleParagraph()
          .withInputSource(TextInputSource.ime)
          .withFocusNode(focusNode)
          .withCustomWidgetTreeBuilder(
            (superEditor) => MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const TextField(),
                    Expanded(child: superEditor),
                  ],
                ),
              ),
            ),
          )
          .pump();

      // Place caret in the middle of a word.
      await tester.placeCaretInParagraph('1', 8);
      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: '1',
            nodePosition: TextNodePosition(offset: 8),
          ),
        ),
      );

      // Focus the textfield.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // Ensure selection was cleared.
      expect(SuperEditorInspector.findDocumentSelection(), isNull);

      // Focus the editor.
      focusNode.requestFocus();
      await tester.pumpAndSettle();

      // Ensure selection is restored.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: '1',
            nodePosition: TextNodePosition(offset: 8),
          ),
        ),
      );

      // Ensure caret is displayed.
      expect(_caretFinder(), findsOneWidget);
    });

    testWidgetsOnAllPlatforms("doesn't restore previous selection upon re-focusing when selected node was deleted",
        (tester) async {
      final focusNode = FocusNode();

      final context = await tester
          .createDocument()
          .withLongTextContent()
          .withInputSource(TextInputSource.ime)
          .withFocusNode(focusNode)
          .withCustomWidgetTreeBuilder(
            (superEditor) => MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const TextField(),
                    Expanded(child: superEditor),
                  ],
                ),
              ),
            ),
          )
          .pump();

      // Place caret at the beginning of the text.
      await tester.placeCaretInParagraph('1', 0);
      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: '1',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );

      // Focus the textfield.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // Ensure selection was cleared.
      expect(SuperEditorInspector.findDocumentSelection(), isNull);

      // Delete the selected node.
      context.findEditContext().editor.execute([
        DeleteNodeRequest(nodeId: "1"),
      ]);

      // Focus the editor.
      focusNode.requestFocus();
      await tester.pumpAndSettle();

      // Ensure no selection was restored.
      expect(SuperEditorInspector.findDocumentSelection(), isNull);
    });

    testWidgetsOnAllPlatforms('retains composer initial selection upon first editor focus', (tester) async {
      final focusNode = FocusNode();

      const initialSelection = DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: '1',
          nodePosition: TextNodePosition(offset: 6),
        ),
      );

      await tester //
          .createDocument()
          .withSingleParagraph()
          .withFocusNode(focusNode)
          .withSelection(initialSelection)
          .pump();

      focusNode.requestFocus();

      await tester.pumpAndSettle();

      // Ensure initial selection was retained.
      expect(SuperEditorInspector.findDocumentSelection(), initialSelection);

      // Ensure caret is displayed.
      expect(_caretFinder(), findsOneWidget);
    });

    testWidgetsOnAllPlatforms("applies selection changes from the platform", (tester) async {
      await tester //
          .createDocument()
          .withSingleParagraph()
          .withInputSource(TextInputSource.ime)
          .pump();

      // Place the caret at the middle of the first word.
      await tester.placeCaretInParagraph('1', 2);

      final text = SuperEditorInspector.findTextInComponent('1').toPlainText();

      await tester.ime.sendDeltas(
        [
          TextEditingDeltaNonTextUpdate(
            oldText: '. $text',
            selection: const TextSelection.collapsed(offset: 8),
            composing: const TextSelection.collapsed(offset: 8),
          )
        ],
        getter: imeClientGetter,
      );

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: '1',
            nodePosition: TextNodePosition(offset: 6),
          ),
        ),
      );
    });

    testWidgetsOnAllPlatforms("doesn't notify about selection changes when the selection hasn't changed",
        (tester) async {
      // The composer pauses and restarts selection notifications, which is an unusual
      // behavior. We want to ensure that when the selection doesn't actually change,
      // this system doesn't send selection change notifications.

      final context = await tester //
          .createDocument()
          .withLongTextContent()
          .autoFocus(true)
          .pump();

      final doc = context.findEditContext().document;
      final composer = context.findEditContext().composer;

      int selectionNotificationCount = 0;
      composer.selectionNotifier.addListener(() {
        selectionNotificationCount += 1;
      });
      int selectionChangeCount = 0;
      composer.selectionChanges.listen((event) {
        selectionChangeCount += 1;
      });

      // Ensure selection is at the last character of the last paragraph.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: doc.last.id,
            nodePosition: const TextNodePosition(offset: 477),
          ),
        ),
      );

      // Send a selection change, using the existing selection.
      context.findEditContext().editor.execute([
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: doc.last.id,
              nodePosition: const TextNodePosition(offset: 477),
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);
      await tester.pump();

      // Ensure that we weren't notified of any selection changes.
      expect(selectionNotificationCount, 0);
      expect(selectionChangeCount, 0);
    });
  });
}

Future<TestDocumentContext> _pumpUnselectableComponentTestApp(WidgetTester tester) async {
  return await tester //
      .createDocument() //
      .fromMarkdown("""
First Paragraph

---

Second Paragraph
""")
      .withComponentBuilders([
        const _UnselectableHrComponentBuilder(),
        ...defaultComponentBuilders,
      ])
      .withEditorSize(const Size(300, 300))
      .pump();
}

/// SuperEditor [ComponentBuilder] that builds a horizontal rule that is
/// not selectable.
class _UnselectableHrComponentBuilder implements ComponentBuilder {
  const _UnselectableHrComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
    List<ComponentBuilder> componentBuilders,
  ) {
    // This builder can work with the standard horizontal rule view model, so
    // we'll defer to the standard horizontal rule builder.
    return null;
  }

  @override
  Widget? createComponent(
      SingleColumnDocumentComponentContext componentContext, SingleColumnLayoutComponentViewModel componentViewModel) {
    if (componentViewModel is! HorizontalRuleComponentViewModel) {
      return null;
    }

    return _UnselectableHorizontalRuleComponent(
      componentKey: componentContext.componentKey,
    );
  }
}

class _UnselectableHorizontalRuleComponent extends StatelessWidget {
  const _UnselectableHorizontalRuleComponent({
    Key? key,
    required this.componentKey,
  }) : super(key: key);

  final GlobalKey componentKey;

  @override
  Widget build(BuildContext context) {
    return BoxComponent(
      key: componentKey,
      isVisuallySelectable: false,
      child: const Divider(
        color: Color(0xFF000000),
        thickness: 1.0,
      ),
    );
  }
}

Finder _caretFinder() {
  return find.byKey(DocumentKeys.caret);
}
