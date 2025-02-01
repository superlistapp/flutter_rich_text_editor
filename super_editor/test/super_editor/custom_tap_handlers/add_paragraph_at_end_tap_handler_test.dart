import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';

import '../../test_tools.dart';
import '../supereditor_test_tools.dart';

void main() {
  group('SuperEditor > SuperEditorAddEmptyParagraphTapHandler > ', () {
    group('when tapping below the end of the document', () {
      testWidgetsOnAllPlatforms('adds a new empty paragraph when the last node is a non-text node', (tester) async {
        // Pump an editor with a height big enough so we know we can tap
        // at a space after the document ends.
        await tester //
            .createDocument()
            .withCustomContent(MutableDocument(
              nodes: [
                ParagraphNode(
                  id: '1',
                  text: AttributedText('First paragraph'),
                ),
                HorizontalRuleNode(id: 'hr')
              ],
            ))
            .withEditorSize(const Size(500, 1000))
            .withTapDelegateFactories([superEditorAddEmptyParagraphTapHandlerFactory]).pump();

        // Tap below the end of the document and wait for the double tap
        // timeout to expire.
        await tester.tapAt(const Offset(490, 990));
        await tester.pumpAndSettle(kDoubleTapTimeout);

        final document = SuperEditorInspector.findDocument()!;

        // Ensure a new empty paragraph was added.
        expect(document.nodeCount, equals(3));
        expect(document.last, isA<ParagraphNode>());
        expect((document.last as ParagraphNode).text.toPlainText(), isEmpty);

        // Ensure the selection was placed in the newly added paragraph.
        expect(
          SuperEditorInspector.findDocumentSelection(),
          selectionEquivalentTo(
            TextNode.caretAt([document.last.id], 0),
          ),
        );
      });

      testWidgetsOnAllPlatforms('does nothing when the last node is a text node', (tester) async {
        // Pump an editor with a height big enough so we know we can tap
        // at a space after the document ends.
        await tester //
            .createDocument()
            .withCustomContent(MutableDocument(
              nodes: [
                HorizontalRuleNode(id: 'hr'),
                ParagraphNode(
                  id: '1',
                  text: AttributedText('First paragraph'),
                ),
              ],
            ))
            .withEditorSize(const Size(500, 1000))
            .withTapDelegateFactories([superEditorAddEmptyParagraphTapHandlerFactory]) //
            .pump();

        // Tap below the end of the document and wait for the double tap
        // timeout to expire.
        await tester.tapAt(const Offset(490, 990));
        await tester.pumpAndSettle(kDoubleTapTimeout);

        final document = SuperEditorInspector.findDocument()!;

        // Ensure the existing paragraph was kept.
        expect(document.nodeCount, equals(2));
        expect(document.last, isA<ParagraphNode>());
        expect((document.last as ParagraphNode).text.toPlainText(), 'First paragraph');

        // Ensure the selection was placed at the end of the paragraph.
        expect(
          SuperEditorInspector.findDocumentSelection(),
          selectionEquivalentTo(
            TextNode.caretAt(["1"], 15),
          ),
        );
      });
    });
  });
}
