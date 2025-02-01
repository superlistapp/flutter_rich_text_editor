import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/src/test/super_editor_test/supereditor_inspector.dart';
import 'package:super_editor/src/test/super_editor_test/supereditor_robot.dart';
import 'package:super_editor/super_editor.dart';

import '../supereditor_test_tools.dart';

void main() {
  group('SuperEditor horizontal rule component', () {
    testWidgetsOnAllPlatforms('inserts a paragraph when typing at the end', (tester) async {
      final testContext = await tester
          .createDocument() //
          .fromMarkdown('''
Paragraph 1

---

Paragraph 2
''')
          .withInputSource(TextInputSource.ime)
          .pump();

      final document = testContext.findEditContext().document;

      // Place the caret at the end of the horizontal rule, by first placing the caret in the paragraph after the
      // horizontal rule, and then pressing the left arrow to move it up.
      await tester.placeCaretInParagraph(document.last.id, 0);
      await tester.pressLeftArrow();

      // Type at the end of the horizontal rule
      await tester.typeImeText('new paragraph');

      // Ensure that the new text was inserted in a new paragraph after the horizontal rule.
      expect(document.nodeCount, 4);
      final insertedNode = document.getNodeAt(2)!;
      expect(insertedNode, isA<ParagraphNode>());
      expect((insertedNode as ParagraphNode).text.toPlainText(), 'new paragraph');
      expect(
        SuperEditorInspector.findDocumentSelection(),
        TextNode.caretAt([insertedNode.id], 13),
      );
    });

    testWidgetsOnAllPlatforms('inserts a paragraph when typing at the beginning', (tester) async {
      final testContext = await tester
          .createDocument() //
          .fromMarkdown('''
Paragraph 1

---

Paragraph 2
''')
          .withInputSource(TextInputSource.ime)
          .pump();

      final document = testContext.findEditContext().document;

      // Place the caret at the beginning of the horizontal rule, by first placing the caret in the paragraph before the
      // horizontal rule, and then pressing the right arrow to move it down.
      await tester.placeCaretInParagraph(document.first.id, 11);
      await tester.pressRightArrow();

      // Type at the beginning of the horizontal rule
      await tester.typeImeText('new paragraph');

      // Ensure that the new text was inserted in a new paragraph before the horizontal rule.
      expect(document.nodeCount, 4);
      final insertedNode = document.getNodeAt(1)!;
      expect(insertedNode, isA<ParagraphNode>());
      expect((insertedNode as ParagraphNode).text.toPlainText(), 'new paragraph');
      expect(
        SuperEditorInspector.findDocumentSelection(),
        TextNode.caretAt([insertedNode.id], 13),
      );
    });
  });
}
