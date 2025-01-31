import 'package:example/demos/in_the_lab/in_the_lab_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class CompositeNodesDemo extends StatefulWidget {
  const CompositeNodesDemo({super.key});

  @override
  State<CompositeNodesDemo> createState() => _CompositeNodesDemoState();
}

class _CompositeNodesDemoState extends State<CompositeNodesDemo> {
  late final Editor _editor;

  @override
  void initState() {
    super.initState();

    _editor = createDefaultDocumentEditor(
      document: _createInitialDocument(),
      composer: MutableDocumentComposer(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InTheLabScaffold(
      content: SuperEditor(
        editor: _editor,
        stylesheet: defaultStylesheet.copyWith(
          addRulesAfter: darkModeStyles,
        ),
        documentOverlayBuilders: [
          DefaultCaretOverlayBuilder(
            caretStyle: const CaretStyle().copyWith(color: Colors.redAccent),
          ),
        ],
        componentBuilders: [
          _BannerComponentBuilder(),
          ...defaultComponentBuilders,
        ],
      ),
    );
  }
}

MutableDocument _createInitialDocument() {
  return MutableDocument(
    nodes: [
      ParagraphNode(id: "1.1", text: AttributedText("Paragraph before the first level of embedding.")),
      CompositeDocumentNode("2", [
        ParagraphNode(id: "2.1", text: AttributedText("Paragraph before the second level of embedding.")),
        CompositeDocumentNode("3", [
          ParagraphNode(id: "3.1", text: AttributedText("This paragraph is in the 3rd level of document.")),
        ]),
        ParagraphNode(id: "2.3", text: AttributedText("Paragraph after the second level of embedding.")),
      ]),
      ParagraphNode(id: "1.3", text: AttributedText("Paragraph after the first level of embedding.")),
    ],
  );
}

class _BannerComponentBuilder implements ComponentBuilder {
  _BannerComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
    List<ComponentBuilder> componentBuilders,
  ) {
    if (node is! CompositeDocumentNode) {
      return null;
    }

    print("Creating a composite view model (${node.id}) with ${node.nodeCount} child nodes");
    final childViewModels = <SingleColumnLayoutComponentViewModel>[];
    for (final childNode in node.nodes) {
      print("  - Creating view model for child node: $childNode");
      SingleColumnLayoutComponentViewModel? viewModel;
      for (final builder in componentBuilders) {
        viewModel = builder.createViewModel(document, childNode, componentBuilders);
        if (viewModel != null) {
          break;
        }
      }

      print("   - view model: $viewModel");
      if (viewModel != null) {
        childViewModels.add(viewModel);
      }
    }

    return CompositeViewModel(
      nodeId: node.id,
      node: node,
      childViewModels: childViewModels,
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! CompositeViewModel) {
      return null;
    }
    print(
        "Composite builder - createComponent() - with ${componentViewModel.childViewModels.length} child view models");

    final childComponentIds = <String>[];
    final childComponents = <Widget>[];
    for (final childViewModel in componentViewModel.childViewModels) {
      print("Creating component for child view model: $childViewModel");
      final childContext = SingleColumnDocumentComponentContext(
        context: componentContext.context,
        componentKey: GlobalKey(),
        componentBuilders: componentContext.componentBuilders,
      );
      Widget? component;
      for (final builder in componentContext.componentBuilders) {
        component = builder.createComponent(childContext, childViewModel);
        if (component != null) {
          break;
        }
      }

      print(" - component: $component");
      if (component != null) {
        childComponentIds.add(childViewModel.nodeId);
        childComponents.add(component);
      }
    }

    return _BannerComponent(
      key: componentContext.componentKey,
      node: componentViewModel.node,
      childComponentIds: childComponentIds,
      childComponents: childComponents,
    );
  }
}

class _BannerComponent extends StatefulWidget {
  const _BannerComponent({
    super.key,
    required this.node,
    required this.childComponentIds,
    required this.childComponents,
  });

  final CompositeDocumentNode node;
  final List<String> childComponentIds;
  final List<Widget> childComponents;

  @override
  State<_BannerComponent> createState() => _BannerComponentState();
}

class _BannerComponentState extends State<_BannerComponent> with DocumentComponent {
  @override
  NodePosition getBeginningPosition() {
    return widget.node.beginningPosition;
  }

  @override
  NodePosition getBeginningPositionNearX(double x) {
    // TODO: implement getBeginningPositionNearX
    throw UnimplementedError();
  }

  @override
  NodePosition getEndPosition() {
    return widget.node.endPosition;
  }

  @override
  NodePosition getEndPositionNearX(double x) {
    // TODO: implement getEndPositionNearX
    throw UnimplementedError();
  }

  @override
  NodeSelection getCollapsedSelectionAt(NodePosition nodePosition) {
    return widget.node.computeSelection(base: nodePosition, extent: nodePosition);
  }

  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) {
    // TODO: implement getDesiredCursorAtOffset
    throw UnimplementedError();
  }

  @override
  Rect getEdgeForPosition(NodePosition nodePosition) {
    // TODO: implement getEdgeForPosition
    throw UnimplementedError();
  }

  @override
  Offset getOffsetForPosition(NodePosition nodePosition) {
    // TODO: implement getOffsetForPosition
    throw UnimplementedError();
  }

  @override
  NodePosition? getPositionAtOffset(Offset localOffset) {
    print("Looking for position in composite component at local offset: $localOffset");
    final compositeBox = context.findRenderObject() as RenderBox;
    for (int i = 0; i < widget.childComponents.length; i += 1) {
      final childComponent = widget.childComponents[i];
      print("Component widget: ${childComponent} - key: ${childComponent.key}");
      final componentKey = childComponent.key as GlobalKey;
      final component = componentKey.currentState as DocumentComponent;
      final componentBox = componentKey.currentContext!.findRenderObject() as RenderBox;
      final componentLocalOffset = componentBox.localToGlobal(Offset.zero, ancestor: compositeBox);
      final offsetInComponent = localOffset - componentLocalOffset;
      final positionInComponent = component.getPositionAtOffset(offsetInComponent);
      if (positionInComponent != null) {
        print("Found position in component! - ${widget.childComponentIds[i]} - $positionInComponent");
        return CompositeNodePosition(
          compositeNodeId: widget.node.id,
          childNodeId: widget.childComponentIds[i],
          childNodePosition: positionInComponent,
        );
      }
    }

    return null;
  }

  @override
  Rect getRectForPosition(NodePosition nodePosition) {
    // TODO: implement getRectForPosition
    throw UnimplementedError();
  }

  @override
  Rect getRectForSelection(NodePosition baseNodePosition, NodePosition extentNodePosition) {
    // TODO: implement getRectForSelection
    throw UnimplementedError();
  }

  @override
  NodeSelection getSelectionBetween({required NodePosition basePosition, required NodePosition extentPosition}) {
    // TODO: implement getSelectionBetween
    throw UnimplementedError();
  }

  @override
  NodeSelection? getSelectionInRange(Offset localBaseOffset, Offset localExtentOffset) {
    // TODO: implement getSelectionInRange
    throw UnimplementedError();
  }

  @override
  NodeSelection getSelectionOfEverything() {
    // TODO: implement getSelectionOfEverything
    throw UnimplementedError();
  }

  @override
  NodePosition? movePositionDown(NodePosition currentPosition) {
    // TODO: implement movePositionDown
    throw UnimplementedError();
  }

  @override
  NodePosition? movePositionLeft(NodePosition currentPosition, [MovementModifier? movementModifier]) {
    // TODO: implement movePositionLeft
    throw UnimplementedError();
  }

  @override
  NodePosition? movePositionRight(NodePosition currentPosition, [MovementModifier? movementModifier]) {
    // TODO: implement movePositionRight
    throw UnimplementedError();
  }

  @override
  NodePosition? movePositionUp(NodePosition currentPosition) {
    // TODO: implement movePositionUp
    throw UnimplementedError();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey),
        color: Colors.grey.withOpacity(0.1),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: widget.childComponents,
      ),
    );
  }
}
