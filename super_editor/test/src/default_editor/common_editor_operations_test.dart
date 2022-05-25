import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import '../_document_test_tools.dart';

void main() {
  group("Common editor operations", () {
    group("deletion", () {
      test("from text node (inclusive) to text node (partial)", () {
        final document = MutableDocument(nodes: [
          ParagraphNode(
            id: "1",
            text: AttributedText(
              text: 'This is a blockquote!',
            ),
          ),
          ParagraphNode(
            id: "2",
            text: AttributedText(
                text:
                    'Cras vitae sodales nisi. Vivamus dignissim vel purus vel aliquet. Sed viverra diam vel nisi rhoncus pharetra. Donec gravida ut ligula euismod pharetra. Etiam sed urna scelerisque, efficitur mauris vel, semper arcu. Nullam sed vehicula sapien. Donec id tellus volutpat, eleifend nulla eget, rutrum mauris.'),
          ),
        ]);
        final editor = DocumentEditor(document: document);
        final composer = DocumentComposer(
          initialSelection: const DocumentSelection(
            base: DocumentPosition(
              nodeId: "1",
              nodePosition: TextNodePosition(offset: 0),
            ),
            extent: DocumentPosition(
              nodeId: "2",
              nodePosition: TextNodePosition(offset: 50),
            ),
          ),
        );
        final commonOps = CommonEditorOperations(
          editor: editor,
          composer: composer,
          documentLayoutResolver: () => FakeDocumentLayout(),
        );

        commonOps.deleteSelection();

        final doc = editor.document;
        expect(doc.nodes.length, 1);
        expect(doc.nodes.first.id, "2");
        expect(composer.selection!.extent.nodeId, "2");
        expect(composer.selection!.extent.nodePosition, const TextNodePosition(offset: 0));
      });

      test("from block node (inclusive) to text node (partial)", () {
        final document = MutableDocument(nodes: [
          HorizontalRuleNode(id: "1"),
          ParagraphNode(
            id: "2",
            text: AttributedText(
                text:
                    'Cras vitae sodales nisi. Vivamus dignissim vel purus vel aliquet. Sed viverra diam vel nisi rhoncus pharetra. Donec gravida ut ligula euismod pharetra. Etiam sed urna scelerisque, efficitur mauris vel, semper arcu. Nullam sed vehicula sapien. Donec id tellus volutpat, eleifend nulla eget, rutrum mauris.'),
          ),
        ]);
        final editor = DocumentEditor(document: document);
        final composer = DocumentComposer(
          initialSelection: const DocumentSelection(
            base: DocumentPosition(
              nodeId: "1",
              nodePosition: UpstreamDownstreamNodePosition.upstream(),
            ),
            extent: DocumentPosition(
              nodeId: "2",
              nodePosition: TextNodePosition(offset: 50),
            ),
          ),
        );
        final commonOps = CommonEditorOperations(
          editor: editor,
          composer: composer,
          documentLayoutResolver: () => FakeDocumentLayout(),
        );

        commonOps.deleteSelection();

        final doc = editor.document;
        expect(doc.nodes.length, 1);
        expect(doc.nodes.first.id, "2");
        expect(composer.selection!.extent.nodeId, "2");
        expect(composer.selection!.extent.nodePosition, const TextNodePosition(offset: 0));
      });

      test("from text node (partial) to block node (inclusive)", () {
        final document = MutableDocument(nodes: [
          ParagraphNode(
            id: "1",
            text: AttributedText(
                text:
                    'Cras vitae sodales nisi. Vivamus dignissim vel purus vel aliquet. Sed viverra diam vel nisi rhoncus pharetra. Donec gravida ut ligula euismod pharetra. Etiam sed urna scelerisque, efficitur mauris vel, semper arcu. Nullam sed vehicula sapien. Donec id tellus volutpat, eleifend nulla eget, rutrum mauris.'),
          ),
          HorizontalRuleNode(id: "2"),
        ]);
        final editor = DocumentEditor(document: document);
        final composer = DocumentComposer(
          initialSelection: const DocumentSelection(
            base: DocumentPosition(
              nodeId: "1",
              nodePosition: TextNodePosition(offset: 50),
            ),
            extent: DocumentPosition(
              nodeId: "2",
              nodePosition: UpstreamDownstreamNodePosition.downstream(),
            ),
          ),
        );
        final commonOps = CommonEditorOperations(
          editor: editor,
          composer: composer,
          documentLayoutResolver: () => FakeDocumentLayout(),
        );

        commonOps.deleteSelection();

        final doc = editor.document;
        expect(doc.nodes.length, 1);
        expect(doc.nodes.first.id, "1");
        expect(composer.selection!.extent.nodeId, "1");
        expect(composer.selection!.extent.nodePosition, const TextNodePosition(offset: 50));
      });

      test("from block node (inclusive) to block node (inclusive)", () {
        final document = MutableDocument(nodes: [
          HorizontalRuleNode(id: "1"),
          HorizontalRuleNode(id: "2"),
        ]);
        final editor = DocumentEditor(document: document);
        final composer = DocumentComposer(
          initialSelection: const DocumentSelection(
            base: DocumentPosition(
              nodeId: "1",
              nodePosition: UpstreamDownstreamNodePosition.upstream(),
            ),
            extent: DocumentPosition(
              nodeId: "2",
              nodePosition: UpstreamDownstreamNodePosition.downstream(),
            ),
          ),
        );
        final commonOps = CommonEditorOperations(
          editor: editor,
          composer: composer,
          documentLayoutResolver: () => FakeDocumentLayout(),
        );

        commonOps.deleteSelection();

        final doc = editor.document;
        expect(doc.nodes.length, 1);
        expect(doc.nodes.first, isA<ParagraphNode>());
        expect(doc.nodes.first.id, "1");
        expect(composer.selection!.extent.nodePosition, const TextNodePosition(offset: 0));
      });
    });
    group("pasting", () {
      testWidgets("automatically converts a URL in the pasted text to a link", (tester) async {
        // Note: We need to ensure initialized because we access the Clipboard.
        TestWidgetsFlutterBinding.ensureInitialized();

        final document = MutableDocument(nodes: [
          ParagraphNode(
            id: 'paragraph',
            text: AttributedText(
              text: 'This  a link',
            ),
          ),
        ]);
        final editor = DocumentEditor(document: document);

        // Place caret at "This | a link"
        final composer = DocumentComposer(
          initialSelection: const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: "paragraph",
              nodePosition: TextNodePosition(offset: 5),
            ),
          ),
        );
        final commonOps = CommonEditorOperations(
          editor: editor,
          composer: composer,
          documentLayoutResolver: () => FakeDocumentLayout(),
        );

        // The Clipboard requires a platform response, which doesn't exist
        // for widget tests. Pretend that we're the platform and handle
        // the incoming clipboard call.
        SystemChannels.platform.setMockMethodCallHandler((call) async {
          if (call.method == 'Clipboard.getData') {
            return {
              'text': 'text: https://flutter.dev is',
            };
          }
        });

        // Paste the block of text containing the link
        commonOps.paste();

        // We have to run these expectations pumping
        // so that the async paste operation has time to complete.
        await tester.pumpAndSettle();

        final textNode = editor.document.nodes.first as TextNode;

        expect(textNode.text.text, 'This text: https://flutter.dev is a link');
        // A [LinkAttribution] should be added at the url
        expect(
          textNode.text.spans.getAttributionSpansInRange(
            attributionFilter: (_) => true,
            start: 0,
            end: 40,
          ),
          {
            AttributionSpan(
              attribution: LinkAttribution(url: Uri.parse('https://flutter.dev')),
              start: 11,
              end: 29,
            )
          },
        );
      });

      testWidgets("does nothing to an existing link", (tester) async {
        // Adding [LinkAttribution] to a position that already has it
        // could cause spans mismatching, which potentially leads to errors.
        // This test prevents that regression

        // Note: We need to ensure initialized because we access the Clipboard.
        TestWidgetsFlutterBinding.ensureInitialized();

        final linkAttribution = LinkAttribution(url: Uri.parse('https://flutter.dev'));

        final document = MutableDocument(nodes: [
          ParagraphNode(
            id: 'paragraph',
            text: AttributedText(
              text: 'This text: https://flutter.dev is already a link',
              spans: AttributedSpans(
                attributions: [
                  SpanMarker(attribution: linkAttribution, offset: 11, markerType: SpanMarkerType.start),
                  SpanMarker(attribution: linkAttribution, offset: 30, markerType: SpanMarkerType.end),
                ],
              ),
            ),
          ),
        ]);
        final editor = DocumentEditor(document: document);

        // Place the caret within the link attributed span's range
        final composer = DocumentComposer(
          initialSelection: const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: "paragraph",
              nodePosition: TextNodePosition(offset: 27),
            ),
          ),
        );
        final commonOps = CommonEditorOperations(
          editor: editor,
          composer: composer,
          documentLayoutResolver: () => FakeDocumentLayout(),
        );

        // The Clipboard requires a platform response, which doesn't exist
        // for widget tests. Pretend that we're the platform and handle
        // the incoming clipboard call.
        SystemChannels.platform.setMockMethodCallHandler((call) async {
          if (call.method == 'Clipboard.getData') {
            return {
              'text': '[block] https://pub.dev [block]',
            };
          }
        });

        // Paste the block of text containing the link
        commonOps.paste();

        // We have to run these expectations after pumping
        // so that the async paste operation has time to complete.
        await tester.pumpAndSettle();

        final textNode = editor.document.nodes.first as TextNode;

        expect(textNode.text.text, 'This text: https://flutter.[block] https://pub.dev [block]dev is already a link');

        // The handler should only expand the link attribution's span and nothing more
        expect(
          textNode.text.spans.getAttributionSpansInRange(
            attributionFilter: (_) => true,
            start: 0,
            end: 79,
          ),
          {
            AttributionSpan(
              attribution: LinkAttribution(url: Uri.parse('https://flutter.dev')),
              start: 11,
              end: 30 + 31, // adding 31 as the length of the newly pasted text
            )
          },
        );
      });
    });
  });
}
