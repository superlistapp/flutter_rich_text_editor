import 'package:flutter/material.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/default_editor/layout_single_column/_presenter.dart';

class CompositeComponentBuilder implements ComponentBuilder {
  const CompositeComponentBuilder();

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
        childComponents.add(component);
      }
    }

    return CompositeComponent(
      key: componentContext.componentKey,
      node: componentViewModel.node,
      childComponents: childComponents,
    );
  }
}

class CompositeViewModel extends SingleColumnLayoutComponentViewModel {
  CompositeViewModel({
    required super.nodeId,
    required this.node,
    super.maxWidth,
    super.padding = EdgeInsets.zero,
    required this.childViewModels,
  });

  final CompositeDocumentNode node;
  final List<SingleColumnLayoutComponentViewModel> childViewModels;

  @override
  void applyStyles(Map<String, dynamic> styles) {
    super.applyStyles(styles);

    // Forward styles to our children.
    for (final child in childViewModels) {
      child.applyStyles(styles);
    }
  }

  @override
  SingleColumnLayoutComponentViewModel copy() {
    return CompositeViewModel(
      nodeId: nodeId,
      node: node,
      maxWidth: maxWidth,
      padding: padding,
      childViewModels: List.from(childViewModels),
    );
  }
}

class CompositeComponent extends StatefulWidget {
  const CompositeComponent({
    super.key,
    required this.node,
    required this.childComponents,
  });

  final CompositeDocumentNode node;
  final List<Widget> childComponents;

  @override
  State<CompositeComponent> createState() => _CompositeComponentState();
}

class _CompositeComponentState extends State<CompositeComponent> with DocumentComponent {
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
    // TODO: implement getPositionAtOffset
    throw UnimplementedError();
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
