import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_markdown/super_editor_markdown.dart';

import 'spot_check_scaffold.dart';

class UrlLauncherSpotChecks extends StatefulWidget {
  const UrlLauncherSpotChecks({super.key});

  @override
  State<UrlLauncherSpotChecks> createState() => _UrlLauncherSpotChecksState();
}

class _UrlLauncherSpotChecksState extends State<UrlLauncherSpotChecks> {
  late final Editor _editor;

  @override
  void initState() {
    super.initState();

    _editor = createDefaultDocumentEditor(
      document: deserializeMarkdownToDocument('''
# Linkification Spot Check
In this spot check, we create a variety of linkification scenarios. We expect each link to be linkified, and to take the expect action when tapped.

## Markdown Links (with schemes)
[https://google.com](https://google.com)
[mailto:somebody@gmail.com](mailto:somebody@gmail.com)
[obsidian://open?vault=my-vault](obsidian://open?vault=my-vault)

## Markdown Links (no schemes)
[google.com](google.com)
[somebody@gmail.com](somebody@gmail.com)

## Pasted Links
The first set of pasted links are all pasted together within a single block of text. Then the same links are pasted with one link per line.
'''),
      composer: MutableDocumentComposer(),
    );

    _pasteLinks();
  }

  Future<void> _pasteLinks() async {
    final links = '''

google.com https://google.com somebody@gmail.com mailto:somebody@gmail.com obsidian://open?vault=my-vault

google.com
https://google.com
somebody@gmail.com
mailto:somebody@gmail.com
obsidian://open?vault=my-vault
''';

    // Put the text on the clipboard.
    await Clipboard.setData(ClipboardData(text: links));

    // Place the caret at the end of the document.
    // TODO: Add a startPosition and endPosition to `Document`.
    _editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            documentPath: NodePath.forNode(_editor.document.last.id),
            nodePosition: (_editor.document.last as TextNode).endPosition,
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);

    // Paste the text from the clipboard, which should include a linkification reaction.
    CommonEditorOperations(
      editor: _editor,
      document: _editor.document,
      composer: _editor.composer,
      documentLayoutResolver: () => throw UnimplementedError(),
    ).paste();
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SpotCheckScaffold(
      content: SuperEditor(
        editor: _editor,
        stylesheet: defaultStylesheet.copyWith(
          addRulesAfter: [
            ..._darkModeStyles,
          ],
        ),
      ),
    );
  }
}

final _darkModeStyles = [
  StyleRule(
    BlockSelector.all,
    (doc, docNode) {
      return {
        Styles.textStyle: const TextStyle(
          color: Color(0xFFCCCCCC),
        ),
      };
    },
  ),
  StyleRule(
    const BlockSelector("header1"),
    (doc, docNode) {
      return {
        Styles.textStyle: const TextStyle(
          color: Color(0xFF888888),
        ),
      };
    },
  ),
  StyleRule(
    const BlockSelector("header2"),
    (doc, docNode) {
      return {
        Styles.textStyle: const TextStyle(
          color: Color(0xFF888888),
        ),
      };
    },
  ),
];
