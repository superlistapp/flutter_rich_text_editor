import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/src/infrastructure/platforms/platform.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';

import '../test_tools.dart';
import 'supereditor_test_tools.dart';

void main() {
  group('SuperEditor > undeletable content > prevents deletion > ', () {
    // Instead of only testing a single arbitrary desktop, the desktop tests run for all desktop
    // platforms because on mac the backspace is handled by selectors and on the other platforms
    // it is handled by the keyboard handlers. See `MacOsSelectors` for more information.
    group('with collapsed selection > ', () {
      group('with backspace', () {
        testWidgetsOnDesktop('at the downstream edge of the node', (tester) async {
          await _pumpHrThenParagraphTestApp(tester);

          const hrDownstreamEdgePosition = DocumentPosition(
            nodeId: 'hr',
            nodePosition: UpstreamDownstreamNodePosition.downstream(),
          );

          // Place the caret at the downstream edge of the horizontal rule.
          await tester.tapAtDocumentPosition(hrDownstreamEdgePosition);

          // Ensure the selection is at the downstream edge of the horizontal rule.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection.collapsed(
              position: hrDownstreamEdgePosition,
            ),
          );

          // Press backspace a few times trying to delete the node.
          await tester.pressBackspace();
          await tester.pressBackspace();
          await tester.pressBackspace();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());

          // Ensure the selection didn't change.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection.collapsed(
              position: hrDownstreamEdgePosition,
            ),
          );
        });

        testWidgetsOnDesktop('at the beginning of the downstream node', (tester) async {
          await _pumpParagraphThenHrThenParagraphTestApp(tester);

          // Place the caret at the beginning of the second paragraph.
          await tester.placeCaretInParagraph('2', 0);

          // Press backspace trying to delete the horizontal rule.
          await tester.pressBackspace();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());

          // Ensure the two paragraphs were merged.
          expect(
            SuperEditorInspector.findTextInComponent('1').toPlainText(),
            'Paragraph 1Paragraph 2',
          );

          // Ensure the caret moved to the end of existing test of the first paragraph.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 11),
                ),
              ),
            ),
          );
        });
      });

      group('with delete', () {
        testWidgetsOnDesktop('at the upstream edge of the node', (tester) async {
          await _pumpParagraphThenHrTestApp(tester);

          const hrUpstreamEdgePosition = DocumentPosition(
            nodeId: 'hr',
            nodePosition: UpstreamDownstreamNodePosition.upstream(),
          );

          // Place the caret at the upstream edge of the horizontal rule.
          await tester.tapAtDocumentPosition(hrUpstreamEdgePosition);

          // Ensure the selection is at the beginning of the horizontal rule.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection.collapsed(
              position: hrUpstreamEdgePosition,
            ),
          );

          // Press delete a few times trying to delete the node.
          await tester.pressDelete();
          await tester.pressDelete();
          await tester.pressDelete();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());

          // Ensure the selection didn't change.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection.collapsed(
              position: hrUpstreamEdgePosition,
            ),
          );
        });

        testWidgetsOnDesktop('at the end of the upstream node', (tester) async {
          await _pumpParagraphThenHrThenParagraphTestApp(tester);

          // Place the caret at the end of the first paragraph.
          await tester.placeCaretInParagraph('1', 11);

          // Press backspace trying to delete the horizontal rule.
          await tester.pressDelete();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());

          // Ensure the two paragraphs were merged.
          expect(
            SuperEditorInspector.findTextInComponent('1').toPlainText(),
            'Paragraph 1Paragraph 2',
          );

          // Ensure the caret stayed where it was.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 11),
                ),
              ),
            ),
          );
        });
      });

      group('with backspace in software keyboard', () {
        testWidgetsOnMobile('at the downstream edge of the node', (tester) async {
          await _pumpHrThenParagraphTestApp(tester);

          const hrDownstreamPosition = DocumentPosition(
            nodeId: 'hr',
            nodePosition: UpstreamDownstreamNodePosition.downstream(),
          );

          // Place the caret at the downstream edge of the horizontal rule.
          await tester.tapAtDocumentPosition(hrDownstreamPosition);
          await tester.pump();

          // Ensure the caret is at the downstream edge of the horizontal rule.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection.collapsed(
              position: hrDownstreamPosition,
            ),
          );

          // Simulate the user pressing backspace. The IME first generates a
          // selection change and then a deletion. Each block node is represented by a "~"
          // in the IME.
          await tester.ime.sendDeltas([
            const TextEditingDeltaNonTextUpdate(
              oldText: '. ~',
              selection: TextSelection(baseOffset: 2, extentOffset: 3),
              composing: TextRange(start: -1, end: -1),
            ),
            const TextEditingDeltaDeletion(
              oldText: '. ~',
              deletedRange: TextSelection(baseOffset: 2, extentOffset: 3),
              selection: TextSelection.collapsed(offset: 2),
              composing: TextRange(start: -1, end: -1),
            ),
          ], getter: imeClientGetter);

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());

          // Ensure the selection was kept where it was.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection.collapsed(
              position: hrDownstreamPosition,
            ),
          );
        });
      });
    });

    group('with expanded selection > ', () {
      group('with backspace', () {
        testWidgetsOnDesktop('for downstream selection', (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          // Select the whole hr. Use a command instead of a user gesture to have
          // precise control over the selection.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
                extent: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press backspace a few times trying to delete the node.
          await tester.pressBackspace();
          await tester.pressBackspace();
          await tester.pressBackspace();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('for upstream selection', (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          // Select the whole hr. Use a command instead of a user gesture to have
          // precise control over the selection.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
                extent: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press backspace a few times trying to delete the node.
          await tester.pressBackspace();
          await tester.pressBackspace();
          await tester.pressBackspace();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnAllPlatforms('when multiple deletable and undeletable nodes are selected', (tester) async {
          final testContext = await _pumpMultipleDeletableAndUndeletableNodesTestApp(tester);

          // Select from "Para>graph 1" to "Paragraph <3".
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
                extent: DocumentPosition(
                  nodeId: '3',
                  nodePosition: TextNodePosition(offset: 10),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press backspace to delete the selected nodes.
          await tester.pressBackspace();

          // Ensure that the deletable content was deleted and the selection moved to upstream edge
          // of the selection.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.nodeCount, 4);
          expect(SuperEditorInspector.findTextInComponent('1'), AttributedText('Para3'));
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 4)),
              ),
            ),
          );

          // Ensure that the undeletable content was not deleted.
          expect(document.getNodeById('hr1'), isNotNull);
          expect(document.getNodeById('hr1'), isA<HorizontalRuleNode>());

          expect(document.getNodeById('hr2'), isNotNull);
          expect(document.getNodeById('hr2'), isA<HorizontalRuleNode>());

          expect(document.getNodeById('hr3'), isNotNull);
          expect(document.getNodeById('hr3'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnDesktop('when selection starts at upstream edge and ends at a downstream deletable node',
            (tester) async {
          final testContext = await _pumpHrThenParagraphTestApp(tester);

          // Select from the upstream edge of the horizontal rule to "Para|graph 1".
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
                extent: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press backspace to delete the selected content.
          await tester.pressBackspace();

          // Ensure that the deletable content was deleted and selection moved to the beginning
          // of the selected paragraph.
          expect(
            SuperEditorInspector.findTextInComponent('1').toPlainText(),
            'graph 1',
          );
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 0)),
              ),
            ),
          );

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnDesktop('when selection starts at downstream edge and ends at an upstream deletable node',
            (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          // Select from the downstream edge of the horizontal rule to "Para|graph 1".
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
                extent: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press backspace to delete the selected content.
          await tester.pressBackspace();

          // Ensure that the deletable content was deleted and selection moved to the upstream edge
          // of the selection
          expect(
            SuperEditorInspector.findTextInComponent('1').toPlainText(),
            'Para',
          );
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 4)),
              ),
            ),
          );

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnDesktop('when selection starts at an upstream deletable node and ends at the downstream edge',
            (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          // Select from the "Para|graph 1" to the downstream edge of the horizontal rule.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
                extent: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press backspace to delete the selected content.
          await tester.pressBackspace();

          // Ensure that the deletable content was deleted and selection moved to the beginning
          // of the selected paragraph.
          expect(SuperEditorInspector.findTextInComponent('1').toPlainText(), 'Para');
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 4)),
              ),
            ),
          );

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnDesktop('when selection starts at a downstream deletable node and ends at the upstream edge',
            (tester) async {
          final testContext = await _pumpHrThenParagraphTestApp(tester);

          // Select from the "Para|graph 2" to the upstream edge of the second horizontal rule.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
                extent: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press backspace to delete the selected content.
          await tester.pressBackspace();

          // Ensure that the deletable content was deleted and selection moved to the beginning
          // of the selected paragraph.
          expect(SuperEditorInspector.findTextInComponent('1').toPlainText(), 'graph 1');
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 0)),
              ),
            ),
          );

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnDesktop(
            'when selection starts at the dowstream edge and ends at the beginning of the downstream node',
            (tester) async {
          final testContext = await _pumpHrThenParagraphTestApp(tester);

          const selection = DocumentSelection(
            base: DocumentPosition(
              nodeId: 'hr',
              nodePosition: UpstreamDownstreamNodePosition.downstream(),
            ),
            extent: DocumentPosition(
              nodeId: '1',
              nodePosition: TextNodePosition(offset: 0),
            ),
          );

          // Select from the end of the horizontal rule to the beginning of the downstream node.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              selection,
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press backspace to delete the selected content.
          await tester.pressBackspace();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());

          // Ensure the selection didn't change.
          expect(SuperEditorInspector.findDocumentSelection(), selection);
        });

        testWidgetsOnDesktop(
            'when selection starts at the upstream edge and ends at the beginning of the downstream node',
            (tester) async {
          final testContext = await _pumpHrThenParagraphTestApp(tester);

          const selection = DocumentSelection(
            base: DocumentPosition(
              nodeId: 'hr',
              nodePosition: UpstreamDownstreamNodePosition.upstream(),
            ),
            extent: DocumentPosition(
              nodeId: '1',
              nodePosition: TextNodePosition(offset: 0),
            ),
          );

          // Select from the beginning of the horizontal rule to the beginning of the downstream node.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              selection,
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press backspace to delete the selected content.
          await tester.pressBackspace();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());

          // Ensure the selection didn't change.
          expect(SuperEditorInspector.findDocumentSelection(), selection);
        });

        testWidgetsOnDesktop('when selection starts at upstream edge and ends at the end of the upstream node',
            (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          // Select from the beginning of the horizontal rule to the end of the upstream node.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
                extent: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 11),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press backspace to delete the selected content.
          await tester.pressBackspace();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());

          // Ensure the selection moved to the end of the upstream node.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 11),
                ),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('when selection starts at downstream edge and ends at the end of the upstream node',
            (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          // Select from the end of the horizontal rule to the end of the downstream node.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
                extent: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 11),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press backspace to delete the selected content.
          await tester.pressBackspace();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());

          // Ensure the selection moved to the end of the upstream node.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 11),
                ),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('when the whole document is selected and starts with a non-deletable node',
            (tester) async {
          await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    HorizontalRuleNode(id: '1', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    ParagraphNode(
                      id: '2',
                      text: AttributedText('This is some text'),
                    ),
                  ],
                ),
              )
              .pump();

          // Place the caret at the beginning of the paragraph.
          await tester.placeCaretInParagraph("2", 0);

          // Select all content.
          if (CurrentPlatform.isApple) {
            await tester.pressCmdA();
          } else {
            await tester.pressCtlA();
          }

          // Ensure everything is selected.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '1',
                nodePosition: UpstreamDownstreamNodePosition.upstream(),
              ),
              extent: DocumentPosition(
                nodeId: '2',
                nodePosition: TextNodePosition(offset: 17),
              ),
            ),
          );

          // Delete all content.
          await tester.pressBackspace();

          final document = SuperEditorInspector.findDocument()!;

          // Ensure the horizontal rule was kept, the paragraph was deleted,
          // and a new empty paragraph was added to the end of the document.
          expect(document.nodeCount, equals(2));
          expect(document.first, isA<HorizontalRuleNode>());
          expect(document.last, isA<ParagraphNode>());
          expect((document.last as TextNode).text.toPlainText(), equals(''));

          // Ensure the caret was placed at the beginning of the newly inserted paragraph.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: document.last.id,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('when the whole document is selected and ends with a non-deletable node', (tester) async {
          await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    ParagraphNode(
                      id: '1',
                      text: AttributedText('This is some text'),
                    ),
                    HorizontalRuleNode(id: '2', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                  ],
                ),
              )
              .pump();

          await tester.placeCaretInParagraph("1", 0);

          // Select all content.
          if (CurrentPlatform.isApple) {
            await tester.pressCmdA();
          } else {
            await tester.pressCtlA();
          }

          // Ensure everything is selected.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '1',
                nodePosition: TextNodePosition(offset: 0),
              ),
              extent: DocumentPosition(
                nodeId: '2',
                nodePosition: UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
          );

          // Delete all content.
          await tester.pressBackspace();

          final document = SuperEditorInspector.findDocument()!;

          // Ensure the horizontal rule was kept, the paragraph was deleted,
          // and a new empty paragraph was added to the end of the document.
          expect(document.nodeCount, equals(2));
          expect(document.first, isA<HorizontalRuleNode>());
          expect(document.last, isA<ParagraphNode>());
          expect((document.last as TextNode).text.toPlainText(), equals(''));

          // Ensure the caret was placed at the beginning of the newly inserted paragraph.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: document.last.id,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('when the whole document is selected and starts and ends with non-deletable nodes',
            (tester) async {
          await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    HorizontalRuleNode(id: '1', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    ParagraphNode(
                      id: '2',
                      text: AttributedText('This is some text'),
                    ),
                    HorizontalRuleNode(id: '3', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                  ],
                ),
              )
              .pump();

          await tester.placeCaretInParagraph("2", 0);

          // Select all content.
          if (CurrentPlatform.isApple) {
            await tester.pressCmdA();
          } else {
            await tester.pressCtlA();
          }

          // Ensure everything is selected.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '1',
                nodePosition: UpstreamDownstreamNodePosition.upstream(),
              ),
              extent: DocumentPosition(
                nodeId: '3',
                nodePosition: UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
          );

          // Delete all content.
          await tester.pressBackspace();

          final document = SuperEditorInspector.findDocument()!;

          // Ensure the horizontal rules were kept, the paragraph was deleted,
          // and a new empty paragraph was added to the end of the document.
          expect(document.nodeCount, equals(3));
          expect(document.getNodeAt(0), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(1), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(2), isA<ParagraphNode>());
          expect((document.last as TextNode).text.toPlainText(), equals(''));

          // Ensure the caret was placed at the beginning of the newly inserted paragraph.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: document.last.id,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('when all nodes are non-deletable', (tester) async {
          await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    HorizontalRuleNode(id: '1', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    HorizontalRuleNode(id: '2', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    HorizontalRuleNode(id: '3', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                  ],
                ),
              )
              .pump();

          // Select the first horizontal rule.
          await tester.tapAtDocumentPosition(
            const DocumentPosition(
              nodeId: "1",
              nodePosition: UpstreamDownstreamNodePosition.upstream(),
            ),
          );

          // Select all content.
          if (CurrentPlatform.isApple) {
            await tester.pressCmdA();
          } else {
            await tester.pressCtlA();
          }

          // Ensure everything is selected.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '1',
                nodePosition: UpstreamDownstreamNodePosition.upstream(),
              ),
              extent: DocumentPosition(
                nodeId: '3',
                nodePosition: UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
          );

          // Try to delete all content.
          await tester.pressBackspace();

          final document = SuperEditorInspector.findDocument()!;

          // Ensure nothing was deleted.
          expect(document.nodeCount, equals(3));
          expect(document.getNodeAt(0), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(1), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(2), isA<HorizontalRuleNode>());

          // Ensure the selection was kept.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '1',
                nodePosition: UpstreamDownstreamNodePosition.upstream(),
              ),
              extent: DocumentPosition(
                nodeId: '3',
                nodePosition: UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('when all nodes in selection are non-deletable and document contains deletable nodes',
            (tester) async {
          final testContext = await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    ParagraphNode(id: '1', text: AttributedText()),
                    HorizontalRuleNode(id: '2', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    HorizontalRuleNode(id: '3', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    HorizontalRuleNode(id: '4', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    ParagraphNode(id: '5', text: AttributedText()),
                  ],
                ),
              )
              .pump();

          // Select the first horizontal rule.
          await tester.tapAtDocumentPosition(
            const DocumentPosition(
              nodeId: "2",
              nodePosition: UpstreamDownstreamNodePosition.upstream(),
            ),
          );

          // Select all non-deletable nodes.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: '2',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
                extent: DocumentPosition(
                  nodeId: '4',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Try to delete all content.
          await tester.pressBackspace();

          final document = SuperEditorInspector.findDocument()!;

          // Ensure nothing was deleted.
          expect(document.nodeCount, equals(5));
          expect(document.getNodeAt(0), isA<ParagraphNode>());
          expect(document.getNodeAt(1), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(2), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(3), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(4), isA<ParagraphNode>());

          // Ensure the selection was kept.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '2',
                nodePosition: UpstreamDownstreamNodePosition.upstream(),
              ),
              extent: DocumentPosition(
                nodeId: '4',
                nodePosition: UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
          );
        });
      });

      group('with delete', () {
        testWidgetsOnDesktop('for downstream selection', (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          // Select the whole hr. Use a command instead of a user gesture to have
          // precise control over the selection.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
                extent: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press delete a few times trying to delete the node.
          await tester.pressDelete();
          await tester.pressDelete();
          await tester.pressDelete();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnDesktop('for upstream selection', (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          // Select the whole hr. Use a command instead of a user gesture to have
          // precise control over the selection.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
                extent: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press delete a few times trying to delete the node.
          await tester.pressDelete();
          await tester.pressDelete();
          await tester.pressDelete();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnDesktop('when multiple deletable and undeletable nodes are selected', (tester) async {
          final testContext = await _pumpMultipleDeletableAndUndeletableNodesTestApp(tester);

          // Select from "Para>graph 1" to "Paragraph <3".
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
                extent: DocumentPosition(
                  nodeId: '3',
                  nodePosition: TextNodePosition(offset: 10),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press delete to delete the selected nodes.
          await tester.pressDelete();

          // Ensure that the deletable content was deleted and selection moved to upstream edge
          // of the first deletable node.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.nodeCount, 4);
          expect(SuperEditorInspector.findTextInComponent('1'), AttributedText('Para3'));
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 4)),
              ),
            ),
          );

          // Ensure that the undeletable content was not deleted.
          expect(document.getNodeById('hr1'), isNotNull);
          expect(document.getNodeById('hr1'), isA<HorizontalRuleNode>());

          expect(document.getNodeById('hr2'), isNotNull);
          expect(document.getNodeById('hr2'), isA<HorizontalRuleNode>());

          expect(document.getNodeById('hr3'), isNotNull);
          expect(document.getNodeById('hr3'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnDesktop('when selection starts at upstream edge and ends at a downstream deletable node',
            (tester) async {
          final testContext = await _pumpHrThenParagraphTestApp(tester);

          // Select from the upstream edge of the horizontal rule to "Para|graph 1".
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
                extent: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press delete to remove the selected content.
          await tester.pressDelete();

          // Ensure that the deletable content was deleted and selection moved to the beginning
          // of the selected paragraph.
          expect(
            SuperEditorInspector.findTextInComponent('1').toPlainText(),
            'graph 1',
          );
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 0)),
              ),
            ),
          );

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnDesktop('when selection starts at downstream edge and ends at an upstream deletable node',
            (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          // Select from the downstream edge of the horizontal rule to "Para|graph 1".
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
                extent: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press delete to remove the selected content.
          await tester.pressDelete();

          // Ensure that the deletable content was deleted and selection moved to the upstream edge
          // of the selection
          expect(
            SuperEditorInspector.findTextInComponent('1').toPlainText(),
            'Para',
          );
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 4)),
              ),
            ),
          );

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnDesktop('when selection starts at an upstream deletable node and ends at the downstream edge',
            (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          // Select from the "Para|graph 1" to the downstream edge of the horizontal rule.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
                extent: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press delete to remove the selected content.
          await tester.pressDelete();

          // Ensure that the deletable content was deleted and selection moved to the beginning
          // of the selected paragraph.
          expect(SuperEditorInspector.findTextInComponent('1').toPlainText(), 'Para');
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 4)),
              ),
            ),
          );

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnDesktop('when selection starts at a downstream deletable node and ends at the upstream edge',
            (tester) async {
          final testContext = await _pumpHrThenParagraphTestApp(tester);

          // Select from the "Para|graph 2" to the upstream edge of the second horizontal rule.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
                extent: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press delete to remove the selected content.
          await tester.pressDelete();

          // Ensure that the deletable content was deleted and selection moved to the beginning
          // of the selected paragraph.
          expect(SuperEditorInspector.findTextInComponent('1').toPlainText(), 'graph 1');
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 0)),
              ),
            ),
          );

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnDesktop(
            'when selection starts at downstream edge and ends at the beginning of the downstream node',
            (tester) async {
          final testContext = await _pumpHrThenParagraphTestApp(tester);

          // Select from the end of horizontal rule to the beginning of the downstream node.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
                extent: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 0),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press backspace to delete the selected content.
          await tester.pressDelete();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());

          // Ensure the selection moved to the beginning of the downstream node.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 0),
                ),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('when selection starts at upstream edge and ends at the beginning of the downstream node',
            (tester) async {
          final testContext = await _pumpHrThenParagraphTestApp(tester);

          // Select from the beginning of horizontal rule to the beginning of the downstream node.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
                extent: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 0),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press backspace to delete the selected content.
          await tester.pressDelete();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());

          // Ensure the selection moved to the beginning of the downstream node.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 0),
                ),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('when selection starts at upstream edge and ends at the end of the upstream node',
            (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          const selection = DocumentSelection(
            base: DocumentPosition(
              nodeId: 'hr',
              nodePosition: UpstreamDownstreamNodePosition.upstream(),
            ),
            extent: DocumentPosition(
              nodeId: '1',
              nodePosition: TextNodePosition(offset: 11),
            ),
          );

          // Select from the beginning of the horizontal rule to the end of the upstream node.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              selection,
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press delete to remove the selected content.
          await tester.pressDelete();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());

          // Ensure the selection didn't change.
          expect(SuperEditorInspector.findDocumentSelection(), selection);
        });

        testWidgetsOnDesktop('when selection starts at downstream edge and ends at the end of the upstream node',
            (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          const selection = DocumentSelection(
            base: DocumentPosition(
              nodeId: 'hr',
              nodePosition: UpstreamDownstreamNodePosition.downstream(),
            ),
            extent: DocumentPosition(
              nodeId: '1',
              nodePosition: TextNodePosition(offset: 11),
            ),
          );

          // Select from the end of the horizontal rule to the end of the downstream node.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              selection,
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Press delete to remove the selected content.
          await tester.pressDelete();

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());

          // Ensure the selection didn't change.
          expect(SuperEditorInspector.findDocumentSelection(), selection);
        });

        testWidgetsOnDesktop('when the whole document is selected and starts with a non-deletable node',
            (tester) async {
          await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    HorizontalRuleNode(id: '1', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    ParagraphNode(
                      id: '2',
                      text: AttributedText('This is some text'),
                    ),
                  ],
                ),
              )
              .pump();

          // Place the caret at the beginning of the paragraph.
          await tester.placeCaretInParagraph("2", 0);

          // Select all content.
          if (CurrentPlatform.isApple) {
            await tester.pressCmdA();
          } else {
            await tester.pressCtlA();
          }

          // Ensure everything is selected.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '1',
                nodePosition: UpstreamDownstreamNodePosition.upstream(),
              ),
              extent: DocumentPosition(
                nodeId: '2',
                nodePosition: TextNodePosition(offset: 17),
              ),
            ),
          );

          // Delete all content.
          await tester.pressDelete();

          final document = SuperEditorInspector.findDocument()!;

          // Ensure the horizontal rule was kept, the paragraph was deleted,
          // and a new empty paragraph was added to the end of the document.
          expect(document.nodeCount, equals(2));
          expect(document.first, isA<HorizontalRuleNode>());
          expect(document.last, isA<ParagraphNode>());
          expect((document.last as TextNode).text.toPlainText(), equals(''));

          // Ensure the caret was placed at the beginning of the newly inserted paragraph.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: document.last.id,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('when the whole document is selected and ends with a non-deletable node', (tester) async {
          await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    ParagraphNode(
                      id: '1',
                      text: AttributedText('This is some text'),
                    ),
                    HorizontalRuleNode(id: '2', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                  ],
                ),
              )
              .pump();

          await tester.placeCaretInParagraph("1", 0);

          // Select all content
          if (CurrentPlatform.isApple) {
            await tester.pressCmdA();
          } else {
            await tester.pressCtlA();
          }

          // Ensure everything is selected.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '1',
                nodePosition: TextNodePosition(offset: 0),
              ),
              extent: DocumentPosition(
                nodeId: '2',
                nodePosition: UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
          );

          // Delete all content.
          await tester.pressDelete();

          final document = SuperEditorInspector.findDocument()!;

          // Ensure the horizontal rule was kept, the paragraph was deleted,
          // and a new empty paragraph was added to the end of the document.
          expect(document.nodeCount, equals(2));
          expect(document.first, isA<HorizontalRuleNode>());
          expect(document.last, isA<ParagraphNode>());
          expect((document.last as TextNode).text.toPlainText(), equals(''));

          // Ensure the caret was placed at the beginning of the newly inserted paragraph.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: document.last.id,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('when the whole document is selected and starts and ends with non-deletable nodes',
            (tester) async {
          await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    HorizontalRuleNode(id: '1', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    ParagraphNode(
                      id: '2',
                      text: AttributedText('This is some text'),
                    ),
                    HorizontalRuleNode(id: '3', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                  ],
                ),
              )
              .pump();

          await tester.placeCaretInParagraph("2", 0);

          // Select all content.
          if (CurrentPlatform.isApple) {
            await tester.pressCmdA();
          } else {
            await tester.pressCtlA();
          }

          // Ensure everything is selected.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '1',
                nodePosition: UpstreamDownstreamNodePosition.upstream(),
              ),
              extent: DocumentPosition(
                nodeId: '3',
                nodePosition: UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
          );

          // Delete all content.
          await tester.pressDelete();

          final document = SuperEditorInspector.findDocument()!;

          // Ensure the horizontal rules were kept, the paragraph was deleted,
          // and a new empty paragraph was added to the end of the document.
          expect(document.nodeCount, equals(3));
          expect(document.getNodeAt(0), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(1), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(2), isA<ParagraphNode>());
          expect((document.last as TextNode).text.toPlainText(), equals(''));

          // Ensure the caret was placed at the beginning of the newly inserted paragraph.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: document.last.id,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('when all nodes are non-deletable', (tester) async {
          await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    HorizontalRuleNode(id: '1', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    HorizontalRuleNode(id: '2', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    HorizontalRuleNode(id: '3', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                  ],
                ),
              )
              .pump();

          // Select the first horizontal rule.
          await tester.tapAtDocumentPosition(
            const DocumentPosition(
              nodeId: "1",
              nodePosition: UpstreamDownstreamNodePosition.upstream(),
            ),
          );

          // Select all content.
          if (CurrentPlatform.isApple) {
            await tester.pressCmdA();
          } else {
            await tester.pressCtlA();
          }

          // Ensure everything is selected.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '1',
                nodePosition: UpstreamDownstreamNodePosition.upstream(),
              ),
              extent: DocumentPosition(
                nodeId: '3',
                nodePosition: UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
          );

          // Try to delete all content.
          await tester.pressDelete();

          final document = SuperEditorInspector.findDocument()!;

          // Ensure nothing was deleted.
          expect(document.nodeCount, equals(3));
          expect(document.getNodeAt(0), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(1), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(2), isA<HorizontalRuleNode>());

          // Ensure the selection was kept.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '1',
                nodePosition: UpstreamDownstreamNodePosition.upstream(),
              ),
              extent: DocumentPosition(
                nodeId: '3',
                nodePosition: UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('when all nodes in selection are non-deletable and document contains deletable nodes',
            (tester) async {
          final testContext = await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    ParagraphNode(id: '1', text: AttributedText()),
                    HorizontalRuleNode(id: '2', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    HorizontalRuleNode(id: '3', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    HorizontalRuleNode(id: '4', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    ParagraphNode(id: '5', text: AttributedText()),
                  ],
                ),
              )
              .pump();

          // Select the first horizontal rule.
          await tester.tapAtDocumentPosition(
            const DocumentPosition(
              nodeId: "2",
              nodePosition: UpstreamDownstreamNodePosition.upstream(),
            ),
          );

          // Select all non-deletable nodes.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: '2',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
                extent: DocumentPosition(
                  nodeId: '4',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Try to delete all content.
          await tester.pressDelete();

          final document = SuperEditorInspector.findDocument()!;

          // Ensure nothing was deleted.
          expect(document.nodeCount, equals(5));
          expect(document.getNodeAt(0), isA<ParagraphNode>());
          expect(document.getNodeAt(1), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(2), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(3), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(4), isA<ParagraphNode>());

          // Ensure the selection was kept.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '2',
                nodePosition: UpstreamDownstreamNodePosition.upstream(),
              ),
              extent: DocumentPosition(
                nodeId: '4',
                nodePosition: UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
          );
        });
      });

      group('when typing', () {
        testWidgetsOnDesktop('with multiple nodes selected', (tester) async {
          final testContext = await _pumpMultipleDeletableAndUndeletableNodesTestApp(tester);

          // Select from "Para>graph 1" to "Paragraph <3".
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
                extent: DocumentPosition(
                  nodeId: '3',
                  nodePosition: TextNodePosition(offset: 10),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Type a character to replace the selected nodes.
          await tester.typeImeText('X');

          // Ensure that the deletable content was deleted and the text was inserted at the upstream
          // edge of the selection.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.nodeCount, 4);
          expect(SuperEditorInspector.findTextInComponent('1'), AttributedText('ParaX3'));
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 5)),
              ),
            ),
          );

          // Ensure that the undeletable content was not deleted.
          expect(document.getNodeById('hr1'), isNotNull);
          expect(document.getNodeById('hr1'), isA<HorizontalRuleNode>());

          expect(document.getNodeById('hr2'), isNotNull);
          expect(document.getNodeById('hr2'), isA<HorizontalRuleNode>());

          expect(document.getNodeById('hr3'), isNotNull);
          expect(document.getNodeById('hr3'), isA<HorizontalRuleNode>());
        });
      });

      group('with backspace in software keyboard', () {
        testWidgetsOnMobile('for downstream selection', (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          // Select the whole hr. Use a command instead of a user gesture to have
          // precise control over the selection.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
                extent: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Simulate the user pressing backspace. The IME first generates a
          // selection change and then a deletion. Each block node is represented by a "~"
          // in the IME.
          await tester.ime.sendDeltas([
            const TextEditingDeltaNonTextUpdate(
              oldText: '. ~',
              selection: TextSelection(baseOffset: 2, extentOffset: 3),
              composing: TextRange(start: -1, end: -1),
            ),
            const TextEditingDeltaDeletion(
              oldText: '. ~',
              deletedRange: TextSelection(baseOffset: 2, extentOffset: 3),
              selection: TextSelection.collapsed(offset: 2),
              composing: TextRange(start: -1, end: -1),
            ),
          ], getter: imeClientGetter);

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnMobile('for upstream selection', (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          // Select the whole hr. Use a command instead of a user gesture to have
          // precise control over the selection.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
                extent: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Simulate the user pressing backspace. The IME first generates a
          // selection change and then a deletion. Each block node is represented by a "~"
          // in the IME.
          await tester.ime.sendDeltas([
            const TextEditingDeltaNonTextUpdate(
              oldText: '. ~',
              selection: TextSelection(baseOffset: 2, extentOffset: 3),
              composing: TextRange(start: -1, end: -1),
            ),
            const TextEditingDeltaDeletion(
              oldText: '. ~',
              deletedRange: TextSelection(baseOffset: 2, extentOffset: 3),
              selection: TextSelection.collapsed(offset: 2),
              composing: TextRange(start: -1, end: -1),
            ),
          ], getter: imeClientGetter);

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnMobile('when multiple deletable and undeletable nodes are selected', (tester) async {
          final testContext = await _pumpMultipleDeletableAndUndeletableNodesTestApp(tester);

          // Select from "Para>graph 1" to "Paragraph <3".
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
                extent: DocumentPosition(
                  nodeId: '3',
                  nodePosition: TextNodePosition(offset: 10),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Simulate the user pressing backspace. The IME first generates a
          // selection change and then a deletion. Each block node is represented by a "~"
          // in the IME.
          await tester.ime.sendDeltas([
            const TextEditingDeltaNonTextUpdate(
              oldText: '. Paragraph 1\n~\n~\nParagraph 2\n~\nParagraph 3',
              selection: TextSelection(baseOffset: 6, extentOffset: 42),
              composing: TextRange(start: -1, end: -1),
            ),
            const TextEditingDeltaDeletion(
              oldText: '. Paragraph 1\n~\n~\nParagraph 2\n~\nParagraph 3',
              deletedRange: TextSelection(baseOffset: 6, extentOffset: 42),
              selection: TextSelection.collapsed(offset: 6),
              composing: TextRange(start: -1, end: -1),
            ),
          ], getter: imeClientGetter);

          // Ensure that the deletable content was deleted and selection moved to upstream edge
          // of the first deletable node.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.nodeCount, 4);
          expect(SuperEditorInspector.findTextInComponent('1'), AttributedText('Para3'));
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 4)),
              ),
            ),
          );

          // Ensure that the undeletable content was not deleted.
          expect(document.getNodeById('hr1'), isNotNull);
          expect(document.getNodeById('hr1'), isA<HorizontalRuleNode>());

          expect(document.getNodeById('hr2'), isNotNull);
          expect(document.getNodeById('hr2'), isA<HorizontalRuleNode>());

          expect(document.getNodeById('hr3'), isNotNull);
          expect(document.getNodeById('hr3'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnMobile('when selection starts at upstream edge and ends at a downstream deletable node',
            (tester) async {
          final testContext = await _pumpHrThenParagraphTestApp(tester);

          // Select from the upstream edge of the horizontal rule to "Para|graph 1".
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
                extent: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Simulate the user pressing backspace. The IME first generates a
          // selection change and then a deletion. Each block node is represented by a "~"
          // in the IME.
          await tester.ime.sendDeltas([
            const TextEditingDeltaNonTextUpdate(
              oldText: '. ~\nParagraph 1',
              selection: TextSelection(baseOffset: 2, extentOffset: 8),
              composing: TextRange(start: -1, end: -1),
            ),
            const TextEditingDeltaDeletion(
              oldText: '. ~\nParagraph 1',
              deletedRange: TextSelection(baseOffset: 2, extentOffset: 8),
              selection: TextSelection.collapsed(offset: 6),
              composing: TextRange(start: -1, end: -1),
            ),
          ], getter: imeClientGetter);

          // Ensure that the deletable content was deleted and selection moved to the beginning
          // of the selected paragraph.
          expect(
            SuperEditorInspector.findTextInComponent('1').toPlainText(),
            'graph 1',
          );
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 0)),
              ),
            ),
          );

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnMobile('when selection starts at downstream edge and ends at an upstream deletable node',
            (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          // Select from the downstream edge of the horizontal rule to "Para|graph 1".
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
                extent: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Simulate the user pressing backspace. The IME first generates a
          // selection change and then a deletion. Each block node is represented by a "~"
          // in the IME.
          await tester.ime.sendDeltas([
            const TextEditingDeltaNonTextUpdate(
              oldText: '. Paragraph 1\n~',
              selection: TextSelection(baseOffset: 15, extentOffset: 6),
              composing: TextRange(start: -1, end: -1),
            ),
            const TextEditingDeltaDeletion(
              oldText: '. Paragraph 1\n~',
              deletedRange: TextSelection(baseOffset: 15, extentOffset: 6),
              selection: TextSelection.collapsed(offset: 6),
              composing: TextRange(start: -1, end: -1),
            ),
          ], getter: imeClientGetter);

          // Ensure that the deletable content was deleted and selection moved to the upstream edge
          // of the selection
          expect(
            SuperEditorInspector.findTextInComponent('1').toPlainText(),
            'Para',
          );
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 4)),
              ),
            ),
          );

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnMobile('when selection starts at an upstream deletable node and ends at the downstream edge',
            (tester) async {
          final testContext = await _pumpParagraphThenHrTestApp(tester);

          // Select from the "Para|graph 1" to the downstream edge of the horizontal rule.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
                extent: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Simulate the user pressing backspace. The IME first generates a
          // selection change and then a deletion. Each block node is represented by a "~"
          // in the IME.
          await tester.ime.sendDeltas([
            const TextEditingDeltaNonTextUpdate(
              oldText: '. Paragraph 1\n~',
              selection: TextSelection(baseOffset: 6, extentOffset: 15),
              composing: TextRange(start: -1, end: -1),
            ),
            const TextEditingDeltaDeletion(
              oldText: '. Paragraph 1\n~',
              deletedRange: TextSelection(baseOffset: 6, extentOffset: 15),
              selection: TextSelection.collapsed(offset: 6),
              composing: TextRange(start: -1, end: -1),
            ),
          ], getter: imeClientGetter);

          // Ensure that the deletable content was deleted and selection moved to the beginning
          // of the selected paragraph.
          expect(SuperEditorInspector.findTextInComponent('1').toPlainText(), 'Para');
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 4)),
              ),
            ),
          );

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnMobile('when selection starts at a downstream deletable node and ends at the upstream edge',
            (tester) async {
          final testContext = await _pumpHrThenParagraphTestApp(tester);

          // Select from the "Para|graph 1" to the upstream edge of the second horizontal rule.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: '1',
                  nodePosition: TextNodePosition(offset: 4),
                ),
                extent: DocumentPosition(
                  nodeId: 'hr',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Simulate the user pressing backspace. The IME first generates a
          // selection change and then a deletion. Each block node is represented by a "~"
          // in the IME.
          await tester.ime.sendDeltas([
            const TextEditingDeltaNonTextUpdate(
              oldText: '. ~\nParagraph 1',
              selection: TextSelection(baseOffset: 8, extentOffset: 2),
              composing: TextRange(start: -1, end: -1),
            ),
            const TextEditingDeltaDeletion(
              oldText: '. ~\nParagraph 1',
              deletedRange: TextSelection(baseOffset: 8, extentOffset: 2),
              selection: TextSelection.collapsed(offset: 2),
              composing: TextRange(start: -1, end: -1),
            ),
          ], getter: imeClientGetter);

          // Ensure that the deletable content was deleted and selection moved to the beginning
          // of the selected paragraph.
          expect(SuperEditorInspector.findTextInComponent('1').toPlainText(), 'graph 1');
          expect(
            SuperEditorInspector.findDocumentSelection(),
            selectionEquivalentTo(
              const DocumentSelection.collapsed(
                position: DocumentPosition(nodeId: '1', nodePosition: TextNodePosition(offset: 0)),
              ),
            ),
          );

          // Ensure that the horizontal rule was not deleted.
          final document = SuperEditorInspector.findDocument()!;
          expect(document.getNodeById('hr'), isNotNull);
          expect(document.getNodeById('hr'), isA<HorizontalRuleNode>());
        });

        testWidgetsOnMobile('when the whole document is selected and starts with a non-deletable node', (tester) async {
          await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    HorizontalRuleNode(id: '1', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    ParagraphNode(
                      id: '2',
                      text: AttributedText('This is some text'),
                    ),
                  ],
                ),
              )
              .pump();

          // Place the caret at the beginning of the paragraph.
          await tester.placeCaretInParagraph("2", 0);

          // Select all content.
          if (CurrentPlatform.isApple) {
            await tester.pressCmdA();
          } else {
            await tester.pressCtlA();
          }

          // Simulate the user pressing backspace. The IME first generates a
          // selection change and then a deletion. Each block node is represented by a "~"
          // in the IME.
          await tester.ime.sendDeltas([
            const TextEditingDeltaNonTextUpdate(
              oldText: '. ~\nThis is some text',
              selection: TextSelection(baseOffset: 0, extentOffset: 21),
              composing: TextRange.empty,
            ),
            const TextEditingDeltaDeletion(
              oldText: '. ~\nThis is some text',
              deletedRange: TextSelection(baseOffset: 0, extentOffset: 21),
              selection: TextSelection.collapsed(offset: 0),
              composing: TextRange.empty,
            ),
          ], getter: imeClientGetter);

          final document = SuperEditorInspector.findDocument()!;

          // Ensure the horizontal rule was kept, the paragraph was deleted,
          // and a new empty paragraph was added to the end of the document.
          expect(document.nodeCount, equals(2));
          expect(document.first, isA<HorizontalRuleNode>());
          expect(document.last, isA<ParagraphNode>());
          expect((document.last as TextNode).text.toPlainText(), equals(''));

          // Ensure the caret was placed at the beginning of the newly inserted paragraph.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: document.last.id,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
          );
        });

        testWidgetsOnMobile('when the whole document is selected and ends with a non-deletable node', (tester) async {
          await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    ParagraphNode(
                      id: '1',
                      text: AttributedText('This is some text'),
                    ),
                    HorizontalRuleNode(id: '2', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                  ],
                ),
              )
              .pump();

          // Place the caret at the beginning of the paragraph.
          await tester.placeCaretInParagraph("1", 0);

          // Select all content.
          if (CurrentPlatform.isApple) {
            await tester.pressCmdA();
          } else {
            await tester.pressCtlA();
          }
          await tester.pump();

          // Simulate the user pressing backspace. The IME first generates a
          // selection change and then a deletion. Each block node is represented by a "~"
          // in the IME.
          await tester.ime.sendDeltas([
            const TextEditingDeltaNonTextUpdate(
              oldText: '. This is some text\n~',
              selection: TextSelection(baseOffset: 0, extentOffset: 21),
              composing: TextRange.empty,
            ),
            const TextEditingDeltaDeletion(
              oldText: '. This is some text\n~',
              deletedRange: TextSelection(baseOffset: 0, extentOffset: 21),
              selection: TextSelection.collapsed(offset: 0),
              composing: TextRange.empty,
            ),
          ], getter: imeClientGetter);

          final document = SuperEditorInspector.findDocument()!;

          // Ensure the horizontal rule was kept, the paragraph was deleted,
          // and a new empty paragraph was added to the end of the document.
          expect(document.nodeCount, equals(2));
          expect(document.first, isA<HorizontalRuleNode>());
          expect(document.last, isA<ParagraphNode>());
          expect((document.last as TextNode).text.toPlainText(), equals(''));

          // Ensure the caret was placed at the beginning of the newly inserted paragraph.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: document.last.id,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('when the whole document is selected and starts and ends with non-deletable nodes',
            (tester) async {
          await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    HorizontalRuleNode(id: '1', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    ParagraphNode(
                      id: '2',
                      text: AttributedText('This is some text'),
                    ),
                    HorizontalRuleNode(id: '3', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                  ],
                ),
              )
              .pump();

          await tester.placeCaretInParagraph("2", 0);

          // Select all content.
          if (CurrentPlatform.isApple) {
            await tester.pressCmdA();
          } else {
            await tester.pressCtlA();
          }

          // Ensure everything is selected.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '1',
                nodePosition: UpstreamDownstreamNodePosition.upstream(),
              ),
              extent: DocumentPosition(
                nodeId: '3',
                nodePosition: UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
          );

          // Simulate the user pressing backspace. The IME first generates a
          // selection change and then a deletion. Each block node is represented by a "~"
          // in the IME.
          await tester.ime.sendDeltas([
            const TextEditingDeltaNonTextUpdate(
              oldText: '. ~\nThis is some text\n~',
              selection: TextSelection(baseOffset: 0, extentOffset: 23),
              composing: TextRange.empty,
            ),
            const TextEditingDeltaDeletion(
              oldText: '. ~\nThis is some text\n~',
              deletedRange: TextSelection(baseOffset: 0, extentOffset: 23),
              selection: TextSelection.collapsed(offset: 0),
              composing: TextRange.empty,
            ),
          ], getter: imeClientGetter);

          final document = SuperEditorInspector.findDocument()!;

          // Ensure the horizontal rules were kept, the paragraph was deleted,
          // and a new empty paragraph was added to the end of the document.
          expect(document.nodeCount, equals(3));
          expect(document.getNodeAt(0), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(1), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(2), isA<ParagraphNode>());
          expect((document.last as TextNode).text.toPlainText(), equals(''));

          // Ensure the caret was placed at the beginning of the newly inserted paragraph.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: document.last.id,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
          );
        });

        testWidgetsOnMobile('when all nodes are non-deletable', (tester) async {
          await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    HorizontalRuleNode(id: '1', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    HorizontalRuleNode(id: '2', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    HorizontalRuleNode(id: '3', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                  ],
                ),
              )
              .pump();

          // Select the first horizontal rule.
          await tester.tapAtDocumentPosition(
            const DocumentPosition(
              nodeId: "1",
              nodePosition: UpstreamDownstreamNodePosition.upstream(),
            ),
          );

          // Select all content.
          if (CurrentPlatform.isApple) {
            await tester.pressCmdA();
          } else {
            await tester.pressCtlA();
          }

          // Simulate the user pressing backspace. The IME first generates a
          // selection change and then a deletion. Each block node is represented by a "~"
          // in the IME.
          await tester.ime.sendDeltas([
            const TextEditingDeltaNonTextUpdate(
              oldText: '. ~\n~\n~',
              selection: TextSelection(baseOffset: 0, extentOffset: 7),
              composing: TextRange.empty,
            ),
            const TextEditingDeltaDeletion(
              oldText: '. ~\n~\n~',
              deletedRange: TextSelection(baseOffset: 0, extentOffset: 7),
              selection: TextSelection.collapsed(offset: 0),
              composing: TextRange.empty,
            ),
          ], getter: imeClientGetter);

          final document = SuperEditorInspector.findDocument()!;

          // Ensure nothing was deleted.
          expect(document.nodeCount, equals(3));
          expect(document.getNodeAt(0), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(1), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(2), isA<HorizontalRuleNode>());

          // Ensure the selection was kept.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '1',
                nodePosition: UpstreamDownstreamNodePosition.upstream(),
              ),
              extent: DocumentPosition(
                nodeId: '3',
                nodePosition: UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
          );
        });

        testWidgetsOnDesktop('when all nodes in selection are non-deletable and document contains deletable nodes',
            (tester) async {
          final testContext = await tester //
              .createDocument()
              .withCustomContent(
                MutableDocument(
                  nodes: [
                    ParagraphNode(id: '1', text: AttributedText()),
                    HorizontalRuleNode(id: '2', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    HorizontalRuleNode(id: '3', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    HorizontalRuleNode(id: '4', metadata: {
                      NodeMetadata.isDeletable: false,
                    }),
                    ParagraphNode(id: '5', text: AttributedText()),
                  ],
                ),
              )
              .pump();

          // Select the first horizontal rule.
          await tester.tapAtDocumentPosition(
            const DocumentPosition(
              nodeId: "2",
              nodePosition: UpstreamDownstreamNodePosition.upstream(),
            ),
          );

          // Select all non-deletable nodes.
          testContext.editor.execute([
            const ChangeSelectionRequest(
              DocumentSelection(
                base: DocumentPosition(
                  nodeId: '2',
                  nodePosition: UpstreamDownstreamNodePosition.upstream(),
                ),
                extent: DocumentPosition(
                  nodeId: '4',
                  nodePosition: UpstreamDownstreamNodePosition.downstream(),
                ),
              ),
              SelectionChangeType.expandSelection,
              SelectionReason.userInteraction,
            )
          ]);
          await tester.pump();

          // Simulate the user pressing backspace. The IME first generates a
          // selection change and then a deletion. Each block node is represented by a "~"
          // in the IME.
          await tester.ime.sendDeltas([
            const TextEditingDeltaNonTextUpdate(
              oldText: '. ~\n~\n~',
              selection: TextSelection(baseOffset: 0, extentOffset: 7),
              composing: TextRange.empty,
            ),
            const TextEditingDeltaDeletion(
              oldText: '. ~\n~\n~',
              deletedRange: TextSelection(baseOffset: 0, extentOffset: 7),
              selection: TextSelection.collapsed(offset: 0),
              composing: TextRange.empty,
            ),
          ], getter: imeClientGetter);

          final document = SuperEditorInspector.findDocument()!;

          // Ensure nothing was deleted.
          expect(document.nodeCount, equals(5));
          expect(document.getNodeAt(0), isA<ParagraphNode>());
          expect(document.getNodeAt(1), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(2), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(3), isA<HorizontalRuleNode>());
          expect(document.getNodeAt(4), isA<ParagraphNode>());

          // Ensure the selection was kept.
          expect(
            SuperEditorInspector.findDocumentSelection(),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: '2',
                nodePosition: UpstreamDownstreamNodePosition.upstream(),
              ),
              extent: DocumentPosition(
                nodeId: '4',
                nodePosition: UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
          );
        });
      });
    });
  });
}

/// Pumps a widget tree with a paragraph followed by a non-deletable horizontal rule.
Future<TestDocumentContext> _pumpParagraphThenHrTestApp(WidgetTester tester) async {
  return await tester
      .createDocument()
      .withCustomContent(
        MutableDocument(
          nodes: [
            ParagraphNode(
              id: '1',
              text: AttributedText('Paragraph 1'),
            ),
            HorizontalRuleNode(id: 'hr', metadata: {
              NodeMetadata.isDeletable: false,
            }),
          ],
        ),
      )
      .withInputSource(TextInputSource.ime)
      .autoFocus(true)
      .pump();
}

/// Pumps a widget tree with a non-deletable horizontal rule followed by a paragraph.
Future<TestDocumentContext> _pumpHrThenParagraphTestApp(WidgetTester tester) async {
  return await tester
      .createDocument()
      .withCustomContent(
        MutableDocument(
          nodes: [
            HorizontalRuleNode(id: 'hr', metadata: {
              NodeMetadata.isDeletable: false,
            }),
            ParagraphNode(
              id: '1',
              text: AttributedText('Paragraph 1'),
            ),
          ],
        ),
      )
      .withInputSource(TextInputSource.ime)
      .autoFocus(true)
      .pump();
}

/// Pumps a widget tree with containing:
/// - Paragraph
/// - Horizontal rule (non-selectable, non-deletable)
/// - Paragraph
Future<TestDocumentContext> _pumpParagraphThenHrThenParagraphTestApp(WidgetTester tester) async {
  return await tester
      .createDocument()
      .withCustomContent(
        MutableDocument(
          nodes: [
            ParagraphNode(
              id: '1',
              text: AttributedText('Paragraph 1'),
            ),
            HorizontalRuleNode(id: 'hr', metadata: {
              NodeMetadata.isDeletable: false,
            }),
            ParagraphNode(
              id: '2',
              text: AttributedText('Paragraph 2'),
            ),
          ],
        ),
      )
      .withAddedComponents([const _UnselectableHrComponentBuilder()])
      .withInputSource(TextInputSource.ime)
      .autoFocus(true)
      .pump();
}

/// Pumps a widget tree containing:
///
/// - Paragraph.
/// - Horizontal rule.
/// - Horizontal rule.
/// - Paragraph.
/// - Horizontal rule.
/// - Paragraph.
Future<TestDocumentContext> _pumpMultipleDeletableAndUndeletableNodesTestApp(WidgetTester tester) async {
  return await tester
      .createDocument()
      .withCustomContent(
        MutableDocument(
          nodes: [
            ParagraphNode(
              id: '1',
              text: AttributedText('Paragraph 1'),
            ),
            HorizontalRuleNode(id: 'hr1', metadata: {
              NodeMetadata.isDeletable: false,
            }),
            HorizontalRuleNode(id: 'hr2', metadata: {
              NodeMetadata.isDeletable: false,
            }),
            ParagraphNode(
              id: '2',
              text: AttributedText('Paragraph 2'),
            ),
            HorizontalRuleNode(id: 'hr3', metadata: {
              NodeMetadata.isDeletable: false,
            }),
            ParagraphNode(
              id: '3',
              text: AttributedText('Paragraph 3'),
            ),
          ],
        ),
      )
      .withInputSource(TextInputSource.ime)
      .autoFocus(true)
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
    return BoxComponent(
      key: componentKey,
      isVisuallySelectable: false,
      child: const Divider(
        color: Color(0xFF000000),
        thickness: 1.0,
      ),
    );
  }
}
