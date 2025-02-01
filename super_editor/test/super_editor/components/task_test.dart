import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/src/test/ime.dart';
import 'package:super_editor/src/test/super_editor_test/supereditor_inspector.dart';
import 'package:super_editor/src/test/super_editor_test/supereditor_robot.dart';
import 'package:super_editor/src/test/super_editor_test/tasks_test_tools.dart';
import 'package:super_editor/super_editor.dart';

import '../../test_runners.dart';

void main() {
  group("SuperEditor task component", () {
    testWidgetsOnAllPlatforms("toggles on tap", (tester) async {
      final document = MutableDocument(
        nodes: [
          TaskNode(id: "1", text: AttributedText("This is a task"), isComplete: false),
        ],
      );
      await _pumpScaffold(tester, document: document);

      // Ensure the task isn't checked.
      expect((document.first as TaskNode).isComplete, false);
      expect(TaskInspector.isChecked("1"), false);

      // Tap to check the box.
      await tester.tapOnCheckbox("1");

      // Ensure the task is checked.
      expect((document.first as TaskNode).isComplete, true);
      expect(TaskInspector.isChecked("1"), true);

      // Tap to uncheck the box.
      await tester.tapOnCheckbox("1");

      // Ensure the task isn't checked.
      expect((document.first as TaskNode).isComplete, false);
      expect(TaskInspector.isChecked("1"), false);
    });

    testWidgetsOnAllPlatforms("can be created from empty paragraph", (tester) async {
      final document = MutableDocument(
        nodes: [
          ParagraphNode(id: "1", text: AttributedText("This will be a task")),
        ],
      );
      final editor = await _pumpScaffold(tester, document: document);

      // Convert the paragraph to a task.
      editor.execute([const ConvertParagraphToTaskRequest(nodeId: "1")]);

      // Ensure the node is now a task.
      expect(document.nodeCount, 1);
      expect(document.first, isA<TaskNode>());
      expect((document.first as TaskNode).text.toPlainText(), "This will be a task");
    });

    group("inserts", () {
      testWidgetsOnAllPlatforms("new task on ENTER at end of existing task", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("This is a task"), isComplete: false),
          ],
        );
        final task = document.getNodeAt(0) as TaskNode;
        await _pumpScaffold(tester, document: document);

        // Place the caret at the end of the task.
        await tester.placeCaretInParagraph("1", task.text.length);

        // Press enter to create a new, empty task, below the original task.
        await tester.pressEnter();

        // Ensure that a new, empty task was created.
        expect(document.nodeCount, 2);
        expect(document.first, isA<TaskNode>());
        expect((document.first as TaskNode).text.toPlainText(), "This is a task");
        expect(document.last, isA<TaskNode>());
        expect((document.last as TaskNode).text.toPlainText(), "");
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnWebDesktop("new task on ENTER at end of existing task", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("This is a task"), isComplete: false),
          ],
        );
        final task = document.getNodeAt(0) as TaskNode;
        await _pumpScaffold(tester, document: document);

        // Place the caret at the end of the task.
        await tester.placeCaretInParagraph("1", task.text.length);

        // Press enter to create a new, empty task, below the original task.
        // On Web, this generates both a newline input action and a key event.
        await tester.pressEnter();
        await tester.testTextInput.receiveAction(TextInputAction.newline);
        await tester.pump();

        // Ensure that a new, empty task was created.
        expect(document.nodeCount, 2);
        expect(document.first, isA<TaskNode>());
        expect((document.first as TaskNode).text.toPlainText(), "This is a task");
        expect(document.last, isA<TaskNode>());
        expect((document.last as TaskNode).text.toPlainText(), "");
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnAndroid("new task upon new line insertion at end of existing task", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("This is a task"), isComplete: false),
          ],
        );
        final task = document.getNodeAt(0) as TaskNode;
        await _pumpScaffold(tester, document: document);

        // Place the caret at the end of the task.
        await tester.placeCaretInParagraph("1", task.text.length);

        // On Android, pressing ENTER generates a "\n" insertion.
        await tester.typeImeText("\n");

        // Ensure that a new, empty task was created.
        expect(document.nodeCount, 2);
        expect(document.first, isA<TaskNode>());
        expect((document.first as TaskNode).text.toPlainText(), "This is a task");
        expect(document.last, isA<TaskNode>());
        expect((document.last as TaskNode).text.toPlainText(), "");
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnMobile("new task upon new line input action at end of existing task", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("This is a task"), isComplete: false),
          ],
        );
        final task = document.getNodeAt(0) as TaskNode;
        await _pumpScaffold(tester, document: document);

        // Place the caret at the end of the task.
        await tester.placeCaretInParagraph("1", task.text.length);

        // On iOS, pressing ENTER generates a newline action.
        await tester.testTextInput.receiveAction(TextInputAction.newline);

        // Ensure that a new, empty task was created.
        expect(document.nodeCount, 2);
        expect(document.first, isA<TaskNode>());
        expect((document.first as TaskNode).text.toPlainText(), "This is a task");
        expect(document.last, isA<TaskNode>());
        expect((document.last as TaskNode).text.toPlainText(), "");
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });
    });

    group("splits", () {
      testWidgetsOnAllPlatforms("task into two on ENTER in middle of existing task", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("This is a task"), isComplete: false),
          ],
        );
        await _pumpScaffold(tester, document: document);

        // Place the caret at "This is |a task"
        await tester.placeCaretInParagraph("1", 8);

        // Press enter to split the existing task into two.
        await tester.pressEnter();

        // Ensure that a new task was created with part of the previous task.
        expect(document.nodeCount, 2);
        expect(document.first, isA<TaskNode>());
        expect((document.first as TaskNode).text.toPlainText(), "This is ");
        expect(document.last, isA<TaskNode>());
        expect((document.last as TaskNode).text.toPlainText(), "a task");
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnAndroid("task into two upon new line insertion in middle of existing task", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("This is a task"), isComplete: false),
          ],
        );
        await _pumpScaffold(tester, document: document);

        // Place the caret at "This is |a task"
        await tester.placeCaretInParagraph("1", 8);

        // On Android, pressing ENTER generates a "\n" insertion.
        await tester.typeImeText("\n");

        // Ensure that a new task was created with part of the previous task.
        expect(document.nodeCount, 2);
        expect(document.first, isA<TaskNode>());
        expect((document.first as TaskNode).text.toPlainText(), "This is ");
        expect(document.last, isA<TaskNode>());
        expect((document.last as TaskNode).text.toPlainText(), "a task");
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnMobile("task into two upon new line input action in middle of existing task", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("This is a task"), isComplete: false),
          ],
        );
        await _pumpScaffold(tester, document: document);

        // Place the caret at "This is |a task"
        await tester.placeCaretInParagraph("1", 8);

        // On iOS, pressing ENTER generates a newline action.
        await tester.testTextInput.receiveAction(TextInputAction.newline);

        // Ensure that a new task was created with part of the previous task.
        expect(document.nodeCount, 2);
        expect(document.first, isA<TaskNode>());
        expect((document.first as TaskNode).text.toPlainText(), "This is ");
        expect(document.last, isA<TaskNode>());
        expect((document.last as TaskNode).text.toPlainText(), "a task");
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });
    });

    group("converts", () {
      testWidgetsOnAllPlatforms("task to paragraph when the user presses BACKSPACE at the beginning", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("This is a task"), isComplete: false),
          ],
        );
        await _pumpScaffold(tester, document: document);

        // Place the caret at the beginning of the task.
        await tester.placeCaretInParagraph("1", 0);

        // Press backspace to merge the task with the previous paragraph.
        await tester.pressBackspace();

        // Ensure the task converted to a paragraph.
        expect(document.nodeCount, 1);
        expect(document.first, isA<ParagraphNode>());
        expect((document.first as ParagraphNode).text.toPlainText(), "This is a task");
      });

      testWidgetsOnAllPlatforms(
          "task to paragraph when the user presses BACKSPACE with software keyboard at the beginning", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("This is a task"), isComplete: false),
          ],
        );
        await _pumpScaffold(tester, document: document);

        // Place the caret at the beginning of the task.
        await tester.placeCaretInParagraph("1", 0);

        // Press backspace to convert the task into a paragraph.
        // Simulate the user pressing BACKSPACE on a software keyboard.
        await tester.ime.sendDeltas([
          const TextEditingDeltaNonTextUpdate(
            oldText: ". This is a task",
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange.empty,
          ),
          const TextEditingDeltaDeletion(
              oldText: ". This is a task",
              deletedRange: TextRange(start: 1, end: 2),
              selection: TextSelection.collapsed(offset: 1),
              composing: TextRange.empty),
        ], getter: imeClientGetter);

        // Ensure the task converted to a paragraph.
        expect(document.nodeCount, 1);
        expect(document.first, isA<ParagraphNode>());
        expect((document.first as ParagraphNode).text.toPlainText(), "This is a task");
      });

      testWidgetsOnAllPlatforms("task to paragraph when the user presses ENTER on an empty task", (tester) async {
        await _pumpScaffold(tester);

        // Place the caret at the beginning of the task.
        await tester.placeCaretInParagraph("1", 0);

        // Press enter to convert the task into a paragraph.
        await tester.pressEnter();

        final document = SuperEditorInspector.findDocument()!;

        // Ensure the task was converted to a paragraph.
        expect(document.nodeCount, 1);
        expect(document.first, isA<ParagraphNode>());
        expect((document.first as ParagraphNode).text.toPlainText(), "");
      });

      testWidgetsOnAndroid("task to paragraph upon new line insertion on an empty task", (tester) async {
        await _pumpScaffold(tester);

        // Place the caret at the beginning of the task.
        await tester.placeCaretInParagraph("1", 0);

        // Press enter to convert the task into a paragraph.
        // On Android, pressing ENTER generates a "\n" insertion.
        await tester.typeImeText("\n");

        final document = SuperEditorInspector.findDocument()!;

        // Ensure the task was converted to a paragraph.
        expect(document.nodeCount, 1);
        expect(document.first, isA<ParagraphNode>());
        expect((document.first as ParagraphNode).text.toPlainText(), "");
      });

      testWidgetsOnIos("task to paragraph new line input action on an empty task", (tester) async {
        await _pumpScaffold(tester);

        // Place the caret at the beginning of the task.
        await tester.placeCaretInParagraph("1", 0);

        // Press enter to convert the task into a paragraph.
        // On iOS, pressing ENTER generates a newline action.
        await tester.testTextInput.receiveAction(TextInputAction.newline);

        final document = SuperEditorInspector.findDocument()!;

        // Ensure the task was converted to a paragraph.
        expect(document.nodeCount, 1);
        expect(document.first, isA<ParagraphNode>());
        expect((document.first as ParagraphNode).text.toPlainText(), "");
      });

      testWidgetsOnWebDesktop("task to paragraph when the user presses ENTER on an empty task", (tester) async {
        await _pumpScaffold(tester);

        // Place the caret at the beginning of the task.
        await tester.placeCaretInParagraph("1", 0);

        // Press enter to convert the task into a paragraph.
        // On Web, this generates both a newline input action and a key event.
        await tester.pressEnter();
        await tester.testTextInput.receiveAction(TextInputAction.newline);
        await tester.pump();

        final document = SuperEditorInspector.findDocument()!;

        // Ensure the task was converted to a paragraph.
        expect(document.nodeCount, 1);
        expect(document.first, isA<ParagraphNode>());
        expect((document.first as ParagraphNode).text.toPlainText(), "");
      });

      testWidgets("paragraph to task for incomplete task", (tester) async {
        final document = MutableDocument(
          nodes: [
            ParagraphNode(id: "1", text: AttributedText("This is a task")),
          ],
        );
        final editor = await _pumpScaffold(tester, document: document);

        // Convert the paragraph to a task.
        editor.execute([
          const ConvertParagraphToTaskRequest(nodeId: "1"),
        ]);

        // Ensure the paragraph is a task, and it's not checked.
        expect(document.first, isA<TaskNode>());
        expect((document.first as TaskNode).isComplete, isFalse);
      });

      testWidgets("paragraph to task for complete task", (tester) async {
        final document = MutableDocument(
          nodes: [
            ParagraphNode(id: "1", text: AttributedText("This is a task")),
          ],
        );
        final editor = await _pumpScaffold(tester, document: document);

        // Convert the paragraph to a task.
        editor.execute([
          const ConvertParagraphToTaskRequest(nodeId: "1", isComplete: true),
        ]);

        // Ensure the paragraph is a task, and it IS checked.
        expect(document.first, isA<TaskNode>());
        expect((document.first as TaskNode).isComplete, isTrue);
      });
    });

    group("indentation >", () {
      testWidgetsOnDesktop("does nothing without parent task", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("can't indent"), isComplete: false),
          ],
        );
        await _pumpScaffold(tester, document: document);

        // Place the caret in the task.
        await tester.placeCaretInParagraph("1", 0);

        // Ensure the task isn't indented.
        expect(SuperEditorInspector.findTaskIndent("1"), 0);

        // Press Tab to try to indent the task.
        await tester.pressTab();

        // Ensure the task still isn't indented.
        expect(SuperEditorInspector.findTaskIndent("1"), 0);
      });

      testWidgetsOnDesktop("applies indent when parent is a task", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("parent"), isComplete: false),
            TaskNode(id: "2", text: AttributedText("can indent"), isComplete: false),
          ],
        );
        await _pumpScaffold(tester, document: document);

        // Place the caret in the child task.
        await tester.placeCaretInParagraph("2", 0);

        // Ensure the task isn't indented.
        expect(SuperEditorInspector.findTaskIndent("2"), 0);

        // Press Tab to indent the task.
        await tester.pressTab();

        // Ensure the task is indented.
        expect(SuperEditorInspector.findTaskIndent("2"), 1);
      });

      testWidgetsOnDesktop("Backspace at start of text un-indents task", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("one"), isComplete: false),
            TaskNode(id: "2", text: AttributedText("two"), isComplete: false, indent: 1),
          ],
        );
        await _pumpScaffold(tester, document: document);

        // Ensure the second task is indented.
        expect(SuperEditorInspector.findTaskIndent("2"), 1);

        // Place the caret at the end of the indented task.
        await tester.placeCaretInParagraph("2", 3);

        // Press Backspace to delete one character.
        await tester.pressBackspace();

        // Ensure that the Backspace deleted a character, instead of un-indenting.
        expect(SuperEditorInspector.findTaskIndent("2"), 1);
        expect(SuperEditorInspector.findTextInComponent("2").toPlainText(), "tw");

        // Place caret at start of task.
        await tester.placeCaretInParagraph("2", 0);

        // Press Backspace to un-indent the task.
        await tester.pressBackspace();

        // Ensure the task was un-indented..
        expect(SuperEditorInspector.findTaskIndent("2"), 0);
      });

      testWidgetsOnDesktop("does not apply to following tasks at same level", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("one"), isComplete: false),
            TaskNode(id: "2", text: AttributedText("two"), isComplete: false),
            TaskNode(id: "3", text: AttributedText("three"), isComplete: false),
          ],
        );
        await _pumpScaffold(tester, document: document);

        // Place the caret in the child task.
        await tester.placeCaretInParagraph("2", 0);

        // Ensure the task isn't indented.
        expect(SuperEditorInspector.findTaskIndent("2"), 0);

        // Press Tab to indent the task.
        await tester.pressTab();

        // Ensure the 2nd task is indented.
        expect(SuperEditorInspector.findTaskIndent("2"), 1);

        // Ensure the 3rd task isn't indented.
        expect(SuperEditorInspector.findTaskIndent("3"), 0);
      });

      testWidgetsOnDesktop("can indent multiple levels based on parent", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("one"), isComplete: false),
            TaskNode(id: "2", text: AttributedText("two"), isComplete: false, indent: 1),
            TaskNode(id: "3", text: AttributedText("three"), isComplete: false, indent: 2),
            TaskNode(id: "4", text: AttributedText("four"), isComplete: false),
          ],
        );
        await _pumpScaffold(tester, document: document);

        // Place the caret in the child task.
        await tester.placeCaretInParagraph("4", 0);

        // Press Tab multiple times to indent multiple levels.
        await tester.pressTab();
        await tester.pressTab();
        await tester.pressTab();

        // Ensure the 4th task is indented to level 3.
        expect(SuperEditorInspector.findTaskIndent("4"), 3);
      });

      testWidgetsOnDesktop("does not indent more than one space past the parent", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("one"), isComplete: false),
            TaskNode(id: "2", text: AttributedText("two"), isComplete: false, indent: 1),
            TaskNode(id: "3", text: AttributedText("three"), isComplete: false, indent: 2),
          ],
        );
        await _pumpScaffold(tester, document: document);

        // Place the caret in the child task.
        await tester.placeCaretInParagraph("2", 0);

        // Ensure the task is initially indented at level 1.
        expect(SuperEditorInspector.findTaskIndent("2"), 1);

        // Press Tab to attempt to further indent.
        await tester.pressTab();

        // Ensure the indent didn't change because it was already at max indent.
        expect(SuperEditorInspector.findTaskIndent("2"), 1);
      });

      testWidgetsOnDesktop("unindenting parent pulls children back", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("one"), isComplete: false),
            TaskNode(id: "2", text: AttributedText("two"), isComplete: false, indent: 1),
            TaskNode(id: "3", text: AttributedText("three"), isComplete: false, indent: 2),
            TaskNode(id: "4", text: AttributedText("four"), isComplete: false, indent: 2),
            TaskNode(id: "5", text: AttributedText("five"), isComplete: false, indent: 3),
          ],
        );
        await _pumpScaffold(tester, document: document);

        // Place the caret in the second task.
        await tester.placeCaretInParagraph("2", 0);

        // Ensure the 2nd task begins indented.
        expect(SuperEditorInspector.findTaskIndent("2"), 1);

        // Un-indent the second task.
        // TODO: add pressShiftTab to flutter_test_robots
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        await tester.pump();

        // Ensure the 2nd task un-indented.
        expect(SuperEditorInspector.findTaskIndent("2"), 0);

        // Ensure the lower tasks reduced their indentation level.
        expect(SuperEditorInspector.findTaskIndent("3"), 1);
        expect(SuperEditorInspector.findTaskIndent("4"), 1);
        expect(SuperEditorInspector.findTaskIndent("5"), 2);
      });

      testWidgetsOnDesktop("deleting parent task pulls children back", (tester) async {
        final document = MutableDocument(
          nodes: [
            TaskNode(id: "1", text: AttributedText("one"), isComplete: false),
            TaskNode(id: "2", text: AttributedText("two"), isComplete: false, indent: 1),
            TaskNode(id: "3", text: AttributedText("three"), isComplete: false, indent: 2),
            TaskNode(id: "4", text: AttributedText("four"), isComplete: false, indent: 1),
            TaskNode(id: "5", text: AttributedText("five"), isComplete: false, indent: 2),
            TaskNode(id: "6", text: AttributedText("six"), isComplete: false, indent: 0),
          ],
        );
        final editor = await _pumpScaffold(tester, document: document);

        // Delete the 2nd task.
        editor.execute([
          DeleteNodeRequest(nodeId: "2"),
        ]);
        await tester.pump();

        // Ensure that the third task automatically decreased its indent.
        expect(SuperEditorInspector.findTaskIndent("3"), 1);

        // Ensure the legal tasks below the deleted task weren't impacted.
        expect(SuperEditorInspector.findTaskIndent("4"), 1);
        expect(SuperEditorInspector.findTaskIndent("5"), 2);
        expect(SuperEditorInspector.findTaskIndent("6"), 0);
      });
    });
  });
}

Future<Editor> _pumpScaffold(WidgetTester tester, {MutableDocument? document}) async {
  document ??= MutableDocument(
    nodes: [
      TaskNode(id: "1", text: AttributedText(), isComplete: false),
    ],
  );

  final composer = MutableDocumentComposer();
  final editor = createDefaultDocumentEditor(document: document, composer: composer);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SuperEditor(
          editor: editor,
        ),
      ),
    ),
  );

  return editor;
}
