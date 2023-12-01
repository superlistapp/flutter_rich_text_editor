import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_text_layout/super_text_layout.dart';

void main() {
  group("SuperTextField", () {
    group("applies color attributions", () {
      testWidgetsOnAllPlatforms("to full text", (tester) async {
        await _pumpTestApp(
          tester,
          text: AttributedText(
            'abcdefghij',
            AttributedSpans(
              attributions: [
                const SpanMarker(
                  attribution: ColorAttribution(Colors.orange),
                  offset: 0,
                  markerType: SpanMarkerType.start,
                ),
                const SpanMarker(
                  attribution: ColorAttribution(Colors.orange),
                  offset: 9,
                  markerType: SpanMarkerType.end,
                ),
              ],
            ),
          ),
        );

        final superText = tester.widget<SuperText>(find.byType(SuperText));

        // Ensure the text is colored orange.
        expect(
          superText.richText.style!.color,
          Colors.orange,
        );
      });

      testWidgetsOnAllPlatforms("to partial text", (tester) async {
        await _pumpTestApp(
          tester,
          text: AttributedText(
            'abcdefghij',
            AttributedSpans(
              attributions: [
                const SpanMarker(
                  attribution: ColorAttribution(Colors.orange),
                  offset: 5,
                  markerType: SpanMarkerType.start,
                ),
                const SpanMarker(
                  attribution: ColorAttribution(Colors.orange),
                  offset: 9,
                  markerType: SpanMarkerType.end,
                ),
              ],
            ),
          ),
        );

        final superText = tester.widget<SuperText>(find.byType(SuperText));

        // Ensure the first span is colored black.
        expect(
          superText.richText.getSpanForPosition(const TextPosition(offset: 0))!.style!.color,
          Colors.black,
        );

        // Ensure the second span is colored orange.
        expect(
          superText.richText.getSpanForPosition(const TextPosition(offset: 5))!.style!.color,
          Colors.orange,
        );
      });
    });
  });
}

/// Pumps a [SuperTextField] with the given attributed [text].
Future<void> _pumpTestApp(
  WidgetTester tester, {
  required AttributedText text,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SuperTextField(
          textController: AttributedTextEditingController(
            text: text,
          ),
        ),
      ),
    ),
  );

  // A SuperTextField configured with maxLines can't render in the first frame.
  // Ask another frame, so the text field can be found by the finder.
  await tester.pump();
}
