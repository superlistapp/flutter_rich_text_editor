import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:flutter_test_runners/flutter_test_runners.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';

import '../test_runners.dart';
import '../test_tools.dart';
import '../test_tools_user_input.dart';
import 'supereditor_test_tools.dart';
import 'test_documents.dart';

void main() {
  group('IME input', () {
    group('types characters', () {
      testWidgetsOnAllPlatforms('at the beginning of existing text', (tester) async {
        final document = MutableDocument(
          nodes: [
            ParagraphNode(id: "1", text: AttributedText("<- text here")),
          ],
        );

        await tester //
            .createDocument()
            .withCustomContent(document)
            .withInputSource(TextInputSource.ime)
            .pump();

        // Place caret at the beginning of the paragraph content.
        await tester.placeCaretInParagraph("1", 0);

        // Type some text.
        await tester.typeImeText("Hello");

        // Ensure the text was typed.
        expect((document.first as ParagraphNode).text.toPlainText(), "Hello<- text here");
      });

      testWidgetsOnAllPlatforms('in the middle of existing text', (tester) async {
        final document = MutableDocument(
          nodes: [
            ParagraphNode(id: "1", text: AttributedText("text here -><---")),
          ],
        );

        await tester //
            .createDocument()
            .withCustomContent(document)
            .withInputSource(TextInputSource.ime)
            .pump();

        // Place caret at the beginning of the paragraph content.
        await tester.placeCaretInParagraph("1", 12);

        // Type some text.
        await tester.typeImeText("Hello");

        // Ensure the text was typed.
        expect((document.first as ParagraphNode).text.toPlainText(), "text here ->Hello<---");
      });

      testWidgetsOnAllPlatforms('at the end of existing text', (tester) async {
        final document = MutableDocument(
          nodes: [
            ParagraphNode(id: "1", text: AttributedText("text here ->")),
          ],
        );

        await tester //
            .createDocument()
            .withCustomContent(document)
            .withInputSource(TextInputSource.ime)
            .pump();

        // Place caret at the beginning of the paragraph content.
        await tester.placeCaretInParagraph("1", 12);

        // Type some text.
        await tester.typeImeText("Hello");

        // Ensure the text was typed.
        expect((document.first as ParagraphNode).text.toPlainText(), "text here ->Hello");
      });
    });

    testWidgetsOnAllPlatforms('allows apps to handle performAction in their own way', (tester) async {
      final document = singleParagraphEmptyDoc();

      int performActionCount = 0;
      TextInputAction? performedAction;
      final imeOverrides = _TestImeOverrides(
        (action) {
          performActionCount += 1;
          performedAction = action;
        },
      );

      await tester //
          .createDocument()
          .withCustomContent(document)
          .withInputSource(TextInputSource.ime)
          .withImeOverrides(imeOverrides)
          .pump();

      // Place the caret in the document so that we open an IME connection.
      await tester.placeCaretInParagraph("1", 0);

      // Simulate a "Newline" action from the platform.
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.textInput.name,
        SystemChannels.textInput.codec.encodeMethodCall(
          const MethodCall(
            "TextInputClient.performAction",
            [-1, "TextInputAction.newline"],
          ),
        ),
        null,
      );

      // Ensure that our override got the performAction call.
      expect(performActionCount, 1);
      expect(performedAction, TextInputAction.newline);

      // Ensure that the editor didn't receive the performAction call, and didn't
      // insert a new node.
      expect(document.nodeCount, 1);
    });

    testWidgetsOnAndroid('allows app to handle newline action', (tester) async {
      // On Android, when the user presses an action button configured as TextInputAction.newline,
      // instead of dispatching the action, the OS sends an insertion delta of '\n'.
      //
      // Then, the IME code that handles deltas translates this insertion into a performAction call.
      // This test ensures that this performAction call honors the IME overrides.

      final document = singleParagraphEmptyDoc();

      int performActionCount = 0;
      TextInputAction? performedAction;
      final imeOverrides = _TestImeOverrides(
        (action) {
          performActionCount += 1;
          performedAction = action;
        },
      );

      await tester //
          .createDocument()
          .withCustomContent(document)
          .withInputSource(TextInputSource.ime)
          .withImeOverrides(imeOverrides)
          .pump();

      // Place the caret in the document so that we open an IME connection.
      await tester.placeCaretInParagraph("1", 0);

      // Simulate the user pressing an action button that generates an insertion of a new line.
      await tester.typeImeText('\n');

      // Ensure that our override got the performAction call.
      expect(performActionCount, 1);
      expect(performedAction, TextInputAction.newline);

      // Ensure that the editor didn't receive the performAction call, and didn't
      // insert a new node.
      expect(document.nodeCount, 1);
    });

    testWidgetsOnMac('allows apps to handle selectors in their own way', (tester) async {
      bool customHandlerCalled = false;

      await tester //
          .createDocument()
          .withCustomContent(
            MutableDocument(
              nodes: [ParagraphNode(id: '1', text: AttributedText('First paragraph'))],
            ),
          )
          .withInputSource(TextInputSource.ime)
          .withSelectorHandlers({
        MacOsSelectors.moveRight: (context) {
          customHandlerCalled = true;
        },
      }).pump();

      // Place the caret at the beginning of the document.
      await tester.placeCaretInParagraph("1", 0);

      // Press right arrow key to trigger the MacOsSelectors.moveRight selector.
      await tester.pressRightArrow();

      // Ensure the custom handler was called.
      expect(customHandlerCalled, isTrue);

      // Ensure that the editor didn't execute the default handler for the MacOsSelectors.moveRight selector.
      expect(
        SuperEditorInspector.findDocumentSelection(),
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: '1',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
    });

    testWidgetsOnAllPlatforms('applies list of deltas the way some IMEs report them', (tester) async {
      // This test simulates an auto-correction scenario,
      // where the IME sends multiple insertion deltas at once.

      await tester //
          .createDocument()
          .withSingleEmptyParagraph()
          .withInputSource(TextInputSource.ime)
          .pump();

      // Place caret at the start of the document.
      await tester.placeCaretInParagraph('1', 0);

      // Send initial delta, insertion of 'Goi'.
      await tester.ime.sendDeltas(
        const [
          TextEditingDeltaNonTextUpdate(
            oldText: '. ',
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange(start: -1, end: -1),
          ),
          TextEditingDeltaInsertion(
            oldText: '. ',
            textInserted: 'Goi',
            insertionOffset: 2,
            selection: TextSelection.collapsed(offset: 5),
            composing: TextRange(start: 2, end: 5),
          )
        ],
        getter: imeClientGetter,
      );

      // Simulate the auto-correction kicking in during the insertion of a '.'.
      await tester.ime.sendDeltas(
        const [
          // This delta represents the '.' typed by the user.
          TextEditingDeltaInsertion(
            oldText: '. Goi',
            textInserted: '.',
            insertionOffset: 3,
            selection: TextSelection.collapsed(offset: 6),
            composing: TextRange(start: -1, end: -1),
          ),
          // Deltas generated by the auto-correction.
          // First, delete everything.
          TextEditingDeltaDeletion(
            oldText: '. Goi.',
            deletedRange: TextRange(start: 2, end: 6),
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange(start: -1, end: -1),
          ),
          // Insert the auto-corrected word.
          TextEditingDeltaInsertion(
            oldText: '. ',
            textInserted: 'Going',
            insertionOffset: 2,
            selection: TextSelection.collapsed(offset: 7),
            composing: TextRange(start: -1, end: -1),
          ),
          // Insert the '.' typed.
          TextEditingDeltaInsertion(
            oldText: '. Going',
            textInserted: '.',
            insertionOffset: 7,
            selection: TextSelection.collapsed(offset: 8),
            composing: TextRange(start: -1, end: -1),
          ),
        ],
        getter: imeClientGetter,
      );

      // Ensure the text was inserted.
      expect(
        SuperEditorInspector.findTextInComponent('1').toPlainText(),
        'Going.',
      );
    });

    group('delta use-cases', () {
      test('can handle an auto-inserted period', () {
        // On iOS, adding 2 spaces causes the two spaces to be replaced by a
        // period and a space. This test applies the same type and order of deltas
        // that were observed on iOS.
        //
        // Previously, we had a bug where the period was appearing after the
        // 2nd space, instead of between the two spaces. This test prevents
        // that regression.
        final document = MutableDocument(nodes: [
          ParagraphNode(
            id: "1",
            text: AttributedText("This is a sentence"),
          ),
        ]);
        final composer = MutableDocumentComposer(
          initialSelection: const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: "1",
              nodePosition: TextNodePosition(offset: 18),
            ),
          ),
        );
        final editor = createDefaultDocumentEditor(document: document, composer: composer);
        final commonOps = CommonEditorOperations(
          editor: editor,
          document: document,
          composer: composer,
          documentLayoutResolver: () => FakeDocumentLayout(),
        );
        final softwareKeyboardHandler = TextDeltasDocumentEditor(
          editor: editor,
          document: document,
          documentLayoutResolver: () => FakeDocumentLayout(),
          selection: composer.selectionNotifier,
          composerPreferences: composer.preferences,
          composingRegion: composer.composingRegion,
          commonOps: commonOps,
          onPerformAction: (_) {},
        );

        softwareKeyboardHandler.applyDeltas([
          const TextEditingDeltaInsertion(
            textInserted: ' ',
            insertionOffset: 20,
            selection: TextSelection.collapsed(offset: 21),
            composing: TextRange(start: -1, end: -1),
            oldText: '. This is a sentence',
          ),
        ]);
        softwareKeyboardHandler.applyDeltas([
          const TextEditingDeltaReplacement(
            oldText: '. This is a sentence ',
            replacementText: '.',
            replacedRange: TextRange(start: 20, end: 21),
            selection: TextSelection.collapsed(offset: 21),
            composing: TextRange(start: -1, end: -1),
          ),
        ]);
        softwareKeyboardHandler.applyDeltas([
          const TextEditingDeltaInsertion(
            textInserted: ' ',
            insertionOffset: 21,
            selection: TextSelection.collapsed(offset: 22),
            composing: TextRange(start: -1, end: -1),
            oldText: '. This is a sentence.',
          ),
        ]);

        expect((document.first as ParagraphNode).text.toPlainText(), "This is a sentence. ");
      });

      testWidgets('can type compound character in an empty paragraph', (tester) async {
        final editContext = await tester //
            .createDocument()
            .withTwoEmptyParagraphs()
            .withInputSource(TextInputSource.ime)
            .withGestureMode(DocumentGestureMode.mouse)
            .autoFocus(true)
            .pump();

        // Start the caret in the 2nd paragraph so that we send a
        // hidden placeholder to the IME to report backspaces.
        await tester.placeCaretInParagraph("2", 0);

        // Send the deltas that should produce a ü.
        //
        // We have to use implementation details to send the simulated IME deltas
        // because Flutter doesn't have any testing tools for IME deltas.
        final imeInteractor = find.byType(SuperEditorImeInteractor).evaluate().first;
        final deltaClient = ((imeInteractor as StatefulElement).state as ImeInputOwner).imeClient;

        // Ensure that the delta client starts with the expected invisible placeholder
        // characters.
        expect(deltaClient.currentTextEditingValue!.text, ". ");
        expect(deltaClient.currentTextEditingValue!.selection, const TextSelection.collapsed(offset: 2));
        expect(deltaClient.currentTextEditingValue!.composing, const TextRange(start: -1, end: -1));

        // Insert the "opt+u" character.
        deltaClient.updateEditingValueWithDeltas([
          const TextEditingDeltaInsertion(
            oldText: ". ",
            textInserted: "¨",
            insertionOffset: 2,
            selection: TextSelection.collapsed(offset: 3),
            composing: TextRange(start: 2, end: 3),
          ),
        ]);
        await tester.pumpAndSettle();

        // Ensure that the empty paragraph now reads "¨".
        expect((editContext.document.getNodeAt(1)! as ParagraphNode).text.toPlainText(), "¨");

        // Ensure that the IME still has the invisible characters.
        expect(deltaClient.currentTextEditingValue!.text, ". ¨");
        expect(deltaClient.currentTextEditingValue!.composing, const TextRange(start: 2, end: 3));

        // Insert the "u" character to create the compound character.
        deltaClient.updateEditingValueWithDeltas([
          const TextEditingDeltaReplacement(
            oldText: ". ¨",
            replacementText: "ü",
            replacedRange: TextRange(start: 2, end: 3),
            selection: TextSelection.collapsed(offset: 3),
            composing: TextRange(start: -1, end: -1),
          ),
        ]);

        // We need a final pump and settle to propagate selection changes while we still
        // have access to the document layout. Otherwise, the selection change callback
        // will execute after the end of this test, and the layout isn't available any
        // more.
        // TODO: trace the selection change call stack and adjust it so that we don't need this pump
        await tester.pumpAndSettle();

        // Ensure that the empty paragraph now reads "ü".
        expect((editContext.document.getNodeAt(1)! as ParagraphNode).text.toPlainText(), "ü");
      });
    });

    // Note: Some Android devices report ENTER and BACKSPACE as hardware keys. Other Android
    //       devices report "\n" insertion and deletion IME deltas, instead.
    group('on Xiaomi Redmi tablet (Android 12 SP1A)', () {
      testWidgetsOnAndroid('applies list of deltas when inserting new lines', (tester) async {
        // This test simulates inserting a line break in the middle of the text,
        // followed by a non-text delta placing the selection/composing region on the new line.
        //
        // This test runs only on Android, because we only map a \n insertion to a new line on Android.

        await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .withInputSource(TextInputSource.ime)
            .pump();

        // Place caret at the start of the document.
        await tester.placeCaretInParagraph('1', 0);

        // Send initial delta.
        await tester.ime.sendDeltas(
          const [
            TextEditingDeltaInsertion(
              oldText: '. ',
              textInserted: 'Before the line break new line',
              insertionOffset: 2,
              selection: TextSelection.collapsed(offset: 32),
              composing: TextRange(start: 2, end: 32),
            )
          ],
          getter: imeClientGetter,
        );

        // Place the caret at "Before the line break |new line".
        await tester.placeCaretInParagraph('1', 22);

        // Add a line break and simulate the OS sending a non-text delta to change the composing region.
        //
        // The OS thinks the editing text is "Before the line break \nnew line".
        //
        // With the insertion of the line break, the paragraph will be split into two and
        // our current editing text will be "new line".
        //
        // The OS selection is invalid to us, as our editing text changed.
        await tester.ime.sendDeltas(
          const [
            TextEditingDeltaInsertion(
              oldText: 'Before the line break new line',
              textInserted: '\n',
              insertionOffset: 22,
              selection: TextSelection.collapsed(offset: 23),
              composing: TextRange(start: -1, end: -1),
            ),
            TextEditingDeltaNonTextUpdate(
              oldText: 'Before the line break \nnew line',
              selection: TextSelection.collapsed(offset: 23),
              composing: TextRange(start: -1, end: -1),
            ),
            TextEditingDeltaNonTextUpdate(
              oldText: 'Before the line break \nnew line',
              selection: TextSelection.collapsed(offset: 23),
              composing: TextRange(start: 23, end: 26),
            ),
          ],
          getter: imeClientGetter,
        );

        final doc = SuperEditorInspector.findDocument()!;

        // Ensure the paragraph was split.
        expect(
          (doc.getNodeAt(0)! as ParagraphNode).text.toPlainText(),
          'Before the line break ',
        );

        // Ensure the paragraph was split.
        expect(
          (doc.getNodeAt(1)! as ParagraphNode).text.toPlainText(),
          'new line',
        );

        // Ensure the selection is at the beginning of the second node.
        expect(
          SuperEditorInspector.findDocumentSelection(),
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: doc.getNodeAt(1)!.id,
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
        );
      });

      testWidgetsOnAndroid('maintains correct selection after merging paragraphs', (tester) async {
        await tester //
            .createDocument()
            .fromMarkdown('''
Paragraph one

Paragraph two
''')
            .withInputSource(TextInputSource.ime)
            .pump();

        final doc = SuperEditorInspector.findDocument()!;

        // Place caret at the start of the second paragraph.
        await tester.placeCaretInParagraph(doc.getNodeAt(1)!.id, 0);

        // Sends the deletion delta followed by non-text deltas.
        //
        // This deletion will cause the two paragraphs to be merged.
        await tester.ime.sendDeltas(
          const [
            TextEditingDeltaNonTextUpdate(
              oldText: '. Paragraph two',
              selection: TextSelection.collapsed(offset: 2),
              composing: TextRange(start: -1, end: -1),
            ),
            TextEditingDeltaNonTextUpdate(
              oldText: 'Paragraph two',
              selection: TextSelection.collapsed(offset: 0),
              composing: TextRange(start: 2, end: 11),
            ),
            TextEditingDeltaDeletion(
              oldText: '. Paragraph two',
              deletedRange: TextRange(start: 1, end: 2),
              selection: TextSelection.collapsed(offset: 1),
              composing: TextRange(start: -1, end: -1),
            ),
          ],
          getter: imeClientGetter,
        );

        // Ensure the paragraph was merged.
        expect(
          (doc.getNodeAt(0)! as ParagraphNode).text.toPlainText(),
          'Paragraph oneParagraph two',
        );

        // Ensure the selection is at "Paragraph one|Paragraph two".
        expect(
          SuperEditorInspector.findDocumentSelection(),
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: doc.getNodeAt(0)!.id,
              nodePosition: const TextNodePosition(offset: 13),
            ),
          ),
        );
      });
    });

    group('on Samsung M51 (Android 12 SP1A)', () {
      testWidgetsOnAndroid('applies keyboard suggestions', (tester) async {
        await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .withInputSource(TextInputSource.ime)
            .pump();

        // Place the caret at the start of the paragraph.
        await tester.placeCaretInParagraph('1', 0);

        // Start typing the word "Anonymous" with typos.
        await tester.typeImeText('Anonimoi');

        // Simulate the user accepting a suggestion.
        // The IME replaces the word and inserts a space after it.
        await tester.ime.sendDeltas(const [
          TextEditingDeltaNonTextUpdate(
            oldText: '. Anonimoi',
            selection: TextSelection.collapsed(
              offset: 10,
              affinity: TextAffinity.downstream,
            ),
            composing: TextRange(start: 2, end: 10),
          ),
          TextEditingDeltaReplacement(
            oldText: '. Anonimoi',
            replacementText: 'Anonymous',
            replacedRange: TextRange(start: 2, end: 10),
            selection: TextSelection.collapsed(offset: 11, affinity: TextAffinity.downstream),
            composing: TextRange(start: -1, end: -1),
          ),
          TextEditingDeltaInsertion(
            oldText: '. Anonymous',
            textInserted: ' ',
            insertionOffset: 11,
            selection: TextSelection.collapsed(
              offset: 12,
              affinity: TextAffinity.downstream,
            ),
            composing: TextRange(start: -1, end: -1),
          )
        ], getter: imeClientGetter);

        expect(
          SuperEditorInspector.findTextInComponent('1').toPlainText(),
          'Anonymous ',
        );
      });
    });

    group('on Samsung M51 (Android 12 SP1A) with GBoard', () {
      testWidgetsOnAndroid('applies keyboard suggestions', (tester) async {
        await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .withInputSource(TextInputSource.ime)
            .pump();

        // Place the caret at the start of the paragraph.
        await tester.placeCaretInParagraph('1', 0);

        // Start typing the word "Anonymous" with typos.
        await tester.typeImeText('Anonimoi');

        // Simulate the user accepting a suggestion.
        // The IME deletes the substring "imoi" and inserts "ymous ".
        await tester.ime.sendDeltas(const [
          TextEditingDeltaDeletion(
            oldText: '. Anonimoi',
            deletedRange: TextRange(start: 6, end: 10),
            selection: TextSelection.collapsed(
              offset: 4,
              affinity: TextAffinity.downstream,
            ),
            composing: TextRange(start: -1, end: -1),
          ),
          TextEditingDeltaInsertion(
            oldText: '. Anon',
            textInserted: 'ymous ',
            insertionOffset: 6,
            selection: TextSelection.collapsed(
              offset: 12,
              affinity: TextAffinity.downstream,
            ),
            composing: TextRange(start: -1, end: -1),
          ),
        ], getter: imeClientGetter);

        expect(
          SuperEditorInspector.findTextInComponent('1').toPlainText(),
          'Anonymous ',
        );
      });
    });

    group('on iPhone 11 (iOS 13.7) with chinese keyboard', () {
      testWidgetsOnIos('applies keyboard suggestions', (tester) async {
        // Holds the composing region that we sent to the IME.
        TextRange? composingRegion;

        await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .withInputSource(TextInputSource.ime)
            .pump();

        // Place the caret at the start of the paragraph.
        await tester.placeCaretInParagraph('1', 0);

        // Simulate the user typing "a a a".
        await tester.ime.sendDeltas(const [
          TextEditingDeltaNonTextUpdate(
            oldText: '. ',
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange(start: -1, end: -1),
          ),
          TextEditingDeltaInsertion(
            oldText: '. ',
            textInserted: 'a',
            insertionOffset: 2,
            selection: TextSelection.collapsed(
              offset: 3,
              affinity: TextAffinity.upstream,
            ),
            composing: TextRange(start: 2, end: 3),
          ),
        ], getter: imeClientGetter);
        await tester.ime.sendDeltas(const [
          TextEditingDeltaInsertion(
            oldText: '. a',
            textInserted: ' a',
            insertionOffset: 3,
            selection: TextSelection.collapsed(
              offset: 5,
              affinity: TextAffinity.upstream,
            ),
            composing: TextRange(start: 2, end: 5),
          ),
        ], getter: imeClientGetter);
        await tester.ime.sendDeltas(const [
          TextEditingDeltaInsertion(
            oldText: '. a a',
            textInserted: ' a',
            insertionOffset: 5,
            selection: TextSelection.collapsed(
              offset: 7,
              affinity: TextAffinity.upstream,
            ),
            composing: TextRange(start: 2, end: 7),
          ),
        ], getter: imeClientGetter);

        // Simulate the user accepting the suggestion from the keyboard.
        //
        // The IME sends the replacement and changes the composing region in the same frame,
        // in separate delta batches.
        final imeClient = imeClientGetter();
        imeClient.updateEditingValueWithDeltas(const [
          TextEditingDeltaReplacement(
            oldText: '. a a a',
            replacementText: '呵呵呵',
            replacedRange: TextRange(start: 2, end: 7),
            selection: TextSelection.collapsed(
              offset: 5,
              affinity: TextAffinity.upstream,
            ),
            composing: TextRange(start: 2, end: 5),
          ),
        ]);

        // Intercept the setEditingState message sent to the platform so we can check
        // which composing region was sent.
        tester
            .interceptChannel(SystemChannels.textInput.name) //
            .interceptMethod(
          'TextInput.setEditingState',
          (methodCall) {
            final params = methodCall.arguments as Map;
            composingRegion = TextRange(
              start: params['composingBase'],
              end: params['composingExtent'],
            );
            return null;
          },
        );

        imeClient.updateEditingValueWithDeltas(const [
          TextEditingDeltaNonTextUpdate(
            oldText: '. 呵呵呵',
            selection: TextSelection.collapsed(
              offset: 5,
              affinity: TextAffinity.upstream,
            ),
            composing: TextRange.empty,
          ),
        ]);
        await tester.pump();

        // Between the two updateEditingValueWithDeltas calls, the IME interactor
        // sends [0, 3) as the new composing region (the composing region of the first delta) to the IME.
        //
        // If the user types with that composing region, all the existing text is replaced.
        //
        // Ensure we cleared the composing region on the IME so the previous entered text is preserved.
        expect(composingRegion, TextRange.empty);
      });

      testWidgetsOnIos('applies keyboard suggestions and keeps styles', (tester) async {
        // Pump an editor with a bold text.
        final testContext = await tester //
            .createDocument()
            .fromMarkdown('**Fix**')
            .withInputSource(TextInputSource.ime)
            .pump();

        // Place the caret at the end of the paragraph.
        await tester.placeCaretInParagraph(testContext.document.first.id, 3);

        // Type a letter simulating a typo. The current text results in "Fixs".
        await tester.typeImeText('s');

        // Simulate the user accepting a suggestion.
        // The IME replaces the word and inserts a space after it.
        await tester.ime.sendDeltas([
          const TextEditingDeltaReplacement(
            oldText: '. Fixs',
            replacementText: 'Fixed',
            replacedRange: TextRange(start: 2, end: 6),
            selection: TextSelection.collapsed(offset: 7),
            composing: TextRange(start: -1, end: -1),
          ),
        ], getter: imeClientGetter);
        await tester.ime.sendDeltas([
          const TextEditingDeltaInsertion(
            oldText: '. Fixed',
            textInserted: ' ',
            insertionOffset: 7,
            selection: TextSelection.collapsed(offset: 8),
            composing: TextRange(start: -1, end: -1),
          )
        ], getter: imeClientGetter);

        // Ensure the text was replaced and the style was preserved.
        expect(testContext.document, equalsMarkdown('**Fixed **'));
      });
    });

    group('on iPhone 13 (iOS 17.2) with korean keyboard', () {
      testWidgetsOnIos('applies keyboard suggestions', (tester) async {
        await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .withInputSource(TextInputSource.ime)
            .pump();

        // Place the caret at the start of the paragraph.
        await tester.placeCaretInParagraph('1', 0);

        // Simulate the user typing "ㅅ".
        await tester.ime.sendDeltas(const [
          TextEditingDeltaNonTextUpdate(
            oldText: '. ',
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange(start: -1, end: -1),
          ),
          TextEditingDeltaInsertion(
            oldText: '. ',
            textInserted: 'ㅅ',
            insertionOffset: 2,
            selection: TextSelection.collapsed(offset: 3, affinity: TextAffinity.downstream),
            composing: TextRange(start: -1, end: -1),
          ),
        ], getter: imeClientGetter);

        // Simulate the user typing "ㅛ" and the IME converting the "ㅅㅛ" to "쇼".
        await tester.ime.sendDeltas(const [
          TextEditingDeltaNonTextUpdate(
            oldText: '. ㅅ',
            selection: TextSelection(baseOffset: 1, extentOffset: 3, isDirectional: false),
            composing: TextRange(start: -1, end: -1),
          ),
          TextEditingDeltaDeletion(
            oldText: '. ㅅ',
            deletedRange: TextRange(start: 1, end: 3),
            selection: TextSelection.collapsed(
              offset: 1,
              affinity: TextAffinity.downstream,
            ),
            composing: TextRange(start: -1, end: -1),
          ),
          TextEditingDeltaInsertion(
            oldText: '.',
            textInserted: ' ',
            insertionOffset: 1,
            selection: TextSelection.collapsed(
              offset: 2,
              affinity: TextAffinity.downstream,
            ),
            composing: TextRange(start: -1, end: -1),
          ),
          TextEditingDeltaInsertion(
            oldText: '. ',
            textInserted: '쇼',
            insertionOffset: 2,
            selection: TextSelection.collapsed(
              offset: 3,
              affinity: TextAffinity.downstream,
            ),
            composing: TextRange(start: -1, end: -1),
          )
        ], getter: imeClientGetter);

        // Ensure text and selection were updated.
        expect(SuperEditorInspector.findTextInComponent('1').toPlainText(), '쇼');
        expect(
          SuperEditorInspector.findDocumentSelection(),
          selectionEquivalentTo(
            const DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: '1',
                nodePosition: TextNodePosition(offset: 1),
              ),
            ),
          ),
        );
      });
    });

    group('on iPhone 15 (iOS 17.5)', () {
      testWidgetsOnIos('ignores keyboard suggestions when pressing the newline button', (tester) async {
        final testContext = await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .withInputSource(TextInputSource.ime)
            .pump();

        // Place the caret at the start of the paragraph.
        await tester.placeCaretInParagraph('1', 0);

        // Type some text.
        await tester.typeImeText('run tom');

        // Press the new line button.
        await tester.testTextInput.receiveAction(TextInputAction.newline);

        // Simulate the IME sending a delta replacing "tom" with "Tom".
        // At this point, we already added a new paragraph to the document,
        // so these text ranges are invalid for us.
        await tester.ime.sendDeltas([
          const TextEditingDeltaReplacement(
            oldText: '. Run tom',
            replacementText: 'Tom',
            replacedRange: TextRange(start: 6, end: 9),
            selection: TextSelection.collapsed(offset: 9),
            composing: TextRange(start: -1, end: -1),
          ),
        ], getter: imeClientGetter);

        await tester.ime.sendDeltas([
          const TextEditingDeltaInsertion(
            oldText: '. Run Tom',
            textInserted: '\n',
            insertionOffset: 9,
            selection: TextSelection.collapsed(
              offset: 10,
              affinity: TextAffinity.downstream,
            ),
            composing: TextRange(start: -1, end: -1),
          ),
        ], getter: imeClientGetter);
        await tester.pump();

        final document = testContext.document;

        // Ensure the replacement was ignored and a new empty node was added.
        expect(document.nodeCount, 2);
        expect((document.getNodeAt(0)! as TextNode).text.toPlainText(), 'run tom');
        expect((document.getNodeAt(1)! as TextNode).text.toPlainText(), '');
      });
    });

    group('moves caret', () {
      testWidgetsOnDesktopAndWeb('to end of previous node when LEFT_ARROW is pressed at the beginning of a paragraph',
          (tester) async {
        await tester
            .createDocument() //
            .withLongDoc()
            .withInputSource(inputSourceVariant.currentValue!)
            .pump();

        // Place the caret at the beginning of the second paragraph.
        await tester.placeCaretInParagraph('2', 0);

        // Press left arrow to move to the previous node.
        await tester.pressLeftArrow();

        // Ensure the caret sits at the end of the first paragraph.
        expect(
          SuperEditorInspector.findDocumentSelection(),
          const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: '1',
              nodePosition: TextNodePosition(offset: 439),
            ),
          ),
        );
      }, variant: inputSourceVariant);

      testWidgetsOnDesktopAndWeb('to the beginning of next node when RIGHT_ARROW is pressed at the end of a paragraph',
          (tester) async {
        await tester
            .createDocument() //
            .withLongDoc()
            .withInputSource(inputSourceVariant.currentValue!)
            .pump();

        // Place the caret at the end of the first paragraph.
        await tester.placeCaretInParagraph('1', 439);

        // Press right arrow to move to the next node.
        await tester.pressRightArrow();

        // Ensure the caret sits at the beginning of the second paragraph.
        expect(
          SuperEditorInspector.findDocumentSelection(),
          const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: '2',
              nodePosition: TextNodePosition(offset: 0),
            ),
          ),
        );
      }, variant: inputSourceVariant);
    });

    testWidgetsOnWebDesktop('inside a CustomScrollView > inserts space instead of scrolling with SPACEBAR',
        (tester) async {
      final testContext = await tester //
          .createDocument()
          .withSingleEmptyParagraph()
          .insideCustomScrollView()
          .withInputSource(TextInputSource.ime)
          .pump();

      final nodeId = testContext.document.first.id;

      // Place the caret at the beginning of the paragraph.
      await tester.placeCaretInParagraph(nodeId, 0);

      // Press space to insert a space character.
      await _typeSpaceAdaptive(tester);

      // Ensure the space character was inserted.
      expect(SuperEditorInspector.findTextInComponent(nodeId).toPlainText(), ' ');
    });

    testWidgetsOnWebDesktop('deletes a character with backspace', (tester) async {
      final testContext = await tester //
          .createDocument()
          .fromMarkdown('This is a paragraph')
          .withInputSource(TextInputSource.ime)
          .pump();

      final nodeId = testContext.document.first.id;

      // Place the caret at the end of the paragraph.
      await tester.placeCaretInParagraph(nodeId, 19);

      // Simulate the user pressing backspace.
      //
      // On web, this generates both a key event and a deletion delta.
      await tester.pressBackspace();
      await tester.ime.sendDeltas(
        [
          const TextEditingDeltaDeletion(
            oldText: '. This is a paragraph',
            deletedRange: TextRange(start: 20, end: 21),
            selection: TextSelection.collapsed(offset: 20),
            composing: TextRange.empty,
          ),
        ],
        getter: imeClientGetter,
      );

      // Ensure the last character was deleted.
      expect(SuperEditorInspector.findTextInComponent(nodeId).toPlainText(), 'This is a paragrap');
    });

    testWidgetsOnWebDesktop('merges paragraphs backspace at the beginning of a paragraph', (tester) async {
      await tester //
          .createDocument()
          .fromMarkdown('''
Paragraph one

Paragraph two
''')
          .withInputSource(TextInputSource.ime)
          .pump();

      final doc = SuperEditorInspector.findDocument()!;

      // Place caret at the start of the second paragraph.
      await tester.placeCaretInParagraph(doc.getNodeAt(1)!.id, 0);

      // Simulates the user pressing BACKSPACE, which generates a deletion delta.
      // This deletion will cause the two paragraphs to be merged.
      await tester.ime.sendDeltas(
        const [
          TextEditingDeltaNonTextUpdate(
            oldText: '. Paragraph two',
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange(start: -1, end: -1),
          ),
          TextEditingDeltaDeletion(
            oldText: '. Paragraph two',
            deletedRange: TextRange(start: 1, end: 2),
            selection: TextSelection.collapsed(offset: 1),
            composing: TextRange(start: -1, end: -1),
          ),
        ],
        getter: imeClientGetter,
      );

      // Ensure the paragraph was merged.
      expect(
        (doc.getNodeAt(0)! as ParagraphNode).text.toPlainText(),
        'Paragraph oneParagraph two',
      );
    });

    group('text serialization and selected content >', () {
      test('within a single node is reported as a TextEditingValue', () {
        const text = "This is a paragraph of text.";

        _expectTextEditingValue(
          actualTextEditingValue: DocumentImeSerializer(
            MutableDocument(nodes: [
              ParagraphNode(id: "1", text: AttributedText(text)),
            ]),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: "1",
                nodePosition: TextNodePosition(offset: 10),
              ),
              extent: DocumentPosition(
                nodeId: "1",
                nodePosition: TextNodePosition(offset: 19),
              ),
            ),
            null,
          ).toTextEditingValue(),
          expectedTextWithSelection: ". This is a |paragraph| of text.",
        );
      });

      test('two text nodes is reported as a TextEditingValue', () {
        const text1 = "This is the first paragraph of text.";
        const text2 = "This is the second paragraph of text.";

        _expectTextEditingValue(
          actualTextEditingValue: DocumentImeSerializer(
            MutableDocument(nodes: [
              ParagraphNode(id: "1", text: AttributedText(text1)),
              ParagraphNode(id: "2", text: AttributedText(text2)),
            ]),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: "1",
                nodePosition: TextNodePosition(offset: 12),
              ),
              extent: DocumentPosition(
                nodeId: "2",
                nodePosition: TextNodePosition(offset: 28),
              ),
            ),
            null,
          ).toTextEditingValue(),
          expectedTextWithSelection: ". This is the |first paragraph of text.\nThis is the second paragraph| of text.",
        );
      });

      test('text with internal non-text reported as a TextEditingValue', () {
        const text = "This is a paragraph of text.";

        _expectTextEditingValue(
          actualTextEditingValue: DocumentImeSerializer(
            MutableDocument(nodes: [
              ParagraphNode(id: "1", text: AttributedText(text)),
              HorizontalRuleNode(id: "2"),
              ParagraphNode(id: "3", text: AttributedText(text)),
            ]),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: "1",
                nodePosition: TextNodePosition(offset: 10),
              ),
              extent: DocumentPosition(
                nodeId: "3",
                nodePosition: TextNodePosition(offset: 19),
              ),
            ),
            null,
          ).toTextEditingValue(),
          expectedTextWithSelection: ". This is a |paragraph of text.\n~\nThis is a paragraph| of text.",
        );
      });

      test('text within a composite node reported as a TextEditingValue', () {
        const text = "This is a paragraph of text.";

        _expectTextEditingValue(
          actualTextEditingValue: DocumentImeSerializer(
            MutableDocument(nodes: [
              CompositeDocumentNode("1", [
                ParagraphNode(id: "2", text: AttributedText(text)),
              ]),
            ]),
            const DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: "1",
                nodePosition: CompositeNodePosition(
                  compositeNodeId: "1",
                  childNodeId: "2",
                  childNodePosition: TextNodePosition(offset: 10),
                ),
              ),
            ),
            null,
          ).toTextEditingValue(),
          expectedTextWithSelection: ". This is a |paragraph of text.",
        );
      });

      test('text within composite nodes and non-text in between reported as a TextEditingValue', () {
        const text = "This is a paragraph of text.";

        _expectTextEditingValue(
          actualTextEditingValue: DocumentImeSerializer(
            MutableDocument(nodes: [
              CompositeDocumentNode("1", [
                ParagraphNode(id: "2", text: AttributedText(text)),
              ]),
              HorizontalRuleNode(id: "3"),
              CompositeDocumentNode("4", [
                ParagraphNode(id: "5", text: AttributedText(text)),
              ])
            ]),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: "1",
                nodePosition: TextNodePosition(offset: 10),
              ),
              extent: DocumentPosition(
                nodeId: "3",
                nodePosition: TextNodePosition(offset: 19),
              ),
            ),
            null,
          ).toTextEditingValue(),
          expectedTextWithSelection: ". This is a |paragraph of text.\n~\nThis is a paragraph| of text.",
        );
      });

      test('text with non-text end-caps reported as a TextEditingValue', () {
        const text = "This is the first paragraph of text.";

        _expectTextEditingValue(
          actualTextEditingValue: DocumentImeSerializer(
            MutableDocument(nodes: [
              HorizontalRuleNode(id: "1"),
              ParagraphNode(id: "2", text: AttributedText(text)),
              HorizontalRuleNode(id: "3"),
            ]),
            const DocumentSelection(
              base: DocumentPosition(
                nodeId: "1",
                nodePosition: UpstreamDownstreamNodePosition.upstream(),
              ),
              extent: DocumentPosition(
                nodeId: "3",
                nodePosition: UpstreamDownstreamNodePosition.downstream(),
              ),
            ),
            null,
          ).toTextEditingValue(),
          expectedTextWithSelection: ". |~\nThis is the first paragraph of text.\n~|",
        );
      });

      testWidgetsOnArbitraryDesktop('sends selection to platform', (tester) async {
        final context = await tester //
            .createDocument()
            .withSingleParagraph()
            .withInputSource(TextInputSource.ime)
            .pump();

        // Place caret at Lorem| ipsum.
        await tester.placeCaretInParagraph('1', 5);

        int selectionBase = -1;
        int selectionExtent = -1;
        String selectionAffinity = "";

        // Intercept messages sent to the platform.
        tester.binding.defaultBinaryMessenger.setMockMessageHandler(SystemChannels.textInput.name, (message) async {
          final methodCall = const JSONMethodCodec().decodeMethodCall(message);
          if (methodCall.method == 'TextInput.setEditingState') {
            selectionBase = methodCall.arguments['selectionBase'];
            selectionExtent = methodCall.arguments['selectionExtent'];
            selectionAffinity = methodCall.arguments['selectionAffinity'];
          }
          return null;
        });

        // Press shift+left to expand the selection upstream.
        await tester.pressShiftLeftArrow();

        final selection = SuperEditorInspector.findDocumentSelection()!;
        final base = (selection.base.nodePosition as TextNodePosition).offset;
        final extent = (selection.extent.nodePosition as TextNodePosition).offset;
        final affinity = context.findEditContext().document.getAffinityForSelection(selection);

        // Ensure we sent the same base, extent and affinity to the platform.
        // Add two to account for the invisble characters prepended to the text.
        expect(selectionBase, base + 2);
        expect(selectionExtent, extent + 2);
        expect(selectionAffinity, affinity.toString());
      });
    });

    group('typing characters near a link', () {
      testWidgetsOnMobile('does not expand the link when inserting before the link', (tester) async {
        // Configure and render a document.
        await tester //
            .createDocument()
            .withCustomContent(_singleParagraphWithLinkDoc())
            .pump();

        // Place the caret at the start of the link.
        await tester.placeCaretInParagraph('1', 0);

        // Type characters before the link using the IME
        await tester.ime.typeText("Go to ", getter: imeClientGetter);

        // Ensure that the link is unchanged
        expect(
          SuperEditorInspector.findDocument(),
          equalsMarkdown("Go to [https://google.com](https://google.com)"),
        );
      });

      testWidgetsOnMobile('does not expand the link when inserting after the link', (tester) async {
        // Configure and render a document.
        await tester //
            .createDocument()
            .withCustomContent(_singleParagraphWithLinkDoc())
            .pump();

        // Place the caret at the end of the link.
        await tester.placeCaretInParagraph('1', 18);

        // Type characters after the link using the IME
        await tester.ime.typeText(" to learn anything", getter: imeClientGetter);

        // Ensure that the link is unchanged
        expect(
          SuperEditorInspector.findDocument(),
          equalsMarkdown("[https://google.com](https://google.com) to learn anything"),
        );
      });
    });

    group('applies keyboard appearance', () {
      testWidgetsOnIos('dark from theme', (tester) async {
        await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .useAppTheme(ThemeData.dark())
            .pump();

        // Holds the keyboard appearance sent to the platform.
        String? keyboardAppearance;

        _interceptKeyboardAppearanceSentToPlatform(
          tester,
          (appearance) => keyboardAppearance = appearance,
        );

        // Place the caret at the empty paragraph to trigger the software keyboard.
        await tester.placeCaretInParagraph('1', 0);

        // Ensure the given keyboardAppearance was applied.
        expect(keyboardAppearance, 'Brightness.dark');
      });

      testWidgetsOnIos('light from theme', (tester) async {
        await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .useAppTheme(ThemeData.light())
            .pump();

        // Holds the keyboard appearance sent to the platform.
        String? keyboardAppearance;

        _interceptKeyboardAppearanceSentToPlatform(
          tester,
          (appearance) => keyboardAppearance = appearance,
        );

        // Place the caret at the empty paragraph to trigger the software keyboard.
        await tester.placeCaretInParagraph('1', 0);

        // Ensure the given keyboardAppearance was applied.
        expect(keyboardAppearance, 'Brightness.light');
      });

      testWidgetsOnIos('from the given configuration', (tester) async {
        // Pump an editor with a light theme to ensure we are a configuration
        // with different brightness.
        await tester //
            .createDocument()
            .withSingleEmptyParagraph()
            .useAppTheme(ThemeData.light())
            .withImeConfiguration(
              const SuperEditorImeConfiguration(
                keyboardBrightness: Brightness.dark,
              ),
            )
            .pump();

        // Holds the keyboard appearance sent to the platform.
        String? keyboardAppearance;

        _interceptKeyboardAppearanceSentToPlatform(
          tester,
          (appearance) => keyboardAppearance = appearance,
        );

        // Place the caret at the empty paragraph to trigger the software keyboard.
        await tester.placeCaretInParagraph('1', 0);

        // Ensure the given keyboardAppearance was applied.
        expect(keyboardAppearance, 'Brightness.dark');
      });
    });

    testWidgetsOnMobile('opens software keyboard when tapping on caret', (tester) async {
      await tester
          .createDocument() //
          .withSingleParagraph()
          .withInputSource(TextInputSource.ime)
          .pump();

      // Place the caret at "Lorem| ipsum".
      await tester.placeCaretInParagraph('1', 5);

      // Hide the software keyboard using the system button.
      tester.testTextInput.hide();

      bool wasKeyboardShown = false;

      // Intercept the messages sent to the platform to check if
      // we showed the software keyboard.
      tester
          .interceptChannel(SystemChannels.textInput.name) //
          .interceptMethod(
        'TextInput.show',
        (methodCall) {
          wasKeyboardShown = true;

          return null;
        },
      );

      // Tap again on the same selected position.
      await tester.placeCaretInParagraph('1', 5);

      // Ensure the keyboard was shown.
      expect(wasKeyboardShown, isTrue);
    });

    testWidgetsOnIos('opens software keyboard when tapping on an expanded selection', (tester) async {
      await tester
          .createDocument() //
          .withSingleParagraph()
          .withInputSource(TextInputSource.ime)
          .pump();

      // Double tap to select "|Lorem| ipsum".
      await tester.doubleTapInParagraph('1', 1);

      // Hide the software keyboard using the system button.
      tester.testTextInput.hide();

      bool wasKeyboardShown = false;

      // Intercept the messages sent to the platform to check if
      // we showed the software keyboard.
      tester
          .interceptChannel(SystemChannels.textInput.name) //
          .interceptMethod(
        'TextInput.show',
        (methodCall) {
          wasKeyboardShown = true;

          return null;
        },
      );

      // Tap somewhere on the existing selection.
      await tester.tapInParagraph('1', 3);

      // Ensure the keyboard was shown.
      expect(wasKeyboardShown, isTrue);
    });

    testWidgetsOnAllPlatforms('clears composing region after losing focus', (tester) async {
      final focusNode = FocusNode();

      final testContext = await tester
          .createDocument() //
          .withTwoEmptyParagraphs()
          .withInputSource(TextInputSource.ime)
          .withFocusNode(focusNode)
          .pump();

      // Place the caret at the beginning of the document.
      await tester.placeCaretInParagraph('1', 0);

      // Type something to have some text to tap on.
      await tester.typeImeText('Composing: ');

      // Ensure we don't have a composing region.
      expect(testContext.composer.composingRegion.value, isNull);

      // Simulate an insertion containing a composing region.
      await tester.ime.sendDeltas(
        [
          const TextEditingDeltaInsertion(
            oldText: '. Composing: ',
            textInserted: "あs",
            insertionOffset: 13,
            selection: TextSelection.collapsed(offset: 15),
            composing: TextRange(start: 13, end: 15),
          ),
        ],
        getter: imeClientGetter,
      );

      // Ensure the editor applied a composing region.
      expect(
        testContext.composer.composingRegion.value,
        isNotNull,
      );

      // Remove focus from the editor.
      focusNode.unfocus();
      await tester.pump();

      // Ensure the composing region was cleared.
      expect(testContext.composer.composingRegion.value, isNull);
    });

    testWidgetsOnAllPlatforms('clears composing region after selection changes', (tester) async {
      final testContext = await tester
          .createDocument() //
          .withTwoEmptyParagraphs()
          .withInputSource(TextInputSource.ime)
          .pump();

      // Place the caret at the beginning of the document.
      await tester.placeCaretInParagraph('1', 0);

      // Type something to have some text to tap on.
      await tester.typeImeText('Composing: ');

      // Ensure we don't have a composing region.
      expect(testContext.composer.composingRegion.value, isNull);

      // Simulate an insertion containing a composing region.
      await tester.ime.sendDeltas(
        [
          const TextEditingDeltaInsertion(
            oldText: '. Composing: ',
            textInserted: "あs",
            insertionOffset: 13,
            selection: TextSelection.collapsed(offset: 15),
            composing: TextRange(start: 13, end: 15),
          ),
        ],
        getter: imeClientGetter,
      );

      // Ensure the editor applied a composing region.
      expect(
        testContext.composer.composingRegion.value,
        isNotNull,
      );

      // Intercept the setEditingState message sent to the platform to check if we
      // cleared the IME composing region when changing the selection.
      int? composingBase;
      int? composingExtent;
      tester
          .interceptChannel(SystemChannels.textInput.name) //
          .interceptMethod(
        'TextInput.setEditingState',
        (methodCall) {
          final params = methodCall.arguments as Map;
          composingBase = params['composingBase'];
          composingExtent = params['composingExtent'];

          return null;
        },
      );

      // Place the caret at the second paragraph.
      await tester.placeCaretInParagraph('2', 0);

      // Ensure the composing region was cleared in the IME.
      expect(composingBase, -1);
      expect(composingExtent, -1);

      // Ensure SuperEditor composing region was cleared.
      expect(testContext.composer.composingRegion.value, isNull);
    });

    testWidgetsOnMac('clears composing region after merging paragraphs', (tester) async {
      final testContext = await tester
          .createDocument() //
          .withTwoEmptyParagraphs()
          .withInputSource(TextInputSource.ime)
          .pump();

      // Place the caret at the beginning of the second paragraph.
      await tester.placeCaretInParagraph('2', 0);

      // Ensure we don't have a composing region.
      expect(testContext.composer.composingRegion.value, isNull);

      // Simulate an insertion containing a composing region.
      await tester.ime.sendDeltas(
        [
          const TextEditingDeltaNonTextUpdate(
            oldText: '. ',
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange(start: 2, end: 2),
          ),
          const TextEditingDeltaInsertion(
            oldText: '. ',
            textInserted: 'あ',
            insertionOffset: 2,
            selection: TextSelection.collapsed(offset: 3),
            composing: TextRange(start: 2, end: 3),
          ),
        ],
        getter: imeClientGetter,
      );

      // Ensure the editor applied the composing region.
      expect(
        testContext.composer.composingRegion.value,
        isNotNull,
      );

      // Intercept the setEditingState message sent to the platform to check if we
      // cleared the IME composing region when merging paragraphs.
      int? composingBase;
      int? composingExtent;
      tester
          .interceptChannel(SystemChannels.textInput.name) //
          .interceptMethod(
        'TextInput.setEditingState',
        (methodCall) {
          final params = methodCall.arguments as Map;
          composingBase = params['composingBase'];
          composingExtent = params['composingExtent'];

          return null;
        },
      );

      // Simulate the user pressing BACKSPACE to delete the first character.
      // Even though the selection sits after a whitespace in the IME, mac still reports
      // a composing region starting after the space.
      await tester.ime.sendDeltas(
        [
          const TextEditingDeltaDeletion(
            oldText: '. あ',
            deletedRange: TextRange(start: 2, end: 3),
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange(start: 2, end: 2),
          ),
        ],
        getter: imeClientGetter,
      );

      // Ensure we still have a composing region in the editor.
      expect(
        testContext.composer.composingRegion.value,
        isNotNull,
      );

      // Simulate the user pressing BACKSPACE to merge the paragraphs.
      // Now that we are deleting a whitespace, mac reports a deleteBackward: selector
      // instead of a deletion delta.
      await _receiveSelector('deleteBackward:');
      await tester.pump();

      // Ensure the composing region was cleared in the IME.
      expect(composingBase, -1);
      expect(composingExtent, -1);

      // Ensure SuperEditor composing region was cleared.
      expect(testContext.composer.composingRegion.value, isNull);

      // Ensure the paragraphs were merged.
      expect(testContext.document.nodeCount, equals(1));
    });
  });
}

/// Intercepts `TextInput.setClient` calls and invokes [onSetKeyboard]
/// with the configured keyboard keyboardAppearance.
void _interceptKeyboardAppearanceSentToPlatform(
    WidgetTester tester, void Function(String keyboardAppearance) onSetKeyboard) {
  tester
      .interceptChannel(SystemChannels.textInput.name) //
      .interceptMethod(
    'TextInput.setClient',
    (methodCall) {
      final params = methodCall.arguments[1] as Map;
      onSetKeyboard(params['keyboardAppearance']);
      return null;
    },
  );
}

/// Expects that the given [expectedTextWithSelection] corresponds to a
/// `TextEditingValue` that matches [actualTextEditingValue].
///
/// By combining the expected text with the expected selection into a formatted
/// `String`, this method provides a naturally readable expectation, as opposed
/// to a `TextSelection` with indices. For example, if the expected selection is
/// `TextSelection(base: 10, extent: 19)`, what segment of text does that include?
/// Instead, the caller provides a formatted `String`, like "Here is so|me text w|ith selection".
///
/// [expectedTextWithSelection] represents the expected text, and the expected
/// selection, all in one. The text within [expectedTextWithSelection] that
/// should be selected should be surrounded with "|" vertical bars.
///
/// Example:
///
///     This is expected text, and |this is the expected selection|.
///
/// This method doesn't work with text that actually contains "|" vertical bars.
void _expectTextEditingValue({
  required String expectedTextWithSelection,
  required TextEditingValue actualTextEditingValue,
}) {
  final selectionStartIndex = expectedTextWithSelection.indexOf("|");
  final selectionEndIndex =
      expectedTextWithSelection.indexOf("|", selectionStartIndex + 1) - 1; // -1 to account for the selection start "|"
  final expectedText = expectedTextWithSelection.replaceAll("|", "");
  final expectedSelection = TextSelection(baseOffset: selectionStartIndex, extentOffset: selectionEndIndex);

  expect(
    actualTextEditingValue,
    TextEditingValue(text: expectedText, selection: expectedSelection),
  );
}

MutableDocument _singleParagraphWithLinkDoc() {
  return MutableDocument(
    nodes: [
      ParagraphNode(
        id: "1",
        text: AttributedText(
          "https://google.com",
          AttributedSpans(
            attributions: [
              SpanMarker(
                attribution: LinkAttribution.fromUri(Uri.parse('https://google.com')),
                offset: 0,
                markerType: SpanMarkerType.start,
              ),
              SpanMarker(
                attribution: LinkAttribution.fromUri(Uri.parse('https://google.com')),
                offset: 17,
                markerType: SpanMarkerType.end,
              ),
            ],
          ),
        ),
      )
    ],
  );
}

class _TestImeOverrides extends DeltaTextInputClientDecorator {
  _TestImeOverrides(this.performActionCallback);

  final void Function(TextInputAction) performActionCallback;

  @override
  void performAction(TextInputAction action) {
    performActionCallback(action);
  }
}

/// Simulates pressing the SPACE key.
///
/// First, this method simulates pressing the SPACE key on a physical keyboard. If that key event goes unhandled
/// then this method generates an insertion delta of " ".
///
// TODO: extract this to the flutter_test_robots package.
Future<void> _typeSpaceAdaptive(WidgetTester tester) async {
  final handled = await tester.sendKeyEvent(LogicalKeyboardKey.space);

  if (handled) {
    await tester.pumpAndSettle();
    return;
  }

  await tester.typeImeText(' ');
}

/// Simulates a `TextInputClient.performSelectors` call from the platform.
Future<void> _receiveSelector(String selectorName) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.textInput.name,
    SystemChannels.textInput.codec.encodeMethodCall(
      MethodCall(
        "TextInputClient.performSelectors",
        [
          -1,
          [selectorName],
        ],
      ),
    ),
    null,
  );
}
