import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_text_layout/super_text_layout.dart';

import 'super_textfield_inspector.dart';

void main() {
  group('SuperTextField', () {
    testWidgetsOnAllPlatforms('single-line jumps scroll position horizontally as the user types', (tester) async {
      final controller = AttributedTextEditingController(
        text: AttributedText("ABCDEFG"),
      );

      // Pump the widget tree with a SuperTextField with a maxWidth smaller
      // than the text width
      await _pumpTestApp(
        tester,
        textController: controller,
        minLines: 1,
        maxLines: 1,
        maxWidth: 50,
      );

      // Move selection to the end of the text
      // TODO: change to simulate user input when IME simulation is available
      controller.selection = const TextSelection.collapsed(offset: 7);
      await tester.pumpAndSettle();

      // Position at the end of the viewport
      final viewportRight = tester.getBottomRight(find.byType(SuperTextField)).dx;

      // Position at the end of the text
      final textRight = tester.getBottomRight(find.byType(SuperText)).dx;

      // Ensure the text field scrolled its content horizontally
      expect(textRight, lessThanOrEqualTo(viewportRight));
    });

    testWidgetsOnAllPlatforms('multi-line jumps scroll position vertically as the user types', (tester) async {
      final controller = AttributedTextEditingController(
        text: AttributedText("A\nB\nC\nD"),
      );

      // Pump the widget tree with a SuperTextField with a maxHeight smaller
      // than the text heght
      await _pumpTestApp(
        tester,
        textController: controller,
        minLines: 1,
        maxLines: 2,
        maxHeight: 20,
      );

      // Move selection to the end of the text
      // TODO: change to simulate user input when IME simulation is available
      controller.selection = const TextSelection.collapsed(offset: 7);
      await tester.pumpAndSettle();

      // Position at the end of the viewport
      final viewportBottom = tester.getBottomRight(find.byType(SuperTextField)).dy;

      // Position at the end of the text
      final textBottom = tester.getBottomRight(find.byType(SuperText)).dy;

      // Ensure the text field scrolled its content vertically
      expect(textBottom, lessThanOrEqualTo(viewportBottom));
    });

    testWidgetsOnAllPlatforms(
        "multi-line jumps scroll position vertically when selection extent moves above or below the visible viewport area",
        (tester) async {
      final controller = AttributedTextEditingController(
        text: AttributedText("First line\nSecond Line\nThird Line\nFourth Line"),
      );

      // Pump the widget tree with a SuperTextField which is two lines tall.
      await _pumpTestApp(
        tester,
        textController: controller,
        minLines: 1,
        maxLines: 2,
        maxHeight: 40,
      );

      // Move selection to the end of the text.
      // This will scroll the text field to the end.
      controller.selection = const TextSelection.collapsed(offset: 45);
      await tester.pumpAndSettle();

      // Ensure the text field has scrolled.
      expect(
        SuperTextFieldInspector.findScrollOffset(),
        greaterThan(0.0),
      );

      // Place the caret at the beginning of the text.
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pumpAndSettle();

      // Ensure the text field scrolled to the top.
      expect(
        SuperTextFieldInspector.findScrollOffset(),
        0.0,
      );
    });

    testWidgetsOnAllPlatforms("multi-line doesn't jump scroll position vertically when selection extent is visible",
        (tester) async {
      final controller = AttributedTextEditingController(
        text: AttributedText("First line\nSecond Line\nThird Line\nFourth Line"),
      );

      // Pump the widget tree with a SuperTextField which is two lines tall.
      await _pumpTestApp(
        tester,
        textController: controller,
        minLines: 1,
        maxLines: 2,
        maxHeight: 40,
      );

      // Move selection to the end of the text.
      // This will scroll the text field to the end.
      controller.selection = const TextSelection.collapsed(offset: 45);
      await tester.pumpAndSettle();

      final scrollOffsetBefore = SuperTextFieldInspector.findScrollOffset();

      // Place the caret at "Third| Line".
      // As we have room for two lines, this line is already visible,
      // and thus shouldn't cause the text field to scroll.
      controller.selection = const TextSelection.collapsed(offset: 28);
      await tester.pumpAndSettle();

      // Ensure the content didn't scroll.
      expect(
        SuperTextFieldInspector.findScrollOffset(),
        scrollOffsetBefore,
      );
    });

    testWidgetsOnDesktop("doesn't scroll vertically when maxLines is null", (tester) async {
      // We use some padding because it affects the viewport height calculation.
      const verticalPadding = 6.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 300),
              child: SuperDesktopTextField(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: verticalPadding),
                minLines: 1,
                maxLines: null,
                textController: AttributedTextEditingController(
                  text: AttributedText("SuperTextField"),
                ),
                textStyleBuilder: (_) => const TextStyle(
                  fontSize: 14,
                  height: 1,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // In the running app, the estimated line height and actual line height differ.
      // This test ensures that we account for that. Ideally, this test would check that the scrollview doesn't scroll.
      // However, in test suites, the estimated and actual line heights are always identical.
      // Therefore, this test ensures that we add up the appropriate dimensions,
      // rather than verify the scrollview's max scroll extent.

      final viewportHeight = tester.getRect(find.byType(SuperTextFieldScrollview)).height;

      final layoutState =
          (find.byType(SuperDesktopTextField).evaluate().single as StatefulElement).state as SuperDesktopTextFieldState;
      final contentHeight = layoutState.textLayout.getLineHeightAtPosition(const TextPosition(offset: 0));

      // Vertical padding is added to both top and bottom
      final totalHeight = contentHeight + (verticalPadding * 2);

      // Ensure the viewport is big enough so the text doesn't scroll vertically
      expect(viewportHeight, greaterThanOrEqualTo(totalHeight));
    });

    testWidgetsOnDesktop("stops momentum on tap down with trackpad and doesn't place the caret", (tester) async {
      // Generate a long text to have enough scrollable content.
      final text = [
        for (int i = 1; i <= 1000; i++) //
          'Line $i',
      ];

      final controller = AttributedTextEditingController(
        text: AttributedText(text.join('\n')),
      );

      // Pump the widget tree with a SuperTextField with a maxHeight smaller
      // than the text height.
      await _pumpTestApp(
        tester,
        textController: controller,
        minLines: 1,
        maxLines: 2,
        maxHeight: 20,
      );

      // Ensure the textfield initially has no selection.
      expect(SuperTextFieldInspector.findSelection(), TextRange.empty);

      // Fling scroll the textfield with the trackpad.
      final scrollGesture = await tester.startGesture(
        tester.getCenter(find.byType(SuperTextField)),
        kind: PointerDeviceKind.trackpad,
      );
      await scrollGesture.moveBy(const Offset(0, -1000));
      await scrollGesture.up();

      // Pump a few frames of momentum.
      for (int i = 0; i < 25; i += 1) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final scrollOffsetInMiddleOfMomentum = SuperTextFieldInspector.findScrollOffset();

      // Ensure the textfield scrolled.
      expect(scrollOffsetInMiddleOfMomentum, greaterThan(0.0));

      // Tap down to stop the momentum.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SuperTextField)),
        kind: PointerDeviceKind.trackpad,
      );

      // Let any remaining momentum run (there shouldn't be any).
      await tester.pumpAndSettle();

      // Ensure that the momentum stopped exactly where we tapped.
      expect(scrollOffsetInMiddleOfMomentum, SuperTextFieldInspector.findScrollOffset());

      // Release the pointer.
      await gesture.up();
      await tester.pump();

      // Ensure the selection didn't change.
      expect(SuperTextFieldInspector.findSelection(), TextRange.empty);
    });

    testWidgetsOnMobile("multi-line is vertically scrollable when text spans more lines than maxLines", (tester) async {
      const initialText = "The first line of text in the field\n"
          "The second line of text in the field\n"
          "The third line of text in the field";
      final controller = AttributedTextEditingController(
        text: AttributedText(initialText),
      );

      // Pump the widget tree with a SuperTextField with a maxHeight of 2 lines
      // of text, which should overflow considering there are 3 lines of text.
      await _pumpTestApp(
        tester,
        textController: controller,
        minLines: 1,
        maxLines: 2,
        maxHeight: 40,
      );

      // Ensure the text field has not yet scrolled.
      var textTop = tester.getTopRight(find.byType(SuperTextField)).dy;
      var viewportTop = tester.getTopRight(find.byType(SuperText)).dy;
      expect(textTop, moreOrLessEquals(viewportTop));
      expect(SuperTextFieldInspector.findScrollOffset(), 0.0);

      // Scroll down to reveal the last line of text.
      await tester.drag(find.byType(SuperTextField), const Offset(0, -1000.0));
      await tester.pumpAndSettle();

      // Ensure the text field has scrolled to the bottom.
      var textBottom = tester.getBottomRight(find.byType(SuperTextField)).dy;
      var viewportBottom = tester.getBottomRight(find.byType(SuperText)).dy;
      expect(textBottom, moreOrLessEquals(viewportBottom));
      // Since the scrollable content is taller than the viewport, and since
      // the bottom of the text field is aligned with the bottom of the
      // viewport, the scroll offset should be greater than 0.
      expect(SuperTextFieldInspector.findScrollOffset(), greaterThan(0.0));

      // Scroll back up to the top of the text field.
      await tester.drag(find.byType(SuperTextField), const Offset(0, 1000.0));
      await tester.pumpAndSettle();

      // Ensure the text field has scrolled back to the top.
      textTop = tester.getTopRight(find.byType(SuperTextField)).dy;
      viewportTop = tester.getTopRight(find.byType(SuperText)).dy;
      expect(textTop, moreOrLessEquals(viewportTop));
      expect(SuperTextFieldInspector.findScrollOffset(), 0.0);
    });

    testWidgetsOnDesktop("multi-line is vertically scrollable when text spans more lines than maxLines",
        (tester) async {
      const initialText = "The first line of text in the field\n"
          "The second line of text in the field\n"
          "The third line of text in the field";
      final controller = AttributedTextEditingController(
        text: AttributedText(initialText),
      );

      // Pump the widget tree with a SuperTextField with a maxHeight of 2 lines
      // of text, which should overflow considering there are 3 lines of text.
      await _pumpTestApp(
        tester,
        textController: controller,
        minLines: 1,
        maxLines: 2,
        maxHeight: 40,
      );

      // Ensure the text field has not yet scrolled.
      var textTop = tester.getTopRight(find.byType(SuperTextField)).dy;
      var viewportTop = tester.getTopRight(find.byType(SuperText)).dy;
      expect(textTop, moreOrLessEquals(viewportTop));
      expect(SuperTextFieldInspector.findScrollOffset(), 0.0);

      // Scroll down to reveal the last line of text.
      await tester.drag(
        find.byType(SuperTextField),
        const Offset(0, -1000.0),
        kind: PointerDeviceKind.trackpad,
      );
      await tester.pumpAndSettle();

      // Ensure the text field has scrolled to the bottom.
      var textBottom = tester.getBottomRight(find.byType(SuperTextField)).dy;
      var viewportBottom = tester.getBottomRight(find.byType(SuperText)).dy;
      expect(textBottom, moreOrLessEquals(viewportBottom));
      // Issue is not present on desktop, further leading me to think that the
      // issue is somehow related to that comment about the scroll offsets
      // being out of sync in the mobile scroll view.
      expect(SuperTextFieldInspector.findScrollOffset(), greaterThan(0.0));

      // Scroll back up to the top of the text field.
      await tester.drag(
        find.byType(SuperTextField),
        const Offset(0, 1000.0),
        kind: PointerDeviceKind.trackpad,
      );
      await tester.pumpAndSettle();

      // Ensure the text field has scrolled back to the top.
      textTop = tester.getTopRight(find.byType(SuperTextField)).dy;
      viewportTop = tester.getTopRight(find.byType(SuperText)).dy;
      expect(textTop, moreOrLessEquals(viewportTop));
      expect(SuperTextFieldInspector.findScrollOffset(), 0.0);
    });
  });
}

Future<void> _pumpTestApp(
  WidgetTester tester, {
  required AttributedTextEditingController textController,
  required int minLines,
  required int maxLines,
  double? maxWidth,
  double? maxHeight,
  EdgeInsets? padding,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth ?? double.infinity,
            maxHeight: maxHeight ?? double.infinity,
          ),
          child: SuperTextField(
            textController: textController,
            lineHeight: 20,
            textStyleBuilder: (_) => const TextStyle(fontSize: 20, color: Colors.black),
            minLines: minLines,
            maxLines: maxLines,
            padding: padding,
          ),
        ),
      ),
    ),
  );

  // The first frame might have a zero viewport height. Pump a second frame to account for the final viewport size.
  await tester.pump();
}
