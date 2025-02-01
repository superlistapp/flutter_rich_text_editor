import 'package:example/demos/in_the_lab/in_the_lab_scaffold.dart';
import 'package:flutter/material.dart' hide ListenableBuilder;
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:super_editor/super_editor.dart';

import 'popover_list.dart';

class ActionTagsFeatureDemo extends StatefulWidget {
  const ActionTagsFeatureDemo({super.key});

  @override
  State<ActionTagsFeatureDemo> createState() => _ActionTagsFeatureDemoState();
}

class _ActionTagsFeatureDemoState extends State<ActionTagsFeatureDemo> {
  late final MutableDocument _document;
  late final MutableDocumentComposer _composer;
  late final Editor _editor;
  late final ActionTagsPlugin _actionTagPlugin;

  late final FocusNode _editorFocusNode;

  final _actions = <String>[];

  @override
  void initState() {
    super.initState();

    _document = MutableDocument.empty();
    _composer = MutableDocumentComposer();
    _editor = Editor(
      editables: {
        Editor.documentKey: _document,
        Editor.composerKey: _composer,
      },
      requestHandlers: [
        (editor, request) => request is ConvertSelectedTextNodeRequest //
            ? ConvertSelectedTextNodeCommand(request.newType)
            : null,
        ...defaultRequestHandlers,
      ],
    );

    _actionTagPlugin = ActionTagsPlugin()..composingActionTag.addListener(_updateActionTagList);

    _editorFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _editorFocusNode.dispose();

    _actionTagPlugin.composingActionTag.removeListener(_updateActionTagList);

    _composer.dispose();
    _editor.dispose();
    _document.dispose();

    super.dispose();
  }

  void _updateActionTagList() {
    setState(() {
      _actions.clear();

      for (final node in _document) {
        if (node is! TextNode) {
          continue;
        }

        final actionSpans = node.text.getAttributionSpansInRange(
          attributionFilter: (a) => a == actionTagComposingAttribution,
          range: SpanRange(0, node.text.length - 1),
        );

        for (final actionSpan in actionSpans) {
          _actions.add(node.text.substring(actionSpan.start, actionSpan.end + 1));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InTheLabScaffold(
          content: _buildEditor(),
          supplemental: _buildTagList(),
        ),
        if (_actionTagPlugin.composingActionTag.value != null)
          Follower.withOffset(
            link: _composingLink,
            offset: Offset(0, 16),
            leaderAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            showWhenUnlinked: false,
            child: _ActionTagsListPopover(
              editor: _editor,
              actionTagPlugin: _actionTagPlugin,
              editorFocusNode: _editorFocusNode,
            ),
          ),
      ],
    );
  }

  Widget _buildEditor() {
    return SuperEditor(
      editor: _editor,
      focusNode: _editorFocusNode,
      componentBuilders: [
        TaskComponentBuilder(_editor),
        ...defaultComponentBuilders,
      ],
      shrinkWrap: true,
      stylesheet: defaultStylesheet.copyWith(
        inlineTextStyler: (attributions, existingStyle) {
          TextStyle style = defaultInlineTextStyler(attributions, existingStyle);

          if (attributions.contains(actionTagComposingAttribution)) {
            style = style.copyWith(
              color: Colors.blue,
            );
          }

          return style;
        },
        addRulesAfter: [
          ...darkModeStyles,
        ],
      ),
      documentOverlayBuilders: [
        AttributedTextBoundsOverlay(
          selector: (a) => a == actionTagComposingAttribution,
          builder: (BuildContext context, Attribution attribution) {
            return Leader(
              link: _composingLink,
              child: const SizedBox(),
            );
          },
        ),
        DefaultCaretOverlayBuilder(
          caretStyle: CaretStyle().copyWith(color: Colors.redAccent),
        ),
      ],
      plugins: {
        _actionTagPlugin,
      },
    );
  }

  Widget _buildTagList() {
    if (_actions.isEmpty) {
      return const SizedBox();
    }

    return Center(
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            for (final tag in _actions) //
              Chip(label: Text(tag)),
          ],
        ),
      ),
    );
  }
}

final _composingLink = LeaderLink();

class _ActionTagsListPopover extends StatefulWidget {
  const _ActionTagsListPopover({
    required this.editor,
    required this.actionTagPlugin,
    required this.editorFocusNode,
  });

  final Editor editor;
  final ActionTagsPlugin actionTagPlugin;
  final FocusNode editorFocusNode;

  @override
  State<_ActionTagsListPopover> createState() => _ActionTagsListPopoverState();
}

class _ActionTagsListPopoverState extends State<_ActionTagsListPopover> {
  static const _actionCandidates = <_TextNodeConversion>[
    _TextNodeConversion("Header 1", TextNodeType.header1),
    _TextNodeConversion("Header 2", TextNodeType.header2),
    _TextNodeConversion("Header 3", TextNodeType.header3),
    _TextNodeConversion("Ordered List Item", TextNodeType.orderedListItem),
    _TextNodeConversion("Unordered List Item", TextNodeType.unorderedListItem),
    _TextNodeConversion("Task", TextNodeType.task),
    _TextNodeConversion("Paragraph ", TextNodeType.paragraph),
  ];
  final _matchingActions = <_TextNodeConversion>[];

  @override
  void initState() {
    super.initState();

    widget.actionTagPlugin.composingActionTag.addListener(_onComposingTokenChange);

    final initialComposingTag = widget.actionTagPlugin.composingActionTag.value?.tag.token;
    if (initialComposingTag != null) {
      _selectMatchingActions(initialComposingTag);
    }
  }

  @override
  void didUpdateWidget(_ActionTagsListPopover oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.actionTagPlugin != oldWidget.actionTagPlugin) {
      oldWidget.actionTagPlugin.composingActionTag.removeListener(_onComposingTokenChange);
      widget.actionTagPlugin.composingActionTag.addListener(_onComposingTokenChange);
    }
  }

  @override
  void dispose() {
    widget.actionTagPlugin.composingActionTag.removeListener(_onComposingTokenChange);

    super.dispose();
  }

  Future<void> _onComposingTokenChange() async {
    final composingTag = widget.actionTagPlugin.composingActionTag.value?.tag.token;
    if (composingTag == null) {
      // The user isn't composing a tag.
      setState(() {
        _matchingActions.clear();
      });
      return;
    }

    // Filter the user list based on the composing token.
    setState(() {
      _selectMatchingActions(composingTag);
    });
  }

  void _selectMatchingActions(String composingTag) {
    _matchingActions
      ..clear()
      ..addAll(_actionCandidates
          .where((availableAction) => availableAction.name.toLowerCase().contains(composingTag.toLowerCase())));
  }

  void _onItemSelected(Object type) {
    widget.editor.execute([
      SubmitComposingActionTagRequest(),
      ConvertSelectedTextNodeRequest(type as TextNodeType),
    ]);
  }

  void _cancelTag() {
    widget.editor.execute([
      CancelComposingActionTagRequest(defaultActionTagRule),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return PopoverList(
      editorFocusNode: widget.editorFocusNode,
      leaderLink: _composingLink,
      listItems: _matchingActions
          .map(
            (action) => PopoverListItem(id: action.type, label: action.name),
          )
          .toList(),
      onListItemSelected: _onItemSelected,
      onCancelRequested: _cancelTag,
    );
  }
}

class ConvertSelectedTextNodeRequest implements EditRequest {
  ConvertSelectedTextNodeRequest(this.newType);

  final TextNodeType newType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConvertSelectedTextNodeRequest && runtimeType == other.runtimeType && newType == other.newType;

  @override
  int get hashCode => newType.hashCode;
}

class ConvertSelectedTextNodeCommand extends EditCommand {
  ConvertSelectedTextNodeCommand(this.newType);

  final TextNodeType newType;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final document = context.find<MutableDocument>(Editor.documentKey);
    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);

    if (composer.selection == null) {
      // There's no selected node to convert.
      return;
    }

    final extentPosition = composer.selection!.extent.nodePosition;
    if (extentPosition is! TextNodePosition) {
      // The selected node isn't a text node. We only convert text nodes.
      return;
    }

    final oldNode = document.getNodeById(composer.selection!.extent.targetNodeId) as TextNode;

    late final TextNode newNode;
    switch (newType) {
      case TextNodeType.header1:
        newNode = ParagraphNode(
          id: oldNode.id,
          text: oldNode.text,
          metadata: Map.from(oldNode.metadata)..["blockType"] = header1Attribution,
        );
      case TextNodeType.header2:
        newNode = ParagraphNode(
          id: oldNode.id,
          text: oldNode.text,
          metadata: Map.from(oldNode.metadata)..["blockType"] = header2Attribution,
        );
      case TextNodeType.header3:
        newNode = ParagraphNode(
          id: oldNode.id,
          text: oldNode.text,
          metadata: Map.from(oldNode.metadata)..["blockType"] = header3Attribution,
        );
      case TextNodeType.orderedListItem:
        newNode = ListItemNode(
          id: oldNode.id,
          itemType: ListItemType.ordered,
          text: oldNode.text,
        );
      case TextNodeType.unorderedListItem:
        newNode = ListItemNode(
          id: oldNode.id,
          itemType: ListItemType.unordered,
          text: oldNode.text,
        );
      case TextNodeType.task:
        newNode = TaskNode(
          id: oldNode.id,
          text: oldNode.text,
          isComplete: false,
        );
      case TextNodeType.paragraph:
        newNode = ParagraphNode(
          id: oldNode.id,
          text: oldNode.text,
          metadata: Map.from(oldNode.metadata)..["blockType"] = paragraphAttribution,
        );
    }

    document.replaceNode(oldNode: oldNode, newNode: newNode);

    executor.logChanges([
      DocumentEdit(
        NodeChangeEvent(newNode.id),
      ),
    ]);
  }
}

class _TextNodeConversion {
  const _TextNodeConversion(this.name, this.type);

  final String name;
  final TextNodeType type;
}

enum TextNodeType {
  header1,
  header2,
  header3,
  orderedListItem,
  unorderedListItem,
  task,
  paragraph,
}
