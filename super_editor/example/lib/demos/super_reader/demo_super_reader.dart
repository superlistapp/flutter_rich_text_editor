import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';

import 'example_document.dart';

class SuperReaderDemo extends StatefulWidget {
  const SuperReaderDemo({Key? key}) : super(key: key);

  @override
  State<SuperReaderDemo> createState() => _SuperReaderDemoState();
}

class _SuperReaderDemoState extends State<SuperReaderDemo> {
  late final Document _document;
  final _selection = ValueNotifier<DocumentSelection?>(null);
  final _selectionLayerLinks = SelectionLayerLinks();
  late MagnifierAndToolbarController _overlayController;
  late final SuperReaderIosControlsController _iosReaderControlsController;

  @override
  void initState() {
    super.initState();
    _document = createInitialDocument();
    _overlayController = MagnifierAndToolbarController();
    _iosReaderControlsController = SuperReaderIosControlsController(
      toolbarBuilder: _buildToolbar,
    );
  }

  @override
  void dispose() {
    _iosReaderControlsController.dispose();
    super.dispose();
  }

  void _copy() {
    if (_selection.value == null) {
      return;
    }

    final textToCopy = _textInSelection(
      document: _document,
      documentSelection: _selection.value!,
    );
    // TODO: figure out a general approach for asynchronous behaviors that
    //       need to be carried out in response to user input.
    _saveToClipboard(textToCopy);
  }

  String _textInSelection({
    required Document document,
    required DocumentSelection documentSelection,
  }) {
    final selectedNodes = document.getNodesInside(
      documentSelection.base,
      documentSelection.extent,
    );

    final buffer = StringBuffer();
    for (int i = 0; i < selectedNodes.length; ++i) {
      final selectedNode = selectedNodes[i];
      dynamic nodeSelection;

      if (i == 0) {
        // This is the first node and it may be partially selected.
        final baseSelectionPosition = selectedNode.id == documentSelection.base.nodeId
            ? documentSelection.base.nodePosition
            : documentSelection.extent.nodePosition;

        final extentSelectionPosition =
            selectedNodes.length > 1 ? selectedNode.endPosition : documentSelection.extent.nodePosition;

        nodeSelection = selectedNode.computeSelection(
          base: baseSelectionPosition,
          extent: extentSelectionPosition,
        );
      } else if (i == selectedNodes.length - 1) {
        // This is the last node and it may be partially selected.
        final nodePosition = selectedNode.id == documentSelection.base.nodeId
            ? documentSelection.base.nodePosition
            : documentSelection.extent.nodePosition;

        nodeSelection = selectedNode.computeSelection(
          base: selectedNode.beginningPosition,
          extent: nodePosition,
        );
      } else {
        // This node is fully selected. Copy the whole thing.
        nodeSelection = selectedNode.computeSelection(
          base: selectedNode.beginningPosition,
          extent: selectedNode.endPosition,
        );
      }

      final nodeContent = selectedNode.copyContent(nodeSelection);
      if (nodeContent != null) {
        buffer.write(nodeContent);
        if (i < selectedNodes.length - 1) {
          buffer.writeln();
        }
      }
    }
    return buffer.toString();
  }

  Future<void> _saveToClipboard(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }

  void _selectAll() {
    if (_document.isEmpty) {
      return;
    }

    _selection.value = _document.selectAll();
  }

  @override
  Widget build(BuildContext context) {
    return SuperReaderIosControlsScope(
      controller: _iosReaderControlsController,
      child: SuperReader(
        document: _document,
        selection: _selection,
        overlayController: _overlayController,
        selectionLayerLinks: _selectionLayerLinks,
        stylesheet: defaultStylesheet.copyWith(
          addRulesAfter: [
            taskStyles,
          ],
        ),
        androidToolbarBuilder: (_) => AndroidTextEditingFloatingToolbar(
          onCopyPressed: _copy,
          onSelectAllPressed: _selectAll,
        ),
      ),
    );
  }

  Widget _buildToolbar(context, mobileToolbarKey, focalPoint) {
    return IOSTextEditingFloatingToolbar(
      key: mobileToolbarKey,
      focalPoint: focalPoint,
      onCopyPressed: _copy,
    );
  }
}
