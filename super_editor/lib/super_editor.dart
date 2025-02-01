library super_editor;

export 'package:attributed_text/attributed_text.dart';
export 'package:super_text_layout/src/caret_layer.dart';

// Fundamental document abstractions
export 'src/core/document.dart';
export 'src/core/document_composer.dart';
export 'src/core/document_debug_paint.dart';
export 'src/core/document_interaction.dart';
export 'src/core/document_layout.dart';
export 'src/core/document_selection.dart';
export 'src/core/edit_context.dart';
export 'src/core/editor.dart';
export 'src/core/styles.dart';

// Super Editor
export 'src/default_editor/attributions.dart';
export 'src/default_editor/blocks/indentation.dart';
export 'src/default_editor/blockquote.dart';
export 'src/default_editor/box_component.dart';
export 'src/default_editor/common_editor_operations.dart';
export 'src/default_editor/composer/composer_reactions.dart';
export 'src/default_editor/composite_component.dart';
export 'src/default_editor/debug_visualization.dart';
export 'src/default_editor/default_document_editor.dart';
export 'src/default_editor/default_document_editor_reactions.dart';
export 'src/default_editor/document_caret_overlay.dart';
export 'src/default_editor/document_focus_and_selection_policies.dart';
export 'src/infrastructure/document_gestures.dart';
export 'src/default_editor/document_gestures_mouse.dart';
export 'src/infrastructure/document_gestures_interaction_overrides.dart';
export 'src/default_editor/document_gestures_touch_ios.dart';
export 'src/default_editor/document_gestures_touch_android.dart';
export 'src/default_editor/document_ime/document_input_ime.dart';
export 'src/default_editor/document_layers/attributed_text_bounds_overlay.dart';
export 'src/default_editor/document_hardware_keyboard/document_input_keyboard.dart';
export 'src/default_editor/horizontal_rule.dart';
export 'src/default_editor/image.dart';
export 'src/default_editor/layout_single_column/layout_single_column.dart';
export 'src/default_editor/list_items.dart';
export 'src/default_editor/multi_node_editing.dart';
export 'src/default_editor/paragraph.dart';
export 'src/default_editor/layout_single_column/selection_aware_viewmodel.dart';
export 'src/default_editor/selection_binary.dart';
export 'src/default_editor/selection_upstream_downstream.dart';
export 'src/default_editor/super_editor.dart';
export 'src/default_editor/tasks.dart';
export 'src/default_editor/text.dart';
export 'src/default_editor/text_tools.dart';
export 'src/default_editor/text_tokenizing/action_tags.dart';
export 'src/default_editor/text_tokenizing/pattern_tags.dart';
export 'src/default_editor/text_tokenizing/tags.dart';
export 'src/default_editor/text_tokenizing/stable_tags.dart';
export 'src/default_editor/spelling_and_grammar/spelling_and_grammar_styler.dart';
export 'src/default_editor/unknown_component.dart';

// Document operations used by SuperEditor and/or SuperReader,
// also made available for public use.
export 'src/document_operations/selection_operations.dart';

export 'src/infrastructure/multi_listenable_builder.dart';
export 'src/infrastructure/_logging.dart';
export 'src/infrastructure/attributed_text_styles.dart';
export 'src/infrastructure/attribution_layout_bounds.dart';
export 'src/infrastructure/composable_text.dart';
export 'src/infrastructure/content_layers.dart';
export 'src/infrastructure/documents/document_layers.dart';
export 'src/infrastructure/documents/document_scroller.dart';
export 'src/infrastructure/documents/selection_leader_document_layer.dart';
export 'src/infrastructure/ime_input_owner.dart';
export 'src/infrastructure/keyboard.dart';
export 'src/infrastructure/multi_tap_gesture.dart';
export 'src/infrastructure/pausable_value_notifier.dart';
export 'src/infrastructure/flutter/overlay_with_groups.dart';
export 'src/infrastructure/flutter/text_selection.dart';
export 'src/infrastructure/platforms/android/android_document_controls.dart';
export 'src/infrastructure/platforms/android/toolbar.dart';
export 'src/infrastructure/platforms/ios/ios_document_controls.dart';
export 'src/infrastructure/platforms/ios/ios_system_context_menu.dart';
export 'src/infrastructure/platforms/ios/floating_cursor.dart';
export 'src/infrastructure/platforms/ios/toolbar.dart';
export 'src/infrastructure/platforms/ios/magnifier.dart';
export 'src/infrastructure/platforms/ios/selection_heuristics.dart';
export 'src/infrastructure/platforms/mac/mac_ime.dart';
export 'src/infrastructure/platforms/mobile_documents.dart';
export 'src/infrastructure/scrolling_diagnostics/scrolling_diagnostics.dart';
export 'src/infrastructure/signal_notifier.dart';
export 'src/infrastructure/strings.dart';
export 'src/super_textfield/super_textfield.dart';
export 'src/infrastructure/touch_controls.dart';
export 'src/infrastructure/text_input.dart';
export 'src/infrastructure/popovers.dart';
export 'src/infrastructure/selectable_list.dart';
export 'src/infrastructure/actions.dart';
export 'src/infrastructure/keyboard_panel_scaffold.dart';

export 'src/default_editor/tap_handlers/tap_handlers.dart';

// Super Reader
export 'src/super_reader/read_only_document_android_touch_interactor.dart';
export 'src/super_reader/read_only_document_ios_touch_interactor.dart';
export 'src/super_reader/read_only_document_keyboard_interactor.dart';
export 'src/super_reader/read_only_document_mouse_interactor.dart';
export 'src/super_reader/reader_context.dart';
export 'src/super_reader/super_reader.dart';

// Export from super_text_layout so that downstream clients don't
// have to add this package to get access to these classes.
export 'package:super_text_layout/super_text_layout.dart'
    show
        UnderlineStyle,
        SquiggleUnderlineStyle,
        SquiggleUnderlinePainter,
        DottedUnderlineStyle,
        DottedUnderlinePainter,
        StraightUnderlineStyle,
        StraightUnderlinePainter;
