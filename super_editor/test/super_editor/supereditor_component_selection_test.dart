import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';

import 'supereditor_test_tools.dart';
import 'test_documents.dart';

/// This test suite illustrates the difference between interacting with
/// selectable non-text nodes and un-selectable non-text nodes.
///
/// Consider horizontal rules.
///
/// An editor might make HRs selectable so that the user can tap them, select
/// them with the keyboard, and delete them when selected.
///
/// Other editors (like Medium) might make HRs un-selectable. When the user
/// taps on an HR, it doesn't become selected. When the user presses arrow
/// keys that would ordinarily select an HR, the selection behaves as if
/// the HR isn't there.
void main() {
  group("Selectable component", () {
    testWidgetsOnDesktop("accepts selection when caret moves down from upstream node", (tester) async {
      await _pumpEditorWithSelectableHrs(tester);
      await tester.placeCaretInParagraph("1", 37);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "2",
            nodePosition: UpstreamDownstreamNodePosition.downstream(),
          ),
        ),
      );
    });

    testWidgetsOnDesktop("accepts selection when selection expands down from upstream node", (tester) async {
      await _pumpEditorWithSelectableHrs(tester);
      await tester.placeCaretInParagraph("1", 37);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection(
          base: DocumentPosition(
            nodeId: "1",
            nodePosition: TextNodePosition(offset: 37, affinity: TextAffinity.upstream),
          ),
          extent: DocumentPosition(
            nodeId: "2",
            nodePosition: UpstreamDownstreamNodePosition.downstream(),
          ),
        ),
      );
    });

    testWidgetsOnDesktop("accepts selection when caret moves up from downstream node", (tester) async {
      await _pumpEditorWithSelectableHrs(tester);
      await tester.placeCaretInParagraph("3", 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "2",
            nodePosition: UpstreamDownstreamNodePosition.upstream(),
          ),
        ),
      );
    });

    testWidgetsOnDesktop("accepts selection when selection expands up from downstream node", (tester) async {
      await _pumpEditorWithSelectableHrs(tester);
      await tester.placeCaretInParagraph("3", 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection(
          base: DocumentPosition(
            nodeId: "3",
            nodePosition: TextNodePosition(offset: 0),
          ),
          extent: DocumentPosition(
            nodeId: "2",
            nodePosition: UpstreamDownstreamNodePosition.upstream(),
          ),
        ),
      );
    });

    testWidgetsOnAllPlatforms("accepts selection when user taps on it", (tester) async {
      await _pumpEditorWithSelectableHrs(tester);

      await tester.tapAtDocumentPosition(
        const DocumentPosition(
          nodeId: "2",
          nodePosition: UpstreamDownstreamNodePosition.upstream(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "2",
            nodePosition: UpstreamDownstreamNodePosition.upstream(),
          ),
        ),
      );
    });

    testWidgetsOnDesktop("moves selection to next node when delete pressed from upstream", (tester) async {
      await _pumpEditorWithSelectableHrs(tester);
      await tester.placeCaretInParagraph("1", 37);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "2",
            nodePosition: UpstreamDownstreamNodePosition.upstream(),
          ),
        ),
      );
    });

    testWidgetsOnDesktop("moves selection to previous node when backspace pressed from downstream", (tester) async {
      await _pumpEditorWithSelectableHrs(tester);
      await tester.placeCaretInParagraph("3", 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "2",
            nodePosition: UpstreamDownstreamNodePosition.downstream(),
          ),
        ),
      );
    });

    testWidgetsOnArbitraryDesktop("defined by the app receives selection color", (tester) async {
      await tester //
          .createDocument()
          .withCustomContent(
            MutableDocument(nodes: [
              ParagraphNode(id: '1', text: AttributedText('Paragraph 1')),
              _ButtonNode(id: '2'),
              ParagraphNode(id: '3', text: AttributedText('Paragraph 3')),
            ]),
          )
          .withAddedComponents(
            [const _ButtonComponentBuilder()],
          )
          .withSelectionStyles(
            const SelectionStyles(selectionColor: Colors.red),
          )
          .pump();

      // Drag to select all content.
      await tester.dragSelectDocumentFromPositionByOffset(
        from: const DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 0)),
        delta: const Offset(0, 100),
      );

      // Ensure the selection color from the selection style was applied.
      expect(
        tester.widget<SelectableBox>(find.byType(SelectableBox)).selectionColor,
        Colors.red,
      );
    });
  });

  group("Unselectable component", () {
    testWidgetsOnDesktop("skips node when down arrow moves caret down from upstream node", (tester) async {
      await _pumpEditorWithUnselectableHrs(tester);
      await tester.placeCaretInParagraph("1", 37);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "3",
            nodePosition: TextNodePosition(offset: 37, affinity: TextAffinity.upstream),
          ),
        ),
      );
    });

    testWidgetsOnDesktop("skips node when right arrow moves caret down from upstream node", (tester) async {
      await _pumpEditorWithUnselectableHrs(tester);
      await tester.placeCaretInParagraph("1", 37);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(nodeId: "3", nodePosition: TextNodePosition(offset: 0)),
        ),
      );
    });

    testWidgetsOnDesktop("rejects selection when down arrow moves caret down from upstream node", (tester) async {
      await _pumpEditorWithUnselectableHrs(tester, customDocument: paragraphThenHrDoc());
      await tester.placeCaretInParagraph("1", 11);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(nodeId: "1", nodePosition: TextNodePosition(offset: 11)),
        ),
      );
    });

    testWidgetsOnDesktop("rejects selection when right arrow moves caret down from upstream node", (tester) async {
      await _pumpEditorWithUnselectableHrs(tester, customDocument: paragraphThenHrDoc());
      await tester.placeCaretInParagraph("1", 11);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "1",
            nodePosition: TextNodePosition(offset: 11, affinity: TextAffinity.upstream),
          ),
        ),
      );
    });

    testWidgetsOnDesktop("skips node when up arrow moves caret up from downstream node", (tester) async {
      await _pumpEditorWithUnselectableHrs(tester);
      await tester.placeCaretInParagraph("3", 37);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "1",
            nodePosition: TextNodePosition(offset: 37, affinity: TextAffinity.upstream),
          ),
        ),
      );
    });

    testWidgetsOnDesktop("skips node when left arrow moves caret up from downstream node", (tester) async {
      await _pumpEditorWithUnselectableHrs(tester);
      await tester.placeCaretInParagraph("3", 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(nodeId: "1", nodePosition: TextNodePosition(offset: 37)),
        ),
      );
    });

    testWidgetsOnDesktop("rejects selection when up arrow moves caret up from downstream node", (tester) async {
      await _pumpEditorWithUnselectableHrs(tester, customDocument: hrThenParagraphDoc());
      await tester.placeCaretInParagraph("2", 11);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(nodeId: "2", nodePosition: TextNodePosition(offset: 0)),
        ),
      );
    });

    testWidgetsOnDesktop("rejects selection when left arrow moves caret up from downstream node", (tester) async {
      await _pumpEditorWithUnselectableHrs(tester, customDocument: hrThenParagraphDoc());
      await tester.placeCaretInParagraph("2", 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(nodeId: "2", nodePosition: TextNodePosition(offset: 0)),
        ),
      );
    });

    testWidgetsOnDesktop("deletes downstream node when delete pressed from upstream", (tester) async {
      await _pumpEditorWithUnselectableHrs(tester);
      await tester.placeCaretInParagraph("1", 37);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "1",
            nodePosition: TextNodePosition(offset: 37, affinity: TextAffinity.upstream),
          ),
        ),
      );
      expect(
        find.byType(SuperEditor),
        equalsMarkdown(
          "This is the first node in a document.\n\n"
          "This is the third node in a document.",
        ),
      );
    });

    testWidgetsOnDesktop("deletes upstream node when backspace pressed from downstream", (tester) async {
      await _pumpEditorWithUnselectableHrs(tester);
      await tester.placeCaretInParagraph("3", 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "3",
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
      expect(
        find.byType(SuperEditor),
        equalsMarkdown(
          "This is the first node in a document.\n\n"
          "This is the third node in a document.",
        ),
      );
    });

    testWidgetsOnAllPlatforms("rejects selection when user taps on it and it's the only node in document",
        (tester) async {
      await _pumpEditorWithUnselectableHrs(
        tester,
        customDocument: singleBlockDoc(),
      );

      await tester.tapAtDocumentPosition(const DocumentPosition(
        nodeId: "1",
        nodePosition: UpstreamDownstreamNodePosition.upstream(),
      ));
      await tester.pumpAndSettle();

      expect(SuperEditorInspector.findDocumentSelection(), isNull);
    });

    testWidgetsOnAllPlatforms("selects nearest selectable node when user taps on it", (tester) async {
      await _pumpEditorWithUnselectableHrs(tester);

      await tester.tapAtDocumentPosition(const DocumentPosition(
        nodeId: "2",
        nodePosition: UpstreamDownstreamNodePosition.upstream(),
      ));
      await tester.pumpAndSettle();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "3",
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
    });

    testWidgetsOnAllPlatforms("selects nearest selectable node when user double taps on it", (tester) async {
      await _pumpEditorWithUnselectableHrs(tester);

      // Double tap the hr.
      const position = DocumentPosition(
        nodeId: "2",
        nodePosition: UpstreamDownstreamNodePosition.upstream(),
      );
      await tester.tapAtDocumentPosition(position);
      await tester.pump(kTapMinTime + const Duration(milliseconds: 1));
      await tester.tapAtDocumentPosition(position);

      await tester.pumpAndSettle();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "3",
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
    });

    testWidgetsOnAllPlatforms("selects nearest selectable node when user triple taps on it", (tester) async {
      await _pumpEditorWithUnselectableHrs(tester);

      // Triple tap the hr.
      const position = DocumentPosition(
        nodeId: "2",
        nodePosition: UpstreamDownstreamNodePosition.upstream(),
      );
      await tester.tapAtDocumentPosition(position);
      await tester.pump(kTapMinTime + const Duration(milliseconds: 1));
      await tester.tapAtDocumentPosition(position);
      await tester.pump(kTapMinTime + const Duration(milliseconds: 1));
      await tester.tapAtDocumentPosition(position);

      await tester.pumpAndSettle();

      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: "3",
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
    });

    testWidgetsOnMobile("closes toolbar when user taps on it", (tester) async {
      final toolbarKey = GlobalKey();

      await _pumpEditorWithUnselectableHrsAndFakeToolbar(
        tester,
        toolbarKey: toolbarKey,
      );

      // Place the selection in the first paragraph.
      await tester.doubleTapInParagraph("1", 0);
      // Avoid triple tap.
      await tester.pump(kTapTimeout);
      await tester.pumpAndSettle();

      // Ensure the toolbar is displayed.
      expect(find.byKey(toolbarKey), findsOneWidget);

      // Tap the hr.
      await tester.tapAtDocumentPosition(const DocumentPosition(
        nodeId: "2",
        nodePosition: UpstreamDownstreamNodePosition.upstream(),
      ));

      await tester.pumpAndSettle();

      // Ensure the toolbar is closed.
      expect(find.byKey(toolbarKey), findsNothing);
    });

    testWidgetsOnMobile("closes toolbar when user double taps on it", (tester) async {
      final toolbarKey = GlobalKey();

      await _pumpEditorWithUnselectableHrsAndFakeToolbar(
        tester,
        toolbarKey: toolbarKey,
      );

      // Place the selection in the first paragraph.
      await tester.doubleTapInParagraph("1", 0);
      await tester.pumpAndSettle();

      // Ensure the toolbar is displayed.
      expect(find.byKey(toolbarKey), findsOneWidget);

      // Double tap the hr.
      const position = DocumentPosition(
        nodeId: "2",
        nodePosition: UpstreamDownstreamNodePosition.upstream(),
      );
      await tester.tapAtDocumentPosition(position);
      await tester.pump(kTapMinTime + const Duration(milliseconds: 1));
      await tester.tapAtDocumentPosition(position);

      await tester.pumpAndSettle();

      // Ensure the toolbar is closed.
      expect(find.byKey(toolbarKey), findsNothing);
    });

    testWidgetsOnMobile("closes toolbar when user triple taps on it", (tester) async {
      final toolbarKey = GlobalKey();

      await _pumpEditorWithUnselectableHrsAndFakeToolbar(
        tester,
        toolbarKey: toolbarKey,
      );

      // Place the selection in the first paragraph.
      await tester.doubleTapInParagraph("1", 0);
      await tester.pumpAndSettle();

      // Ensure the toolbar is displayed.
      expect(find.byKey(toolbarKey), findsOneWidget);

      // Triple tap the hr.
      const position = DocumentPosition(
        nodeId: "2",
        nodePosition: UpstreamDownstreamNodePosition.upstream(),
      );
      await tester.tapAtDocumentPosition(position);
      await tester.pump(kTapMinTime + const Duration(milliseconds: 1));
      await tester.tapAtDocumentPosition(position);
      await tester.pump(kTapMinTime + const Duration(milliseconds: 1));
      await tester.tapAtDocumentPosition(position);

      await tester.pumpAndSettle();

      // Ensure the toolbar is closed.
      expect(find.byKey(toolbarKey), findsNothing);
    });
  });
}

Future<TestDocumentContext> _pumpEditorWithSelectableHrs(WidgetTester tester) => tester //
    .createDocument() //
    .withCustomContent(paragraphThenHrThenParagraphDoc()) //
    .forDesktop() //
    .useStylesheet(_testStylesheet)
    .pump();

Future<TestDocumentContext> _pumpEditorWithUnselectableHrs(
  WidgetTester tester, {
  MutableDocument? customDocument,
}) =>
    tester //
        .createDocument() //
        .withCustomContent(customDocument ?? paragraphThenHrThenParagraphDoc()) //
        .useStylesheet(_testStylesheet)
        .withAddedComponents([const _UnselectableHrComponentBuilder()]) //
        .pump();

Future<void> _pumpEditorWithUnselectableHrsAndFakeToolbar(
  WidgetTester tester, {
  required GlobalKey toolbarKey,
}) async {
  await tester //
      .createDocument()
      .withCustomContent(paragraphThenHrThenParagraphDoc())
      .withComponentBuilders(const [
        _UnselectableHrComponentBuilder(),
        ...defaultComponentBuilders,
      ])
      .withAndroidToolbarBuilder((context, mobileToolbarKey, focalPoint) => SizedBox(key: toolbarKey))
      .withiOSToolbarBuilder((context, mobileToolbarKey, focalPoint) => SizedBox(key: toolbarKey))
      .pump();
}

/// SuperEditor [ComponentBuilder] that builds a horizontal rule that is
/// not selectable.
class _UnselectableHrComponentBuilder implements ComponentBuilder {
  const _UnselectableHrComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
    List<ComponentBuilder> componentBuilders,
  ) {
    // This builder can work with the standard horizontal rule view model, so
    // we'll defer to the standard horizontal rule builder.
    return null;
  }

  @override
  Widget? createComponent(
      SingleColumnDocumentComponentContext componentContext, SingleColumnLayoutComponentViewModel componentViewModel) {
    if (componentViewModel is! HorizontalRuleComponentViewModel) {
      return null;
    }

    return _UnselectableHorizontalRuleComponent(
      componentKey: componentContext.componentKey,
    );
  }
}

class _UnselectableHorizontalRuleComponent extends StatelessWidget {
  const _UnselectableHorizontalRuleComponent({
    Key? key,
    required this.componentKey,
  }) : super(key: key);

  final GlobalKey componentKey;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: BoxComponent(
        key: componentKey,
        isVisuallySelectable: false,
        child: const Divider(
          color: Color(0xFF000000),
          thickness: 1.0,
        ),
      ),
    );
  }
}

/// A [DocumentNode] used to display a button.
@immutable
class _ButtonNode extends BlockNode {
  _ButtonNode({
    required this.id,
  });

  @override
  final String id;

  @override
  String? copyContent(dynamic selection) => '';

  @override
  _ButtonNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return _ButtonNode(id: id);
  }

  @override
  _ButtonNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return _ButtonNode(id: id);
  }

  @override
  DocumentNode copy() {
    return _ButtonNode(id: id);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ButtonNode && //
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class _ButtonViewModel extends SingleColumnLayoutComponentViewModel with SelectionAwareViewModelMixin {
  _ButtonViewModel({
    required String nodeId,
    double? maxWidth,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    DocumentNodeSelection? selection,
    Color selectionColor = Colors.transparent,
  }) : super(nodeId: nodeId, maxWidth: maxWidth, padding: padding) {
    this.selection = selection;
    this.selectionColor = selectionColor;
  }

  @override
  _ButtonViewModel copy() {
    return _ButtonViewModel(
      nodeId: nodeId,
      maxWidth: maxWidth,
      padding: padding,
      selection: selection,
      selectionColor: selectionColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is _ButtonViewModel &&
          runtimeType == other.runtimeType &&
          nodeId == other.nodeId &&
          selection == other.selection &&
          selectionColor == other.selectionColor;

  @override
  int get hashCode => super.hashCode ^ nodeId.hashCode ^ selection.hashCode ^ selectionColor.hashCode;
}

class _ButtonComponent extends StatelessWidget {
  const _ButtonComponent({
    Key? key,
    required this.componentKey,
    this.selectionColor = Colors.blue,
    this.selection,
  }) : super(key: key);

  final GlobalKey componentKey;
  final Color selectionColor;
  final DocumentNodeSelection? selection;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: SelectableBox(
            selection: selection?.nodeSelection as UpstreamDownstreamNodeSelection?,
            selectionColor: selectionColor,
            child: BoxComponent(
              key: componentKey,
              child: const SizedBox(),
            ),
          ),
        ),
        Center(
          child: ElevatedButton(
            onPressed: () {},
            child: const Text('My Button'),
          ),
        ),
      ],
    );
  }
}

class _ButtonComponentBuilder implements ComponentBuilder {
  const _ButtonComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
    List<ComponentBuilder> componentBuilders,
  ) {
    if (node is! _ButtonNode) {
      return null;
    }

    return _ButtonViewModel(nodeId: node.id);
  }

  @override
  Widget? createComponent(
      SingleColumnDocumentComponentContext componentContext, SingleColumnLayoutComponentViewModel componentViewModel) {
    if (componentViewModel is! _ButtonViewModel) {
      return null;
    }

    return _ButtonComponent(
      componentKey: componentContext.componentKey,
      selection: componentViewModel.selection,
      selectionColor: componentViewModel.selectionColor,
    );
  }
}

final _testStylesheet = defaultStylesheet.copyWith(
  addRulesAfter: [
    StyleRule(BlockSelector.all, (doc, node) {
      return {
        Styles.textStyle: const TextStyle(
          fontSize: 12,
        ),
      };
    })
  ],
);
