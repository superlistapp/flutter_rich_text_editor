import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';

import '../supereditor_test_tools.dart';

void main() {
  group("Common editor operations", () {
    group("deletion", () {
      test("from text node (inclusive) to text node (partial)", () {
        final document = MutableDocument(nodes: [
          ParagraphNode(
            id: "1",
            text: AttributedText('This is a blockquote!'),
          ),
          ParagraphNode(
            id: "2",
            text: AttributedText(
              'Cras vitae sodales nisi. Vivamus dignissim vel purus vel aliquet. Sed viverra diam vel nisi rhoncus pharetra. Donec gravida ut ligula euismod pharetra. Etiam sed urna scelerisque, efficitur mauris vel, semper arcu. Nullam sed vehicula sapien. Donec id tellus volutpat, eleifend nulla eget, rutrum mauris.',
            ),
          ),
        ]);
        final composer = MutableDocumentComposer(
          initialSelection: DocumentSelection(
            base: DocumentPosition(
              documentPath: NodePath.forNode("1"),
              nodePosition: const TextNodePosition(offset: 0),
            ),
            extent: DocumentPosition(
              documentPath: NodePath.forNode("2"),
              nodePosition: const TextNodePosition(offset: 50),
            ),
          ),
        );
        final editor = createDefaultDocumentEditor(document: document, composer: composer);
        final commonOps = CommonEditorOperations(
          editor: editor,
          document: document,
          composer: composer,
          documentLayoutResolver: () => FakeDocumentLayout(),
        );

        commonOps.deleteSelection(TextAffinity.downstream);

        expect(document.nodeCount, 1);
        expect(document.first.id, "2");
        expect(composer.selection!.extent.nodeId, "2");
        expect(composer.selection!.extent.nodePosition, const TextNodePosition(offset: 0));
      });

      test("from block node (inclusive) to text node (partial)", () {
        final document = MutableDocument(nodes: [
          HorizontalRuleNode(id: "1"),
          ParagraphNode(
            id: "2",
            text: AttributedText(
              'Cras vitae sodales nisi. Vivamus dignissim vel purus vel aliquet. Sed viverra diam vel nisi rhoncus pharetra. Donec gravida ut ligula euismod pharetra. Etiam sed urna scelerisque, efficitur mauris vel, semper arcu. Nullam sed vehicula sapien. Donec id tellus volutpat, eleifend nulla eget, rutrum mauris.',
            ),
          ),
        ]);
        final composer = MutableDocumentComposer(
          initialSelection: DocumentSelection(
            base: DocumentPosition(
              documentPath: NodePath.forNode("1"),
              nodePosition: const UpstreamDownstreamNodePosition.upstream(),
            ),
            extent: DocumentPosition(
              documentPath: NodePath.forNode("2"),
              nodePosition: const TextNodePosition(offset: 50),
            ),
          ),
        );
        final editor = createDefaultDocumentEditor(document: document, composer: composer);
        final commonOps = CommonEditorOperations(
          editor: editor,
          document: document,
          composer: composer,
          documentLayoutResolver: () => FakeDocumentLayout(),
        );

        commonOps.deleteSelection(TextAffinity.downstream);

        expect(document.nodeCount, 1);
        expect(document.first.id, "2");
        expect(composer.selection!.extent.nodeId, "2");
        expect(composer.selection!.extent.nodePosition, const TextNodePosition(offset: 0));
      });

      test("from text node (partial) to block node (inclusive)", () {
        final document = MutableDocument(nodes: [
          ParagraphNode(
            id: "1",
            text: AttributedText(
              'Cras vitae sodales nisi. Vivamus dignissim vel purus vel aliquet. Sed viverra diam vel nisi rhoncus pharetra. Donec gravida ut ligula euismod pharetra. Etiam sed urna scelerisque, efficitur mauris vel, semper arcu. Nullam sed vehicula sapien. Donec id tellus volutpat, eleifend nulla eget, rutrum mauris.',
            ),
          ),
          HorizontalRuleNode(id: "2"),
        ]);
        final composer = MutableDocumentComposer(
          initialSelection: DocumentSelection(
            base: DocumentPosition(
              documentPath: NodePath.forNode("1"),
              nodePosition: const TextNodePosition(offset: 50),
            ),
            extent: DocumentPosition(
              documentPath: NodePath.forNode("2"),
              nodePosition: const UpstreamDownstreamNodePosition.downstream(),
            ),
          ),
        );
        final editor = createDefaultDocumentEditor(document: document, composer: composer);
        final commonOps = CommonEditorOperations(
          editor: editor,
          document: document,
          composer: composer,
          documentLayoutResolver: () => FakeDocumentLayout(),
        );

        commonOps.deleteSelection(TextAffinity.downstream);

        expect(document.nodeCount, 1);
        expect(document.first.id, "1");
        expect(composer.selection!.extent.nodeId, "1");
        expect(composer.selection!.extent.nodePosition, const TextNodePosition(offset: 50));
      });

      test("from block node (inclusive) to block node (inclusive)", () {
        final document = MutableDocument(nodes: [
          HorizontalRuleNode(id: "1"),
          HorizontalRuleNode(id: "2"),
        ]);
        final composer = MutableDocumentComposer(
          initialSelection: DocumentSelection(
            base: DocumentPosition(
              documentPath: NodePath.forNode("1"),
              nodePosition: const UpstreamDownstreamNodePosition.upstream(),
            ),
            extent: DocumentPosition(
              documentPath: NodePath.forNode("2"),
              nodePosition: const UpstreamDownstreamNodePosition.downstream(),
            ),
          ),
        );
        final editor = createDefaultDocumentEditor(document: document, composer: composer);
        final commonOps = CommonEditorOperations(
          editor: editor,
          document: document,
          composer: composer,
          documentLayoutResolver: () => FakeDocumentLayout(),
        );

        commonOps.deleteSelection(TextAffinity.downstream);

        expect(document.nodeCount, 1);
        expect(document.first, isA<ParagraphNode>());
        expect(document.first.id, "1");
        expect(composer.selection!.extent.nodePosition, const TextNodePosition(offset: 0));
      });
    });

    group('pasting', () {
      testWidgetsOnMac('splits a link in two when pasting in the middle of a link', (tester) async {
        tester
          ..simulateClipboard()
          ..setSimulatedClipboardContent("Some text");

        // Configure and render a document.
        await tester //
            .createDocument()
            .withCustomContent(_singleParagraphWithLinkDoc())
            .forDesktop()
            .pump();

        // Tap to place the caret in the first paragraph.
        await tester.placeCaretInParagraph("1", 11);
        // Simulate the user pasting content from clipboard
        await tester.pressCmdV();

        // Ensure that the link is split
        expect(
          SuperEditorInspector.findDocument(),
          equalsMarkdown('[https://goo](https://google.com)Some text[gle.com](https://google.com)'),
        );
      });
    });

    group('getDocumentPositionAfterExpandedDeletion', () {
      test('returns null for collapsed selection', () {
        final node = HorizontalRuleNode(
          id: "1",
        );

        expect(
          CommonEditorOperations.getDocumentPositionAfterExpandedDeletion(
            document: MutableDocument(nodes: [
              node,
            ]),
            selection: BlockNode.caretAtEdge([node.id], node.endPosition.affinity),
          ),
          isNull,
        );
      });
    });
  });
}

MutableDocument _singleParagraphWithLinkDoc() {
  return MutableDocument(
    nodes: [
      ParagraphNode(
        id: "1",
        text: AttributedText(
          "https://google.com",
          AttributedSpans(
            attributions: [
              SpanMarker(
                attribution: LinkAttribution.fromUri(Uri.parse('https://google.com')),
                offset: 0,
                markerType: SpanMarkerType.start,
              ),
              SpanMarker(
                attribution: LinkAttribution.fromUri(Uri.parse('https://google.com')),
                offset: 17,
                markerType: SpanMarkerType.end,
              ),
            ],
          ),
        ),
      )
    ],
  );
}
