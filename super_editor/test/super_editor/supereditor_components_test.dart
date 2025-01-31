import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';

import 'supereditor_test_tools.dart';
import 'test_documents.dart';

void main() {
  group("SuperEditor component", () {
    testWidgetsOnMac("HintTextComponent places caret on tap", (tester) async {
      // Based on bug #726
      await tester //
          .createDocument()
          .withSingleEmptyParagraph()
          .withAddedComponents([const HintTextComponentBuilder()])
          .autoFocus(false)
          .pump();

      // Tap on the hint text component to place the caret.
      await tester.placeCaretInParagraph("1", 0);

      // Ensure that the document now shows the caret within the hint text component.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "1",
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
    });

    group('ImageComponent', () {
      testWidgetsOnArbitraryDesktop('scrolls on mouse wheel', (tester) async {
        final controller = ScrollController();

        await _pumpImageTestApp(tester, scrollController: controller);

        // Ensure the document started without any scrolling.
        expect(controller.offset, 0.0);

        final pointer = TestPointer(1, PointerDeviceKind.mouse);

        // Hover the image.
        pointer.hover(SuperEditorInspector.findComponentOffset('img-node', Alignment.center));
        await tester.pump();

        // Simulate scrolling with mouse wheel.
        await tester.sendEventToBinding(pointer.scroll(const Offset(0.0, 50.0)));
        await tester.pumpAndSettle();

        // Ensure the document scrolled down.
        expect(controller.offset, greaterThan(0.0));
      });

      testWidgetsOnArbitraryDesktop('has basic mouse cursor', (tester) async {
        await _pumpImageTestApp(tester);

        // Start a gesture outside the image bounds. (The image is 100x100)
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: const Offset(0, 110));
        addTearDown(gesture.removePointer);
        await tester.pump();

        // Ensure the cursor type is 'text' when not hovering the image.
        expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.text);

        // Hover the image.
        await gesture.moveTo(SuperEditorInspector.findComponentOffset('img-node', Alignment.center));
        await tester.pump();

        // Ensure the cursor type is 'basic' when hovering the image.
        expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.basic);
      });
    });

    testWidgetsOnArbitraryDesktop('does not crash when if finds an unkown node type', (tester) async {
      // Pump an editor with a node that has no corresponding component builder.
      await tester //
          .createDocument()
          .withCustomContent(
            MutableDocument(
              nodes: [_UnknownNode(id: '1')],
            ),
          )
          .pump();

      // Reaching this point means the editor did not crash because of the
      // unkown node.
    });
  });
}

class HintTextComponentBuilder implements ComponentBuilder {
  const HintTextComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
    List<ComponentBuilder> componentBuilders,
  ) {
    // This component builder can work with the standard paragraph view model.
    // We'll defer to the standard paragraph component builder to create it.
    return null;
  }

  @override
  Widget? createComponent(
      SingleColumnDocumentComponentContext componentContext, SingleColumnLayoutComponentViewModel componentViewModel) {
    if (componentViewModel is! ParagraphComponentViewModel) {
      return null;
    }

    final textSelection = componentViewModel.selection;

    return TextWithHintComponent(
      key: componentContext.componentKey,
      text: componentViewModel.text,
      textStyleBuilder: defaultStyleBuilder,
      metadata: componentViewModel.blockType != null
          ? {
              'blockType': componentViewModel.blockType,
            }
          : {},
      // This is the text displayed as a hint.
      hintText: AttributedText(
        'this is hint text...',
        AttributedSpans(
          attributions: [
            const SpanMarker(attribution: italicsAttribution, offset: 12, markerType: SpanMarkerType.start),
            const SpanMarker(attribution: italicsAttribution, offset: 15, markerType: SpanMarkerType.end),
          ],
        ),
      ),
      // This is the function that selects styles for the hint text.
      hintStyleBuilder: (Set<Attribution> attributions) => defaultStyleBuilder(attributions).copyWith(
        color: const Color(0xFFDDDDDD),
      ),
      textSelection: textSelection,
      selectionColor: componentViewModel.selectionColor,
      underlines: componentViewModel.createUnderlines(),
    );
  }
}

/// Pump a SuperEditor containing an image which will render as an 100x100 box
/// and content big enough to cause the document to be scrollable.
Future<void> _pumpImageTestApp(
  WidgetTester tester, {
  ScrollController? scrollController,
}) async {
  await tester
      .createDocument()
      .withCustomContent(
        MutableDocument(
          nodes: [
            ImageNode(
              id: "img-node",
              imageUrl: 'https://this.is.a.fake.image',
              metadata: const SingleColumnLayoutComponentStyles(
                width: double.infinity,
              ).toMetadata(),
            ),
            ...longTextDoc(),
          ],
        ),
      )
      .withAddedComponents([const _FakeImageComponentBuilder()])
      .withEditorSize(const Size(300, 300))
      .withScrollController(scrollController)
      .pump();
}

/// A [ComponentBuilder] which builds an [ImageComponent] that always renders
/// images as an 100x100 [SizedBox].
class _FakeImageComponentBuilder implements ComponentBuilder {
  const _FakeImageComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
    List<ComponentBuilder> componentBuilders,
  ) {
    return null;
  }

  @override
  Widget? createComponent(
      SingleColumnDocumentComponentContext componentContext, SingleColumnLayoutComponentViewModel componentViewModel) {
    if (componentViewModel is! ImageComponentViewModel) {
      return null;
    }

    return ImageComponent(
      componentKey: componentContext.componentKey,
      imageUrl: componentViewModel.imageUrl,
      selection: componentViewModel.selection?.nodeSelection as UpstreamDownstreamNodeSelection?,
      selectionColor: componentViewModel.selectionColor,
      imageBuilder: (context, imageUrl) => const SizedBox(height: 100, width: 100),
    );
  }
}

/// A [DocumentNode] without any content.
///
/// Used to simulate an app-level node type that the editor
/// doesn't know about.
@immutable
class _UnknownNode extends BlockNode {
  _UnknownNode({required this.id});

  @override
  final String id;

  @override
  String? copyContent(NodeSelection selection) => '';

  @override
  _UnknownNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return _UnknownNode(id: id);
  }

  @override
  _UnknownNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return _UnknownNode(id: id);
  }

  @override
  _UnknownNode copy() {
    return _UnknownNode(id: id);
  }
}
