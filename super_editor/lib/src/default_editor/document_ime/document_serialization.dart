import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/default_editor/selection_upstream_downstream.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';

/// Serializes a [Document] and [DocumentSelection] into a form that's understood by
/// the Input Method Engine (IME), and vis-a-versa.
///
/// The IME only understands strings of plain text. Therefore, to make [Document] content
/// available for IME editing, the [Document] structure needs to be serialized into a run of text.
///
/// When the IME alters the given content, that plain text needs to be deserialized back into
/// a [Document] structure.
///
/// This class implements both [Document] serialization and deserialization for the IME.
class DocumentImeSerializer {
  static const _leadingCharacter = '. ';

  DocumentImeSerializer(
    this._doc,
    this.selection,
    this.composingRegion, [
    // Always prepend the placeholder characters because
    // changing the editing value when the IME is composing
    // causes the IME composition to restart.
    //
    // See https://github.com/superlistapp/super_editor/issues/1641 for details.
    this._prependedCharacterPolicy = PrependedCharacterPolicy.include,
  ]) {
    _serialize();
  }

  final Document _doc;
  DocumentSelection selection;
  DocumentRange? composingRegion;
  final imeRangesToDocTextNodes = <TextRange, NodePath>{};
  final docTextNodesToImeRanges = <NodePath, TextRange>{};
  final selectedNodes = <DocumentNode>[];
  late String imeText;
  final PrependedCharacterPolicy _prependedCharacterPolicy;
  String _prependedPlaceholder = '';

  // TextNode(1) - Hello world
  // TextNode(2) - Paragraph 2
  // ImageNode(3)
  // TextNode(4) - YOLO
  // CompositeNode(5)
  //    TextNode(6) - Inner paragraph
  //    ListItemNode(7) - Item 1
  //    ListItemNode(8) - Item 2
  //    ListItemNode(9) - Item 3
  // TextNode(10) - Final paragraph

  // CompositeNode(5)
  //    TextNode(6) - Inner para|graph
  //
  // CompositeNodePosition
  //  - node ID: "5"
  //  - child node ID: "6"
  //  - child node position: TextNodePosition(offset: 10)
  //
  // .Inner Paragraph

  void _serialize() {
    editorImeLog.fine("Creating an IME model from document, selection, and composing region");
    print("Serializing document to send to the IME");
    final buffer = StringBuffer();
    int characterCount = 0;

    if (_shouldPrependPlaceholder()) {
      // Put an arbitrary character at the front of the text so that
      // the IME will report backspace buttons when the caret sits at
      // the beginning of the node. For example, the caret is at the
      // beginning of some text and we want to combine this text with
      // the text above it when the user presses backspace.
      //
      //     Text above...
      //     |The selected text node.
      _prependedPlaceholder = _leadingCharacter;
      buffer.write(_prependedPlaceholder);
      characterCount = _prependedPlaceholder.length;
    } else {
      _prependedPlaceholder = '';
    }

    print("Selection: $selection");
    print("");
    selectedNodes.clear();
    selectedNodes.addAll(_doc.getNodesInContentOrder(selection));
    for (int i = 0; i < selectedNodes.length; i += 1) {
      // Append a newline character before appending another node's text.
      //
      // The choice to separate each node with a newline was a judgement call.
      // There is no OS-level expectation for how structured content should
      // collapse down to IME content.
      if (i != 0) {
        buffer.write('\n');
        characterCount += 1;
      }

      var node = selectedNodes[i];
      final nodePath = NodePath.forNode(node.id);
      print("Serializing node for IME: $node");
      if (node is CompositeDocumentNode) {
        final serializedCharacterCount = _serializeCompositeNode(NodePath.forNode(node.id), node, buffer);
        characterCount += serializedCharacterCount;

        continue;
      }

      if (node is! TextNode) {
        buffer.write('~');
        characterCount += 1;

        final imeRange = TextRange(start: characterCount - 1, end: characterCount);
        imeRangesToDocTextNodes[imeRange] = nodePath;
        docTextNodesToImeRanges[nodePath] = imeRange;

        continue;
      }

      // Cache mappings between the IME text range and the document position
      // so that we can easily convert between the two, when requested.
      final imeRange = TextRange(start: characterCount, end: characterCount + node.text.length);
      editorImeLog.finer("IME range $imeRange -> text node content '${node.text.toPlainText()}'");
      imeRangesToDocTextNodes[imeRange] = nodePath;
      docTextNodesToImeRanges[nodePath] = imeRange;

      // Concatenate this node's text with the previous nodes.
      buffer.write(node.text.toPlainText());
      characterCount += node.text.length;
    }

    imeText = buffer.toString();
    editorImeLog.fine("IME serialization:\n'$imeText'");
  }

  int _serializeCompositeNode(NodePath nodePath, CompositeDocumentNode node, StringBuffer buffer) {
    int characterCount = 0;
    for (final innerNode in node.nodes) {
      final innerNodePath = nodePath.addSubPath(innerNode.id);
      if (innerNode is CompositeDocumentNode) {
        characterCount += _serializeCompositeNode(innerNodePath, innerNode, buffer);
        continue;
      }

      characterCount += _serializeNonCompositeNode(innerNodePath, node, buffer, characterCount);

      if (innerNode != node.nodes.last) {
        buffer.write('\n');
        characterCount += 1;
      }
    }

    return characterCount;
  }

  int _serializeNonCompositeNode(NodePath nodePath, DocumentNode node, StringBuffer buffer, int characterCount) {
    if (node is! TextNode) {
      buffer.write('~');

      final imeRange = TextRange(start: characterCount - 1, end: characterCount);
      imeRangesToDocTextNodes[imeRange] = nodePath;
      docTextNodesToImeRanges[nodePath] = imeRange;

      return 1;
    }

    // Cache mappings between the IME text range and the document position
    // so that we can easily convert between the two, when requested.
    final imeRange = TextRange(start: characterCount, end: characterCount + node.text.length);
    editorImeLog.finer("IME range $imeRange -> text node content '${node.text.text}'");
    imeRangesToDocTextNodes[imeRange] = nodePath;
    docTextNodesToImeRanges[nodePath] = imeRange;

    // Concatenate this node's text with the previous nodes.
    buffer.write(node.text.text);
    return node.text.length;
  }

  bool _shouldPrependPlaceholder() {
    if (_prependedCharacterPolicy == PrependedCharacterPolicy.include) {
      // The client explicitly requested prepended characters. This is
      // useful, for example, when a client has an existing serialization that
      // includes prepended characters and wants to compare that serialization
      // to a new serialization. The client wants to ensure that the new
      // serialization has prepended characters, too.
      return true;
    } else if (_prependedCharacterPolicy == PrependedCharacterPolicy.exclude) {
      return false;
    }

    // We want to prepend an arbitrary placeholder character whenever the
    // user's selection is collapsed at the beginning of a node. Without the
    // arbitrary character, the IME would assume that there's no content
    // before the current node and therefore it wouldn't report the backspace
    // button.
    final selectedNode = _doc.getNode(selection.extent)!;
    return selection.isCollapsed && selection.extent.nodePosition == selectedNode.beginningPosition;
  }

  bool get didPrependPlaceholder => _prependedPlaceholder.isNotEmpty;

  DocumentSelection? imeToDocumentSelection(TextSelection imeSelection) {
    editorImeLog.fine("Creating doc selection from IME selection: $imeSelection");
    if (!imeSelection.isValid) {
      editorImeLog.fine("The IME selection is empty. Returning a null document selection.");
      return null;
    }

    if (didPrependPlaceholder) {
      // The IME might be trying to select our invisible prepended characters.
      // If so, we need to adjust the IME selection bounds.
      if ((imeSelection.isCollapsed && imeSelection.extentOffset < _prependedPlaceholder.length) ||
          (imeSelection.start < _prependedPlaceholder.length && imeSelection.end == _prependedPlaceholder.length)) {
        // The IME is only trying to select our invisible characters. Return null
        // for an empty document selection.
        editorImeLog.fine("The IME only selected invisible characters. Returning a null document selection.");
        return null;
      } else if (imeSelection.start < _prependedPlaceholder.length) {
        // The IME is trying to select some invisible characters and some real
        // characters. Remove the invisible characters from the IME selection before
        // converting it to a document selection.
        editorImeLog.fine("Removing invisible characters from IME selection.");
        imeSelection = imeSelection.copyWith(
          baseOffset: max(imeSelection.baseOffset, _prependedPlaceholder.length),
          extentOffset: max(imeSelection.extentOffset, _prependedPlaceholder.length),
        );
        editorImeLog.fine("Adjusted IME selection is: $imeSelection");
      } else {
        editorImeLog.fine("The IME only selected visible characters. No adjustment necessary.");
      }
    } else {
      editorImeLog.fine("The serialization doesn't have any invisible characters. No adjustment necessary.");
    }

    editorImeLog.fine("Calculating the base DocumentPosition for the DocumentSelection");
    final base = _imeToDocumentPosition(
      imeSelection.base,
      isUpstream: imeSelection.base.affinity == TextAffinity.upstream,
    );
    editorImeLog.fine("Selection base: $base");

    editorImeLog.fine("Calculating the extent DocumentPosition for the DocumentSelection");
    final extent = _imeToDocumentPosition(
      imeSelection.extent,
      isUpstream: imeSelection.extent.affinity == TextAffinity.upstream,
    );
    editorImeLog.fine("Selection extent: $extent");

    return DocumentSelection(base: base, extent: extent);
  }

  DocumentRange? imeToDocumentRange(TextRange imeRange) {
    editorImeLog.fine("Creating doc range from IME range: $imeRange");
    if (!imeRange.isValid) {
      editorImeLog.fine("The IME range is empty. Returning null document range.");
      // The range is empty. Return null.
      return null;
    }

    if (didPrependPlaceholder) {
      // The IME might be trying to select our invisible prepended characters.
      // If so, we need to adjust the IME selection bounds.
      if ((imeRange.isCollapsed && imeRange.end < _prependedPlaceholder.length) ||
          (imeRange.start < _prependedPlaceholder.length && imeRange.end == _prependedPlaceholder.length)) {
        // The IME is only trying to select our invisible characters. Return null
        // for an empty document range.
        editorImeLog
            .fine("The IME tried to create a range around invisible characters. Returning null document range.");
        return null;
      } else {
        // The IME is trying to select some invisible characters and some real
        // characters. Remove the invisible characters from the IME range before
        // converting it to a document range.
        editorImeLog.fine("Removing arbitrary character from IME range.");
        editorImeLog.fine("Before adjustment, range: $imeRange");
        editorImeLog.fine("Prepended characters length: ${_prependedPlaceholder.length}");
        imeRange = TextRange(
          start: max(imeRange.start, _prependedPlaceholder.length),
          end: max(imeRange.end, _prependedPlaceholder.length),
        );
        editorImeLog.fine("Adjusted IME range to: $imeRange");
      }
    } else {
      editorImeLog.fine("The IME is only composing visible characters. No adjustment necessary.");
    }

    return DocumentRange(
      start: _imeToDocumentPosition(
        TextPosition(offset: imeRange.start),
        isUpstream: false,
      ),
      end: _imeToDocumentPosition(
        TextPosition(offset: imeRange.end),
        isUpstream: false,
      ),
    );
  }

  /// Returns `true` if the [imePosition] is inside the prepended placeholder,
  /// or `false` otherwise.
  ///
  /// The placeholder is a sequence of characters that are sent to the IME, but are
  /// invisible to the user.
  bool isPositionInsidePlaceholder(TextPosition imePosition) {
    if (!didPrependPlaceholder) {
      return false;
    }

    if (imePosition.offset <= -1) {
      // The given imePosition might be a selection or a composing region.
      // The IME composing position always has a value. When the IME wants
      // to describe the absence of a composing region, the offset is set to -1.
      // Therefore, this position refers to the absence of a composing region, so
      // this position isn't sitting in the placeholder.
      return false;
    }

    if (imePosition.offset >= _prependedPlaceholder.length) {
      return false;
    }

    return true;
  }

  /// Returns the first visible position in the IME content.
  ///
  /// If a placeholder is prepended, returns the first position after the placeholder,
  /// otherwise, returns the first position.
  TextPosition get firstVisiblePosition {
    return didPrependPlaceholder //
        ? TextPosition(offset: _prependedPlaceholder.length)
        : const TextPosition(offset: 0);
  }

  DocumentPosition _imeToDocumentPosition(TextPosition imePosition, {required bool isUpstream}) {
    for (final range in imeRangesToDocTextNodes.keys) {
      if (range.start <= imePosition.offset && imePosition.offset <= range.end) {
        final nodePath = imeRangesToDocTextNodes[range]!;
        final node = _doc.getNodeById(nodePath.nodeIds.last)!;

        late NodePosition contentNodePosition;
        if (node is TextNode) {
          contentNodePosition = TextNodePosition(offset: imePosition.offset - range.start);
          // return DocumentPosition(
          //   nodeId: node.id,
          //   nodePosition: TextNodePosition(offset: imePosition.offset - range.start),
          // );
        } else {
          if (imePosition.offset <= range.start) {
            // Return a position at the start of the node.
            contentNodePosition = node.beginningPosition;
            // return DocumentPosition(
            //   nodeId: node.id,
            //   nodePosition: node.beginningPosition,
            // );
          } else {
            // Return a position at the end of the node.
            contentNodePosition = node.endPosition;
            // return DocumentPosition(
            //   nodeId: node.id,
            //   nodePosition: node.endPosition,
            // );
          }
        }

        if (nodePath.nodeIds.length == 1) {
          // This is a single node - not a composite node. Return it as-is.
          return DocumentPosition(
            nodeId: node.id,
            nodePosition: contentNodePosition,
          );
        }

        NodePosition compositeNodePosition = contentNodePosition;
        for (int i = nodePath.nodeIds.length - 2; i >= 0; i -= 1) {
          compositeNodePosition = CompositeNodePosition(
            compositeNodeId: nodePath.nodeIds[i],
            childNodeId: nodePath.nodeIds[i + 1],
            childNodePosition: compositeNodePosition,
          );
        }
        return DocumentPosition(
          nodeId: nodePath.nodeIds.first,
          nodePosition: compositeNodePosition,
        );
      }
    }

    editorImeLog.shout("---------------DocumentImeSerializer----------------------");
    editorImeLog.shout("Couldn't map an IME position to a document position.");
    editorImeLog.shout("Desired IME position: '$imePosition'");
    editorImeLog.shout("");
    editorImeLog.shout("IME text: '$imeText'");
    editorImeLog.shout("IME prepended placeholder: '$_prependedPlaceholder'");
    editorImeLog.shout("");
    editorImeLog.shout("Document selection: $selection");
    editorImeLog.shout("Document composing region: $composingRegion");
    editorImeLog.shout("");
    editorImeLog.shout("IME Ranges to text nodes:");
    for (final entry in imeRangesToDocTextNodes.entries) {
      editorImeLog.shout(" - IME range: ${entry.key} -> Text node: ${entry.value}");
      editorImeLog.shout("    ^ node content: '${_getTextNodeAtNodePath(entry.value).text.toPlainText()}'");
    }
    editorImeLog.shout("-----------------------------------------------------------");
    throw Exception(
        "Couldn't map an IME position to a document position. \nTextEditingValue: '$imeText'\nIME position: $imePosition");
  }

  TextNode _getTextNodeAtNodePath(NodePath path) {
    return _doc.getNodeById(path.nodeIds.last) as TextNode;
  }

  TextSelection documentToImeSelection(DocumentSelection docSelection) {
    editorImeLog.fine("Converting doc selection to ime selection: $docSelection");
    final selectionAffinity = _doc.getAffinityForSelection(docSelection);
    final startImePosition = _documentToImePosition(docSelection.base);
    final endImePosition = _documentToImePosition(docSelection.extent);

    editorImeLog.fine("Start IME position: $startImePosition");
    editorImeLog.fine("End IME position: $endImePosition");
    return TextSelection(
      baseOffset: startImePosition.offset,
      extentOffset: endImePosition.offset,
      affinity: selectionAffinity,
    );
  }

  TextRange documentToImeRange(DocumentRange? documentRange) {
    editorImeLog.fine("Converting doc range to ime range: $documentRange");
    if (documentRange == null) {
      editorImeLog.fine("The document range is null. Returning an empty IME range.");
      return const TextRange(start: -1, end: -1);
    }

    final startImePosition = _documentToImePosition(documentRange.start);
    final endImePosition = _documentToImePosition(documentRange.end);

    editorImeLog.fine("After converting DocumentRange to TextRange:");
    editorImeLog.fine("Start IME position: $startImePosition");
    editorImeLog.fine("End IME position: $endImePosition");
    return TextRange(
      start: startImePosition.offset,
      end: endImePosition.offset,
    );
  }

  TextPosition _documentToImePosition(DocumentPosition docPosition) {
    editorImeLog.fine("Converting DocumentPosition to IME TextPosition: $docPosition");
    // FIXME: don't assume top-level node
    final nodePath = NodePath.forNode(docPosition.nodeId);
    final imeRange = docTextNodesToImeRanges[nodePath];
    if (imeRange == null) {
      print("Available node paths in mapping:");
      for (final entry in docTextNodesToImeRanges.entries) {
        print(" - ${entry.key}");
      }
      throw Exception("No such node path in the IME content: $nodePath");
    }

    final nodePosition = docPosition.nodePosition;

    if (nodePosition is UpstreamDownstreamNodePosition) {
      if (nodePosition.affinity == TextAffinity.upstream) {
        editorImeLog.fine("The doc position is an upstream position on a block.");
        // Return the text position before the special character,
        // e.g., "|~".
        return TextPosition(offset: imeRange.start);
      } else {
        editorImeLog.fine("The doc position is a downstream position on a block.");
        // Return the text position after the special character,
        // e.g., "~|".
        return TextPosition(offset: imeRange.start + 1);
      }
    }

    if (nodePosition is TextNodePosition) {
      return TextPosition(offset: imeRange.start + (docPosition.nodePosition as TextNodePosition).offset);
    }

    if (nodePosition is CompositeNodePosition) {
      final innerDocumentPosition =
          DocumentPosition(nodeId: nodePosition.childNodeId, nodePosition: nodePosition.childNodePosition);

      // Recursive call to create the IME text position for the content within the composite node.
      return _documentToImePosition(innerDocumentPosition);
    }

    throw Exception("Super Editor doesn't know how to convert a $nodePosition into an IME-compatible selection");
  }

  TextEditingValue toTextEditingValue() {
    editorImeLog.fine("Creating TextEditingValue from document. Selection: $selection");
    editorImeLog.fine("Text:\n'$imeText'");
    final imeSelection = documentToImeSelection(selection);
    editorImeLog.fine("Selection: $imeSelection");
    final imeComposingRegion = documentToImeRange(composingRegion);
    editorImeLog.fine("Composing region: $imeComposingRegion");

    return TextEditingValue(
      text: imeText,
      selection: imeSelection,
      composing: imeComposingRegion,
    );
  }
}

enum PrependedCharacterPolicy {
  automatic,
  include,
  exclude,
}
