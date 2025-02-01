import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  group('Document selection extensions', () {
    group('getAllAttributions', () {
      test('returns empty list when the selection range does not contain any attributions', () {
        final document = MutableDocument(
          nodes: [
            ParagraphNode(
              id: '1',
              text: AttributedText('Text without attributions'),
            ),
          ],
        );

        // Create a selection for the whole text.
        final selection = TextNode.selectionWithin(["1"], 0, 25);

        expect(document.getAllAttributions(selection), isEmpty);
      });

      test('returns attributions that span throughout the entirety of the text', () {
        // Create a paragraph with the following attributions:
        // - bold: applied throughout the entire paragraph.
        // - underline: applied to the word "with",
        // - italics: applied to the "th".
        final document = MutableDocument(
          nodes: [
            ParagraphNode(
              id: '1',
              text: AttributedText(
                'Text with attributions',
                AttributedSpans(
                  attributions: const [
                    SpanMarker(attribution: boldAttribution, offset: 0, markerType: SpanMarkerType.start),
                    SpanMarker(attribution: underlineAttribution, offset: 5, markerType: SpanMarkerType.start),
                    SpanMarker(attribution: italicsAttribution, offset: 7, markerType: SpanMarkerType.start),
                    SpanMarker(attribution: italicsAttribution, offset: 8, markerType: SpanMarkerType.end),
                    SpanMarker(attribution: underlineAttribution, offset: 8, markerType: SpanMarkerType.end),
                    SpanMarker(attribution: boldAttribution, offset: 21, markerType: SpanMarkerType.end),
                  ],
                ),
              ),
            ),
          ],
        );

        // Create a selection for the word "with".
        final selection = TextNode.selectionWithin(["1"], 5, 9);

        expect(document.getAllAttributions(selection), {boldAttribution, underlineAttribution});
      });
    });

    group('getAttributionsByType', () {
      test('returns empty set when the selection range does not contain any attributions', () {
        final document = MutableDocument(
          nodes: [
            ParagraphNode(
              id: '1',
              text: AttributedText('Text without attributions'),
            ),
          ],
        );

        // Create a selection for the whole text.
        final selection = TextNode.selectionWithin(["1"], 0, 25);

        expect(document.getAttributionsByType<FontSizeAttribution>(selection), isEmpty);
      });

      test('does not return attributions that dont apply to the entire range', () {
        // Create a paragraph with a font size applied to "wit".
        final document = MutableDocument(
          nodes: [
            ParagraphNode(
              id: '1',
              text: AttributedText(
                'Text with attributions',
                AttributedSpans(
                  attributions: [
                    const SpanMarker(attribution: FontSizeAttribution(14), offset: 5, markerType: SpanMarkerType.start),
                    const SpanMarker(attribution: FontSizeAttribution(14), offset: 7, markerType: SpanMarkerType.end),
                  ],
                ),
              ),
            ),
          ],
        );

        // Create a selection for the word "with";
        final selection = TextNode.selectionWithin(["1"], 5, 9);

        expect(document.getAttributionsByType<FontSizeAttribution>(selection), isEmpty);
      });

      test('does not return attributions that dont apply to the entire range', () {
        // Create a paragraph with a font size applied to "wit".
        final document = MutableDocument(
          nodes: [
            ParagraphNode(
              id: '1',
              text: AttributedText(
                'Text with attributions',
                AttributedSpans(
                  attributions: [
                    const SpanMarker(attribution: FontSizeAttribution(14), offset: 5, markerType: SpanMarkerType.start),
                    const SpanMarker(attribution: FontSizeAttribution(14), offset: 7, markerType: SpanMarkerType.end),
                  ],
                ),
              ),
            ),
          ],
        );

        // Create a selection for the word "with";
        final selection = TextNode.selectionWithin(["1"], 5, 9);

        expect(document.getAttributionsByType<FontSizeAttribution>(selection), isEmpty);
      });

      test('return attributions that apply to the entire range', () {
        // Create a paragraph with a font size applied to "with".
        final document = MutableDocument(
          nodes: [
            ParagraphNode(
              id: '1',
              text: AttributedText(
                'Text with attributions',
                AttributedSpans(
                  attributions: [
                    const SpanMarker(attribution: FontSizeAttribution(14), offset: 5, markerType: SpanMarkerType.start),
                    const SpanMarker(attribution: FontSizeAttribution(14), offset: 8, markerType: SpanMarkerType.end),
                  ],
                ),
              ),
            ),
          ],
        );

        // Create a selection for the word "with";
        final selection = TextNode.selectionWithin(["1"], 5, 9);

        expect(document.getAttributionsByType<FontSizeAttribution>(selection), {const FontSizeAttribution(14)});
      });
    });
  });
}
