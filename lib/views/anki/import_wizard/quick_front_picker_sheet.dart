import 'package:flutter/material.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

/// In-place modal bottom sheet for quickly resolving blocking schema issues
/// where the front (prompt) field is ambiguous or missing.
void showQuickFrontPicker({
  required BuildContext context,
  required OfficialAnkiProjectionSchema schema,
  required OfficialAnkiMappingSuggestion currentSuggestion,
  required void Function(OfficialAnkiMappingSuggestion updated) onConfirmed,
}) {
  final sample = schema.samples.firstOrNull;

  showTurnaSheet<void>(
    context: context,
    title: AppStrings.ankiFrontPickerTitle(schema.name),
    subtitle: AppStrings.ankiFrontPickerBody,
    body: ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        AppSpacing.sm,
        AppSpacing.pageMargin,
        AppSpacing.xl,
      ),
      itemCount: schema.fieldNames.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (itemContext, index) {
        final fieldName = schema.fieldNames[index];
        final sampleVal = sample != null && index < sample.fields.length
            ? sample.fields[index].replaceAll(RegExp(r'<[^>]*>'), '').trim()
            : '';

        return InkWell(
          onTap: () {
            final nextCandidates = <OfficialAnkiFieldCandidate>[];
            for (var i = 0; i < schema.fieldNames.length; i++) {
              final name = schema.fieldNames[i];
              if (i == index) {
                nextCandidates.add(
                  OfficialAnkiFieldCandidate(
                    role: FieldRole.prompt,
                    fieldIndex: i,
                    fieldName: name,
                    confidence: 1.0,
                    evidence: const ['user:quick_pick'],
                  ),
                );
              } else if (i == (index == 0 ? 1 : 0) &&
                  schema.fieldNames.length > 1) {
                nextCandidates.add(
                  OfficialAnkiFieldCandidate(
                    role: FieldRole.response,
                    fieldIndex: i,
                    fieldName: name,
                    confidence: 1.0,
                    evidence: const ['user:quick_pick'],
                  ),
                );
              } else {
                nextCandidates.add(
                  OfficialAnkiFieldCandidate(
                    role: FieldRole.ignored,
                    fieldIndex: i,
                    fieldName: name,
                    confidence: 0.2,
                    evidence: const ['unmatched'],
                  ),
                );
              }
            }

            final updated = currentSuggestion.copyWith(
              candidates: nextCandidates,
              status: OfficialAnkiMappingStatus.manual,
              userConfirmed: true,
            );
            onConfirmed(updated);
            Navigator.of(itemContext).pop();
          },
          borderRadius: TurnaTheme.borderRadius,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: TurnaTheme.brandTeal.withValues(alpha: 0.2),
              ),
              borderRadius: TurnaTheme.borderRadius,
            ),
            child: Row(
              children: [
                const TurnaIcon(
                  TurnaIconId.radioUnchecked,
                  color: TurnaTheme.brandTeal,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fieldName,
                        style: AppTextStyles.cardTitle(itemContext),
                      ),
                      if (sampleVal.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          sampleVal,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.captionSm(itemContext).copyWith(
                            color: TurnaTheme.textHintColor(itemContext),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
