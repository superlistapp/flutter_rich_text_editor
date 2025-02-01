import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  group("Bug fix", () {
    group("429 - delete multiple new nodes", () {
      testWidgets("bug repro", (tester) async {
        final document = MutableDocument.empty("1");
        final composer = MutableDocumentComposer(
          initialSelection: DocumentSelection.collapsed(
            position: DocumentPosition(
              documentPath: NodePath.forNode("1"),
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
        );
        final editor = createDefaultDocumentEditor(document: document, composer: composer);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SuperEditor(
                editor: editor,
                gestureMode: DocumentGestureMode.mouse,
                inputSource: TextInputSource.keyboard,
              ),
            ),
          ),
        );

        await tester.tap(find.byType(SuperEditor));
        await tester.pumpAndSettle();

        // Create a couple new nodes.
        await tester.pressEnter();
        await tester.pressEnter();

        // Ensure we created the new nodes.
        expect(document.nodeCount, 3);

        // Select the new nodes.
        editor.execute([
          ChangeSelectionRequest(
            DocumentSelection(
              base: DocumentPosition(
                documentPath: NodePath.forNode(document.getNodeAt(2)!.id),
                nodePosition: document.getNodeAt(2)!.endPosition,
              ),
              extent: DocumentPosition(
                documentPath: NodePath.forNode(document.getNodeAt(1)!.id),
                nodePosition: document.getNodeAt(1)!.beginningPosition,
              ),
            ),
            SelectionChangeType.expandSelection,
            SelectionReason.userInteraction,
          ),
        ]);
        await tester.pumpAndSettle();

        // Delete the new nodes.
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle();

        // Bug #429 - the deletion threw an error due to a selection
        // type mismatch.
        expect(document.nodeCount, 2);
        expect(composer.selection!.isCollapsed, true);
        expect(
          composer.selection!.extent,
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgets("related to bug", (tester) async {
        final document = MutableDocument.empty("1");
        final composer = MutableDocumentComposer(
          initialSelection: TextNode.caretAt(["1"], 0),
        );
        final editor = createDefaultDocumentEditor(document: document, composer: composer);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SuperEditor(
                editor: editor,
                gestureMode: DocumentGestureMode.mouse,
                inputSource: TextInputSource.keyboard,
              ),
            ),
          ),
        );
        await tester.tap(find.byType(SuperEditor));
        await tester.pumpAndSettle();

        // Create a couple new nodes.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        // Select the new nodes.
        editor.execute([
          ChangeSelectionRequest(
            DocumentSelection(
              base: DocumentPosition(
                documentPath: NodePath.forNode(document.getNodeAt(1)!.id),
                nodePosition: document.getNodeAt(1)!.beginningPosition,
              ),
              extent: DocumentPosition(
                documentPath: NodePath.forNode(document.getNodeAt(2)!.id),
                nodePosition: document.getNodeAt(2)!.endPosition,
              ),
            ),
            SelectionChangeType.expandSelection,
            SelectionReason.userInteraction,
          ),
        ]);
        await tester.pumpAndSettle();

        // Delete the new nodes.
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle();

        // The bug was a problem with an expanded upstream selection.
        // Here we make sure that deleting an expanded downstream
        // selection works, too.
        expect(document.nodeCount, 2);
        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent, TextNode.caretAt([document.last.id], 0));
      });
    });
  });
}
