// Compatibility barrel: every Settings widget import keeps pointing at
// `settings_common.dart`, while the implementations live in focused files
// split by purpose (Plan §14.1):
//  * primitives/settings_section.dart — section titles, cards, tiles, dividers
//  * feedback/settings_feedback.dart  — info/empty cards, pills, dialogs,
//    buttons, shared scaffold
//  * controls/settings_controls.dart  — switch tile, form rows, dropdowns
//  * diagnostics/settings_diagnostics_view.dart — key-value tiles, segmented
//    bars
// Import from the split files in new code; this barrel exists so the dozens
// of existing call sites keep working unchanged.
export 'primitives/settings_section.dart';
export 'feedback/settings_feedback.dart';
export 'controls/settings_controls.dart';
export 'diagnostics/settings_diagnostics_view.dart';
