import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/src/test/super_editor_test/supereditor_inspector.dart';
import 'package:super_editor/src/test/super_editor_test/supereditor_robot.dart';
import 'package:super_editor/super_editor.dart';

import '../supereditor_test_tools.dart';
import '../test_documents.dart';

/// Upstream/downstream selection refers components that only support
/// a caret position at the upstream edge, or downstream edge. For
/// example, an image component might use upstream/downstream selection.
void main() {
  group("Block nodes", () {
    group("move caret up", () {
      testWidgets("up arrow moves text caret to upstream edge of block from node below", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: TextNode.caretAt(["3"], 0),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "2");
        expect(composer.selection!.extent.nodePosition, const UpstreamDownstreamNodePosition.upstream());
      });

      testWidgets("up arrow moves text caret to downstream edge of block from node below", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          // The caret needs to be on the 1st line, in the right half of the line.
          initialSelection: TextNode.caretAt(["3"], 33),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "2");
        expect(composer.selection!.extent.nodePosition, const UpstreamDownstreamNodePosition.downstream());
      });

      testWidgets("up arrow moves caret from upstream edge to text node above", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtUpstreamEdge(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "1");
        expect(composer.selection!.extent.nodePosition, isA<TextNodePosition>());
      });

      testWidgets("up arrow moves caret from downstream edge to text node above", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtDownstreamEdge(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "1");
        expect(composer.selection!.extent.nodePosition, isA<TextNodePosition>());
      });

      testWidgets("left arrow moves caret to text node above", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtUpstreamEdge(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "1");
        expect(composer.selection!.extent.nodePosition, isA<TextNodePosition>());
        expect((composer.selection!.extent.nodePosition as TextNodePosition).offset, 37);
      });

      testWidgets("right arrow moves caret to text node below", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtDownstreamEdge(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "3");
        expect(composer.selection!.extent.nodePosition, isA<TextNodePosition>());
        expect((composer.selection!.extent.nodePosition as TextNodePosition).offset, 0);
      });

      testWidgets("delete moves caret down to block from node above", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: TextNode.caretAt(["1"], 37),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "2");
        expect(composer.selection!.extent.nodePosition, const UpstreamDownstreamNodePosition.upstream());
      });

      testWidgets("backspace moves caret up to block from node below", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: TextNode.caretAt(["3"], 0),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "2");
        expect(composer.selection!.extent.nodePosition, const UpstreamDownstreamNodePosition.downstream());
      });
    });

    group("move caret down", () {
      testWidgets("text caret moves to upstream edge of block from node above", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          // Caret needs to sit on the left half of the last line in the paragraph.
          initialSelection: TextNode.caretAt(["1"], 0),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "2");
        expect(composer.selection!.extent.nodePosition, const UpstreamDownstreamNodePosition.upstream());
      });

      testWidgets("text caret moves to downstream edge of block from node above", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          // Caret needs to sit in right half of the last line in the paragraph.
          initialSelection: TextNode.caretAt(["1"], 37),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "2");
        expect(composer.selection!.extent.nodePosition, const UpstreamDownstreamNodePosition.downstream());
      });

      testWidgets("upstream block caret moves to text node below", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtUpstreamEdge(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "3");
        expect(composer.selection!.extent.nodePosition, isA<TextNodePosition>());
      });

      testWidgets("downstream block caret moves to text node below", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtDownstreamEdge(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "3");
        expect(composer.selection!.extent.nodePosition, isA<TextNodePosition>());
      });

      testWidgets("right arrow moves caret to text node below", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtDownstreamEdge(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "3");
        expect(composer.selection!.extent.nodePosition, isA<TextNodePosition>());
        expect((composer.selection!.extent.nodePosition as TextNodePosition).offset, 0);
      });
    });

    group("move caret horizontally", () {
      testWidgets("right arrow moves caret downstream", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtUpstreamEdge(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "2");
        expect(composer.selection!.extent.nodePosition, const UpstreamDownstreamNodePosition.downstream());
      });

      testWidgets("left arrow moves caret upstream", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtDownstreamEdge(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "2");
        expect(composer.selection!.extent.nodePosition, const UpstreamDownstreamNodePosition.upstream());
      });

      testWidgets("right arrow collapses the expanded selection around block node to a caret on the downstream edge",
          (tester) async {
        await tester
            .createDocument()
            .withCustomContent(paragraphThenHrThenParagraphDoc())
            .withEditorSize(const Size(300, 300))
            .pump();

        await tester.doubleTapAtDocumentPosition(DocumentPosition(
          documentPath: NodePath.forNode("2"),
          nodePosition: const UpstreamDownstreamNodePosition.upstream(),
        ));
        await tester.pump(kTapMinTime + const Duration(milliseconds: 1));

        expect(
          SuperEditorInspector.findDocumentSelection(),
          BlockNode.selectNodeInDoc(["2"]),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();

        final selection = SuperEditorInspector.findDocumentSelection();

        expect(selection!.isCollapsed, true);
        expect(selection.extent.nodeId, "2");
        expect(selection.extent.nodePosition, const UpstreamDownstreamNodePosition.downstream());
      });
    });

    group("deletion", () {
      testWidgets("backspace moves caret to node above when caret is on upstream edge", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtUpstreamEdge(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "1");
        expect((composer.selection!.extent.nodePosition as TextNodePosition).offset, 37);
      });

      testWidgets("backspace removes block node when caret is on downstream edge", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtDownstreamEdge(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "2");
        expect((composer.selection!.extent.nodePosition as TextNodePosition).offset, 0);
      });

      testWidgets("delete moves caret to node below when caret is at downstream edge", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtDownstreamEdge(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "3");
        expect((composer.selection!.extent.nodePosition as TextNodePosition).offset, 0);
      });

      testWidgets("delete removes block node when caret is at upstream edge", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtUpstreamEdge(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "2");
        expect((composer.selection!.extent.nodePosition as TextNodePosition).offset, 0);
      });

      testWidgets("backspace removes block node when selected", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.selectNodeInDoc(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "2");
        expect((composer.selection!.extent.nodePosition as TextNodePosition).offset, 0);
      });

      testWidgets("delete removes block node when selected", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.selectNodeInDoc(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "2");
        expect((composer.selection!.extent.nodePosition as TextNodePosition).offset, 0);
      });

      testWidgets("backspace removes block and part of node above", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: const DocumentSelection(
            base: DocumentPosition(documentPath: NodePath(["1"]), nodePosition: TextNodePosition(offset: 20)),
            extent: DocumentPosition(
                documentPath: NodePath(["2"]), nodePosition: UpstreamDownstreamNodePosition.downstream()),
          ),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(document.nodeCount, 2);
        expect(composer.selection!.extent.nodeId, "1");
        expect((composer.selection!.extent.nodePosition as TextNodePosition).offset, 20);
      });

      testWidgets("backspace removes block and part of node below", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: const DocumentSelection(
            base: DocumentPosition(
                documentPath: NodePath(["2"]), nodePosition: UpstreamDownstreamNodePosition.upstream()),
            extent: DocumentPosition(documentPath: NodePath(["3"]), nodePosition: TextNodePosition(offset: 20)),
          ),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(document.nodeCount, 2);
        expect(composer.selection!.extent.nodeId, "3");
        expect((composer.selection!.extent.nodePosition as TextNodePosition).offset, 0);
      });

      testWidgets("backspace removes block and merges surrounding text nodes", (tester) async {
        final document = paragraphThenHrThenParagraphDoc();
        final composer = MutableDocumentComposer(
          initialSelection: const DocumentSelection(
            base: DocumentPosition(documentPath: NodePath(["1"]), nodePosition: TextNodePosition(offset: 20)),
            extent: DocumentPosition(documentPath: NodePath(["3"]), nodePosition: TextNodePosition(offset: 20)),
          ),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(document.nodeCount, 1);
        expect(composer.selection!.extent.nodeId, "1");
        expect((composer.selection!.extent.nodePosition as TextNodePosition).offset, 20);
      });

      testWidgets("backspace does nothing at beginning of document", (tester) async {
        final document = singleBlockDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtUpstreamEdge(["1"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "1");
        expect(composer.selection!.extent.nodePosition, const UpstreamDownstreamNodePosition.upstream());
      });

      testWidgets("delete does nothing at end of document", (tester) async {
        final document = singleBlockDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtDownstreamEdge(["1"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(composer.selection!.extent.nodeId, "1");
        expect(composer.selection!.extent.nodePosition, const UpstreamDownstreamNodePosition.downstream());
      });
    });

    group("Insert new nodes", () {
      testWidgets("newline inserts paragraph before block", (tester) async {
        final document = singleBlockDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtUpstreamEdge(["1"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(document.nodeCount, 2);
        expect(composer.selection!.extent.nodePosition, isA<TextNodePosition>());
        expect((composer.selection!.extent.nodePosition as TextNodePosition).offset, 0);
        expect(document.getNodeAt(0)!.id, composer.selection!.extent.nodeId);
      });

      testWidgets("newline inserts paragraph after block", (tester) async {
        final document = singleBlockDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtDownstreamEdge(["1"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(document.nodeCount, 2);
        expect(composer.selection!.extent.nodePosition, isA<TextNodePosition>());
        expect((composer.selection!.extent.nodePosition as TextNodePosition).offset, 0);
        expect(document.getNodeAt(1)!.id, composer.selection!.extent.nodeId);
      });
    });

    group("typing at boundary", () {
      testWidgets("inserts paragraph before upstream edge", (tester) async {
        final document = singleBlockDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtUpstreamEdge(["1"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(document.nodeCount, 2);
        expect(document.getNodeAt(0)!, isA<ParagraphNode>());
        expect(document.getNodeAt(1)!, isA<HorizontalRuleNode>());
        expect(composer.selection!.extent.nodePosition, const TextNodePosition(offset: 1));
      });

      testWidgets("inserts paragraph after downstream edge", (tester) async {
        final document = singleBlockDoc();
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtDownstreamEdge(["1"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(document.nodeCount, 2);
        expect(document.getNodeAt(0)!, isA<HorizontalRuleNode>());
        expect(document.getNodeAt(1)!, isA<ParagraphNode>());
        expect(composer.selection!.extent.nodePosition, const TextNodePosition(offset: 1));
      });

      testWidgets("deletes empty paragraph in node above when backspace pressed from upstream edge", (tester) async {
        final document = MutableDocument(
          nodes: [
            ParagraphNode(id: "1", text: AttributedText()),
            HorizontalRuleNode(id: "2"),
          ],
        );
        final composer = MutableDocumentComposer(
          initialSelection: BlockNode.caretAtUpstreamEdge(["2"]),
        );
        await tester.pumpWidget(_buildHardwareKeyboardEditor(document, composer));

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();

        expect(composer.selection!.isCollapsed, true);
        expect(document.nodeCount, 1);
        expect(document.getNodeAt(0)!, isA<HorizontalRuleNode>());
        expect(composer.selection!.extent.nodePosition, const UpstreamDownstreamNodePosition.upstream());
      });
    });
  });
}

Widget _buildHardwareKeyboardEditor(MutableDocument document, MutableDocumentComposer composer) {
  final editor = createDefaultDocumentEditor(document: document, composer: composer);

  return MaterialApp(
    home: Scaffold(
      body: SuperEditor(
        editor: editor,
        // Make the text small so that the test paragraphs fit on a single
        // line, so that we can place the caret on the left/right halves
        // of lines, as needed.
        stylesheet: defaultStylesheet.copyWith(
          addRulesAfter: [
            StyleRule(BlockSelector.all, (doc, node) {
              return {
                Styles.textStyle: const TextStyle(
                  fontSize: 12,
                ),
              };
            })
          ],
        ),
        gestureMode: DocumentGestureMode.mouse,
        inputSource: TextInputSource.keyboard,
        autofocus: true,
      ),
    ),
  );
}
