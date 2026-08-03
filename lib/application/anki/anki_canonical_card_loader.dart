// Project imports:
import 'package:varnamala/application/anki/anki_card_html_renderer.dart';
import 'package:varnamala/application/anki/anki_media_reference_extractor.dart';
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/data/anki_note_dao.dart';
import 'package:varnamala/domain/audio/anki_audio_resolver.dart';
import 'package:varnamala/domain/course/interaction.dart';

/// Resolves a lightweight Anki card reference into its canonical rendered
/// front/back faces from the NoteStore.
///
/// Both course-path virtual lessons and due-review batches use this loader so
/// render mode never changes whether a card exists in navigation.
class AnkiCanonicalCardLoader {
  final AnkiNoteDao _noteDao;
  final AnkiCardHtmlRenderer _htmlRenderer;
  final AnkiAudioResolver _mediaResolver;

  AnkiCanonicalCardLoader(
    this._noteDao, {
    AnkiCardHtmlRenderer htmlRenderer = const AnkiCardHtmlRenderer(),
    AnkiAudioResolver? mediaResolver,
  })  : _htmlRenderer = htmlRenderer,
        _mediaResolver = mediaResolver ?? AnkiAudioResolver();

  Future<AnkiHtmlCard?> load(String wordId) async {
    final meta = await _noteDao.cardMetaByWordId(wordId);
    if (meta == null) return null;
    final noteRec = await _noteDao.note(meta.importId, meta.noteId);
    if (noteRec == null) return null;
    final ntRec = await _noteDao.notetype(meta.importId, noteRec.mid);
    if (ntRec == null) return null;

    final cached = ntRec.allowJs ? await _noteDao.prerendered(wordId) : null;
    final useCache = cached != null && cached.isComplete;
    final note = AnkiNote(
      id: noteRec.noteId,
      mid: noteRec.mid,
      tags: noteRec.tags,
      fields: noteRec.fields,
    );
    final notetype = AnkiNotetype(
      id: ntRec.mid,
      name: ntRec.name,
      isCloze: ntRec.isCloze,
      fieldNames: ntRec.fieldNames,
      templates: ntRec.templates,
      css: ntRec.css,
    );
    final card = AnkiCardData(
      id: meta.cardId,
      nid: meta.noteId,
      did: meta.did,
      ord: meta.ord,
    );
    final mediaBasePath =
        await _mediaResolver.getImportMediaPath(meta.importId);
    final frontHtml = useCache
        ? AnkiCardHtmlRenderer.wrapBody(
            cached.frontHtml!,
            css: ntRec.css,
            mediaBasePath: mediaBasePath,
          )
        : _htmlRenderer.renderFront(
            notetype: notetype,
            note: note,
            card: card,
            mediaBasePath: mediaBasePath,
          );
    final backHtml = useCache
        ? AnkiCardHtmlRenderer.wrapBody(
            cached.backHtml!,
            css: ntRec.css,
            mediaBasePath: mediaBasePath,
          )
        : _htmlRenderer.renderBack(
            notetype: notetype,
            note: note,
            card: card,
            mediaBasePath: mediaBasePath,
          );
    final audioAssets = const AnkiMediaReferenceExtractor()
        .extract('$frontHtml\n$backHtml', meta.importId)
        .audios;

    return Interaction.ankiHtmlCard(
      id: '$wordId-c${meta.ord}',
      frontHtml: frontHtml,
      backHtml: backHtml,
      css: useCache ? '' : ntRec.css,
      allowJs: useCache ? false : ntRec.allowJs,
      audioAssets: audioAssets,
      sourceNoteId: '${meta.noteId}',
      sourceCardId: '${meta.cardId}',
      wordId: wordId,
      mediaBasePath: mediaBasePath,
    ) as AnkiHtmlCard;
  }
}
