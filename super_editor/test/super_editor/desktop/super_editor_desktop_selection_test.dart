import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';

import '../supereditor_test_tools.dart';

void main() {
  group("Super Editor > desktop >", () {
    testWidgetsOnDesktop("selects by word when double tap and dragging downstream", (tester) async {
      // "Lorem ipsum |dolor sit| amet, consectetur adipiscing elit, sed do eiusmod tempor..."
      //              ^  ^      ^
      //             12  14    21
      await _pumpSingleParagraphScaffold(tester);

      final gesture = await tester.doubleTapDownInParagraph("1", 14);

      for (int i = 0; i < 10; i += 1) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump();
      }

      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection(
          base: DocumentPosition(
            documentPath: NodePath.forNode("1"),
            nodePosition: const TextNodePosition(offset: 12),
          ),
          extent: DocumentPosition(
            documentPath: NodePath.forNode("1"),
            nodePosition: const TextNodePosition(offset: 21),
          ),
        ),
      );

      await gesture.up();
    });

    testWidgetsOnDesktop("selects by word when double tap and dragging upstream", (tester) async {
      // "Lorem |ipsum dolor| sit amet, consectetur adipiscing elit, sed do eiusmod tempor..."
      //        ^        ^  ^
      //        6       14  17
      await _pumpSingleParagraphScaffold(tester);

      final gesture = await tester.doubleTapDownInParagraph("1", 14);

      for (int i = 0; i < 10; i += 1) {
        await gesture.moveBy(const Offset(-10, 0));
        await tester.pump();
      }

      expect(
        SuperEditorInspector.findDocumentSelection(),
        DocumentSelection(
          base: DocumentPosition(
            documentPath: NodePath.forNode("1"),
            nodePosition: const TextNodePosition(offset: 17),
          ),
          extent: DocumentPosition(
            documentPath: NodePath.forNode("1"),
            nodePosition: const TextNodePosition(offset: 6),
          ),
        ),
      );

      await gesture.up();
    });
  });
}

Future<void> _pumpSingleParagraphScaffold(WidgetTester tester) async {
  await tester //
      .createDocument()
      .withSingleParagraph()
      .pump();
}
