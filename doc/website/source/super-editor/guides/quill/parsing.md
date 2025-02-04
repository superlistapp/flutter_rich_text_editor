---
title: Parsing Quill Delta Documents
contentRenderers:
  - jinja
  - markdown
---
Super Editor supports parsing of [Quill Delta documents](https://quilljs.com/docs/delta/) into Super Editor documents.

To get started with parsing Quill documents, add the Super Editor Quill package:

```yaml
dependencies:
  super_editor: any
  super_editor_quill: ^{{ pub.super_editor_quill.version }}
```

A Quill Delta document is a JSON object, which contains a list of `ops`. You can parse
a full document, or you can parse just a list of `ops`. Global functions are provided
for both cases.

Parse a complete Quill Delta document with `parseQuillDeltaDocument()`:

```dart
final quillDocument = getMyQuillDocument();

final superEditorDocument = parseQuillDeltaDocument(quillDocument);
```

Parse a list of Quill Delta operations with `parseQuillDeltaOps()`:

```dart
final quillOps = getMyQuillOps();

final superEditorDocument = parseQuillDeltaOps(quillOps);
```

Both parsing methods produce a `MutableDocument`, which you can then use within
a logical `Editor`, and then within a visual `SuperEditor` widget.

## Custom Parsing
Super Editor Quill supports multiple customizations for document parsing.

### Custom Blocks, Attributes, and Embeds.
It's common among Quill-based editors to use custom inline attributes, custom
inline embeds, and custom block formats. Super Editor Quill supports custom
parsing behaviors within each of the global parsing methods.

Add support for your custom blocks, attributes, and embeds by passing those
artifacts to the parser methods:

```dart
final superEditorDocument = parseQuillDeltaDocument(
  quillDocument,
  blockFormats: {
    const MyVideoBlockFormat(),
    ...defaultBlockFormats
  },
  inlineFormats: {
    const MyUserTagFormat(),
    ...defaultInlineFormats
  },
  inlineEmbedFormats: [
    const MyMathFormulaFormat(),
  ],
);
```

#### Custom Blocks
A "block" is a standalone unit within a document, e.g., a paragraph, image, video, etc.

To parse a custom block, implement `BlockDeltaFormat`.

The following example implements a hypothetical video block:

```dart
class VideoBlockFormat implements BlockDeltaFormat {
  const VideoBlockFormat();

  @override
  List<EditRequest>? applyTo(Operation operation, Editor editor) {
    // Pull out the data based on your custom video Delta format...
    if (!operation.hasAttribute('video')) {
      return null;
    }
    final videoUrl = operation['video'];
    if (videoUrl is! String) {
      return null;
    }
    
    // This example assumes that your editor supports a `InsertVideoRequest`.
    editor.executeRequests([
      InsertVideoRequest(videoUrl),
    ]);
  }
}
```

#### Custom Inline Attributes
Inline attributes are metadata that applies to spans of text. Typically this metadata represents styles,
such as bold, italic, and underline. These attributes can also mix styling with logical information
such as for links.

To parse a custom inline attribute, implement `InlineDeltaFormat`.

The following example implements a hypothetical user tag inline style:

```dart
class UserTagFormat implements InlineDeltaFormat {
  @override
  Attribution? from(Operation operation) {
    // Pull out the data based on your custom user tag Delta attribute format...
    if (!operation.hasAttribute('tag')) {
      return null;
    }
    final tag = operation['tag'];
    if (tag is! Map<String, dynamic>) {
      return null;
    }
    
    final userId = tag['userId'];
    final userName = tag['userName'];
    if (userId is! String || userName is! String) {
      return null;
    }
    
    // This hypothetical example assumes that your editor supports a
    // `InsertUserTagRequest`.
    editor.executeRequests([
      InsertUserTagRequest(
        id: userId,
        name: userName,
      ),
    ]);

    return attribution;
  }
}
```

#### Custom Inline Embeds
Inline embeds are pieces of non-text content that are placed within lines of text. For example,
a math formula, or a tiny bitmap image.

Currently, Super Editor doesn't support inline widgets. Therefore, the actions that you can take
with inline embeds, is limited. However, Super Editor Quill supports parsing those embeds.

To parse a custom inline embed, implement `InlineEmbedFormat`.

The following hypothetical example parses an inline bitmap image:

```dart
class InlineImageFormat implements InlineEmbedFormat {
  @override
  bool insert(Editor editor, DocumentComposer composer, Map<String, dynamic> embed) {
    // Pull out the data based on your custom Delta inline image format...
    final url = embed['image'];
    if (url is! String) {
      return false;
    }
    
    // TODO: take whatever action you'd like with the inline image URL.
    
    return true;
  }
}
```

### Custom Editor
When Super Editor Quill parses a Quill document, it internally creates an `Editor`, `MutableDocument`,
and a `MutableDocumentComposer`, which is then used to run every content insertion listed in the Quill
document.

Apps with custom formats might need to take unusual actions to insert those blocks, attributes, and
inline embeds through an `Editor` and into the `MutableDocument`. For this reason, Super Editor Quill
allows you to pass your own `Editor`, with custom request handlers and editables, into the global
parsers.

```dart
final superEditorDocument = MutableDocument.empty();
final editor = Editor(/* custom config */);

final quillDocument = getQuillDocument();

// Parse the `quillDocument` into the given `customEditor`, which will use
// the request handlers that you chose to register with your `editor`.
parseQuillDeltaDocument(
  quillDocument,
  customEditor: editor,
);
```