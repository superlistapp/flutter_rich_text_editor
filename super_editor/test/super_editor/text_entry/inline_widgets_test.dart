import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/src/test/super_editor_test/supereditor_inspector.dart';
import 'package:super_editor/src/test/super_editor_test/supereditor_robot.dart';
import 'package:super_editor/super_editor.dart';

import '../supereditor_test_tools.dart';

void main() {
  group("Super Editor > inline widgets >", () {
    testWidgetsOnArbitraryDesktop("can insert an inline widget in the middle of typing", (tester) async {
      final editor = await _pumpScaffold(tester);

      await tester.typeImeText("Hello ");
      editor.execute([
        const InsertInlinePlaceholderAtCaretRequest(_TestPlaceholder()),
      ]);
      await tester.typeImeText(" inline widgets");

      expect(
        SuperEditorInspector.findTextInComponent("1"),
        AttributedText(
          "Hello  inline widgets",
          null,
          {
            6: const _TestPlaceholder(),
          },
        ),
      );
    });

    testWidgetsOnArbitraryDesktop("can backspace delete an inline placeholder", (tester) async {
      final editor = await _pumpScaffold(tester);

      // Insert text with an inline placeholder.
      await tester.typeImeText("Hello ");
      editor.execute([
        const InsertInlinePlaceholderAtCaretRequest(_TestPlaceholder()),
      ]);
      await tester.pump();

      // Ensure we inserted the placeholder.
      expect(
        SuperEditorInspector.findTextInComponent("1"),
        AttributedText(
          "Hello ",
          null,
          {
            6: const _TestPlaceholder(),
          },
        ),
      );

      // Backspace to delete the placeholder.
      await tester.pressBackspace();

      // Ensure the inline placeholder was deleted.
      expect(
        SuperEditorInspector.findTextInComponent("1"),
        AttributedText(
          "Hello ",
          null,
          {},
        ),
      );
    });

    testWidgetsOnArbitraryDesktop("can select text and apply a style change without losing placeholder",
        (tester) async {
      final editor = await _pumpScaffold(tester);

      // Insert text with an inline placeholder in the middle.
      await tester.typeImeText("Hello ");
      editor.execute([
        const InsertInlinePlaceholderAtCaretRequest(_TestPlaceholder()),
      ]);
      await tester.typeImeText(" inline widgets");

      // Select text and also the inline placeholder.
      // TODO: Create tester extension to drag and select text on desktop
      editor.execute([
        const ChangeSelectionRequest(
          DocumentSelection(
            base: DocumentPosition(
              nodeId: "1",
              nodePosition: TextNodePosition(offset: 6),
            ),
            extent: DocumentPosition(
              nodeId: "1",
              nodePosition: TextNodePosition(offset: 14),
            ),
          ),
          SelectionChangeType.expandSelection,
          SelectionReason.userInteraction,
        ),
      ]);
      await tester.pump();

      // Apply bold to the text.
      await tester.pressCmdB();

      // Ensure the inline placeholder is still there.
      expect(
        SuperEditorInspector.findTextInComponent("1"),
        AttributedText(
          "Hello  inline widgets",
          AttributedSpans(
            attributions: const [
              SpanMarker(attribution: boldAttribution, offset: 6, markerType: SpanMarkerType.start),
              SpanMarker(attribution: boldAttribution, offset: 13, markerType: SpanMarkerType.end),
            ],
          ),
          {
            6: const _TestPlaceholder(),
          },
        ),
      );

      // Un-apply bold to the text.
      await tester.pressCmdB();

      // Ensure the inline placeholder is still there.
      expect(
        SuperEditorInspector.findTextInComponent("1"),
        AttributedText(
          "Hello  inline widgets",
          null,
          {
            6: const _TestPlaceholder(),
          },
        ),
      );
    });

    testWidgetsOnArbitraryDesktop("can insert an inline widget with attributions in an empty paragraph",
        (tester) async {
      final editor = await _pumpScaffold(tester);

      // Insert an empty text containing a placeholder with an attribution around it.
      editor.execute([
        InsertStyledTextAtCaretRequest(
          AttributedText(
              '',
              AttributedSpans(
                attributions: [
                  const SpanMarker(
                    attribution: _emojiAttribution,
                    offset: 0,
                    markerType: SpanMarkerType.start,
                  ),
                  const SpanMarker(
                    attribution: _emojiAttribution,
                    offset: 0,
                    markerType: SpanMarkerType.end,
                  ),
                ],
              ),
              {
                0: const _TestPlaceholder(),
              }),
        ),
      ]);
      await tester.pump();

      // Ensure we can type after the inline placeholder was added.
      await tester.typeImeText('hello');

      // Ensure the inline widget was kept, the text was inserted, and the attribution
      // was not applied to the inserted characters.
      expect(
        SuperEditorInspector.findTextInComponent('1'),
        AttributedText(
          'hello',
          AttributedSpans(
            attributions: const [
              SpanMarker(attribution: _emojiAttribution, offset: 0, markerType: SpanMarkerType.start),
              SpanMarker(attribution: _emojiAttribution, offset: 0, markerType: SpanMarkerType.end),
            ],
          ),
          {
            0: const _TestPlaceholder(),
          },
        ),
      );
    });
  });
}

Future<Editor> _pumpScaffold(WidgetTester tester) async {
  final context = await tester
      .createDocument()
      .withSingleEmptyParagraph()
      .withInputSource(TextInputSource.ime)
      .useStylesheet(defaultStylesheet.copyWith(
        inlineWidgetBuilders: [_buildInlineTestWidget],
      ))
      .autoFocus(true)
      .pump();

  return context.editor;
}

Widget? _buildInlineTestWidget(BuildContext context, TextStyle style, Object placeholder) {
  if (placeholder is! _TestPlaceholder) {
    return null;
  }

  return Container(
    width: 16,
    height: 16,
    color: Colors.black,
  );
}

class _TestPlaceholder {
  const _TestPlaceholder();
}

const _emojiAttribution = NamedAttribution('emoji');
