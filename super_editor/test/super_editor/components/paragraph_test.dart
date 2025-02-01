import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';

import '../../test_runners.dart';
import '../supereditor_test_tools.dart';

void main() {
  group("SuperEditor > Paragraph Component >", () {
    testWidgetsOnAllPlatforms("visually updates alignment immediately after it is changed", (tester) async {
      final editorContext = await tester //
          .createDocument()
          .withSingleParagraph()
          .pump();

      // Place the caret at the beginning of the paragraph.
      await tester.placeCaretInParagraph("1", 0);

      // Note the visual offset of the caret when left-aligned.
      final leftAlignedCaretOffset = SuperEditorInspector.findCaretOffsetInDocument();

      // Ensure that we begin with a visually left-aligned paragraph widget.
      var paragraphComponent = find.byType(TextComponent).evaluate().first.widget as TextComponent;
      expect(paragraphComponent.textAlign, TextAlign.left);

      // Change the paragraph to right-alignment.
      editorContext.editor.execute([
        ChangeParagraphAlignmentRequest(nodeId: "1", alignment: TextAlign.right),
      ]);
      await tester.pump();

      // Ensure that the paragraph's associated widget is now right-aligned.
      //
      // This is as close as we can get to verifying visual text alignment without either
      // inspecting the render object, or generating a golden file.
      paragraphComponent = find.byType(TextComponent).evaluate().first.widget as TextComponent;
      expect(paragraphComponent.textAlign, TextAlign.right);

      // Ensure that the caret didn't stay in the same location after changing the
      // alignment of the paragraph. This check ensures that the caret overlay updated
      // itself in response to the paragraph layout changing.
      expect(SuperEditorInspector.findCaretOffsetInDocument() == leftAlignedCaretOffset, isFalse);
    });

    group("block newlines >", () {
      testWidgetsOnAllPlatforms("inserts newline in middle and splits paragraph into two paragraphs",
          (WidgetTester tester) async {
        await tester
            .createDocument() //
            .withSingleShortParagraph()
            .pump();

        // Place the caret in the middle of the paragraph:
        // "This is the first |node in a document."
        await tester.placeCaretInParagraph("1", 18);

        // Insert a newline.
        switch (debugDefaultTargetPlatformOverride) {
          case TargetPlatform.android:
          case TargetPlatform.iOS:
            // FIXME: pressEnterWithIme should work, but it seems to think there are no
            //        connected IME clients, so it fizzles. For now, we use the implementation
            //        directly.
            // await tester.pressEnterWithIme();
            await tester.testTextInput.receiveAction(TextInputAction.newline);
          case TargetPlatform.macOS:
          case TargetPlatform.windows:
          case TargetPlatform.linux:
          case TargetPlatform.fuchsia:
          case null:
            await tester.pressEnter();
        }

        // Ensure we have two paragraphs, each with part of the original text.
        final document = SuperEditorInspector.findDocument()!;
        expect(document.nodeCount, 2);

        expect(document.first.metadata["blockType"], paragraphAttribution);
        expect(document.first.asTextNode.text.toPlainText(), "This is the first ");

        expect(document.last.metadata["blockType"], paragraphAttribution);
        expect(document.last.asTextNode.text.toPlainText(), "node in a document.");
      });

      testWidgetsOnAllPlatforms("inserts newline at end of paragraph to create a new empty paragraph",
          (WidgetTester tester) async {
        await tester
            .createDocument() //
            .withSingleShortParagraph()
            .pump();

        // Place caret at the end of the paragraph.
        await tester.placeCaretInParagraph("1", 37);

        // Insert a newline.
        switch (debugDefaultTargetPlatformOverride) {
          case TargetPlatform.android:
          case TargetPlatform.iOS:
            // FIXME: pressEnterWithIme should work, but it seems to think there are no
            //        connected IME clients, so it fizzles. For now, we use the implementation
            //        directly.
            // await tester.pressEnterWithIme();
            await tester.testTextInput.receiveAction(TextInputAction.newline);
          case TargetPlatform.macOS:
          case TargetPlatform.windows:
          case TargetPlatform.linux:
          case TargetPlatform.fuchsia:
          case null:
            await tester.pressEnter();
        }

        // Ensure a new, empty paragraph was inserted after the blockquote.
        final document = SuperEditorInspector.findDocument()!;
        expect(document.nodeCount, 2);

        expect(document.first.metadata["blockType"], paragraphAttribution);
        expect(document.first.asTextNode.text.toPlainText(), "This is the first node in a document.");

        expect(document.last.metadata["blockType"], paragraphAttribution);
        expect(document.last.asTextNode.text.toPlainText(), "");
      });

      testWidgetsOnAllPlatforms("does nothing when caret is in non-deletable paragraph", (tester) async {
        await tester
            .createDocument()
            .withCustomContent(
              MutableDocument(
                nodes: [
                  ParagraphNode(
                    id: "1",
                    text: AttributedText("Non-deletable paragraph."),
                    metadata: const {
                      NodeMetadata.isDeletable: false,
                    },
                  ),
                  ParagraphNode(
                    id: "2",
                    text: AttributedText("A deletable paragraph."),
                  ),
                ],
              ),
            )
            .pump();

        // Place caret in the middle of the non-deletable paragraph.
        await tester.placeCaretInParagraph("1", 5);

        // Press enter to try to split the paragraph.
        switch (debugDefaultTargetPlatformOverride) {
          case TargetPlatform.android:
          case TargetPlatform.iOS:
            // FIXME: pressEnterWithIme should work, but it seems to think there are no
            //        connected IME clients, so it fizzles. For now, we use the implementation
            //        directly.
            // await tester.pressEnterWithIme();
            await tester.testTextInput.receiveAction(TextInputAction.newline);
          case TargetPlatform.macOS:
          case TargetPlatform.windows:
          case TargetPlatform.linux:
          case TargetPlatform.fuchsia:
          case null:
            await tester.pressEnter();
        }

        // Ensure the paragraph wasn't changed.
        final document = SuperEditorInspector.findDocument()!;
        expect(document.nodeCount, 2);
        expect(document.first.asTextNode.text.toPlainText(), "Non-deletable paragraph.");
      });

      testWidgetsOnAllPlatforms("does nothing when non-deletable content is selected", (tester) async {
        final editContext = await tester
            .createDocument()
            .withCustomContent(
              MutableDocument(
                nodes: [
                  ParagraphNode(
                    id: "1",
                    text: AttributedText("A paragraph."),
                  ),
                  HorizontalRuleNode(
                    id: "2",
                    metadata: const {
                      NodeMetadata.isDeletable: false,
                    },
                  ),
                ],
              ),
            )
            .autoFocus(true)
            .pump();

        // Select from the paragraph across the HR.
        editContext.editor.execute([
          ChangeSelectionRequest(
            DocumentSelection(
              base: DocumentPosition(
                documentPath: NodePath.forNode("1"),
                nodePosition: const TextNodePosition(offset: 5),
              ),
              extent: DocumentPosition(
                documentPath: NodePath.forNode("2"),
                nodePosition: const UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
            SelectionChangeType.expandSelection,
            SelectionReason.userInteraction,
          ),
        ]);
        await tester.pump();

        // Press enter to try to delete part of the paragraph and a non-deletable
        // horizontal rule.
        switch (debugDefaultTargetPlatformOverride) {
          case TargetPlatform.android:
          case TargetPlatform.iOS:
            // FIXME: pressEnterWithIme should work, but it seems to think there are no
            //        connected IME clients, so it fizzles. For now, we use the implementation
            //        directly.
            // await tester.pressEnterWithIme();
            await tester.testTextInput.receiveAction(TextInputAction.newline);
          case TargetPlatform.macOS:
          case TargetPlatform.windows:
          case TargetPlatform.linux:
          case TargetPlatform.fuchsia:
          case null:
            await tester.pressEnter();
        }

        // Ensure nothing happened to the document.
        final document = SuperEditorInspector.findDocument()!;
        expect(document.nodeCount, 2);
        expect(document.first.asTextNode.text.toPlainText(), "A paragraph.");
        expect(document.last, isA<HorizontalRuleNode>());
      });
    });

    group("soft newlines >", () {
      testWidgetsOnDesktop("SHIFT + ENTER inserts a soft newline in middle of paragraph", (tester) async {
        final editorContext = await tester //
            .createDocument()
            .withSingleShortParagraph()
            .pump();

        // Place the caret in the middle of the paragraph:
        // "This is the first |node in a document."
        await tester.placeCaretInParagraph("1", 18);

        // Hold shift and press enter.
        await tester.pressShiftEnter();

        // Ensure that we still have a single paragraph, but there's a newline in the middle.
        expect(editorContext.document.nodeCount, 1);
        expect(editorContext.document.first.asTextNode.text.toPlainText(), "This is the first \nnode in a document.");
      });

      testWidgetsOnDesktop("SHIFT + ENTER inserts a soft newline at end of paragraph", (tester) async {
        final editorContext = await tester //
            .createDocument()
            .withSingleShortParagraph()
            .pump();

        // Place the caret at the end of the paragraph.
        await tester.placeCaretInParagraph("1", 37);

        // Hold shift and press enter.
        await tester.pressShiftEnter();

        // Ensure that we still have a single paragraph, but it ends with a newline.
        expect(editorContext.document.nodeCount, 1);
        expect(editorContext.document.first.asTextNode.text.last, "\n");
      });
    });

    group("indentation >", () {
      testWidgetsOnDesktop("indents with Tab and un-indents with Shift+Tab", (tester) async {
        await tester //
            .createDocument()
            .withSingleParagraph()
            .pump();

        // Place the caret in the child task.
        await tester.placeCaretInParagraph("1", 0);

        // Ensure the paragraph isn't indented.
        expect(SuperEditorInspector.findParagraphIndent("1"), 0);

        // Press Tab to indent the paragraph.
        await tester.pressTab();

        // Ensure the paragraph is indented.
        expect(SuperEditorInspector.findParagraphIndent("1"), 1);

        // Press Tab to indent a second time.
        await tester.pressTab();

        // Ensure the paragraph is indented at level 2.
        expect(SuperEditorInspector.findParagraphIndent("1"), 2);

        // Press Shift+Tab to unindent.
        // TODO: add pressShiftTab to flutter_test_robots - https://github.com/Flutter-Bounty-Hunters/flutter_test_robots/issues/30
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        await tester.pump();

        // Ensure the paragraph was un-indented.
        expect(SuperEditorInspector.findParagraphIndent("1"), 1);

        // Press Shift+Tab to unindent.
        // TODO: add pressShiftTab to flutter_test_robots
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        await tester.pump();

        // Ensure the paragraph was un-indented.
        expect(SuperEditorInspector.findParagraphIndent("1"), 0);

        // Press Shift+Tab to unindent (should have no effect).
        // TODO: add pressShiftTab to flutter_test_robots
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        await tester.pump();

        // Ensure the indentation didn't change because it was already at zero.
        expect(SuperEditorInspector.findParagraphIndent("1"), 0);
      });

      testWidgetsOnDesktop("indents with Tab when caret is in middle of text", (tester) async {
        await tester //
            .createDocument()
            .withSingleParagraph()
            .pump();

        // Place the caret in the middle of the text.
        await tester.placeCaretInParagraph("1", 2);

        // Ensure the paragraph isn't indented.
        expect(SuperEditorInspector.findParagraphIndent("1"), 0);

        // Press Tab to indent the paragraph.
        await tester.pressTab();

        // Ensure the paragraph is indented.
        expect(SuperEditorInspector.findParagraphIndent("1"), 1);

        // Press Shift+Tab to unindent.
        // TODO: add pressShiftTab to flutter_test_robots
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        await tester.pump();

        // Ensure the paragraph was un-indented.
        expect(SuperEditorInspector.findParagraphIndent("1"), 0);
      });

      testWidgetsOnDesktop("next paragraph preserves indent, pressing Enter removes inherited indent", (tester) async {
        await tester //
            .createDocument()
            .withSingleParagraph()
            .pump();

        // Place caret at the end of the paragraph.
        await tester.placeCaretInParagraph("1", SuperEditorInspector.findTextInComponent("1").length);

        // Indent the paragraph.
        await tester.pressTab();

        // Insert a new paragraph.
        await tester.pressEnter();

        // Ensure the new paragraph is indented.
        var newParagraph = SuperEditorInspector.findDocument()!.getNodeAt(1) as ParagraphNode;
        expect(newParagraph.indent, 1);

        // Press Enter again to reset the indent.
        await tester.pressEnter();

        // Ensure the new paragraph is no longer indented.
        newParagraph = SuperEditorInspector.findDocument()!.getNodeAt(1) as ParagraphNode;
        expect(newParagraph.indent, 0);
      });

      testWidgetsOnDesktopAndWeb("Backspace at start of text un-indents paragraph", (tester) async {
        await tester //
            .createDocument()
            .withSingleParagraph()
            .withInputSource(TextInputSource.ime)
            .pump();

        await tester.placeCaretInParagraph("1", 0);

        // Indent the paragraph.
        await tester.pressTab();

        // Ensure the second task is indented.
        expect(SuperEditorInspector.findParagraphIndent("1"), 1);

        // Place the caret in the middle of the text
        await tester.placeCaretInParagraph("1", 3);

        // Press Backspace to delete one character.
        await tester.pressBackspace();

        // Ensure that the Backspace didn't un-indent the paragraph.
        expect(SuperEditorInspector.findParagraphIndent("1"), 1);

        // Place caret at start of the paragraph.
        await tester.placeCaretInParagraph("1", 0);

        // Press Backspace to un-indent the task.
        await tester.pressBackspace();

        // Ensure the paragraph was un-indented.
        expect(SuperEditorInspector.findParagraphIndent("1"), 0);
      });
    });
  });
}
