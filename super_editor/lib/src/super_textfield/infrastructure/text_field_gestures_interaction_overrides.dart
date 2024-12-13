import 'package:flutter/widgets.dart';
import 'package:super_editor/src/infrastructure/document_gestures_interaction_overrides.dart';
import 'package:super_editor/super_text_field.dart';
import 'package:super_text_layout/super_text_layout.dart';

/// Delegate for mouse status and clicking on special types of content,
/// e.g., tapping on a link open the URL.
///
/// Listeners are notified when any time that the desired mouse cursor
/// may have changed.
abstract class SuperTextFieldTapHandler with ChangeNotifier {
  MouseCursor? mouseCursorForContentHover(TextFieldGestureDetails details) => null;

  TapHandlingInstruction onTap(TextFieldGestureDetails details) => TapHandlingInstruction.continueHandling;

  TapHandlingInstruction onDoubleTap(TextFieldGestureDetails details) => TapHandlingInstruction.continueHandling;

  TapHandlingInstruction onTripleTap(TextFieldGestureDetails details) => TapHandlingInstruction.continueHandling;
}

/// Information about a gesture that happened within a [SuperTextField].
class TextFieldGestureDetails {
  TextFieldGestureDetails({
    required this.textLayout,
    required this.textController,
    required this.globalOffset,
    required this.layoutOffset,
    required this.textOffset,
  });

  /// The text layout of the text field.
  ///
  /// It can be used to pull information about the logical position
  /// where the tap occurred. For example, to find the [TextPosition]
  /// that is nearest to the tap.
  final ProseTextLayout textLayout;

  /// The controller that holds the current text and selection of the text field.
  /// It can be used to pull information about the text and its attributions.
  final AttributedTextEditingController textController;

  /// The position of the gesture in global coordinates.
  final Offset globalOffset;

  /// The position of the gesture in [SuperTextField]'s coordinate space. This
  /// coordinate space contains the text layout and the padding around the text.
  final Offset layoutOffset;

  /// The position of the gesture in the text coordinate space.
  final Offset textOffset;
}
