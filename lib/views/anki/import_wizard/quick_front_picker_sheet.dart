import 'package:flutter/material.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/views/theme.dart';

/// In-place modal bottom sheet for quickly resolving blocking schema issues
/// where the front (prompt) field is ambiguous or missing.
void showQuickFrontPicker({
  required BuildContext context,
  required OfficialAnkiProjectionSchema schema,
  required OfficialAnkiMappingSuggestion currentSuggestion,
  required void Function(OfficialAnkiMappingSuggestion updated) onConfirmed,
}) {
  final sample = schema.samples.firstOrNull;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TurnaTheme.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(TurnaTheme.radiusLarge),
      ),
    ),
    builder: (bottomSheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: TurnaTheme.textHintColor(context)
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '选择卡片正面（${schema.name}）',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '请指定哪个字段作为题目正面，其余字段将作为背面或辅助内容：',
                style: TextStyle(
                  fontSize: 13,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: schema.fieldNames.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final fieldName = schema.fieldNames[index];
                    final sampleVal = sample != null &&
                            index < sample.fields.length
                        ? sample.fields[index]
                            .replaceAll(RegExp(r'<[^>]*>'), '')
                            .trim()
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
                        Navigator.of(bottomSheetContext).pop();
                      },
                      borderRadius: BorderRadius.circular(
                        TurnaTheme.radiusMedium,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: TurnaTheme.brandTeal.withValues(alpha: 0.2),
                          ),
                          borderRadius: BorderRadius.circular(
                            TurnaTheme.radiusMedium,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.radio_button_unchecked_rounded,
                              color: TurnaTheme.brandTeal,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fieldName,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (sampleVal.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      sampleVal,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            TurnaTheme.textHintColor(context),
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
              ),
            ],
          ),
        ),
      );
    },
  );
}
