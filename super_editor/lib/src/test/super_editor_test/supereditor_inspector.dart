import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/src/test/flutter_extensions/finders.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_text_layout/super_text_layout.dart';

/// Inspects a given [SuperEditor] in the widget tree.
class SuperEditorInspector {
  /// Returns `true` if the given [SuperEditor] widget currently has focus, or
  /// `false` otherwise.
  ///
  /// {@template supereditor_finder}
  /// By default, this method expects a single [SuperEditor] in the widget tree and
  /// finds it `byType`. To specify one [SuperEditor] among many, pass a [superEditorFinder].
  /// {@endtemplate}
  static bool hasFocus([Finder? finder]) {
    final element = (finder ?? find.byType(SuperEditor)).evaluate().single as StatefulElement;
    final superEditor = element.state as SuperEditorState;
    return superEditor.focusNode.hasFocus;
  }

  /// Returns `true` if the given [SuperEditor] widget currently has an open IME connection,
  /// or `false` if no IME connection is open, or if [SuperEditor] is in keyboard mode.
  ///
  /// {@template supereditor_finder}
  /// By default, this method expects a single [SuperEditor] in the widget tree and
  /// finds it `byType`. To specify one [SuperEditor] among many, pass a [superEditorFinder].
  /// {@endtemplate}
  static bool isImeConnectionOpen([Finder? finder]) {
    final element = (finder ?? find.byType(SuperEditor)).evaluate().single as StatefulElement;
    final superEditor = element.widget as SuperEditor;

    // Keyboard mode never has an IME connection.
    if (superEditor.inputSource == TextInputSource.keyboard) {
      return false;
    }

    final imeInteractorElement = find
        .descendant(
          of: find.byWidget(superEditor),
          matching: find.byType(SuperEditorImeInteractor),
        )
        .evaluate()
        .single as StatefulElement;
    final imeInteractor = imeInteractorElement.state as SuperEditorImeInteractorState;

    return imeInteractor.isAttachedToIme;
  }

  /// Returns the [Document] within the [SuperEditor] matched by [finder],
  /// or the singular [SuperEditor] in the widget tree, if [finder] is `null`.
  ///
  /// {@macro supereditor_finder}
  static Document? findDocument([Finder? finder]) {
    final element = (finder ?? find.byType(SuperEditor)).evaluate().single as StatefulElement;
    final superEditor = element.state as SuperEditorState;
    return superEditor.editContext.document;
  }

  /// Returns the [DocumentComposer] within the [SuperEditor] matched by [finder],
  /// or the singular [SuperEditor] in the widget tree, if [finder] is `null`.
  ///
  /// {@macro supereditor_finder}
  static DocumentComposer? findComposer([Finder? finder]) {
    final element = (finder ?? find.byType(SuperEditor)).evaluate().single as StatefulElement;
    final superEditor = element.state as SuperEditorState;
    return superEditor.editContext.composer;
  }

  /// Returns the current [DocumentSelection] for the [SuperEditor] matched by
  /// [finder], or the singular [SuperEditor] in the widget tree, if [finder]
  /// is `null`.
  ///
  /// {@macro supereditor_finder}
  static DocumentSelection? findDocumentSelection([Finder? finder]) {
    final element = (finder ?? find.byType(SuperEditor)).evaluate().single as StatefulElement;
    final superEditor = element.state as SuperEditorState;
    return superEditor.editContext.composer.selection;
  }

  /// Returns the current composing region for the [SuperEditor] matched by
  /// [finder], or the singular [SuperEditor] in the widget tree, if [finder]
  /// is `null`.
  ///
  /// {@macro supereditor_finder}
  static DocumentRange? findComposingRegion([Finder? finder]) {
    final element = (finder ?? find.byType(SuperEditor)).evaluate().single as StatefulElement;
    final superEditor = element.state as SuperEditorState;
    return superEditor.editContext.composer.composingRegion.value;
  }

  /// Returns the (x,y) offset for the caret that's currently visible in the document.
  static Offset findCaretOffsetInDocument([Finder? finder]) {
    final caret = find.byKey(DocumentKeys.caret).evaluate().singleOrNull?.renderObject as RenderBox?;
    if (caret != null) {
      final globalCaretOffset = caret.localToGlobal(Offset.zero);
      final documentLayout = findDocumentLayout(finder);
      return documentLayout.getDocumentOffsetFromAncestorOffset(globalCaretOffset);
    }

    throw Exception('Could not locate caret in document');
  }

  /// Returns the (x,y) offset for the component which renders the node with the given [nodeId].
  ///
  /// {@macro supereditor_finder}
  static Offset findComponentOffset(String nodeId, Alignment alignment, [Finder? finder]) {
    final documentLayout = findDocumentLayout(finder);
    final component = documentLayout.getComponentByNodeId(nodeId);
    assert(component != null);
    final componentBox = component!.context.findRenderObject() as RenderBox;
    final rect = componentBox.localToGlobal(Offset.zero) & componentBox.size;
    return alignment.withinRect(rect);
  }

  /// Returns the size of the component which renders the node with the given [nodeId].
  ///
  /// {@macro supereditor_finder}
  static Size findComponentSize(String nodeId, [Finder? finder]) {
    final documentLayout = findDocumentLayout(finder);
    final component = documentLayout.getComponentByNodeId(nodeId);
    assert(component != null);
    final componentBox = component!.context.findRenderObject() as RenderBox;
    return componentBox.size;
  }

  /// Returns the (x,y) offset for a caret, if that caret appeared at the given [position].
  ///
  /// {@macro supereditor_finder}
  static Offset calculateOffsetForCaret(DocumentPosition position, [Finder? finder]) {
    final documentLayout = findDocumentLayout(finder);
    final positionRect = documentLayout.getRectForPosition(position);
    assert(positionRect != null);
    return positionRect!.topLeft;
  }

  /// Returns `true` if the entire content rectangle at [position] is visible on
  /// screen, or `false` otherwise.
  ///
  /// {@macro supereditor_finder}
  static bool isPositionVisibleGlobally(DocumentPosition position, Size globalSize, [Finder? finder]) {
    final documentLayout = findDocumentLayout(finder);
    final positionRect = documentLayout.getRectForPosition(position)!;
    final globalDocumentOffset = documentLayout.getGlobalOffsetFromDocumentOffset(Offset.zero);
    final globalPositionRect = positionRect.translate(globalDocumentOffset.dx, globalDocumentOffset.dy);

    return globalPositionRect.top >= 0 &&
        globalPositionRect.left >= 0 &&
        globalPositionRect.bottom <= globalSize.height &&
        globalPositionRect.right <= globalSize.width;
  }

  /// Finds and returns the [Widget] that configures the [DocumentComponent] with the
  /// given [nodeId].
  ///
  /// The given [nodeId] must exist in the [SuperEditor]'s document. The [Widget] that
  /// configures the give node must be of type [WidgetType].
  ///
  /// {@macro supereditor_finder}
  static WidgetType findWidgetForComponent<WidgetType>(String nodeId, [Finder? superEditorFinder]) {
    final documentLayout = findDocumentLayout(superEditorFinder);
    final widget = (documentLayout.getComponentByNodeId(nodeId) as State).widget;
    if (widget is! WidgetType) {
      throw Exception("Looking for a component's widget. Expected type $WidgetType, but found ${widget.runtimeType}");
    }

    return widget as WidgetType;
  }

  /// Returns the [AttributedText] within the [ParagraphNode] associated with the
  /// given [nodeId].
  ///
  /// There must be a [ParagraphNode] with the given [nodeId], displayed in a
  /// [SuperEditor].
  ///
  /// {@macro supereditor_finder}
  static AttributedText findTextInComponent(String nodeId, [Finder? superEditorFinder]) {
    final documentLayout = findDocumentLayout(superEditorFinder);
    final component = documentLayout.getComponentByNodeId(nodeId);

    if (component is TextComponentState) {
      return component.widget.text;
    }

    if (component is ProxyDocumentComponent) {
      return (component.childDocumentComponentKey.currentState as TextComponentState).widget.text;
    }

    throw Exception('The component for node id $nodeId is not a TextComponent.');
  }

  /// Finds the paragraph with the given [nodeId] and returns the paragraph's content as a [TextSpan].
  ///
  /// A [TextSpan] is the fundamental way that Flutter styles text. It's the lowest level reflection
  /// of what the user will see, short of rendering the actual UI.
  ///
  /// {@macro supereditor_finder}
  static TextSpan findRichTextInParagraph(String nodeId, [Finder? superEditorFinder]) {
    final documentLayout = findDocumentLayout(superEditorFinder);

    final component = documentLayout.getComponentByNodeId(nodeId) as DocumentComponent;
    final superText = find
        .descendant(of: find.byWidget(component.widget), matching: find.byType(SuperText))
        .evaluate()
        .single
        .widget as SuperText;
    return superText.richText as TextSpan;
  }

  /// Finds and returns the [TextStyle] that's applied to the top-level of the [TextSpan]
  /// in the paragraph with the given [nodeId].
  ///
  /// {@macro supereditor_finder}
  static TextStyle? findParagraphStyle(String nodeId, [Finder? superEditorFinder]) {
    return findRichTextInParagraph(nodeId, superEditorFinder).style;
  }

  /// Finds the paragraph with the given [nodeId] and returns its indent level.
  ///
  /// Indent levels start at zero and increment by `1` for each level.
  ///
  /// {@macro supereditor_finder}
  static int findParagraphIndent(String nodeId, [Finder? superEditorFinder]) {
    final component = SuperEditorInspector.findWidgetForComponent(nodeId) as ParagraphComponent;
    return component.viewModel.indent;
  }

  /// Finds the ordered list item with the given [nodeId] and returns its ordinal value.
  ///
  /// List items ordinals start from 1.
  ///
  /// {@macro supereditor_finder}
  static int findListItemOrdinal(String nodeId, [Finder? superEditorFinder]) {
    final listItem = find
        .ancestor(
          of: find.byWidget(SuperEditorInspector.findWidgetForComponent(nodeId)),
          matching: find.byType(OrderedListItemComponent),
        )
        .evaluate()
        .single
        .widget as OrderedListItemComponent;

    return listItem.listIndex;
  }

  /// Finds the task with the given [nodeId] and returns its indent level.
  ///
  /// Indent levels start at zero and increment by `1` for each level.
  ///
  /// {@macro supereditor_finder}
  static int findTaskIndent(String nodeId, [Finder? superEditorFinder]) {
    final component = SuperEditorInspector.findWidgetForComponent(nodeId) as TaskComponent;
    return component.viewModel.indent;
  }

  /// Calculates the delta between the center of the character at [textOffset1] and and the
  /// center of the character at [textOffset2] within the node with the given [nodeId].
  ///
  /// {@macro supereditor_finder}
  static Offset findDeltaBetweenCharactersInTextNode(NodePath nodePath, int textOffset1, int textOffset2,
      [Finder? superEditorFinder]) {
    final docLayout = findDocumentLayout(superEditorFinder);
    final characterBoxStart = docLayout.getRectForPosition(
      DocumentPosition(
        documentPath: nodePath,
        nodePosition: TextNodePosition(offset: textOffset1),
      ),
    );
    final characterBoxEnd = docLayout.getRectForPosition(
      DocumentPosition(
        documentPath: nodePath,
        nodePosition: TextNodePosition(offset: textOffset2),
      ),
    );
    return characterBoxEnd!.center - characterBoxStart!.center;
  }

  /// Returns the [DocumentNode] at given the [index].
  ///
  /// The given [index] must be a valid node index inside the [Document].The node at [index]
  /// must be of type [NodeType].
  ///
  /// {@macro supereditor_finder}
  static NodeType getNodeAt<NodeType extends DocumentNode>(int index, [Finder? superEditorFinder]) {
    final doc = findDocument(superEditorFinder);

    if (doc == null) {
      throw Exception('SuperEditor not found');
    }

    if (index >= doc.nodeCount) {
      throw Exception('Tried to access index $index in a document where the max index is ${doc.nodeCount - 1}');
    }

    final node = doc.getNodeAt(index);
    if (node is! NodeType) {
      throw Exception('Tried to access a ${node.runtimeType} as $NodeType');
    }

    return node;
  }

  /// Locates the first line break in a text node, or throws an exception if it cannot find one.
  static int findOffsetOfLineBreak(String nodeId, [Finder? superEditorFinder]) {
    final documentLayout = findDocumentLayout(superEditorFinder);

    final componentState = documentLayout.getComponentByNodeId(nodeId) as State;
    late final GlobalKey textComponentKey;
    if (componentState is ProxyDocumentComponent) {
      textComponentKey = componentState.childDocumentComponentKey;
    } else {
      textComponentKey = componentState.widget.key as GlobalKey;
    }

    final textLayout = (textComponentKey.currentState as TextComponentState).textLayout;
    if (textLayout.getLineCount() < 2) {
      throw Exception('Specified node does not contain a line break');
    }
    return textLayout.getPositionAtEndOfLine(const TextPosition(offset: 0)).offset;
  }

  /// Finds the [DocumentLayout] that backs a [SuperEditor] in the widget tree.
  ///
  /// {@macro supereditor_finder}
  static DocumentLayout findDocumentLayout([Finder? superEditorFinder]) {
    late final Finder layoutFinder;
    if (superEditorFinder != null) {
      layoutFinder = find.descendant(of: superEditorFinder, matching: find.byType(SingleColumnDocumentLayout));
    } else {
      layoutFinder = find.byType(SingleColumnDocumentLayout);
    }
    final documentLayoutElement = layoutFinder.evaluate().single as StatefulElement;
    return documentLayoutElement.state as DocumentLayout;
  }

  /// Returns `true` if [SuperEditor]'s policy believes that a mobile toolbar should
  /// be visible right now, or `false` otherwise.
  ///
  /// This inspection is different from [isMobileToolbarVisible] in a couple ways:
  ///  * On mobile web, [SuperEditor] defers to the browser's built-in overlay
  ///    controls. Therefore, [wantsMobileToolbarToBeVisible] is `true` but
  ///    [isMobileToolbarVisible] is `false`.
  ///  * When an app customizes the toolbar, [SuperEditor] might want to build
  ///    and display a toolbar, but the app overrode the toolbar widget and chose
  ///    to build empty space instead of a toolbar. In this case
  ///    [wantsMobileToolbarToBeVisible] is `true`, but [isMobileToolbarVisible]
  ///    is `false`.
  static bool wantsMobileToolbarToBeVisible([Finder? superEditorFinder]) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final toolbarManager = find.state<SuperEditorAndroidControlsOverlayManagerState>(superEditorFinder);
        if (toolbarManager == null) {
          throw Exception(
              "Tried to verify that SuperEditor wants mobile toolbar to be visible on Android, but couldn't find the toolbar manager widget.");
        }
        return toolbarManager.wantsToDisplayToolbar;
      case TargetPlatform.iOS:
        final toolbarManager = find.state<SuperEditorIosToolbarOverlayManagerState>(superEditorFinder);
        if (toolbarManager == null) {
          throw Exception(
              "Tried to verify that SuperEditor wants mobile toolbar to be visible on iOS, but couldn't find the toolbar manager widget.");
        }
        return toolbarManager.wantsToDisplayToolbar;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  /// Returns `true` if the mobile floating toolbar is currently visible, or `false`
  /// if it's not.
  ///
  /// The mobile floating toolbar looks different for iOS and Android, but on both
  /// platforms it appears on top of the editor, near selected content.
  ///
  /// This method doesn't take a `superEditorFinder` because the toolbar is displayed
  /// in the application overlay, and is therefore completely independent from the
  /// [SuperEditor] subtree. There's no obvious way to associate a toolbar with
  /// a specific [SuperEditor].
  ///
  /// See also: [wantsMobileToolbarToBeVisible].
  static bool isMobileToolbarVisible() {
    return find.byKey(DocumentKeys.mobileToolbar).evaluate().isNotEmpty;
  }

  /// Returns `true` if [SuperEditor]'s policy believes that a mobile magnifier
  /// should be visible right now, or `false` otherwise.
  ///
  /// This inspection is different from [isMobileMagnifierVisible] in a couple ways:
  ///  * On mobile web, [SuperEditor] defers to the browser's built-in overlay
  ///    controls. Therefore, [wantsMobileMagnifierToBeVisible] is `true` but
  ///    [isMobileMagnifierVisible] is `false`.
  ///  * When an app customizes the magnifier, [SuperEditor] might want to build
  ///    and display a magnifier, but the app overrode the magnifier widget and chose
  ///    to build empty space instead of a magnifier. In this case
  ///    [wantsMobileMagnifierToBeVisible] is `true`, but [isMobileMagnifierVisible]
  ///    is `false`.
  static bool wantsMobileMagnifierToBeVisible([Finder? superEditorFinder]) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final magnifierManager = find.state<SuperEditorAndroidControlsOverlayManagerState>(superEditorFinder);
        if (magnifierManager == null) {
          throw Exception(
              "Tried to verify that SuperEditor wants mobile magnifier to be visible on Android, but couldn't find the magnifier manager widget.");
        }

        return magnifierManager.wantsToDisplayMagnifier;
      case TargetPlatform.iOS:
        final magnifierManager = find.state<SuperEditorIosMagnifierOverlayManagerState>(superEditorFinder);
        if (magnifierManager == null) {
          throw Exception(
              "Tried to verify that SuperEditor wants mobile magnifier to be visible on iOS, but couldn't find the magnifier manager widget.");
        }

        return magnifierManager.wantsToDisplayMagnifier;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  /// Returns `true` if a mobile magnifier is currently visible, or `false` if it's
  /// not.
  ///
  /// The mobile magnifier looks different for iOS and Android. The magnifier also
  /// follows different focal points depending on whether it's iOS or Android.
  /// But in both cases, a magnifier is a small shape near the user's finger or
  /// selection, which shows the editor content at an enlarged/magnified level.
  ///
  /// This method doesn't take a `superEditorFinder` because the magnifier is displayed
  /// in the application overlay, and is therefore completely independent from the
  /// [SuperEditor] subtree. There's no obvious way to associate a magnifier with
  /// a specific [SuperEditor].
  ///
  /// See also: [wantsMobileMagnifierToBeVisible]
  static bool isMobileMagnifierVisible() {
    return find.byKey(DocumentKeys.magnifier).evaluate().isNotEmpty;
  }

  /// Returns `true` if any type of mobile drag handles are visible, or `false`
  /// if not.
  ///
  /// On iOS, drag handles include the caret, as well as the upstream and downstream
  /// handles.
  ///
  /// On Android, drag handles include the caret handle, as well as the upstream and
  /// downstream drag handles. The caret drag handle on Android disappears after a brief
  /// period of inactivity, and reappears upon another user interaction.
  static Finder findAllMobileDragHandles([Finder? superEditorFinder]) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return find.byWidgetPredicate(
          (widget) =>
              widget.key == DocumentKeys.androidCaretHandle ||
              widget.key == DocumentKeys.upstreamHandle ||
              widget.key == DocumentKeys.downstreamHandle,
        );
      case TargetPlatform.iOS:
        return find.byWidgetPredicate(
          (widget) =>
              widget.key == DocumentKeys.caret ||
              widget.key == DocumentKeys.upstreamHandle ||
              widget.key == DocumentKeys.downstreamHandle,
        );
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return FindsNothing();
    }
  }

  static Finder findMobileCaret([Finder? superEditorFinder]) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return find.byKey(DocumentKeys.caret);
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return FindsNothing();
    }
  }

  /// Returns `true` if the caret is currently visible and 100% opaque, or `false` if it's
  /// not.
  ///
  /// {@macro supereditor_finder}
  static bool isCaretVisible([Finder? superEditorFinder]) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidCaretLayerState = _findAndroidControlsLayer(superEditorFinder);
      return androidCaretLayerState.isCaretVisible;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iOSCaretLayer = _findIosControlsLayer(superEditorFinder);
      return iOSCaretLayer.isCaretVisible;
    }

    final desktopCaretLayer = _findDesktopCaretOverlay(superEditorFinder);
    return desktopCaretLayer.isCaretVisible;
  }

  /// Returns the [Duration] to switch the caret between visible and invisible.
  ///
  /// {@macro supereditor_finder}
  static Duration caretFlashPeriod([Finder? superEditorFinder]) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidCaretLayerState = _findAndroidControlsLayer(superEditorFinder);
      return androidCaretLayerState.caretFlashPeriod;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iOSCaretLayer = _findIosControlsLayer(superEditorFinder);
      return iOSCaretLayer.caretFlashPeriod;
    }

    final desktopCaretLayer = _findDesktopCaretOverlay(superEditorFinder);
    return desktopCaretLayer.caretFlashPeriod;
  }

  static Finder findMobileCaretDragHandle([Finder? superEditorFinder]) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return find.byKey(DocumentKeys.androidCaretHandle);
      case TargetPlatform.iOS:
        return find.byKey(DocumentKeys.caret);
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return FindsNothing();
    }
  }

  static Finder findMobileExpandedDragHandles([Finder? superEditorFinder]) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return find.byWidgetPredicate(
          (widget) => widget.key == DocumentKeys.upstreamHandle || widget.key == DocumentKeys.downstreamHandle,
        );
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return FindsNothing();
    }
  }

  /// Finds the upstream drag handle for a mobile `SuperEditor`.
  ///
  /// This handle might be the base handle or the extent handle, depending on selection direction.
  static Finder findMobileUpstreamDragHandle([Finder? superEditorFinder]) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return find.byKey(DocumentKeys.upstreamHandle);
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return FindsNothing();
    }
  }

  /// Finds the downstream drag handle for a mobile `SuperEditor`.
  ///
  /// This handle might be the base handle or the extent handle, depending on selection direction.
  static Finder findMobileDownstreamDragHandle([Finder? superEditorFinder]) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return find.byKey(DocumentKeys.downstreamHandle);
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return FindsNothing();
    }
  }

  /// Finds the base drag handle for a mobile `SuperEditor`.
  ///
  /// Keep in mind that the base handle is the handle at the beginning of a selection.
  /// The beginning of a selection might appear on the left side or right side of a
  /// selection, depending on the direction that the user dragged to select content.
  static Finder findMobileBaseDragHandle([Finder? superEditorFinder]) {
    final selection = findDocumentSelection(superEditorFinder);
    expect(selection, isNotNull,
        reason: "Tried to find the mobile handle for the selection base, but the selection is null.");

    if (selection!.isCollapsed) {
      // When the selection is collapsed, the base and extent are the same. The choice is irrelevant.
      return findMobileDownstreamDragHandle(superEditorFinder);
    }

    if (selection.hasDownstreamAffinity(findDocument(superEditorFinder)!)) {
      return findMobileUpstreamDragHandle(superEditorFinder);
    } else {
      return findMobileDownstreamDragHandle(superEditorFinder);
    }
  }

  /// Finds the extent drag handle for a mobile `SuperEditor`.
  ///
  /// Keep in mind that the extent handle is the handle at the end of a selection.
  /// The end of a selection might appear on the left side or right side of a
  /// selection, depending on the direction that the user dragged to select content.
  static Finder findMobileExtentDragHandle([Finder? superEditorFinder]) {
    final selection = findDocumentSelection(superEditorFinder);
    expect(selection, isNotNull,
        reason: "Tried to find the mobile handle for the selection extent, but the selection is null.");

    if (selection!.isCollapsed) {
      // When the selection is collapsed, the base and extent are the same. The choice is irrelevant.
      return findMobileDownstreamDragHandle(superEditorFinder);
    }

    if (selection.hasDownstreamAffinity(findDocument(superEditorFinder)!)) {
      return findMobileDownstreamDragHandle(superEditorFinder);
    } else {
      return findMobileUpstreamDragHandle(superEditorFinder);
    }
  }

  /// Finds the magnifier for a mobile `SuperEditor`.
  static Finder findMobileMagnifier([Finder? superEditorFinder]) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return find.byKey(DocumentKeys.magnifier);

      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return FindsNothing();
    }
  }

  static AndroidControlsDocumentLayerState _findAndroidControlsLayer([Finder? superEditorFinder]) {
    final element = find
        .descendant(
          of: (superEditorFinder ?? find.byType(SuperEditor)),
          matching: find.byType(AndroidHandlesDocumentLayer),
        )
        .evaluate()
        .single as StatefulElement;

    return element.state as AndroidControlsDocumentLayerState;
  }

  static IosControlsDocumentLayerState _findIosControlsLayer([Finder? superEditorFinder]) {
    final element = find
        .descendant(
          of: (superEditorFinder ?? find.byType(SuperEditor)),
          matching: find.byType(IosHandlesDocumentLayer),
        )
        .evaluate()
        .single as StatefulElement;

    return element.state as IosControlsDocumentLayerState;
  }

  static CaretDocumentOverlayState _findDesktopCaretOverlay([Finder? superEditorFinder]) {
    final element = find
        .descendant(
          of: (superEditorFinder ?? find.byType(SuperEditor)),
          matching: find.byType(CaretDocumentOverlay),
        )
        .evaluate()
        .single as StatefulElement;

    return element.state as CaretDocumentOverlayState;
  }

  SuperEditorInspector._();
}
