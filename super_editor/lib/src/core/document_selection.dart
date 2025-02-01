import 'dart:ui';

import 'package:super_editor/src/default_editor/text.dart';

import 'document.dart';

/// A selection within a [Document].
///
/// A [DocumentSelection] spans from a [base] position to an
/// [extent] position, and includes all content in between.
///
/// [base] and [extent] are instances of [DocumentPosition],
/// which represents a single position within a [Document].
///
/// A [DocumentSelection] does not hold a reference to a
/// [Document], it only represents a directional selection
/// within a [Document]. The [base] and [extent] positions must
/// be interpreted within the context of a specific [Document]
/// to locate nodes between [base] and [extent], and to identify
/// partial content that is selected within the [base] and [extent]
/// nodes within the document.
class DocumentSelection extends DocumentRange {
  /// Creates a collapsed selection at the given [position] within the document.
  ///
  /// See also:
  ///
  ///  * [isCollapsed], which determines whether a selection is collapsed or
  ///    not.
  const DocumentSelection.collapsed({
    required DocumentPosition position,
  })  : base = position,
        extent = position,
        super(start: position, end: position);

  /// Creates a selection from the [base] position to the [extent] position
  /// within the document.
  const DocumentSelection({
    required this.base,
    required this.extent,
  }) : super(start: base, end: extent);

  /// The base position of the selection within the document.
  ///
  /// If [base] equals [extent], the selection is collapsed.
  ///
  /// If [base] comes before [extent], the selection is expanded in the
  /// downstream direction.
  ///
  /// If [base] comes after [extent], the selection is expanded in the upstream
  /// direction.
  final DocumentPosition base;

  /// The extent position of the selection within the document.
  ///
  /// If [extent] equals [base], the selection is collapsed.
  ///
  /// If [extent] comes after [base], the selection is expanded in the
  /// downstream direction.
  ///
  /// If [extent] comes before [base], the selection is expanded in the upstream
  /// direction.
  final DocumentPosition extent;

  /// Returns `true` if this selection is collapsed, or `false` if this
  /// selection is expanded.
  ///
  /// A [DocumentSelection] is "collapsed" when its [base] and [extent] are
  /// equivalent. Otherwise, the [DocumentSelection] is "expanded".
  bool get isCollapsed => base.nodeId == extent.nodeId && base.nodePosition.isEquivalentTo(extent.nodePosition);

  /// Returns the affinity (direction) for this selection - downstream refers to a selection
  /// that starts at earlier content and ends at later content, upstream refers to a selection
  /// that starts at later content and ends at earlier content.
  ///
  /// Calculating the selection affinity requires a [Document] because only the [Document] knows the
  /// relative position of various [DocumentPosition]s.
  TextAffinity calculateAffinity(Document document) => document.getAffinityBetween(base: base, extent: extent);

  /// Returns `true` if this selection has an affinity of [TextAffinity.downstream].
  ///
  /// See [calculateAffinity] for more info.
  bool hasDownstreamAffinity(Document document) => calculateAffinity(document) == TextAffinity.downstream;

  /// Returns `true` if this selection has an affinity of [TextAffinity.upstream].
  ///
  /// See [calculateAffinity] for more info.
  bool hasUpstreamAffinity(Document document) => calculateAffinity(document) == TextAffinity.upstream;

  @override
  String toString() {
    if (base.nodeId == extent.nodeId) {
      final basePosition = base.nodePosition;
      final extentPosition = extent.nodePosition;
      if (basePosition is TextNodePosition && extentPosition is TextNodePosition) {
        if (basePosition.offset == extentPosition.offset) {
          return "[Selection] - ${base.nodeId}: ${extentPosition.offset}";
        }

        return "[Selection] - ${base.nodeId}: [${basePosition.offset}, ${extentPosition.offset}]";
      }

      return "[Selection] - ${base.nodeId}: [${base.nodePosition}, ${extent.nodePosition}]";
    }

    return '[DocumentSelection] - \n  base: ($base),\n  extent: ($extent)';
  }

  /// Returns a version of this that is collapsed at the [extent] position.
  ///
  /// Note, the returned [DocumentSelection] is collapsed at this selection's
  /// [extent], regardless of whether this selection's [extent] comes before or
  /// after its [base].
  ///
  /// See also:
  ///
  ///  * [isCollapsed], which determines whether a selection is collapsed or
  ///    not.
  ///  * [collapseUpstream], which collapses the selection in the upstream
  ///    direction relative to the document.
  ///  * [collapseDownstream], which collapses the selection in the downstream
  ///    direction relative to the document.
  DocumentSelection collapse() {
    if (isCollapsed) {
      return this;
    } else {
      return DocumentSelection(
        base: extent,
        extent: extent,
      );
    }
  }

  /// Returns a version of this [DocumentSelection] that is collapsed
  /// in the upstream (start) direction.
  ///
  /// The source [Document] is required so that the upstream [DocumentPosition]
  /// can be selected from [base] and [extent].
  ///
  /// See also:
  ///
  ///  * [isCollapsed], which determines whether a selection is collapsed or
  ///    not.
  ///  * [collapseDownstream], which collapses the selection in the downstream
  ///    direction relative to the document.
  ///  * [collapse], which collapses the selection to the extent position.
  DocumentSelection collapseUpstream(Document document) {
    if (isCollapsed) {
      // The selection is already collapsed. Therefore, the collapsed
      // version of this selection is the same as this selection.
      return this;
    }

    final selectionAffinity = document.getAffinityForSelection(this);
    return selectionAffinity == TextAffinity.downstream //
        ? DocumentSelection.collapsed(position: base)
        : DocumentSelection.collapsed(position: extent);
  }

  /// Returns a version of this [DocumentSelection] that is collapsed
  /// in the downstream (end) direction.
  ///
  /// The source [Document] is required so that the downstream [DocumentPosition]
  /// can be selected from [base] and [extent].
  ///
  /// See also:
  ///
  ///  * [isCollapsed], which determines whether a selection is collapsed or
  ///    not.
  ///  * [collapseUpstream], which collapses the selection in the upstream
  ///    direction relative to the document.
  ///  * [collapse], which collapses the selection to the extent position.
  DocumentSelection collapseDownstream(Document document) {
    if (isCollapsed) {
      // The selection is already collapsed. Therefore, the collapsed
      // version of this selection is the same as this selection.
      return this;
    }

    final selectionAffinity = document.getAffinityForSelection(this);
    return selectionAffinity == TextAffinity.downstream //
        ? DocumentSelection.collapsed(position: extent)
        : DocumentSelection.collapsed(position: base);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentSelection && runtimeType == other.runtimeType && base == other.base && extent == other.extent;

  @override
  int get hashCode => base.hashCode ^ extent.hashCode;

  /// Creates a new [DocumentSelection] based on the current selection, with the
  /// provided parameters overridden.
  DocumentSelection copyWith({
    DocumentPosition? base,
    DocumentPosition? extent,
  }) {
    return DocumentSelection(
      base: base ?? this.base,
      extent: extent ?? this.extent,
    );
  }

  /// Creates a copy of this selection but with the [extent] expanded to the
  /// given new extent.
  ///
  /// This is like calling [copyWith] with the [newExtent] as the new value for
  /// the extent.
  DocumentSelection expandTo(DocumentPosition newExtent) {
    return copyWith(
      extent: newExtent,
    );
  }
}

/// A span within a [Document] with one side bounded at [start] and the other
/// side bounded at [end].
///
/// A [DocumentRange] is considered "normalized" if [start] comes before [end].
/// A [DocumentRange] is NOT "normalized" if [end] comes before [start].
///
/// To check if a [DocumentRange] is normalized, call [isNormalized] with
/// a [Document].
///
/// Use [normalize] to create a version of this [DocumentRange] that's guaranteed
/// to be normalized for the given [Document].
///
/// Determining normalization requires a [Document] because a [Document] is the
/// source of truth for [DocumentNode] content order.
class DocumentRange {
  /// Creates a document range between [start] and [end].
  const DocumentRange({
    required this.start,
    required this.end,
  });

  /// The bounding position of one side of a [DocumentRange].
  ///
  /// {@template start_and_end}
  /// If this [DocumentRange] is normalized then [start] comes before [end], otherwise
  /// [end] comes before [start].
  /// {@endtemplate}
  final DocumentPosition start;

  /// The bounding position of the other side of a [DocumentRange].
  ///
  /// {@macro start_and_end}
  final DocumentPosition end;

  /// Returns `true` if this range is collapsed, e.g., it starts and ends
  /// at the sample place.
  bool get isCollapsed => start == end;

  /// Returns `true` if [start] appears at, or before [end], or `false` otherwise.
  bool isNormalized(Document document) => document.getAffinityForRange(this) == TextAffinity.downstream;

  /// Returns a version of this [DocumentRange] that's normalized.
  ///
  /// See [isNormalized] for a definition of normalized.
  DocumentRange normalize(Document document) {
    if (isNormalized(document)) {
      return this;
    }

    // We're not normalized. To return a normalized version, reverse our bounds.
    return DocumentRange(start: end, end: start);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentRange && runtimeType == other.runtimeType && start == other.start && end == other.end;

  @override
  int get hashCode => start.hashCode ^ end.hashCode;

  @override
  String toString() {
    if (start.nodeId == end.nodeId) {
      final startPosition = start.nodePosition;
      final endPosition = end.nodePosition;
      if (startPosition is TextNodePosition && endPosition is TextNodePosition) {
        if (startPosition.offset == endPosition.offset) {
          return "[Range] - ${start.nodeId}: ${endPosition.offset}";
        }

        return "[Range] - ${start.nodeId}: [${startPosition.offset}, ${endPosition.offset}]";
      }

      return "[Range] - ${start.nodeId}: [${start.nodePosition}, ${end.nodePosition}]";
    }

    return '[Range] - \n  start: ($start),\n  end: ($end)';
  }
}

extension InspectDocumentAffinity on Document {
  TextAffinity getAffinityForSelection(DocumentSelection selection) {
    return getAffinityBetween(base: selection.base, extent: selection.extent);
  }

  TextAffinity getAffinityForRange(DocumentRange range) {
    return getAffinityBetween(base: range.start, extent: range.end);
  }

  TextAffinity getAffinityBetweenNodes(DocumentNode base, DocumentNode extent) {
    return getAffinityForSelection(
      DocumentSelection(
        base: DocumentPosition(
          documentPath: getPathByNodeId(base.id)!,
          nodePosition: base.beginningPosition,
        ),
        extent: DocumentPosition(
          documentPath: getPathByNodeId(extent.id)!,
          nodePosition: extent.beginningPosition,
        ),
      ),
    );
  }

  /// Returns the affinity direction implied by the given [base] and [extent].
  // TODO: Replace TextAffinity with a DocumentAffinity to avoid confusion.
  TextAffinity getAffinityBetween({
    required DocumentPosition base,
    required DocumentPosition extent,
  }) {
    final baseNode = getNode(base);
    if (baseNode == null) {
      throw Exception('No such position in document: $base');
    }

    final extentNode = getNode(extent);
    if (extentNode == null) {
      throw Exception('No such position in document: $extent');
    }

    // A document is a tree, but it's a tree where every position in that tree has
    // a conceptual downstream and upstream direction.
    //
    // In the nominal case, we're dealing with a couple of top-level nodes. In that
    // case, whichever node comes first in the root node list is the upstream node.
    //
    // The more complicated case is when one or both of the nodes are sub-nodes of
    // other nodes. In that scenario, the nodes might have an ancestor/descendant
    // relationship, sibling relationship, or cousin relationship.
    //
    // The following examples demonstrate how we define affinity.
    //
    // Root siblings:
    //
    //    Document
    //    > 1: Upstream
    //    > 2: ...
    //    > 3: ...
    //    > 4: Downstream
    //
    // Descendant siblings:
    //
    //    Document
    //    > 1:
    //      > 1.1: Upstream
    //      > 1.2: ...
    //      > 1.3: Downstream
    //    > 2:
    //
    // Cousins:
    //
    //    Document
    //    > 1:
    //      > 1.1: Upstream
    //    > 2:
    //      > 2.1:
    //        > 2.1.1: Downstream
    //
    // Ancestor/Descendant:
    //
    //    Document
    //    > 1: Upstream
    //      > 1.1: Downstream
    //
    // To determine affinity, we do a level-by-level position comparison
    // between the two node paths. I.e., we compare their top-level node
    // positions. If those are equal, we compare their 2nd level node positions.
    // Etc. If at any point the node positions aren't equal, the path with
    // the upstream node position is marked upstream, and the other downstream.
    //
    // If, during the level-by-level path comparison, one path runs out of nodes
    // before the other, then we have an ancestor/descendant relationship, in which
    // case the ancestor is marked as upstream, and the descendant is marked as downstream.

    int depth = 0;
    do {
      final baseIndex = getNodeIndexInParent(base.documentPath.atDepth(depth));
      final extentIndex = getNodeIndexInParent(extent.documentPath.atDepth(depth));
      if (baseIndex < extentIndex) {
        return TextAffinity.downstream;
      }
      if (extentIndex < baseIndex) {
        return TextAffinity.upstream;
      }

      depth += 1;
    } while (depth < base.documentPath.depth && depth < extent.documentPath.depth);

    if (base.documentPath.depth != extent.documentPath.depth) {
      // One of these nodes is a descendant of the other.
      return base.documentPath.depth < extent.documentPath.depth //
          ? TextAffinity.downstream
          : TextAffinity.upstream;
    }

    // These paths point to the same node. Defer to node affinity.
    return extentNode.getAffinityBetween(base: base.nodePosition, extent: extent.nodePosition);
  }
}

extension InspectDocumentRange on Document {
  /// Returns a [DocumentRange] that ranges from [position1] to [position2],
  /// including [position1] and [position2].
  DocumentRange getRangeBetween(DocumentPosition position1, DocumentPosition position2) {
    late TextAffinity affinity = getAffinityBetween(base: position1, extent: position2);
    return DocumentRange(
      start: affinity == TextAffinity.downstream ? position1 : position2,
      end: affinity == TextAffinity.downstream ? position2 : position1,
    );
  }
}

extension InspectDocumentSelection on Document {
  DocumentSelection selectAll() {
    return DocumentSelection(
      base: DocumentPosition(
        documentPath: NodePath.forNode(first.id),
        nodePosition: first.beginningPosition,
      ),
      extent: DocumentPosition(
        documentPath: NodePath.forNode(last.id),
        nodePosition: first.endPosition,
      ),
    );
  }

  /// Returns a list of all the `DocumentNodes` within the given [selection], ordered
  /// from upstream to downstream.
  List<DocumentNode> getNodesInContentOrder(DocumentSelection selection) {
    final upstreamPosition = selectUpstreamPosition(selection.base, selection.extent);
    final downstreamPosition = selectDownstreamPosition(selection.base, selection.extent);

    return getNodesInside(upstreamPosition, downstreamPosition);
  }

  /// Given [docPosition1] and [docPosition2], returns the `DocumentPosition` that
  /// appears first in the document.
  DocumentPosition selectUpstreamPosition(DocumentPosition docPosition1, DocumentPosition docPosition2) {
    if (docPosition1.nodeId != docPosition2.nodeId) {
      final affinity = getAffinityBetween(base: docPosition1, extent: docPosition2);
      return affinity == TextAffinity.downstream //
          ? docPosition1
          : docPosition2;
    }

    // Both document positions are in the same node. Figure out which
    // node position comes first.
    final theNode = getNodeById(docPosition1.targetNodeId)!;
    return theNode.selectUpstreamPosition(docPosition1.nodePosition, docPosition2.nodePosition) ==
            docPosition1.nodePosition
        ? docPosition1
        : docPosition2;
  }

  /// Given [docPosition1] and [docPosition2], returns the `DocumentPosition` that
  /// appears last in the document.
  DocumentPosition selectDownstreamPosition(DocumentPosition docPosition1, DocumentPosition docPosition2) {
    final upstreamPosition = selectUpstreamPosition(docPosition1, docPosition2);
    return upstreamPosition == docPosition1 ? docPosition2 : docPosition1;
  }

  /// Returns `true` if, and only if, the given [position] sits within the
  /// given [selection] in this `Document`.
  bool doesSelectionContainPosition(DocumentSelection selection, DocumentPosition position) {
    if (selection.isCollapsed) {
      return false;
    }

    final selectionAffinity = getAffinityForSelection(selection);
    final upstreamPosition = selectionAffinity == TextAffinity.downstream ? selection.base : selection.extent;
    final downstreamPosition = selectionAffinity == TextAffinity.downstream ? selection.extent : selection.base;

    // The selection contains the position if the ordering is as follows:
    //
    //   selection start <= position <= selection end
    //
    // Another way of stating this relationship is that there's a downstream
    // affinity from selection start to the position, and from the position to
    // the selection end.
    return getAffinityBetween(base: upstreamPosition, extent: position) == TextAffinity.downstream &&
        getAffinityBetween(base: position, extent: downstreamPosition) == TextAffinity.downstream;
  }
}
