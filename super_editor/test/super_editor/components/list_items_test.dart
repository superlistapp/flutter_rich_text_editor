import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';
import 'package:super_text_layout/super_text_layout.dart';

import '../../test_runners.dart';
import '../supereditor_test_tools.dart';

void main() {
  group('List items', () {
    group('node conversion', () {
      testWidgetsOnArbitraryDesktop("applies styles when unordered list item is converted to and from a paragraph",
          (WidgetTester tester) async {
        final testContext = await _pumpUnorderedList(
          tester,
          styleSheet: _styleSheet,
        );
        final doc = SuperEditorInspector.findDocument()!;

        LayoutAwareRichText richText;

        // Ensure that the textStyle for a list item was applied.
        expect(find.byType(LayoutAwareRichText), findsWidgets);
        richText = (find.byType(LayoutAwareRichText).evaluate().first.widget) as LayoutAwareRichText;
        expect(richText.text.style!.color, Colors.blue);

        // Tap to place caret.
        await tester.placeCaretInParagraph(doc.first.id, 0);

        // Convert the list item to a paragraph.
        testContext.findEditContext().commonOps.convertToParagraph(
          newMetadata: {
            'blockType': const NamedAttribution("paragraph"),
          },
        );
        await tester.pumpAndSettle();

        // Ensure that the textStyle for a paragraph was applied.
        expect(find.byType(LayoutAwareRichText), findsWidgets);
        richText = (find.byType(LayoutAwareRichText).evaluate().first.widget) as LayoutAwareRichText;
        expect(richText.text.style!.color, Colors.red);

        // Convert the paragraph back to an unordered list item.
        testContext.findEditContext().commonOps.convertToListItem(
              ListItemType.unordered,
              (doc.first as ParagraphNode).text,
            );
        await tester.pumpAndSettle();

        // Ensure that the textStyle for a list item was applied.
        expect(find.byType(LayoutAwareRichText), findsWidgets);
        richText = (find.byType(LayoutAwareRichText).evaluate().first.widget) as LayoutAwareRichText;
        expect(richText.text.style!.color, Colors.blue);
      });

      testWidgetsOnArbitraryDesktop("applies styles when ordered list item is converted to and from a paragraph",
          (WidgetTester tester) async {
        final testContext = await _pumpOrderedList(
          tester,
          styleSheet: _styleSheet,
        );
        final doc = SuperEditorInspector.findDocument()!;

        LayoutAwareRichText richText;

        // Ensure that the textStyle for a list item was applied.
        expect(find.byType(LayoutAwareRichText), findsWidgets);
        richText = (find.byType(LayoutAwareRichText).evaluate().first.widget) as LayoutAwareRichText;
        expect(richText.text.style!.color, Colors.blue);

        // Tap to place caret.
        await tester.placeCaretInParagraph(doc.first.id, 0);

        // Convert the list item to a paragraph.
        testContext.findEditContext().commonOps.convertToParagraph(
          newMetadata: {
            'blockType': const NamedAttribution("paragraph"),
          },
        );
        await tester.pumpAndSettle();

        // Ensure that the textStyle for a paragraph was applied.
        expect(find.byType(LayoutAwareRichText), findsWidgets);
        richText = (find.byType(LayoutAwareRichText).evaluate().first.widget) as LayoutAwareRichText;
        expect(richText.text.style!.color, Colors.red);

        // Convert the paragraph back to an ordered list item.
        testContext.findEditContext().commonOps.convertToListItem(
              ListItemType.ordered,
              (doc.first as ParagraphNode).text,
            );
        await tester.pumpAndSettle();

        // Ensure that the textStyle for a list item was applied.
        expect(find.byType(LayoutAwareRichText), findsWidgets);
        richText = (find.byType(LayoutAwareRichText).evaluate().first.widget) as LayoutAwareRichText;
        expect(richText.text.style!.color, Colors.blue);
      });
    });

    group('newlines >', () {
      testWidgetsOnAllPlatforms("does nothing when caret is in non-deletable task", (tester) async {
        await tester
            .createDocument()
            .withCustomContent(
              MutableDocument(
                nodes: [
                  ListItemNode.unordered(
                    id: "1",
                    text: AttributedText("Non-deletable list item."),
                    metadata: const {
                      NodeMetadata.isDeletable: false,
                    },
                  ),
                  ParagraphNode(
                    id: "2",
                    text: AttributedText("A deletable paragraph."),
                  ),
                ],
              ),
            )
            .pump();

        // Place caret in the middle of the non-deletable list item.
        await tester.placeCaretInParagraph("1", 5);

        // Press enter to try to split the list item.
        switch (debugDefaultTargetPlatformOverride) {
          case TargetPlatform.android:
          case TargetPlatform.iOS:
            // FIXME: pressEnterWithIme should work, but it seems to think there are no
            //        connected IME clients, so it fizzles. For now, we use the implementation
            //        directly.
            // await tester.pressEnterWithIme();
            await tester.testTextInput.receiveAction(TextInputAction.newline);
          case TargetPlatform.macOS:
          case TargetPlatform.windows:
          case TargetPlatform.linux:
          case TargetPlatform.fuchsia:
          case null:
            await tester.pressEnter();
        }

        // Ensure the list item wasn't changed.
        final document = SuperEditorInspector.findDocument()!;
        expect(document.nodeCount, 2);
        expect(document.first.asTextNode.text.toPlainText(), "Non-deletable list item.");
        expect(document.first, isA<ListItemNode>());
      });

      testWidgetsOnAllPlatforms("does nothing when non-deletable content is selected", (tester) async {
        final editContext = await tester
            .createDocument()
            .withCustomContent(
              MutableDocument(
                nodes: [
                  ListItemNode.ordered(
                    id: "1",
                    text: AttributedText("A list item."),
                  ),
                  HorizontalRuleNode(
                    id: "2",
                    metadata: const {
                      NodeMetadata.isDeletable: false,
                    },
                  ),
                ],
              ),
            )
            .autoFocus(true)
            .pump();

        // Select from the list item across the HR.
        editContext.editor.execute([
          ChangeSelectionRequest(
            DocumentSelection(
              base: DocumentPosition(
                documentPath: NodePath.forNode("1"),
                nodePosition: const TextNodePosition(offset: 5),
              ),
              extent: DocumentPosition(
                documentPath: NodePath.forNode("2"),
                nodePosition: const UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
            SelectionChangeType.expandSelection,
            SelectionReason.userInteraction,
          ),
        ]);
        await tester.pump();

        // Press enter to try to delete part of the list item and a non-deletable
        // horizontal rule.
        switch (debugDefaultTargetPlatformOverride) {
          case TargetPlatform.android:
          case TargetPlatform.iOS:
            // FIXME: pressEnterWithIme should work, but it seems to think there are no
            //        connected IME clients, so it fizzles. For now, we use the implementation
            //        directly.
            // await tester.pressEnterWithIme();
            await tester.testTextInput.receiveAction(TextInputAction.newline);
          case TargetPlatform.macOS:
          case TargetPlatform.windows:
          case TargetPlatform.linux:
          case TargetPlatform.fuchsia:
          case null:
            await tester.pressEnter();
        }

        // Ensure nothing happened to the document.
        final document = SuperEditorInspector.findDocument()!;
        expect(document.nodeCount, 2);
        expect(document.first.asTextNode.text.toPlainText(), "A list item.");
        expect(document.last, isA<HorizontalRuleNode>());
      });
    });

    group('unordered list', () {
      testWidgetsOnDesktop('updates caret position when indenting', (tester) async {
        await _pumpOrderedListWithTextField(tester);

        final doc = SuperEditorInspector.findDocument()!;

        // Place caret at the first list item, which has one level of indentation.
        await tester.placeCaretInParagraph(doc.first.id, 0);

        // Ensure the list item has first level of indentation.
        expect(doc.first.asListItem.indent, 0);

        // Ensure the caret is initially positioned near the upstream edge of the first
        // character of the list item.
        //
        // We only care about a roughly accurate caret offset because the logic around
        // exact caret positioning might change and we don't want that to break this test.
        final caretOffsetBeforeIndent = SuperEditorInspector.findCaretOffsetInDocument();
        final firstCharacterRectBeforeIndent = SuperEditorInspector.findDocumentLayout().getRectForPosition(
          DocumentPosition(documentPath: NodePath([doc.first.id]), nodePosition: const TextNodePosition(offset: 0)),
        )!;
        expect(caretOffsetBeforeIndent.dx, moreOrLessEquals(firstCharacterRectBeforeIndent.left, epsilon: 5));

        // Press tab to trigger the list indent command.
        await tester.pressTab();

        // Ensure the list item has second level of indentation.
        expect(doc.first.asListItem.indent, 1);

        // Ensure that the caret's current offset is downstream from the initial caret offset,
        // and also that the current caret offset is roughly positioned near the upstream edge
        // of the first list item character.
        //
        // We only care about a roughly accurate caret offset because the logic around
        // exact caret positioning might change and we don't want that to break this test.
        final caretOffsetAfterIndent = SuperEditorInspector.findCaretOffsetInDocument();
        expect(caretOffsetAfterIndent.dx, greaterThan(caretOffsetBeforeIndent.dx));
        final firstCharacterRectAfterIndent = SuperEditorInspector.findDocumentLayout().getRectForPosition(
          DocumentPosition(documentPath: NodePath([doc.first.id]), nodePosition: const TextNodePosition(offset: 0)),
        )!;
        expect(caretOffsetAfterIndent.dx, moreOrLessEquals(firstCharacterRectAfterIndent.left, epsilon: 5));
      });

      testWidgetsOnDesktop('updates caret position when unindenting', (tester) async {
        await _pumpUnorderedListWithTextField(tester);

        final doc = SuperEditorInspector.findDocument()!;

        // Place caret at the last list item, which has two levels of indentation.
        // For some reason, taping at the first character isn't displaying any caret,
        // so we put the caret at the second character and then go back one position.
        await tester.placeCaretInParagraph(doc.last.id, 1);
        await tester.pressLeftArrow();

        // Ensure the list item has second level of indentation.
        expect(doc.last.asListItem.indent, 1);

        // Ensure the caret is initially positioned near the upstream edge of the first
        // character of the list item.
        //
        // We only care about a roughly accurate caret offset because the logic around
        // exact caret positioning might change and we don't want that to break this test.
        final caretOffsetBeforeUnIndent = SuperEditorInspector.findCaretOffsetInDocument();
        final firstCharacterRectBeforeUnIndent = SuperEditorInspector.findDocumentLayout().getRectForPosition(
          DocumentPosition(documentPath: NodePath([doc.last.id]), nodePosition: const TextNodePosition(offset: 0)),
        )!;
        expect(caretOffsetBeforeUnIndent.dx, moreOrLessEquals(firstCharacterRectBeforeUnIndent.left, epsilon: 5));

        // Press backspace to trigger the list unindent command.
        await tester.pressBackspace();

        // Ensure the list item has first level of indentation.
        expect(doc.last.asListItem.indent, 0);

        // Ensure that the caret's current offset is upstream from the initial caret offset,
        // and also that the current caret offset is roughly positioned near the upstream edge
        // of the first list item character.
        //
        // We only care about a roughly accurate caret offset because the logic around
        // exact caret positioning might change and we don't want that to break this test.
        final caretOffsetAfterUnIndent = SuperEditorInspector.findCaretOffsetInDocument();
        expect(caretOffsetAfterUnIndent.dx, lessThan(caretOffsetBeforeUnIndent.dx));
        final firstCharacterRectAfterUnIndent = SuperEditorInspector.findDocumentLayout().getRectForPosition(
          DocumentPosition(documentPath: NodePath([doc.last.id]), nodePosition: const TextNodePosition(offset: 0)),
        )!;
        expect(caretOffsetAfterUnIndent.dx, moreOrLessEquals(firstCharacterRectAfterUnIndent.left, epsilon: 5));
      });

      testWidgetsOnDesktop('unindents with SHIFT + TAB', (tester) async {
        await _pumpUnorderedListWithTextField(tester);

        final doc = SuperEditorInspector.findDocument()!;

        // Place caret at the last list item, which has two levels of indentation.
        // For some reason, tapping at the first character isn't displaying any caret,
        // so we put the caret at the second character and then go back one position.
        await tester.placeCaretInParagraph(doc.last.id, 1);
        await tester.pressLeftArrow();

        // Ensure the list item has second level of indentation.
        expect(doc.last.asListItem.indent, 1);

        // Press SHIFT + TAB to trigger the list unindent command.
        await _pressShiftTab(tester);

        // Ensure the list item has first level of indentation.
        expect(doc.last.asListItem.indent, 0);
      });

      testWidgetsOnDesktopAndWeb('unindents with BACKSPACE with caret at beginning of list item', (tester) async {
        await _pumpUnorderedListWithTextField(tester);

        final doc = SuperEditorInspector.findDocument()!;

        // Place caret at the last list item, which has two levels of indentation.
        await tester.placeCaretInParagraph(doc.last.id, 0);

        // Ensure the list item has second level of indentation.
        expect(doc.last.asListItem.indent, 1);

        // Press BACKSPACE to trigger the list unindent command.
        await tester.pressBackspace();

        // Ensure the list item has first level of indentation.
        expect(doc.last.asListItem.indent, 0);
      });

      testWidgetsOnAllPlatforms("inserts new item on ENTER at end of existing item", (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown('* Item 1')
            .pump();

        final document = context.findEditContext().document;

        // Place the caret at the end of the list item.
        await tester.placeCaretInParagraph(document.last.id, 6);

        // Type at the end of the list item to generate a composing region,
        // simulating the Samsung keyboard.
        await tester.typeImeText('2');
        await tester.ime.sendDeltas(const [
          TextEditingDeltaNonTextUpdate(
            oldText: '. Item 12',
            selection: TextSelection.collapsed(offset: 9),
            composing: TextRange.collapsed(9),
          ),
        ], getter: imeClientGetter);

        // Press enter to create a new list item.
        await tester.pressEnter();

        // Ensure that a new, empty list item was created.
        expect(document.nodeCount, 2);

        // Ensure the existing item remains the same.
        expect(document.first, isA<ListItemNode>());
        expect((document.first as ListItemNode).text.toPlainText(), "Item 12");

        // Ensure the new item has the correct list item type and indentation.
        expect(document.last, isA<ListItemNode>());
        expect((document.last as ListItemNode).text.toPlainText(), "");
        expect((document.last as ListItemNode).type, ListItemType.unordered);
        expect((document.last as ListItemNode).indent, 0);
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnAndroid("inserts new item upon new line insertion at end of existing item", (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown('* Item 1')
            .pump();

        final document = context.findEditContext().document;

        // Place the caret at the end of the list item.
        await tester.placeCaretInParagraph(document.first.id, 6);

        // Type at the end of the list item to generate a composing region,
        // simulating the Samsung keyboard.
        await tester.typeImeText('2');
        await tester.ime.sendDeltas(const [
          TextEditingDeltaNonTextUpdate(
            oldText: '. Item 12',
            selection: TextSelection.collapsed(offset: 9),
            composing: TextRange.collapsed(9),
          ),
        ], getter: imeClientGetter);

        // On Android, pressing ENTER generates a "\n" insertion.
        await tester.typeImeText("\n");

        // Ensure that a new, empty list item was created.
        expect(document.nodeCount, 2);

        // Ensure the existing item remains the same.
        expect(document.first, isA<ListItemNode>());
        expect((document.first as ListItemNode).text.toPlainText(), "Item 12");

        // Ensure the new item has the correct list item type and indentation.
        expect(document.last, isA<ListItemNode>());
        expect((document.last as ListItemNode).text.toPlainText(), "");
        expect((document.last as ListItemNode).type, ListItemType.unordered);
        expect((document.last as ListItemNode).indent, 0);
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnMobile("inserts new item upon new line input action at end of existing item", (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown('* Item 1')
            .pump();

        final document = context.findEditContext().document;

        // Place the caret at the end of the list item.
        await tester.placeCaretInParagraph(document.first.id, 6);

        // Type at the end of the list item to generate a composing region,
        // simulating the Samsung keyboard.
        await tester.typeImeText('2');
        await tester.ime.sendDeltas(const [
          TextEditingDeltaNonTextUpdate(
            oldText: '. Item 12',
            selection: TextSelection.collapsed(offset: 9),
            composing: TextRange.collapsed(9),
          ),
        ], getter: imeClientGetter);

        // On iOS, pressing ENTER generates a newline action.
        await tester.testTextInput.receiveAction(TextInputAction.newline);

        // Ensure that a new, empty list item was created.
        expect(document.nodeCount, 2);

        // Ensure the existing item remains the same.
        expect(document.first, isA<ListItemNode>());
        expect((document.first as ListItemNode).text.toPlainText(), "Item 12");

        // Ensure the new item has the correct list item type and indentation.
        expect(document.last, isA<ListItemNode>());
        expect((document.last as ListItemNode).text.toPlainText(), "");
        expect((document.last as ListItemNode).type, ListItemType.unordered);
        expect((document.last as ListItemNode).indent, 0);
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnAllPlatforms("splits list item into two on ENTER in middle of existing item", (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown('* List Item')
            .pump();

        final document = context.findEditContext().document;

        // Place the caret at "List |Item"
        await tester.placeCaretInParagraph(document.first.id, 5);

        // Press enter to split the existing item into two.
        await tester.pressEnter();

        // Ensure that a new item was created with part of the previous item.
        expect(document.nodeCount, 2);
        expect(document.first, isA<ListItemNode>());
        expect((document.first as ListItemNode).text.toPlainText(), "List ");
        expect(document.last, isA<ListItemNode>());
        expect((document.last as ListItemNode).text.toPlainText(), "Item");
        expect((document.last as ListItemNode).type, ListItemType.unordered);
        expect((document.last as ListItemNode).indent, 0);
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnAndroid("splits list item into two upon new line insertion in middle of existing item",
          (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown('* List Item')
            .pump();

        final document = context.findEditContext().document;

        // Place the caret at "List |Item"
        await tester.placeCaretInParagraph(document.first.id, 5);

        // On Android, pressing ENTER generates a "\n" insertion.
        await tester.typeImeText("\n");

        // Ensure that a new item was created with part of the previous item.
        expect(document.nodeCount, 2);
        expect(document.first, isA<ListItemNode>());
        expect((document.first as ListItemNode).text.toPlainText(), "List ");
        expect(document.last, isA<ListItemNode>());
        expect((document.last as ListItemNode).text.toPlainText(), "Item");
        expect((document.last as ListItemNode).type, ListItemType.unordered);
        expect((document.last as ListItemNode).indent, 0);
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnMobile("splits list item into two upon new line input action in middle of existing item",
          (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown('* List Item')
            .pump();

        final document = context.findEditContext().document;

        // Place the caret at "List |Item"
        await tester.placeCaretInParagraph(document.first.id, 5);

        // On iOS, pressing ENTER generates a newline action.
        await tester.testTextInput.receiveAction(TextInputAction.newline);

        // Ensure that a new item was created with part of the previous item.
        expect(document.nodeCount, 2);
        expect(document.first, isA<ListItemNode>());
        expect((document.first as ListItemNode).text.toPlainText(), "List ");
        expect(document.last, isA<ListItemNode>());
        expect((document.last as ListItemNode).text.toPlainText(), "Item");
        expect((document.last as ListItemNode).type, ListItemType.unordered);
        expect((document.last as ListItemNode).indent, 0);
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });
    });

    group('ordered list', () {
      testWidgetsOnArbitraryDesktop('keeps sequence for items split by unordered list', (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown("""
1. First ordered item
   - First unordered item
   - Second unoredered item

2. Second ordered item
   - First unordered item
   - Second unoredered item""") //
            .pump();

        expect(context.document.nodeCount, 6);

        // Ensure the nodes have the correct type.
        expect(context.document.getNodeAt(0), isA<ListItemNode>());
        expect((context.document.getNodeAt(0) as ListItemNode).type, ListItemType.ordered);

        expect(context.document.getNodeAt(1), isA<ListItemNode>());
        expect((context.document.getNodeAt(1) as ListItemNode).type, ListItemType.unordered);

        expect(context.document.getNodeAt(2), isA<ListItemNode>());
        expect((context.document.getNodeAt(2) as ListItemNode).type, ListItemType.unordered);

        expect(context.document.getNodeAt(3), isA<ListItemNode>());
        expect((context.document.getNodeAt(3) as ListItemNode).type, ListItemType.ordered);

        expect(context.document.getNodeAt(4), isA<ListItemNode>());
        expect((context.document.getNodeAt(4) as ListItemNode).type, ListItemType.unordered);

        expect(context.document.getNodeAt(5), isA<ListItemNode>());
        expect((context.document.getNodeAt(5) as ListItemNode).type, ListItemType.unordered);

        // Ensure the sequence was kept.
        final firstOrderedItem = tester.widget<OrderedListItemComponent>(
          find.ancestor(
            of: find.byWidget(SuperEditorInspector.findWidgetForComponent(context.document.getNodeAt(0)!.id)),
            matching: find.byType(OrderedListItemComponent),
          ),
        );
        expect(firstOrderedItem.listIndex, 1);

        final secondOrderedItem = tester.widget<OrderedListItemComponent>(
          find.ancestor(
            of: find.byWidget(SuperEditorInspector.findWidgetForComponent(context.document.getNodeAt(3)!.id)),
            matching: find.byType(OrderedListItemComponent),
          ),
        );
        expect(secondOrderedItem.listIndex, 2);
      });

      testWidgetsOnArbitraryDesktop('keeps sequence for items split by ordered list items with higher indentation',
          (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown("""
 1. list item 1
 2. list item 2
    1. list item 2.1
    2. list item 2.2
 3. list item 3
    1. list item 3.1
""") //
            .pump();

        expect(context.document.nodeCount, 6);

        // Ensure the nodes have the correct type.
        for (int i = 0; i < 6; i++) {
          expect(context.document.getNodeAt(i), isA<ListItemNode>());
          expect((context.document.getNodeAt(i) as ListItemNode).type, ListItemType.ordered);
        }

        // Ensure the sequence was kept.
        expect(SuperEditorInspector.findListItemOrdinal(context.document.getNodeAt(0)!.id), 1);
        expect(SuperEditorInspector.findListItemOrdinal(context.document.getNodeAt(1)!.id), 2);
        expect(SuperEditorInspector.findListItemOrdinal(context.document.getNodeAt(2)!.id), 1);
        expect(SuperEditorInspector.findListItemOrdinal(context.document.getNodeAt(3)!.id), 2);
        expect(SuperEditorInspector.findListItemOrdinal(context.document.getNodeAt(4)!.id), 3);
        expect(SuperEditorInspector.findListItemOrdinal(context.document.getNodeAt(5)!.id), 1);
      });

      testWidgetsOnArbitraryDesktop('restarts item order when separated by an unordered item', (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown("""
1. First ordered item
2. Second ordered item
- First unordered item
- Second unordered item
1. First ordered item
2. Second ordered item""") //
            .pump();

        expect(context.document.nodeCount, 6);

        // Ensure the nodes have the correct type.
        expect(context.document.getNodeAt(0), isA<ListItemNode>());
        expect((context.document.getNodeAt(0) as ListItemNode).type, ListItemType.ordered);

        expect(context.document.getNodeAt(1), isA<ListItemNode>());
        expect((context.document.getNodeAt(1) as ListItemNode).type, ListItemType.ordered);

        expect(context.document.getNodeAt(2), isA<ListItemNode>());
        expect((context.document.getNodeAt(2) as ListItemNode).type, ListItemType.unordered);

        expect(context.document.getNodeAt(3), isA<ListItemNode>());
        expect((context.document.getNodeAt(3) as ListItemNode).type, ListItemType.unordered);

        expect(context.document.getNodeAt(4), isA<ListItemNode>());
        expect((context.document.getNodeAt(4) as ListItemNode).type, ListItemType.ordered);

        expect(context.document.getNodeAt(5), isA<ListItemNode>());
        expect((context.document.getNodeAt(5) as ListItemNode).type, ListItemType.ordered);

        // Ensure the sequence restarted after the unordered items.
        expect(SuperEditorInspector.findListItemOrdinal(context.document.getNodeAt(0)!.id), 1);
        expect(SuperEditorInspector.findListItemOrdinal(context.document.getNodeAt(1)!.id), 2);
        expect(SuperEditorInspector.findListItemOrdinal(context.document.getNodeAt(4)!.id), 1);
        expect(SuperEditorInspector.findListItemOrdinal(context.document.getNodeAt(5)!.id), 2);
      });

      testWidgetsOnArbitraryDesktop('does not keep sequence for items split by paragraphs', (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown("""
1. First ordered item

A paragraph

2. Second ordered item""") //
            .pump();

        expect(context.document.nodeCount, 3);

        // Ensure the nodes have the correct type.
        expect(context.document.getNodeAt(0), isA<ListItemNode>());
        expect((context.document.getNodeAt(0) as ListItemNode).type, ListItemType.ordered);

        expect(context.document.getNodeAt(1), isA<ParagraphNode>());

        expect(context.document.getNodeAt(2), isA<ListItemNode>());
        expect((context.document.getNodeAt(2) as ListItemNode).type, ListItemType.ordered);

        // Ensure the sequence reset when reaching the second list item.
        final firstOrderedItem = tester.widget<OrderedListItemComponent>(
          find.ancestor(
            of: find.byWidget(SuperEditorInspector.findWidgetForComponent(context.document.getNodeAt(0)!.id)),
            matching: find.byType(OrderedListItemComponent),
          ),
        );
        expect(firstOrderedItem.listIndex, 1);

        final secondOrderedItem = tester.widget<OrderedListItemComponent>(
          find.ancestor(
            of: find.byWidget(SuperEditorInspector.findWidgetForComponent(context.document.getNodeAt(2)!.id)),
            matching: find.byType(OrderedListItemComponent),
          ),
        );
        expect(secondOrderedItem.listIndex, 1);
      });

      testWidgetsOnArbitraryDesktop('updates caret position when indenting', (tester) async {
        await _pumpOrderedListWithTextField(tester);

        final doc = SuperEditorInspector.findDocument()!;

        // Place caret at the first list item, which has one level of indentation.
        await tester.placeCaretInParagraph(doc.first.id, 0);

        // Ensure the list item has first level of indentation.
        expect(doc.first.asListItem.indent, 0);

        // Ensure the caret is initially positioned near the upstream edge of the first
        // character of the list item.
        //
        // We only care about a roughly accurate caret offset because the logic around
        // exact caret positioning might change and we don't want that to break this test.
        final caretOffsetBeforeIndent = SuperEditorInspector.findCaretOffsetInDocument();
        final firstCharacterRectBeforeIndent = SuperEditorInspector.findDocumentLayout().getRectForPosition(
          DocumentPosition(documentPath: NodePath([doc.first.id]), nodePosition: const TextNodePosition(offset: 0)),
        )!;
        expect(caretOffsetBeforeIndent.dx, moreOrLessEquals(firstCharacterRectBeforeIndent.left, epsilon: 5));

        // Press tab to trigger the list indent command.
        await tester.pressTab();

        // Ensure the list item has second level of indentation.
        expect(doc.first.asListItem.indent, 1);

        // Ensure that the caret's current offset is downstream from the initial caret offset,
        // and also that the current caret offset is roughly positioned near the upstream edge
        // of the first list item character.
        //
        // We only care about a roughly accurate caret offset because the logic around
        // exact caret positioning might change and we don't want that to break this test.
        final caretOffsetAfterIndent = SuperEditorInspector.findCaretOffsetInDocument();
        expect(caretOffsetAfterIndent.dx, greaterThan(caretOffsetBeforeIndent.dx));
        final firstCharacterRectAfterIndent = SuperEditorInspector.findDocumentLayout().getRectForPosition(
          DocumentPosition(documentPath: NodePath([doc.first.id]), nodePosition: const TextNodePosition(offset: 0)),
        )!;
        expect(caretOffsetAfterIndent.dx, moreOrLessEquals(firstCharacterRectAfterIndent.left, epsilon: 5));
      });

      testWidgetsOnArbitraryDesktop('updates caret position when unindenting', (tester) async {
        await _pumpOrderedListWithTextField(tester);

        final doc = SuperEditorInspector.findDocument()!;

        // Place caret at the last list item, which has two levels of indentation.
        // For some reason, taping at the first character isn't displaying any caret,
        // so we put the caret at the second character and then go back one position.
        await tester.placeCaretInParagraph(doc.last.id, 1);
        await tester.pressLeftArrow();

        // Ensure the list item has second level of indentation.
        expect(doc.last.asListItem.indent, 1);

        // Ensure the caret is initially positioned near the upstream edge of the first
        // character of the list item.
        //
        // We only care about a roughly accurate caret offset because the logic around
        // exact caret positioning might change and we don't want that to break this test.
        final caretOffsetBeforeUnIndent = SuperEditorInspector.findCaretOffsetInDocument();
        final firstCharacterRectBeforeUnIndent = SuperEditorInspector.findDocumentLayout().getRectForPosition(
          DocumentPosition(documentPath: NodePath([doc.last.id]), nodePosition: const TextNodePosition(offset: 0)),
        )!;
        expect(caretOffsetBeforeUnIndent.dx, moreOrLessEquals(firstCharacterRectBeforeUnIndent.left, epsilon: 5));

        // Press backspace to trigger the list unindent command.
        await tester.pressBackspace();

        // Ensure the list item has first level of indentation.
        expect(doc.last.asListItem.indent, 0);

        // Ensure that the caret's current offset is upstream from the initial caret offset,
        // and also that the current caret offset is roughly positioned near the upstream edge
        // of the first list item character.
        //
        // We only care about a roughly accurate caret offset because the logic around
        // exact caret positioning might change and we don't want that to break this test.
        final caretOffsetAfterUnIndent = SuperEditorInspector.findCaretOffsetInDocument();
        expect(caretOffsetAfterUnIndent.dx, lessThan(caretOffsetBeforeUnIndent.dx));
        final firstCharacterRectAfterUnIndent = SuperEditorInspector.findDocumentLayout().getRectForPosition(
          DocumentPosition(documentPath: NodePath([doc.last.id]), nodePosition: const TextNodePosition(offset: 0)),
        )!;
        expect(caretOffsetAfterUnIndent.dx, moreOrLessEquals(firstCharacterRectAfterUnIndent.left, epsilon: 5));
      });

      testWidgetsOnDesktop('unindents with SHIFT + TAB', (tester) async {
        await _pumpOrderedListWithTextField(tester);

        final doc = SuperEditorInspector.findDocument()!;

        // Place caret at the last list item, which has two levels of indentation.
        // For some reason, taping at the first character isn't displaying any caret,
        // so we put the caret at the second character and then go back one position.
        await tester.placeCaretInParagraph(doc.last.id, 1);
        await tester.pressLeftArrow();

        // Ensure the list item has second level of indentation.
        expect(doc.last.asListItem.indent, 1);

        // Press SHIFT + TAB to trigger the list unindent command.
        await _pressShiftTab(tester);

        // Ensure the list item has first level of indentation.
        expect(doc.last.asListItem.indent, 0);
      });

      testWidgetsOnAllPlatforms("inserts new item on ENTER at end of existing item", (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown('1. Item 1')
            .pump();

        final document = context.findEditContext().document;

        // Place the caret at the end of the list item.
        await tester.placeCaretInParagraph(document.first.id, 6);

        // Press enter to create a new list item.
        await tester.pressEnter();

        // Ensure that a new, empty list item was created.
        expect(document.nodeCount, 2);

        // Ensure the existing item remains the same.
        expect(document.first, isA<ListItemNode>());
        expect((document.first as ListItemNode).text.toPlainText(), "Item 1");

        // Ensure the new item has the correct list item type and indentation.
        expect(document.last, isA<ListItemNode>());
        expect((document.last as ListItemNode).text.toPlainText(), "");
        expect((document.last as ListItemNode).type, ListItemType.ordered);
        expect((document.last as ListItemNode).indent, 0);
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnAndroid("inserts new item upon new line insertion at end of existing item", (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown('1. Item 1')
            .pump();

        final document = context.findEditContext().document;

        // Place the caret at the end of the list item.
        await tester.placeCaretInParagraph(document.first.id, 6);

        // On Android, pressing ENTER generates a "\n" insertion.
        await tester.typeImeText("\n");

        // Ensure that a new, empty list item was created.
        expect(document.nodeCount, 2);

        // Ensure the existing item remains the same.
        expect(document.first, isA<ListItemNode>());
        expect((document.first as ListItemNode).text.toPlainText(), "Item 1");

        // Ensure the new item has the correct list item type and indentation.
        expect(document.last, isA<ListItemNode>());
        expect((document.last as ListItemNode).text.toPlainText(), "");
        expect((document.last as ListItemNode).type, ListItemType.ordered);
        expect((document.last as ListItemNode).indent, 0);
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnMobile("inserts new item upon new line input action at end of existing item", (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown('1. Item 1')
            .pump();

        final document = context.findEditContext().document;

        // Place the caret at the end of the list item.
        await tester.placeCaretInParagraph(document.first.id, 6);

        // On iOS, pressing ENTER generates a newline action.
        await tester.testTextInput.receiveAction(TextInputAction.newline);

        // Ensure that a new, empty list item was created.
        expect(document.nodeCount, 2);

        // Ensure the existing item remains the same.
        expect(document.first, isA<ListItemNode>());
        expect((document.first as ListItemNode).text.toPlainText(), "Item 1");

        // Ensure the new item has the correct list item type and indentation.
        expect(document.last, isA<ListItemNode>());
        expect((document.last as ListItemNode).text.toPlainText(), "");
        expect((document.last as ListItemNode).type, ListItemType.ordered);
        expect((document.last as ListItemNode).indent, 0);
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnAllPlatforms("splits list item into two on ENTER in middle of existing item", (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown('1. List Item')
            .pump();

        final document = context.findEditContext().document;

        // Place the caret at "List |Item"
        await tester.placeCaretInParagraph(document.first.id, 5);

        // Press enter to split the existing item into two.
        await tester.pressEnter();

        // Ensure that a new item was created with part of the previous item.
        expect(document.nodeCount, 2);
        expect(document.first, isA<ListItemNode>());
        expect((document.first as ListItemNode).text.toPlainText(), "List ");
        expect(document.last, isA<ListItemNode>());
        expect((document.last as ListItemNode).text.toPlainText(), "Item");
        expect((document.last as ListItemNode).type, ListItemType.ordered);
        expect((document.last as ListItemNode).indent, 0);
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnAndroid("splits list item into two upon new line insertion in middle of existing item",
          (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown('1. List Item')
            .pump();

        final document = context.findEditContext().document;

        // Place the caret at "List |Item"
        await tester.placeCaretInParagraph(document.first.id, 5);

        // On Android, pressing ENTER generates a "\n" insertion.
        await tester.typeImeText("\n");

        // Ensure that a new item was created with part of the previous item.
        expect(document.nodeCount, 2);
        expect(document.first, isA<ListItemNode>());
        expect((document.first as ListItemNode).text.toPlainText(), "List ");
        expect(document.last, isA<ListItemNode>());
        expect((document.last as ListItemNode).text.toPlainText(), "Item");
        expect((document.last as ListItemNode).type, ListItemType.ordered);
        expect((document.last as ListItemNode).indent, 0);
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });

      testWidgetsOnMobile("splits list item into two upon new line input action in middle of existing item",
          (tester) async {
        final context = await tester //
            .createDocument()
            .fromMarkdown('1. List Item')
            .pump();

        final document = context.findEditContext().document;

        // Place the caret at "List |Item"
        await tester.placeCaretInParagraph(document.first.id, 5);

        // On iOS, pressing ENTER generates a newline action.
        await tester.testTextInput.receiveAction(TextInputAction.newline);

        // Ensure that a new item was created with part of the previous item.
        expect(document.nodeCount, 2);
        expect(document.first, isA<ListItemNode>());
        expect((document.first as ListItemNode).text.toPlainText(), "List ");
        expect(document.last, isA<ListItemNode>());
        expect((document.last as ListItemNode).text.toPlainText(), "Item");
        expect((document.last as ListItemNode).type, ListItemType.ordered);
        expect((document.last as ListItemNode).indent, 0);
        expect(
          SuperEditorInspector.findDocumentSelection(),
          TextNode.caretAt([document.last.id], 0),
        );
      });
    });
  });
}

/// Pumps a [SuperEditor] containing 3 unordered list items.
///
/// The first two items have one level of indentation.
///
/// The last two items have two levels of indentation.
Future<TestDocumentContext> _pumpUnorderedList(
  WidgetTester tester, {
  Stylesheet? styleSheet,
}) async {
  const markdown = '''
 * list item 1
 * list item 2
   * list item 2.1
   * list item 2.2''';

  return await tester //
      .createDocument()
      .fromMarkdown(markdown)
      .useStylesheet(styleSheet)
      .pump();
}

/// Pumps a [SuperEditor] containing 4 unordered list items and a [TextField] below it.
///
/// The first two items have one level of indentation.
///
/// The last two items have two levels of indentation.
Future<TestDocumentContext> _pumpUnorderedListWithTextField(
  WidgetTester tester, {
  Stylesheet? styleSheet,
}) async {
  const markdown = '''
 * list item 1
 * list item 2
   * list item 2.1
   * list item 2.2''';

  return await tester //
      .createDocument()
      .fromMarkdown(markdown)
      .useStylesheet(styleSheet)
      .withInputSource(TextInputSource.ime)
      .withCustomWidgetTreeBuilder(
        (superEditor) => MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const TextField(),
                Expanded(child: superEditor),
                const TextField(),
              ],
            ),
          ),
        ),
      )
      .pump();
}

/// Pumps a [SuperEditor] containing 4 ordered list items.
///
/// The first two items have one level of indentation.
///
/// The last two items have two levels of indentation.
Future<TestDocumentContext> _pumpOrderedList(
  WidgetTester tester, {
  Stylesheet? styleSheet,
}) async {
  const markdown = '''
 1. list item 1
 1. list item 2
    1. list item 2.1
    1. list item 2.2''';

  return await tester //
      .createDocument()
      .fromMarkdown(markdown)
      .useStylesheet(styleSheet)
      .pump();
}

/// Pumps a [SuperEditor] containing 4 ordered list items and a [TextField] below it.
///
/// The first two items have one level of indentation.
///
/// The last two items have two levels of indentation.
Future<TestDocumentContext> _pumpOrderedListWithTextField(
  WidgetTester tester, {
  Stylesheet? styleSheet,
}) async {
  const markdown = '''
 1. list item 1
 1. list item 2
    1. list item 2.1
    1. list item 2.2''';

  return await tester //
      .createDocument()
      .fromMarkdown(markdown)
      .useStylesheet(styleSheet)
      .withInputSource(TextInputSource.ime)
      .withCustomWidgetTreeBuilder(
        (superEditor) => MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(child: superEditor),
                const TextField(),
              ],
            ),
          ),
        ),
      )
      .pump();
}

Future<void> _pressShiftTab(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  await tester.pumpAndSettle();
}

TextStyle _inlineTextStyler(Set<Attribution> attributions, TextStyle base) => base;

final _styleSheet = Stylesheet(
  inlineTextStyler: _inlineTextStyler,
  rules: [
    StyleRule(
      const BlockSelector("paragraph"),
      (doc, docNode) {
        return {
          Styles.textStyle: const TextStyle(
            color: Colors.red,
            fontSize: 16,
          ),
        };
      },
    ),
    StyleRule(
      const BlockSelector("listItem"),
      (doc, docNode) {
        return {
          Styles.textStyle: const TextStyle(
            color: Colors.blue,
            fontSize: 16,
          ),
        };
      },
    ),
  ],
);
