import 'package:flutter/widgets.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';

import '../core/document.dart';
import 'layout_single_column/layout_single_column.dart';

class UnknownComponentBuilder implements ComponentBuilder {
  const UnknownComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
    List<ComponentBuilder> componentBuilders,
  ) {
    return _UnkownViewModel(
      nodeId: node.id,
      padding: EdgeInsets.zero,
    );
  }

  @override
  Widget? createComponent(
      SingleColumnDocumentComponentContext componentContext, SingleColumnLayoutComponentViewModel componentViewModel) {
    editorLayoutLog.warning("Building component widget for unknown component: $componentViewModel");
    return UnknownComponent(
      key: componentContext.componentKey,
    );
  }
}

/// A [SingleColumnLayoutComponentViewModel] that represents an unknown content.
///
/// This is used so the editor doesn't crash when it encounters a node that it
/// doesn't know how to render.
class _UnkownViewModel extends SingleColumnLayoutComponentViewModel {
  _UnkownViewModel({
    required super.nodeId,
    required super.padding,
  });

  @override
  SingleColumnLayoutComponentViewModel copy() {
    return _UnkownViewModel(
      nodeId: nodeId,
      padding: padding,
    );
  }
}

/// Displays a `Placeholder` widget within a document layout.
///
/// An `UnknownComponent` is intended to represent any
/// `DocumentNode` for which there is no corresponding
/// component builder.
class UnknownComponent extends StatelessWidget {
  const UnknownComponent({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: double.infinity,
      height: 100,
      child: Placeholder(),
    );
  }
}
