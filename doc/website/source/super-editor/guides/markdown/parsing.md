---
title: Parsing Markdown Documents
contentRenderers:
  - jinja
  - markdown
---
Super Editor supports parsing of Markdown documents into Super Editor documents.

To get started with parsing Markdown documents, add the Super Editor Markdown package:

```yaml
dependencies:
  super_editor: any
  super_editor_markdown: ^{{ pub.super_editor_markdown.version }}
```

[TODO: we use `any` for one and `^{{ pub.super_editor_markdown.version }}` for the other and in another guide we use a variable from `_data.yaml`. Should we use a consistent method or keep them as they are?]

Parse a Markdown document by calling the provided global function:

```dart
final superEditorDocument = deserializeMarkdownToDocument(markdownText);
```

## Custom Parsing
Super Editor Markdown offers a few options to customize Markdown parsing.

### Pre-Configured Syntax
Super Editor Markdown has a concept called `MarkdownSyntax`, which represents an entire
set of syntax preferences. The `deserializeMarkdownToDocument()` function accepts a
`MarkdownSyntax`.

There are only two options:
 * `MarkdownSyntax.superEditor`: Standard Markdown syntax, along with a number of custom
   Markdown syntaxes, including paragraph alignment with notation like `:---` for left alignment
   and `:---:` for center alignment.
 * `MarkdownSyntax.normal`: Standard Markdown syntax as defined by the `markdown` package.

By default, the `MarkdownSyntax.superEditor` option is used. To restrict parsing to the normal
syntax, pass that option into `deserializeMarkdownToDocument()`.

```dart
final superEditorDocument = deserializeMarkdownToDocument(
   markdownText,
   syntax: MarkdownSyntax.normal,
);
```

### Encode HTML or Leave Alone
When parsing Markdown text, HTML-based symbols can be converted to HTML escape codes,
or not.

For example, when encoding HTML characters, given the following Markdown:

```markdown
Flutter & Dart are > Android
```

The parsed output would become:

```
Flutter &amp; Dart are gt; Android
```

Using HTML escape codes ensures that non-HTML text isn't treated as HTML.

By default `deserializeMarkdownToDocument()` doesn't make these conversions.

To automatically convert characters to HTML escape codes, pass `true` for `encodeHtml`.

```dart
final superEditorDocument = deserializeMarkdownToDocument(
   markdownText,
   encodeHtml: true,
);
```

### Custom Markdown Blocks.
Markdown is sometimes extended with custom block syntaxes. These are non-standard syntaxes,
and they're not understood by standard parsers, like the `markdown` package parser. However,
the `markdown` package parser accepts `BlockSyntax` objects to parse custom Markdown blocks,
and Super Editor Markdown forwards those `BlockSyntax`es.

To parse custom Markdown block syntaxes, pass your `BlockSyntax`s to 
`deserializeMarkdownToDocument()`:

```dart
final superEditorDocument = deserializeMarkdownToDocument(
  markdownText,
  customBlockSyntax: [
    const TableSyntax(),
  ],
);
```

`TableSyntax` is an example custom `BlockSyntax` that you could create.

### Custom Super Editor Nodes
When parsing custom Markdown syntaxes, you'll need to tell Super Editor Markdown how to
convert those syntaxes into Super Editor `DocumentNode`s. Also, sometimes you might want
to deserialize a standard Markdown syntax into a Super Editor configuration that's different
from how Super Editor handles that syntax by default.

To customize how Markdown converts into Super Editor documents, provide custom
`ElementToNodeConverter`s to `deserializeMarkdownToDocument()`.

```dart
final superEditorDocument = deserializeMarkdownToDocument(
   markdownText,
   customBlockSyntax: [
     const TableSyntax(),
   ],
   customElementToNodeConverters: [
     const MarkdownTableToNodeConverter(),
   ],
);
```

[TODO: Is there any documentation anywhere how to create a `BlockSyntax` or a `TableSyntax` or `MarkdownTableToNodeConverter`? This should be added here.]