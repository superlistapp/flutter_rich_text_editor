import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  group("Document selection", () {
    group("selects upstream position", () {
      test("when the positions are the same", () {
        final position = DocumentPosition(
          documentPath: NodePath.forNode("1"),
          nodePosition: const TextNodePosition(offset: 0),
        );
        expect(
          _testDoc.selectUpstreamPosition(position, position),
          position,
        );
      });

      test("when the positions are in the same node", () {
        final position1 = DocumentPosition(
          documentPath: NodePath.forNode("1"),
          nodePosition: const TextNodePosition(offset: 0),
        );
        final position2 = DocumentPosition(
          documentPath: NodePath.forNode("1"),
          nodePosition: const TextNodePosition(offset: 1),
        );
        expect(
          _testDoc.selectUpstreamPosition(position1, position2),
          position1,
        );
        expect(
          _testDoc.selectUpstreamPosition(position2, position1),
          position1,
        );
      });

      test("when the positions are in different nodes", () {
        final position1 = DocumentPosition(
          documentPath: NodePath.forNode("1"),
          nodePosition: const TextNodePosition(offset: 0),
        );
        final position2 = DocumentPosition(
          documentPath: NodePath.forNode("2"),
          nodePosition: const TextNodePosition(offset: 0),
        );
        expect(
          _testDoc.selectUpstreamPosition(position1, position2),
          position1,
        );
        expect(
          _testDoc.selectUpstreamPosition(position2, position1),
          position1,
        );
      });
    });

    group("selects downstream position", () {
      test("when the positions are the same", () {
        final position = DocumentPosition(
          documentPath: NodePath.forNode("1"),
          nodePosition: const TextNodePosition(offset: 0),
        );
        expect(
          _testDoc.selectDownstreamPosition(position, position),
          position,
        );
      });

      test("when the positions are in the same node", () {
        final position1 = DocumentPosition(
          documentPath: NodePath.forNode("1"),
          nodePosition: const TextNodePosition(offset: 0),
        );
        final position2 = DocumentPosition(
          documentPath: NodePath.forNode("1"),
          nodePosition: const TextNodePosition(offset: 1),
        );
        expect(
          _testDoc.selectDownstreamPosition(position1, position2),
          position2,
        );
        expect(
          _testDoc.selectDownstreamPosition(position2, position1),
          position2,
        );
      });

      test("when the positions are in different nodes", () {
        final position1 = DocumentPosition(
          documentPath: NodePath.forNode("1"),
          nodePosition: const TextNodePosition(offset: 0),
        );
        final position2 = DocumentPosition(
          documentPath: NodePath.forNode("2"),
          nodePosition: const TextNodePosition(offset: 0),
        );
        expect(
          _testDoc.selectDownstreamPosition(position1, position2),
          position2,
        );
        expect(
          _testDoc.selectDownstreamPosition(position2, position1),
          position2,
        );
      });
    });

    group("knows if it contains a position", () {
      test("when the selection is collapsed", () {
        final selection = TextNode.caretAt(["1"], 0);
        final position = DocumentPosition(
          documentPath: NodePath.forNode("1"),
          nodePosition: const TextNodePosition(offset: 0),
        );
        expect(_testDoc.doesSelectionContainPosition(selection, position), false);
      });

      test("when the selection is within one node and contains the position", () {
        final downstreamSelection = TextNode.selectionWithin(["1"], 0, 2);
        final upstreamSelection = TextNode.selectionWithin(["1"], 2, 0);
        final position = DocumentPosition(
          documentPath: NodePath.forNode("1"),
          nodePosition: const TextNodePosition(offset: 1),
        );

        expect(_testDoc.doesSelectionContainPosition(downstreamSelection, position), true);
        expect(_testDoc.doesSelectionContainPosition(upstreamSelection, position), true);
      });

      test("when the selection is within one node and the position sits before selection", () {
        final downstreamSelection = TextNode.selectionWithin(["1"], 1, 2);
        final upstreamSelection = TextNode.selectionWithin(["1"], 2, 1);
        final position = DocumentPosition(
          documentPath: NodePath.forNode("1"),
          nodePosition: const TextNodePosition(offset: 0),
        );

        expect(_testDoc.doesSelectionContainPosition(downstreamSelection, position), false);
        expect(_testDoc.doesSelectionContainPosition(upstreamSelection, position), false);
      });

      test("when the selection is within one node and the position sits after selection", () {
        final downstreamSelection = TextNode.selectionWithin(["1"], 0, 1);
        final upstreamSelection = TextNode.selectionWithin(["1"], 1, 0);
        final position = DocumentPosition(
          documentPath: NodePath.forNode("1"),
          nodePosition: const TextNodePosition(offset: 2),
        );

        expect(_testDoc.doesSelectionContainPosition(downstreamSelection, position), false);
        expect(_testDoc.doesSelectionContainPosition(upstreamSelection, position), false);
      });

      test("when the selection is across two nodes and contains the position", () {
        final downstreamSelection = DocumentSelection(
          base: DocumentPosition(documentPath: NodePath.forNode("1"), nodePosition: const TextNodePosition(offset: 0)),
          extent:
              DocumentPosition(documentPath: NodePath.forNode("2"), nodePosition: const TextNodePosition(offset: 0)),
        );
        final upstreamSelection = DocumentSelection(
          base: DocumentPosition(documentPath: NodePath.forNode("2"), nodePosition: const TextNodePosition(offset: 0)),
          extent:
              DocumentPosition(documentPath: NodePath.forNode("1"), nodePosition: const TextNodePosition(offset: 0)),
        );
        final position = DocumentPosition(
          documentPath: NodePath.forNode("1"),
          nodePosition: const TextNodePosition(offset: 1),
        );

        expect(_testDoc.doesSelectionContainPosition(downstreamSelection, position), true);
        expect(_testDoc.doesSelectionContainPosition(upstreamSelection, position), true);
      });

      test("when the selection is across two nodes and the position comes before the selection", () {
        final downstreamSelection = DocumentSelection(
          base: DocumentPosition(documentPath: NodePath.forNode("1"), nodePosition: const TextNodePosition(offset: 1)),
          extent:
              DocumentPosition(documentPath: NodePath.forNode("2"), nodePosition: const TextNodePosition(offset: 0)),
        );
        final upstreamSelection = DocumentSelection(
          base: DocumentPosition(documentPath: NodePath.forNode("2"), nodePosition: const TextNodePosition(offset: 0)),
          extent:
              DocumentPosition(documentPath: NodePath.forNode("1"), nodePosition: const TextNodePosition(offset: 1)),
        );
        final position = DocumentPosition(
          documentPath: NodePath.forNode("1"),
          nodePosition: const TextNodePosition(offset: 0),
        );

        expect(_testDoc.doesSelectionContainPosition(downstreamSelection, position), false);
        expect(_testDoc.doesSelectionContainPosition(upstreamSelection, position), false);
      });

      test("when the selection is across two nodes and the position comes after the selection", () {
        final downstreamSelection = DocumentSelection(
          base: DocumentPosition(documentPath: NodePath.forNode("1"), nodePosition: const TextNodePosition(offset: 0)),
          extent:
              DocumentPosition(documentPath: NodePath.forNode("2"), nodePosition: const TextNodePosition(offset: 0)),
        );
        final upstreamSelection = DocumentSelection(
          base: DocumentPosition(documentPath: NodePath.forNode("2"), nodePosition: const TextNodePosition(offset: 0)),
          extent:
              DocumentPosition(documentPath: NodePath.forNode("1"), nodePosition: const TextNodePosition(offset: 0)),
        );
        final position = DocumentPosition(
          documentPath: NodePath.forNode("2"),
          nodePosition: const TextNodePosition(offset: 1),
        );

        expect(_testDoc.doesSelectionContainPosition(downstreamSelection, position), false);
        expect(_testDoc.doesSelectionContainPosition(upstreamSelection, position), false);
      });

      test("when the selection is across three nodes and the position is in the middle", () {
        final downstreamSelection = DocumentSelection(
          base: DocumentPosition(documentPath: NodePath.forNode("1"), nodePosition: const TextNodePosition(offset: 0)),
          extent:
              DocumentPosition(documentPath: NodePath.forNode("3"), nodePosition: const TextNodePosition(offset: 0)),
        );
        final upstreamSelection = DocumentSelection(
          base: DocumentPosition(documentPath: NodePath.forNode("3"), nodePosition: const TextNodePosition(offset: 0)),
          extent:
              DocumentPosition(documentPath: NodePath.forNode("1"), nodePosition: const TextNodePosition(offset: 0)),
        );
        final position = DocumentPosition(
          documentPath: NodePath.forNode("2"),
          nodePosition: const TextNodePosition(offset: 0),
        );

        expect(_testDoc.doesSelectionContainPosition(downstreamSelection, position), true);
        expect(_testDoc.doesSelectionContainPosition(upstreamSelection, position), true);
      });
    });
  });
}

final _testDoc = MutableDocument(
  nodes: [
    ParagraphNode(id: "1", text: AttributedText("Paragraph 1")),
    ParagraphNode(id: "2", text: AttributedText("Paragraph 2")),
    ParagraphNode(id: "3", text: AttributedText("Paragraph 3")),
  ],
);
