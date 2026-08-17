//! Official Typed Answer resolution. Dart must not parse templates or clozes.

use anki::cloze::extract_cloze_for_typing;
use anki::notes::Note;
use anki::notetype::Notetype;
use anki::prelude::*;
use anki::services::CardRenderingService;
use anki_proto::card_rendering::CompareAnswerRequest;
use serde::Deserialize;
use serde_json::json;
use serde_json::Value;

use crate::engine::STATUS_CARD_NOT_FOUND;
use crate::engine::STATUS_INVALID_ARGUMENT;
use crate::engine::STATUS_INVALID_STATE;
use crate::engine::STATUS_RENDER_FAILED;
use crate::engine::STATUS_TYPED_CLOZE_EMPTY;
use crate::engine::STATUS_TYPED_FIELD_NOT_FOUND;
use crate::engine::MAX_REQUEST_BYTES;
use crate::ops::map_anki_error;
use crate::ops::require_open;

const TYPE_MARKER_PREFIX: &str = "[[type:";
const TYPE_MARKER_SUFFIX: &str = "]]";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TypedSpec {
    pub marker: String,
    pub field_name: String,
    pub combining: bool,
    pub cloze: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CompareRequest {
    #[serde(alias = "card_id")]
    card_id: i64,
    marker: String,
    provided: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ExtractRequest {
    #[serde(default)]
    text: Option<String>,
    #[serde(default)]
    ordinal: Option<u16>,
    #[serde(default, alias = "card_id")]
    card_id: Option<i64>,
    #[serde(default)]
    marker: Option<String>,
}

pub fn parse_type_marker(raw: &str) -> Result<TypedSpec, i32> {
    let start = raw.find(TYPE_MARKER_PREFIX).ok_or(STATUS_INVALID_ARGUMENT)?;
    let after = &raw[start + TYPE_MARKER_PREFIX.len()..];
    let end = after.find(TYPE_MARKER_SUFFIX).ok_or(STATUS_INVALID_ARGUMENT)?;
    let inner = &after[..end];
    if inner.is_empty() || inner.len() > 128 {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let marker = format!("{TYPE_MARKER_PREFIX}{inner}{TYPE_MARKER_SUFFIX}");
    if let Some(field) = inner.strip_prefix("cloze:") {
        if field.is_empty() {
            return Err(STATUS_INVALID_ARGUMENT);
        }
        return Ok(TypedSpec {
            marker,
            field_name: field.to_string(),
            combining: true,
            cloze: true,
        });
    }
    if let Some(field) = inner.strip_prefix("nc:") {
        if field.is_empty() {
            return Err(STATUS_INVALID_ARGUMENT);
        }
        return Ok(TypedSpec {
            marker,
            field_name: field.to_string(),
            combining: false,
            cloze: false,
        });
    }
    Ok(TypedSpec {
        marker,
        field_name: inner.to_string(),
        combining: true,
        cloze: false,
    })
}

pub fn find_type_marker(html: &str) -> Option<TypedSpec> {
    parse_type_marker(html).ok()
}

fn field_value(note: &Note, nt: &Notetype, name: &str) -> Result<(String, String, u32), i32> {
    for (idx, field) in nt.fields.iter().enumerate() {
        if field.name == name {
            let value = note.fields().get(idx).cloned().unwrap_or_default();
            return Ok((
                value,
                field.config.font_name.clone(),
                field.config.font_size,
            ));
        }
    }
    Err(STATUS_TYPED_FIELD_NOT_FOUND)
}

fn load_card_note_nt(
    col: &mut Collection,
    card_id: i64,
) -> Result<(Card, Note, std::sync::Arc<Notetype>), i32> {
    if card_id <= 0 {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let card = col
        .storage
        .get_card(CardId(card_id))
        .map_err(map_anki_error)?
        .ok_or(STATUS_CARD_NOT_FOUND)?;
    let note = col
        .storage
        .get_note(card.note_id())
        .map_err(map_anki_error)?
        .ok_or(STATUS_CARD_NOT_FOUND)?;
    let nt = col
        .get_notetype(note.notetype_id)
        .map_err(map_anki_error)?
        .ok_or(STATUS_RENDER_FAILED)?;
    Ok((card, note, nt))
}

pub fn typed_hint_json(
    col: &mut Collection,
    card_id: i64,
    question: &str,
    answer: &str,
) -> Result<Option<Value>, i32> {
    let Some(spec) = find_type_marker(question).or_else(|| find_type_marker(answer)) else {
        return Ok(None);
    };
    let (card, note, nt) = load_card_note_nt(col, card_id)?;
    let (_, font_family, font_size) = field_value(&note, &nt, &spec.field_name)?;
    let cloze_ordinal = if spec.cloze {
        Some(card.template_idx() as u32 + 1)
    } else {
        None
    };
    Ok(Some(json!({
        "marker": spec.marker,
        "fontFamily": font_family,
        "fontSizePx": font_size,
        "combining": spec.combining,
        "clozeOrdinal": cloze_ordinal,
    })))
}

fn expected_for_spec(
    col: &mut Collection,
    card_id: i64,
    spec: &TypedSpec,
) -> Result<(String, bool), i32> {
    let (card, note, nt) = load_card_note_nt(col, card_id)?;
    let (field_text, _, _) = field_value(&note, &nt, &spec.field_name)?;
    if spec.cloze {
        let ordinal = card.template_idx() + 1;
        let extracted = extract_cloze_for_typing(&field_text, ordinal);
        if extracted.is_empty() {
            return Err(STATUS_TYPED_CLOZE_EMPTY);
        }
        return Ok((extracted.into_owned(), spec.combining));
    }
    Ok((field_text, spec.combining))
}

pub fn compare_typed_answer(handle: u64, request: &[u8]) -> Result<Value, i32> {
    if request.len() > MAX_REQUEST_BYTES {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let parsed: CompareRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if parsed.provided.len() > 16_384 {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let spec = parse_type_marker(&parsed.marker)?;
    let slot = crate::engine::slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let (expected, combining) = expected_for_spec(col, parsed.card_id, &spec)?;
    let html = col
        .compare_answer(CompareAnswerRequest {
            expected: expected.clone(),
            provided: parsed.provided,
            combining,
        })
        .map_err(map_anki_error)?;
    Ok(json!({
        "comparisonHtml": html.val,
        "hasExpected": !expected.is_empty(),
    }))
}

pub fn extract_cloze_op(handle: u64, request: &[u8]) -> Result<Value, i32> {
    if request.len() > MAX_REQUEST_BYTES {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let parsed: ExtractRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if let (Some(text), Some(ordinal)) = (parsed.text.as_ref(), parsed.ordinal) {
        if text.len() > 1_048_576 || ordinal == 0 {
            return Err(STATUS_INVALID_ARGUMENT);
        }
        let extracted = extract_cloze_for_typing(text, ordinal);
        if extracted.is_empty() {
            return Err(STATUS_TYPED_CLOZE_EMPTY);
        }
        return Ok(json!({ "text": extracted.into_owned() }));
    }
    let card_id = parsed.card_id.ok_or(STATUS_INVALID_ARGUMENT)?;
    let marker = parsed.marker.ok_or(STATUS_INVALID_ARGUMENT)?;
    let spec = parse_type_marker(&marker)?;
    if !spec.cloze {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let slot = crate::engine::slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let (expected, _) = expected_for_spec(col, card_id, &spec)?;
    Ok(json!({ "text": expected }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_field_cloze_and_nc_markers() {
        let field = parse_type_marker("typed-front\n[[type:Back]]").unwrap();
        assert_eq!(field.field_name, "Back");
        assert!(field.combining);
        assert!(!field.cloze);
        let cloze = parse_type_marker("[[type:cloze:Text]]").unwrap();
        assert_eq!(cloze.field_name, "Text");
        assert!(cloze.cloze);
        let nc = parse_type_marker("[[type:nc:Back]]").unwrap();
        assert!(!nc.combining);
        assert_eq!(nc.field_name, "Back");
    }

    #[test]
    fn rejects_empty_marker() {
        assert_eq!(
            parse_type_marker("no marker here").unwrap_err(),
            STATUS_INVALID_ARGUMENT
        );
    }
}
