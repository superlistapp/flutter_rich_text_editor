import 'package:attributed_text/attributed_text.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/content_layers.dart';

/// Positions invisible widgets around runs of attributed text.
///
/// The attributions that are bounded are selected with a given [selector].
///
/// The bounding widget is build with a given [builder], so that any number
/// of use-cases can be implemented with this widget.
class AttributionBounds extends ContentLayerStatefulWidget {
  const AttributionBounds({
    Key? key,
    required this.document,
    required this.layout,
    required this.selector,
    required this.builder,
  }) : super(key: key);

  final Document document;
  final DocumentLayout layout;
  final AttributionBoundsSelector selector;
  final AttributionBoundsBuilder builder;

  @override
  ContentLayerState<ContentLayerStatefulWidget, List<AttributionBoundsLayout>> createState() =>
      _AttributionBoundsState();
}

class _AttributionBoundsState extends ContentLayerState<AttributionBounds, List<AttributionBoundsLayout>> {
  @override
  void initState() {
    super.initState();
    widget.document.addListener(_onDocumentChange);
  }

  @override
  void dispose() {
    widget.document.removeListener(_onDocumentChange);
    super.dispose();
  }

  void _onDocumentChange(DocumentChangeLog changeLog) {
    if (!mounted) {
      return;
    }

    setState(() {
      // Rebuild, which will cause ContentLayerState to re-compute layout data, i.e., attribution bounds.
    });
  }

  @override
  List<AttributionBoundsLayout>? computeLayoutData(Element? contentElement, RenderObject? contentLayout) {
    final bounds = <AttributionBoundsLayout>[];

    for (final node in widget.document) {
      if (node is! TextNode) {
        continue;
      }
      final nodePath = widget.document.getPathByNodeId(node.id)!;

      final spans = node.text.getAttributionSpansInRange(
        attributionFilter: widget.selector,
        range: SpanRange(0, node.text.length - 1),
      );

      for (final span in spans) {
        final range = DocumentRange(
          start: DocumentPosition(documentPath: nodePath, nodePosition: TextNodePosition(offset: span.start)),
          end: DocumentPosition(documentPath: nodePath, nodePosition: TextNodePosition(offset: span.end + 1)),
        );

        bounds.add(
          AttributionBoundsLayout(
            span.attribution,
            widget.layout.getRectForSelection(range.start, range.end) ?? Rect.zero,
          ),
        );
      }
    }

    return bounds;
  }

  @override
  Widget doBuild(BuildContext context, List<AttributionBoundsLayout>? layoutData) {
    if (layoutData == null) {
      return const SizedBox();
    }

    return IgnorePointer(
      child: Stack(
        children: _buildBounds(layoutData),
      ),
    );
  }

  List<Widget> _buildBounds(List<AttributionBoundsLayout> bounds) {
    final boundWidgets = <Widget>[];
    for (final bound in bounds) {
      final boundWidget = widget.builder(context, bound.attribution);
      if (boundWidget != null) {
        boundWidgets.add(
          Positioned.fromRect(
            rect: bound.rect,
            child: boundWidget,
          ),
        );
      }
    }

    return boundWidgets;
  }
}

class AttributionBoundsLayout {
  const AttributionBoundsLayout(this.attribution, this.rect);

  final Attribution attribution;
  final Rect rect;
}

/// Filter function that decides whether the text with the given [attribution]
/// should have a widget boundary placed around it.
typedef AttributionBoundsSelector = bool Function(Attribution attribution);

/// Builder that (optionally) returns a widget that positioned at the size
/// and location of attributed text.
typedef AttributionBoundsBuilder = Widget? Function(BuildContext context, Attribution attribution);
