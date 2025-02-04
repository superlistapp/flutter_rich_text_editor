---
title: Assemble a Document
---
# Assemble a Document
In Super Editor, a document is typically represented by an instance of `MutableDocument`. The
easiest way to assemble a `MutableDocument` is by [de-serializing Markdown](/guides/document-from-markdown).
However, there are situations where you might need to construct a `MutableDocument` directly. This
guide shows you how.

## What is a Document?
In Super Editor, a `Document` is a series of nodes - specifically `DocumentNode`s. Different types of
`DocumentNode`s are available for different types of content, such as `ParagraphNode` and `ImageNode`.

Assembling a `Document` means assembling a list of desired `DocumentNode`s.

## Construct a `MutableDocument` with Content
The `MutableDocument` constructor accepts a list of `DocumentNode`s as initial content.

```dart
final document = MutableDocument(
  nodes: [
    ParagraphNode(
      id: "node1", 
      text: AttributedText("Hello, world!"),
    ),
  ],
);
```

## Alter an existing `MutableDocument`
A `MutableDocument` can be altered after construction.

You can insert nodes.

```dart
document.insertNodeAt(
  1,
  ParagraphNode(
    id: Editor.createNodeId(),
    text: AttributedText("New paragraph"),
  ),
);
```

`Editor.createNodeId()` is a convenience method that generates a random UUID string for the node.

You can move nodes.

```dart
document.moveNode(nodeId: "node1", targetIndex: 1);
```

You can remove nodes.

```dart
document.deleteNodeAt(0);
```

If your goal is to use a `MutableDocument` in an editor experience, consider wrapping the
`MutableDocument` in an `Editor`, and then use the standard edit pipeline to alter the document's
content. [TODO: what is the standard editor pipeline? Let's link to those docs or give a brief explanation.]