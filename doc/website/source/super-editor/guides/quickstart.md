---
title: Super Editor Quickstart
contentRenderers: ["jinja", "markdown"]
---

# Super Editor Quickstart
Super Editor comes with sane defaults to help you get started quickly with an editor experience. These defaults include support for images, list items, blockquotes, and horizontal rules, as well as selection gestures and various keyboard shortcuts.

Drop in the default editor and start editing.

## Add `super_editor` to your project
To use `super_editor`, add a dependency in your `pubspec.yaml`.

```yaml
dependencies:
  super_editor: {{ super_editor_version }}
```

## Display an editor
Super Editor is both the visual editor that users see and interact with, as well as the logical editor that handles those interactions behind the scenes. 

Start by initializing the logical editor:

```dart
import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

class MyEditorPage extends StatefulWidget {
  const MyEditorPage({super.key});

  @override
  State<MyEditorPage> createState() => _MyEditorPageState();
}

class _MyEditorPageState extends State<MyEditorPage> {
  late Editor _editor;

  @override
  void initState() {
    super.initState();
    _editor = createDefaultDocumentEditor(
      document: MutableDocument.empty(),
      composer: MutableDocumentComposer(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SuperEditor(
      editor: _editor,
    );
  }
}
```

Multiple objects work together to edit documents. A `Document` provides a consistent structure for content within a document. A `DocumentComposer` holds the user's current selection, along with any styles that should be applied to newly typed text. An `Editor` alters the `Document`.

The `Editor` fulfills a number of responsibilities, each of which is configurable. Rather than force every user to fully configure an `Editor`, `super_editor` provides a global factory called `createDefaultDocumentEditor`, which configures an `Editor` with sane defaults. To adjust those defaults, consider copying the implementation of `createDefaultDocumentEditor` and then altering the implementation to meet your needs.

The `SuperEditor` widget creates a user interface for visualizing the `Document`, changing the selection in the `DocumentComposer`, and submitting change requests to the `Editor`. The `SuperEditor` widget is the part that most people think of when they think of "document editing". The `SuperEditor` widget includes many configurable properties, all of which focus on user interactions, e.g., selection and focus policies, gesture interceptors, scroll control, mobile selection handles, and more.

That's all it takes to get started with your very own editor. Run your app, tap in the editor, and start typing!

Check out the other guides for more help.
