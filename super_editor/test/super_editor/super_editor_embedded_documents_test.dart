import 'package:attributed_text/attributed_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/editor.dart';
import 'package:super_editor/src/default_editor/paragraph.dart';

import 'supereditor_test_tools.dart';

void main() {
  group("SuperEditor embedded documents >", () {
    testWidgetsOnAllPlatforms("displays embedded documents", (tester) async {
      tester.view.physicalSize = const Size(600, 600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
      });

      await tester
          .createDocument()
          .withCustomContent(MutableDocument(nodes: [
            ParagraphNode(id: "1.1", text: AttributedText("Paragraph before the first level of embedding.")),
            CompositeDocumentNode("2", [
              ParagraphNode(id: "2.1", text: AttributedText("Paragraph before the second level of embedding.")),
              CompositeDocumentNode("3", [
                ParagraphNode(id: "3.1", text: AttributedText("This paragraph is in the 3rd level of document.")),
              ]),
              ParagraphNode(id: "2.3", text: AttributedText("Paragraph after the second level of embedding.")),
            ]),
            ParagraphNode(id: "1.3", text: AttributedText("Paragraph after the first level of embedding.")),
          ]))
          .pump();

      await expectLater(find.byType(MaterialApp), matchesGoldenFile("deletme.png"));
    });
  });
}
