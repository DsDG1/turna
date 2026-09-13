# P5-A01 Legacy Anki dependency inventory

> 日期：2026-08-18  
> 范围：`lib/application/anki` + `lib/views/anki`  
> 口径：只读盘点。不改变任何用户来源的 engine。

`wc -l` 合计 **14,995** 行，30 个 Dart 文件（含 generated）。

## 目录内文件

| Path | Lines | Role |
|---|---:|---|
| `lib/application/anki/anki_importer.dart` | 654 | import / package decode |
| `lib/application/anki/anki_import_platform_io.dart` | 78 | import / platform IO |
| `lib/application/anki/anki_import_platform_stub.dart` | 56 | import / platform fallback |
| `lib/application/anki/anki_import_cleanup_service.dart` | 47 | import / cleanup |
| `lib/application/anki/anki_deck_assembler.dart` | 980 | import / course projection |
| `lib/application/anki/anki_organization_resolver.dart` | 159 | course projection |
| `lib/application/anki/anki_notetype_ai.dart` | 171 | import / mapping helper |
| `lib/application/anki/anki_sample_deck.dart` | 103 | import / fixture |
| `lib/application/anki/anki_models.dart` | 231 | DAO / models |
| `lib/application/anki/anki_models.freezed.dart` | 3559 | generated |
| `lib/application/anki/anki_models.g.dart` | 67 | generated |
| `lib/application/anki/anki_card_adapter.dart` | 1359 | render / course projection |
| `lib/application/anki/anki_card_adapter.freezed.dart` | 403 | generated |
| `lib/application/anki/anki_card_adapter.g.dart` | 35 | generated |
| `lib/application/anki/anki_template_renderer.dart` | 238 | render |
| `lib/application/anki/anki_card_html_renderer.dart` | 219 | render |
| `lib/application/anki/anki_canonical_card_loader.dart` | 99 | render |
| `lib/application/anki/anki_media_reference_extractor.dart` | 159 | render / media |
| `lib/application/anki/anki_media_url_resolver.dart` | 48 | render / media |
| `lib/application/anki/anki_type_answer.dart` | 66 | render |
| `lib/application/anki/anki_render_policy.dart` | 149 | render |
| `lib/application/anki/anki_review_assembler.dart` | 419 | review |
| `lib/application/anki/anki_deck_manager.dart` | 302 | review / DAO |
| `lib/application/anki/anki_srs_migrator.dart` | 288 | review / Turna SRS write |
| `lib/views/anki/anki_import_screen.dart` | 2972 | UI / import |
| `lib/views/anki/anki_review_screen.dart` | 640 | UI / review |
| `lib/views/anki/anki_review_session_page.dart` | 612 | UI / review |
| `lib/views/anki/anki_html_card_view.dart` | 332 | UI / render |
| `lib/views/anki/anki_card_browser_page.dart` | 374 | UI |
| `lib/views/anki/anki_deck_stats_page.dart` | 176 | UI |

## 目录外生产引用

| Path | Uses |
|---|---|
| `lib/data/anki_note_dao.dart` | Legacy note/card DAO writes |
| `lib/data/anki_import_dao.dart` | `anki_imports` metadata |
| `lib/application/review_progress_provider.dart` | due / review assembler |
| `lib/application/anki_official/import/anki_import_facade.dart` | official/legacy import switch |
| `lib/views/lesson/components/interactions/anki_html_card_renderer.dart` | lesson preview render |
| `lib/views/play/play_hub_screen.dart` | review entry |
| `lib/views/profile/widgets/profile_quick_actions.dart` | review entry |
| `lib/views/courses/course_management_page.dart` | import entry |
| `lib/views/settings/settings_page.dart` | deck manager |
| `lib/views/settings/widgets/settings_learning_section.dart` | deck manager |
| `lib/routing/routing.gr.dart` | generated routes |

正常复习入口仍是 `AnkiReviewRoute` / `AnkiReviewAssembler` + Turna `SrsProvider`。正式官方复习仍只在内部调试页。
