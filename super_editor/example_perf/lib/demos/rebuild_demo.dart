import 'package:flutter/material.dart';

import 'package:super_editor/super_editor.dart';

/// Example of a task component whose height is animated.
class RebuildCountDemo extends StatefulWidget {
  const RebuildCountDemo({super.key});

  @override
  State<RebuildCountDemo> createState() => _RebuildCountDemoState();
}

class _RebuildCountDemoState extends State<RebuildCountDemo> {
  late MutableDocument _doc;
  late MutableDocumentComposer _composer;
  late Editor _docEditor;

  @override
  void initState() {
    super.initState();
    _doc = _createDocument();
    _composer = MutableDocumentComposer();
    _docEditor = createDefaultDocumentEditor(document: _doc, composer: _composer);
  }

  @override
  void dispose() {
    _doc.dispose();
    super.dispose();
  }

  MutableDocument _createDocument() {
    return MutableDocument(
      nodes: [
        ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText(
            "Below are several tasks. These tasks will animate the appearance of a subtitle depending on whether they have selection. Only changed tasks will rebuild. Try and find out:\n",
          ),
        ),
        ...List.generate(
          10,
          (index) => TaskNode(
            id: Editor.createNodeId(),
            text: AttributedText("Task ${index + 1}"),
            isComplete: false,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SuperEditor(
      editor: _docEditor,
      stylesheet: defaultStylesheet.copyWith(
        documentPadding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      ),
      // Add a new component builder that creates a task that animates its height,
      // instead of creating the usual static kind.
      componentBuilders: [
        const AnimatedTaskComponentBuilder(),
        TaskComponentBuilder(_docEditor),
        ...defaultComponentBuilders,
      ],
    );
  }
}

/// SuperEditor [ComponentBuilder] that builds a task that is animates the appearance of
/// a subtitle depending on whether it has selection.
class AnimatedTaskComponentBuilder implements ComponentBuilder {
  const AnimatedTaskComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
    List<ComponentBuilder> componentBuilders,
  ) {
    // This builder can work with the standard task view model, so
    // we'll defer to the standard task builder.
    return null;
  }

  @override
  Widget? createComponent(
      SingleColumnDocumentComponentContext componentContext, SingleColumnLayoutComponentViewModel componentViewModel) {
    if (componentViewModel is! TaskComponentViewModel) {
      return null;
    }

    return _AnimatedTaskComponent(
      key: componentContext.componentKey,
      viewModel: componentViewModel,
    );
  }
}

class _AnimatedTaskComponent extends StatefulWidget {
  const _AnimatedTaskComponent({
    super.key,
    required this.viewModel,
    // TODO(srawlins): `unused_element`, when reporting a parameter, is being
    // renamed to `unused_element_parameter`. For now, ignore each; when the SDK
    // constraint is >= 3.6.0, just ignore `unused_element_parameter`.
    // ignore: unused_element, unused_element_parameter
    this.showDebugPaint = false,
  });

  final TaskComponentViewModel viewModel;
  final bool showDebugPaint;

  @override
  State<_AnimatedTaskComponent> createState() => _AnimatedTaskComponentState();
}

class _AnimatedTaskComponentState extends State<_AnimatedTaskComponent>
    with ProxyDocumentComponent<_AnimatedTaskComponent>, ProxyTextComposable {
  final _textKey = GlobalKey();

  @override
  GlobalKey<State<StatefulWidget>> get childDocumentComponentKey => _textKey;

  @override
  TextComposable get childTextComposable => childDocumentComponentKey.currentState as TextComposable;

  int _counter = 0;

  @override
  Widget build(BuildContext context) {
    ++_counter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rebuild count $_counter'),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Checkbox(
                value: widget.viewModel.isComplete,
                onChanged: (newValue) {
                  widget.viewModel.setComplete?.call(newValue!);
                },
              ),
            ),
            Expanded(
              child: TextComponent(
                key: _textKey,
                text: widget.viewModel.text,
                textStyleBuilder: (attributions) {
                  // Show a strikethrough across the entire task if it's complete.
                  final style = widget.viewModel.textStyleBuilder(attributions);
                  return widget.viewModel.isComplete
                      ? style.copyWith(
                          decoration: style.decoration == null
                              ? TextDecoration.lineThrough
                              : TextDecoration.combine([TextDecoration.lineThrough, style.decoration!]),
                        )
                      : style;
                },
                textSelection: widget.viewModel.selection,
                selectionColor: widget.viewModel.selectionColor,
                highlightWhenEmpty: widget.viewModel.highlightWhenEmpty,
                showDebugPaint: widget.showDebugPaint,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 56),
          child: SizeChangedLayoutNotifier(
            child: AnimatedSize(
              key: _animatedSizeKey,
              duration: const Duration(milliseconds: 100),
              child: widget.viewModel.selection != null
                  ? const SizedBox(
                      height: 20,
                      child: Row(
                        children: [
                          Icon(Icons.label_important_outline, size: 16),
                          SizedBox(width: 4),
                          Icon(Icons.timelapse_sharp, size: 16),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }

  final _animatedSizeKey = GlobalKey();
}
