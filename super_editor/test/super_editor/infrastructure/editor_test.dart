import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import '../../super_editor/supereditor_test_tools.dart';
import '../../super_editor/test_documents.dart';

void main() {
  group('DocumentEditor', () {
    group('editing', () {
      // TODO: test that Document gets notified of changes before Composer, because selection
      //       is based on document structure, not the other way around

      test('throws exception when there is no command for a given request', () {
        final editor = Editor(
          editables: {
            Editor.documentKey: MutableDocument.empty(),
          },
          requestHandlers: [],
        );

        expectLater(() {
          editor.execute([InsertCharacterAtCaretRequest(character: "a")]);
        }, throwsException);
      });

      test('executes a single command', () {
        final editorPieces = _createStandardEditor(
          initialSelection: TextNode.caretAt(["1"], 0),
        );
        List<EditEvent>? changeLog;
        editorPieces.editor.addListener(FunctionalEditListener((changeList) {
          changeLog = changeList;
        }));

        editorPieces.editor.execute([InsertCharacterAtCaretRequest(character: "a")]);

        expect(changeLog, isNotNull);
        expect(changeLog!.length, 2);
        expect(changeLog!.first, isA<DocumentEdit>());
        expect((changeLog!.first as DocumentEdit).change, isA<NodeChangeEvent>());
        expect(changeLog!.last, isA<SelectionChangeEvent>());
      });

      test('executes a series of commands', () {
        final editorPieces = _createStandardEditor(
          initialSelection: TextNode.caretAt(["1"], 0),
        );
        int changeLogCount = 0;
        int changeEventCount = 0;
        editorPieces.editor.addListener(FunctionalEditListener((changeList) {
          changeLogCount += 1;
          changeEventCount += changeList.length;
        }));

        editorPieces.editor
          ..execute([InsertCharacterAtCaretRequest(character: "H")])
          ..execute([InsertCharacterAtCaretRequest(character: "e")])
          ..execute([InsertCharacterAtCaretRequest(character: "l")])
          ..execute([InsertCharacterAtCaretRequest(character: "l")])
          ..execute([InsertCharacterAtCaretRequest(character: "o")]);

        expect(changeLogCount, 5);
        expect(changeEventCount, 10); // 2 events per character insertion
        expect((editorPieces.document.getNodeAt(0) as ParagraphNode).text.toPlainText(), "Hello");
      });

      test('executes multiple expanding commands', () {
        // This test ensures that if one command expands into multiple commands,
        // and those commands expand to additional commands, the overall command
        // order is what we expect.
        List<EditEvent>? changeList;
        final document = MutableDocument.empty();

        final composer = MutableDocumentComposer(
          initialSelection: TextNode.caretAt(["1"], 0),
        );
        final editor = Editor(
          editables: {
            Editor.documentKey: document,
            Editor.composerKey: composer,
          },
          requestHandlers: [
            (editor, request) => request is _ExpandingCommandRequest //
                ? _ExpandingCommand(request)
                : null,
          ],
          listeners: [
            FunctionalEditListener((newChangeList) {
              changeList = newChangeList;
            }),
          ],
        );

        editor.execute([
          const _ExpandingCommandRequest(
            generationId: 0,
            batchId: 0,
            newCommandCount: 3,
            levelsOfGeneration: 2,
          ),
        ]);

        // Ensure that the commands printed the number and spacing that we expected,
        // given the expansion order.
        //
        // Each value is "(a.b)" where "a" is the generation, and "b" is the batch ID
        // within the generation. The output should look like a depth first tree
        // traversal.
        final paragraph = document.getNodeAt(0) as ParagraphNode;
        expect(
          paragraph.text.toPlainText(),
          '''(0.0)
  (1.0)
    (2.0)
    (2.1)
    (2.2)
  (1.1)
    (2.0)
    (2.1)
    (2.2)
  (1.2)
    (2.0)
    (2.1)
    (2.2)''',
        );

        expect(changeList, isNotNull);
        expect(changeList!.length, 13 * 2); // 13 commands * 2 events per command
      });

      test('runs reactions after a command', () {
        int reactionCount = 0;

        final document = MutableDocument.empty("1");

        final composer = MutableDocumentComposer(
          initialSelection: TextNode.caretAt(["1"], 0),
        );
        final editor = Editor(
          editables: {
            Editor.documentKey: document,
            Editor.composerKey: composer,
          },
          requestHandlers: List.from(defaultRequestHandlers),
          reactionPipeline: [
            FunctionalEditReaction(
              react: (editorContext, requestDispatcher, changeList) {
                reactionCount += 1;
              },
            ),
          ],
        );

        editor.execute([
          InsertTextRequest(
            documentPosition: DocumentPosition(
              documentPath: NodePath.forNode("1"),
              nodePosition: const TextNodePosition(offset: 0),
            ),
            textToInsert: "H",
            attributions: const {},
          ),
        ]);

        // Ensure that our reaction ran after the requested command.
        expect(reactionCount, 1);
      });

      test('interrupts back-to-back commands to run a reaction', () {
        final document = MutableDocument.empty("1");

        final composer = MutableDocumentComposer(
          initialSelection: TextNode.caretAt(["1"], 0),
        );

        final editor = Editor(
          editables: {
            Editor.documentKey: document,
            Editor.composerKey: composer,
          },
          requestHandlers: List.from(defaultRequestHandlers),
          reactionPipeline: [
            FunctionalEditReaction(react: (editorContext, requestDispatcher, changeList) {
              TextInsertionEvent? insertEEvent;
              for (final edit in changeList) {
                if (edit is! DocumentEdit) {
                  continue;
                }
                final change = edit.change;
                if (change is! TextInsertionEvent) {
                  continue;
                }

                insertEEvent = change.text.toPlainText().endsWith("e") ? change : null;
              }

              if (insertEEvent == null) {
                return;
              }

              // Insert "ll" after "e" to get "Hello" when all the commands are done.
              requestDispatcher.execute([
                InsertTextRequest(
                  documentPosition: DocumentPosition(
                    documentPath: NodePath.forNode(insertEEvent.nodeId),
                    nodePosition: TextNodePosition(offset: insertEEvent.offset + 1), // +1 for "e"
                  ),
                  textToInsert: "ll",
                  attributions: {},
                ),
              ]);
            }),
          ],
        );

        editor
          ..execute([
            InsertTextRequest(
              documentPosition: DocumentPosition(
                documentPath: NodePath.forNode("1"),
                nodePosition: const TextNodePosition(offset: 0),
              ),
              textToInsert: "H",
              attributions: const {},
            ),
          ])
          ..execute([
            InsertTextRequest(
              documentPosition: DocumentPosition(
                documentPath: NodePath.forNode("1"),
                nodePosition: const TextNodePosition(offset: 1),
              ),
              textToInsert: "e",
              attributions: const {},
            ),
          ])
          ..execute([
            InsertTextRequest(
              documentPosition: DocumentPosition(
                documentPath: NodePath.forNode("1"),
                nodePosition: const TextNodePosition(offset: 4),
              ),
              textToInsert: "o",
              attributions: const {},
            ),
          ]);

        // Ensure that our reaction ran in the middle of the requests.
        expect((document.first as TextNode).text.toPlainText(), "Hello");
      });

      test('reactions receive a change list with events from earlier reactions', () {
        final document = MutableDocument.empty("1");

        final composer = MutableDocumentComposer(
          initialSelection: TextNode.caretAt(["1"], 0),
        );

        final editor = Editor(
          editables: {
            Editor.documentKey: document,
            Editor.composerKey: composer,
          },
          requestHandlers: List.from(defaultRequestHandlers),
          reactionPipeline: [
            // Reaction 1 causes a change
            FunctionalEditReaction(react: (editorContext, requestDispatcher, changeList) {
              TextInsertionEvent? insertHEvent;
              for (final edit in changeList) {
                if (edit is! DocumentEdit) {
                  continue;
                }
                final change = edit.change;
                if (change is! TextInsertionEvent) {
                  continue;
                }

                insertHEvent = change.text.toPlainText() == "H" ? change : null;
              }

              if (insertHEvent == null) {
                return;
              }

              // Insert "e" after "H".
              requestDispatcher.execute([
                InsertTextRequest(
                  documentPosition: DocumentPosition(
                    documentPath: NodePath.forNode(insertHEvent.nodeId),
                    nodePosition: TextNodePosition(offset: insertHEvent.offset),
                  ),
                  textToInsert: "e",
                  attributions: {},
                ),
              ]);
            }),
            // Reaction 2 verifies that it sees the change event from reaction 1.
            FunctionalEditReaction(react: (editorContext, requestDispatcher, changeList) {
              TextInsertionEvent? insertEEvent;
              for (final edit in changeList) {
                if (edit is! DocumentEdit) {
                  continue;
                }
                final change = edit.change;
                if (change is! TextInsertionEvent) {
                  continue;
                }

                insertEEvent = change.text.toPlainText() == "e" ? change : null;
              }

              expect(insertEEvent, isNotNull, reason: "Reaction 2 didn't receive the change from reaction 1");
            }),
          ],
        );

        editor.execute([
          InsertTextRequest(
            documentPosition: DocumentPosition(
              documentPath: NodePath.forNode("1"),
              nodePosition: const TextNodePosition(offset: 0),
            ),
            textToInsert: "H",
            attributions: const {},
          ),
        ]);

        // If execution makes it here then the test is successful.
      });

      test('reactions do not run in response to reactions', () {
        final document = MutableDocument.empty("1");

        final composer = MutableDocumentComposer(
          initialSelection: TextNode.caretAt(["1"], 0),
        );

        int reactionRunCount = 0;

        final editor = Editor(
          editables: {
            Editor.documentKey: document,
            Editor.composerKey: composer,
          },
          requestHandlers: List.from(defaultRequestHandlers),
          reactionPipeline: [
            FunctionalEditReaction(react: (editorContext, requestDispatcher, changeList) {
              reactionRunCount += 1;

              // We expect this reaction to run after we execute a command, but we don't
              // expect this reaction to react to its own command.
              expect(reactionRunCount, lessThan(2));

              // Insert "e" after "H".
              requestDispatcher.execute([
                InsertTextRequest(
                  documentPosition: DocumentPosition(
                    documentPath: NodePath.forNode("1"),
                    nodePosition: const TextNodePosition(offset: 1),
                  ),
                  textToInsert: "e",
                  attributions: {},
                ),
                InsertTextRequest(
                  documentPosition: DocumentPosition(
                    documentPath: NodePath.forNode("1"),
                    nodePosition: const TextNodePosition(offset: 2),
                  ),
                  textToInsert: "l",
                  attributions: {},
                ),
              ]);
            }),
          ],
        );

        editor.execute([
          InsertTextRequest(
            documentPosition: DocumentPosition(
              documentPath: NodePath.forNode("1"),
              nodePosition: const TextNodePosition(offset: 0),
            ),
            textToInsert: "H",
            attributions: const {},
          ),
        ]);

        // Ensure that our reaction ran once, but only once.
        expect(reactionRunCount, 1);
      });

      test('inserts character at caret', () {
        final editorPieces = _createStandardEditor(
          initialSelection: TextNode.caretAt(["1"], 0),
        );

        editorPieces.editor
          ..execute([
            InsertTextRequest(
              documentPosition: DocumentPosition(
                documentPath: NodePath.forNode("1"),
                nodePosition: const TextNodePosition(offset: 0),
              ),
              textToInsert: 'H',
              attributions: const {},
            ),
          ])
          ..execute([
            ChangeSelectionRequest(
              TextNode.caretAt(["1"], 1),
              SelectionChangeType.placeCaret,
              "test",
            ),
          ]);

        // Ensure the character was inserted, and the caret moved forward.
        expect((editorPieces.document.getNodeAt(0) as TextNode).text.toPlainText(), "H");
        expect(editorPieces.composer.selection, isNotNull);
        expect(
          editorPieces.composer.selection,
          TextNode.caretAt(["1"], 1),
        );
      });

      test('inserts new paragraph node at caret', () {
        final editorPieces = _createStandardEditor(
          initialSelection: TextNode.caretAt(["1"], 0),
        );
        int changeLogCount = 0;
        int changeEventCount = 0;
        final document = editorPieces.document;
        editorPieces.editor.addListener(FunctionalEditListener((changeList) {
          changeLogCount += 1;
          changeEventCount += changeList.length;
        }));

        editorPieces.editor.execute([
          SplitParagraphRequest(
            nodeId: "1",
            splitPosition: const TextNodePosition(offset: 0),
            newNodeId: "2",
            replicateExistingMetadata: true,
          )
        ]);

        // Verify content changes.
        expect(document.nodeCount, 2);
        expect(document.getNodeAt(0)!.id, "1");
        expect(document.getNodeAt(1)!.id, "2");

        // Verify reported changes.
        expect(changeLogCount, 1);
        // Expected events:
        //  - submit paragraph intention: start
        //  - node change event: node 1
        //  - node inserted event
        //  - selection change event
        //  - composing region change event
        //  - submit paragraph intention: end
        expect(changeEventCount, 6);
      });

      test('moves a document node to a higher index', () {
        final editorPieces = _createStandardEditor(
          initialDocument: longTextDoc(),
          initialSelection: TextNode.caretAt(["1"], 0),
        );

        int changeLogCount = 0;
        int changeEventCount = 0;
        editorPieces.editor.addListener(FunctionalEditListener((changeList) {
          changeLogCount += 1;
          changeEventCount += changeList.length;
        }));

        late DocumentChangeLog documentChangeLog;
        editorPieces.document.addListener((changeLog) {
          documentChangeLog = changeLog;
        });

        editorPieces.editor.execute([const MoveNodeRequest(nodeId: "1", newIndex: 2)]);

        // Verify final node indices.
        expect(editorPieces.document.getNodeAt(0)!.id, "2");
        expect(editorPieces.document.getNodeAt(1)!.id, "3");
        expect(editorPieces.document.getNodeAt(2)!.id, "1");
        expect(editorPieces.document.getNodeAt(3)!.id, "4");

        // Verify reported editor changes.
        expect(changeLogCount, 1);
        expect(changeEventCount, 3); // 3 nodes were moved

        // Verify reported document changes.
        expect(
          documentChangeLog.changes,
          [
            const NodeMovedEvent(nodeId: "1", from: 0, to: 2),
            const NodeMovedEvent(nodeId: "2", from: 1, to: 0),
            const NodeMovedEvent(nodeId: "3", from: 2, to: 1),
          ],
        );
      });

      test('moves a document node to a lower index', () {
        final editorPieces = _createStandardEditor(
          initialDocument: longTextDoc(),
          initialSelection: TextNode.caretAt(["1"], 0),
        );

        int changeLogCount = 0;
        int changeEventCount = 0;
        editorPieces.editor.addListener(FunctionalEditListener((changeList) {
          changeLogCount += 1;
          changeEventCount += changeList.length;
        }));

        late DocumentChangeLog documentChangeLog;
        editorPieces.document.addListener((changeLog) {
          documentChangeLog = changeLog;
        });

        editorPieces.editor.execute([const MoveNodeRequest(nodeId: "3", newIndex: 0)]);

        // Verify final node indices.
        expect(editorPieces.document.getNodeAt(0)!.id, "3");
        expect(editorPieces.document.getNodeAt(1)!.id, "1");
        expect(editorPieces.document.getNodeAt(2)!.id, "2");

        // Verify reported editor changes.
        expect(changeLogCount, 1);
        expect(changeEventCount, 3); // 3 nodes were moved

        // Verify reported document changes.
        expect(
          documentChangeLog.changes,
          [
            const NodeMovedEvent(nodeId: "1", from: 0, to: 1),
            const NodeMovedEvent(nodeId: "2", from: 1, to: 2),
            const NodeMovedEvent(nodeId: "3", from: 2, to: 0),
          ],
        );
      });

      test('reports the node that was removed', () {
        DocumentNode? removedNode;
        final editorPieces = _createStandardEditor(
          initialDocument: longTextDoc(),
          additionalReactions: [
            FunctionalEditReaction(react: (editorContext, requestDispatcher, changeList) {
              expect(changeList.length, 1);

              final event = changeList.first as DocumentEdit;
              final change = event.change as NodeRemovedEvent;
              removedNode = change.removedNode;
            }),
          ],
        );

        final nodeToRemove = editorPieces.document.getNodeById("2")!;

        editorPieces.editor.execute([
          DeleteNodeRequest(nodeId: nodeToRemove.id),
        ]);

        expect(removedNode, nodeToRemove);
      });
    });
  });
}

// TODO: check how/why this is different from default_document_editor.dart method called createDefaultDocumentEditor()
StandardEditorPieces _createStandardEditor({
  MutableDocument? initialDocument,
  DocumentSelection? initialSelection,
  List<EditReaction> additionalReactions = const [],
}) {
  final document = initialDocument ?? singleParagraphEmptyDoc();

  final composer = MutableDocumentComposer(initialSelection: initialSelection);
  final editor = Editor(
    editables: {
      Editor.documentKey: document,
      Editor.composerKey: composer,
    },
    requestHandlers: List.from(defaultRequestHandlers),
    reactionPipeline: [
      ...additionalReactions,
      const LinkifyReaction(),
      const UnorderedListItemConversionReaction(),
      const OrderedListItemConversionReaction(),
      const BlockquoteConversionReaction(),
      const HorizontalRuleConversionReaction(),
      const ImageUrlConversionReaction(),
    ],
  );

  return StandardEditorPieces(document, composer, editor);
}

/// Request that runs a command, which spawns more commands, based on the
/// given [newCommandCount] and [levelsOfGeneration].
///
/// This request, and its command, are used to test the command spawning and
/// ordering behavior of [Editor] without finding real commands that
/// exemplify the necessary spawning behavior.
class _ExpandingCommandRequest implements EditRequest {
  const _ExpandingCommandRequest({
    required this.generationId,
    required this.batchId,
    required this.newCommandCount,
    required this.levelsOfGeneration,
  });

  /// The generation of this request, e.g., `0` for the first generation,
  /// `1` for the second, etc.
  final int generationId;

  /// The ID of this request within its generation batch.
  ///
  /// If three requests are created within a newly spawned generation, then the
  /// first request to be generated will be given ID `0`, the second `1`, etc.
  final int batchId;

  /// The number of new commands that this request will generate (breadth of a tree).
  final int newCommandCount;

  /// The number of generations of commands that this request will generate (depth
  /// of a tree).
  final int levelsOfGeneration;
}

class _ExpandingCommand extends EditCommand {
  const _ExpandingCommand(this.request);

  final _ExpandingCommandRequest request;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.find<MutableDocument>(Editor.documentKey);
    final paragraph = document.getNodeAt(0) as ParagraphNode;

    executor.executeCommand(
      InsertTextCommand(
        documentPosition: DocumentPosition(
          documentPath: NodePath.forNode(paragraph.id),
          nodePosition: TextNodePosition(offset: paragraph.text.length),
        ),
        textToInsert:
            "${request.generationId > 0 ? "\n" : ""}${List.filled(request.generationId, "  ").join()}(${request.generationId}.${request.batchId})",
        attributions: {},
      ),
    );

    if (request.levelsOfGeneration > 0) {
      for (int i = 0; i < request.newCommandCount; i += 1) {
        executor.executeCommand(
          _ExpandingCommand(
            _ExpandingCommandRequest(
              generationId: request.generationId + 1, // +1 for next generation
              batchId: i, // i'th member of this generation
              newCommandCount: request.newCommandCount,
              levelsOfGeneration: request.levelsOfGeneration - 1, // -1 generations to go
            ),
          ),
        );
      }
    }
  }
}
